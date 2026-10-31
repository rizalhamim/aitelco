"""Safe, read-only BigQuery execution tool.

Guards:
- Only a single SELECT / WITH statement allowed (no DML/DDL).
- Rejects multiple statements and dangerous keywords.
- Dry-run first to estimate scanned bytes; reject if over MAX_BYTES_BILLED.
- Enforces a row LIMIT if the user query has none.
- Hard maximum_bytes_billed on the actual job as a backstop.
"""
import json
import re
import threading
from datetime import date, datetime
from decimal import Decimal

from google.oauth2.credentials import Credentials
from google.cloud import bigquery

from . import config

# DDL/write keywords. We MUST allow scalar-function uses of REPLACE(...) (very
# common in SQL: REPLACE(string, from, to)), and column/identifier names that
# coincidentally contain words like "merge_status" or "load_dt". So the regex
# below rejects the keyword only when it is NOT followed by '(' (function call)
# and IS followed by whitespace + a SQL noun typical of write statements
# (INTO/TABLE/DATABASE/VIEW/INDEX/SCHEMA/FUNCTION/PROCEDURE/MODEL/...).
# This catches `INSERT INTO ...`, `DROP TABLE ...`, `CREATE OR REPLACE TABLE ...`
# while leaving `REPLACE(s,'a','b')`, `merge_status` and similar alone.
_DDL_FOLLOWERS = (
    r"(?:into|from|table|tables|temp|temporary|database|view|index|schema|"
    r"function|procedure|model|materialized|or\s+replace|external|"
    r"role|user|warehouse|column)"
)
_FORBIDDEN = re.compile(
    # Group 1: write/DDL keywords NOT used as function calls and followed by a DDL noun.
    r"\b(insert|delete|drop|create|alter|truncate|grant|revoke)\s+(?!\()"
    + _DDL_FOLLOWERS
    + r"|"
    # Group 2: keywords that always indicate write statements when followed by SET/whitespace.
    r"\b(update\s+`?\w+`?\s+set)\b|"
    # Group 3: CALL ... (stored procedure) and EXPORT DATA/MODEL.
    # (Note: no trailing \b — \w followed by another \w isn't a word boundary, and we don't need one.)
    r"\b(call\s+\w|export\s+(?:data|model)\b)",
    re.IGNORECASE,
)
_MULTI_STMT = re.compile(r";\s*\S")  # semicolon followed by more content
_QUOTED_IDENTIFIER = re.compile(r"`([^`]+)`")
_UNQUOTED_TABLE = re.compile(
    r"\b(?:from|join)\s+"
    r"([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z_][a-zA-Z0-9_]*)",
    re.IGNORECASE,
)

_client = None
_lock = threading.Lock()


def get_client() -> bigquery.Client:
    global _client
    with _lock:
        if _client is None:
            info = json.load(open(config.BQ_ADC))
            creds = Credentials(
                token=None,
                refresh_token=info["refresh_token"],
                client_id=info["client_id"],
                client_secret=info["client_secret"],
                token_uri="https://oauth2.googleapis.com/token",
            )
            _client = bigquery.Client(
                project=config.BQ_PROJECT, credentials=creds, location=config.BQ_LOCATION
            )
        return _client


class QueryError(Exception):
    pass


def _json_default(o):
    if isinstance(o, (date, datetime)):
        return o.isoformat()
    if isinstance(o, Decimal):
        return float(o)
    if isinstance(o, bytes):
        return o.decode("utf-8", "replace")
    return str(o)


def extract_table_references(sql: str) -> set[tuple[str, str, str]]:
    """Extract physical fully qualified table references conservatively."""
    refs: set[tuple[str, str, str]] = set()
    identifiers = list(_QUOTED_IDENTIFIER.findall(sql or ""))
    identifiers.extend(_UNQUOTED_TABLE.findall(sql or ""))
    for identifier in identifiers:
        parts = identifier.split(".")
        if len(parts) == 3 and all(parts):
            refs.add((parts[0], parts[1], parts[2]))
    return refs


def validate_table_policy(
    sql: str, allowed_tables: set[str] | list[str] | tuple[str, ...] | None = None
) -> set[str]:
    """Reject unknown, cross-dataset, banned, and unselected physical tables."""
    from . import knowledge

    refs = extract_table_references(sql)
    approved = knowledge.approved_table_names()
    blocked = knowledge.blocked_table_names()
    selected = set(allowed_tables or [])
    used: set[str] = set()
    for project, dataset, table in refs:
        if project != config.BQ_PROJECT or dataset != config.BQ_DATASET:
            raise QueryError(
                f"Table `{project}.{dataset}.{table}` is outside the approved dataset."
            )
        if table in blocked:
            raise QueryError(
                f"Table `{table}` is rejected by governance and cannot be queried."
            )
        if table not in approved:
            raise QueryError(
                f"Table `{table}` is not approved in the runtime knowledge base."
            )
        if selected and table not in selected:
            raise QueryError(
                f"Table `{table}` was not selected for this question. "
                "Regenerate SQL using only the retrieved schema."
            )
        used.add(table)
    _reject_sensitive_columns(sql, used)
    return used

def _reject_sensitive_columns(sql: str, used: set[str]) -> None:
    """Block identity columns (KB sensitive_dimensions) of any queried table.

    Name match is conservative: a same-named column of a joined table is also
    refused, and SELECT * is refused because it would expose them implicitly.
    """
    from . import knowledge
    import sqlglot
    from sqlglot import exp

    index = knowledge.table_index()
    sensitive = {c.lower() for t in used for c in index.get(t, {}).get("sensitive_dimensions") or []}
    if not sensitive:
        return
    try:
        tree = sqlglot.parse_one(sql, read="bigquery")
    except sqlglot.errors.SqlglotError as exc:
        raise QueryError(f"Invalid BigQuery SQL: {exc}") from exc
    # A bare table alias (SELECT o, TO_JSON_STRING(o)) serialises the whole row.
    aliases = {t.alias_or_name.lower() for t in tree.find_all(exp.Table)}
    names = {c.name.lower() for c in tree.find_all(exp.Column) if not isinstance(c.this, exp.Star)}
    hit = sorted(names & (sensitive | aliases))
    if hit:
        raise QueryError(f"Columns {', '.join(hit)} are personal or sales identity data and cannot be queried. Aggregate by territory, status or vendor instead.")
    if any(isinstance(s.parent, (exp.Select, exp.Column)) for s in tree.find_all(exp.Star)):
        raise QueryError("SELECT * is not allowed on tables with personal data. List the aggregate columns you need.")


def validate_sql(
    sql: str, allowed_tables: set[str] | list[str] | tuple[str, ...] | None = None
) -> str:
    s = sql.strip()
    # Strip a leading/trailing markdown code fence if the LLM wrapped the SQL.
    if s.startswith("```"):
        s = s.split("\n", 1)[1] if "\n" in s else s[3:]
        if s.rstrip().endswith("```"):
            s = s.rstrip()[:-3]
    s = s.strip()
    # Strip leading SQL line-comments (-- ...) and block comments (/* ... */) so a
    # narrative/comment prefix doesn't trip the read-only check on valid SELECT/WITH.
    import re as _re
    while True:
        ns = _re.sub(r"^\s*--[^\n]*\n", "", s)
        ns = _re.sub(r"^\s*/\*.*?\*/\s*", "", ns, flags=_re.DOTALL)
        if ns == s:
            break
        s = ns
    s = s.strip().rstrip(";").strip()
    if not s:
        raise QueryError("Empty query.")
    low = s.lower()
    if not (low.startswith("select") or low.startswith("with")):
        raise QueryError("Only SELECT/WITH queries are allowed (read-only).")
    if _MULTI_STMT.search(s):
        raise QueryError("Multiple statements are not allowed.")
    if _FORBIDDEN.search(s):
        raise QueryError("Query contains a forbidden (write/DDL) keyword.")
    validate_table_policy(s, allowed_tables=allowed_tables)
    return s


def check_sql_balance(sql: str) -> str | None:
    """Cheap pre-flight structural check for TRUNCATED generated SQL.

    The SQL writer occasionally runs out of tokens mid-CTE, producing SQL with an
    unclosed paren or string. BigQuery answers that with a paid round trip and an
    opaque "Expected ) but got end of script". Catching it locally lets the pipeline
    retry with a simplify instruction instead. Returns a reason string when the SQL is
    structurally broken, or None when it looks well formed.

    String literals and comments are skipped so an apostrophe inside a value or a
    paren inside a comment never trips the counter.
    """
    depth = 0
    i = 0
    n = len(sql)
    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""
        if ch == "-" and nxt == "-":
            j = sql.find("\n", i)
            i = n if j == -1 else j + 1
            continue
        if ch == "/" and nxt == "*":
            j = sql.find("*/", i + 2)
            if j == -1:
                return "unterminated block comment"
            i = j + 2
            continue
        if ch in ("'", '"', "`"):
            quote = ch
            j = i + 1
            while j < n:
                if sql[j] == "\\":
                    j += 2
                    continue
                if sql[j] == quote:
                    break
                j += 1
            if j >= n:
                return f"unterminated {quote} literal, the query looks cut off"
            i = j + 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                return "unbalanced parentheses (one ')' too many)"
        i += 1
    if depth > 0:
        return f"unbalanced parentheses ({depth} unclosed), the query looks cut off"

    tail = sql.rstrip().rstrip(";").rstrip()
    last = tail.rsplit(None, 1)[-1].upper() if tail else ""
    if last in {"SELECT", "FROM", "WHERE", "AND", "OR", "BY", "JOIN", "ON", "AS",
                "GROUP", "ORDER", "HAVING", "WITH", "CASE", "WHEN", "THEN", "ELSE",
                "LIMIT", "UNION", "OVER", "PARTITION", ","}:
        return f"query ends on the dangling keyword '{last}', it looks cut off"
    return None


def _ensure_limit(sql: str, limit: int) -> str:
    # add a LIMIT if the outermost query lacks one
    if re.search(r"\blimit\s+\d+\s*$", sql, re.IGNORECASE):
        return sql
    return f"{sql}\nLIMIT {limit}"


def dry_run(sql: str) -> int:
    client = get_client()
    cfg = bigquery.QueryJobConfig(dry_run=True, use_query_cache=False)
    job = client.query(sql, job_config=cfg)
    return int(job.total_bytes_processed or 0)


def run_query(
    sql: str,
    row_limit: int | None = None,
    allowed_tables: set[str] | list[str] | tuple[str, ...] | None = None,
) -> dict:
    """Validate -> dry-run cost check -> execute. Returns dict with rows/columns/meta."""
    limit = row_limit or config.DEFAULT_ROW_LIMIT
    clean = validate_sql(sql, allowed_tables=allowed_tables)
    # Catch truncated generations locally: a dry run would cost a round trip and come
    # back with an opaque parser error that the retry loop cannot act on.
    broken = check_sql_balance(clean)
    if broken:
        raise QueryError(
            f"Generated SQL is structurally invalid: {broken}. Rewrite it as a SIMPLER "
            f"query (fewer CTEs, no redundant subselects) that fits in one complete "
            f"statement."
        )
    had_outer_limit = bool(re.search(r"\blimit\s+\d+\s*$", clean, re.IGNORECASE))
    clean = _ensure_limit(clean, limit)

    from .query_cost import prepare_query
    clean, cost_notes = prepare_query(clean, get_client())
    budget = min(config.MAX_BYTES_BILLED, config.QUERY_SCAN_BUDGET_BYTES)

    # Cost estimate
    est_bytes = dry_run(clean)
    if est_bytes > budget:
        raise QueryError(
            f"Query would scan {est_bytes/1024**3:.1f} GB, exceeding the "
            f"{budget/1024**3:.1f} GB scan budget. "
            f"Add a tighter dt_id/month_id filter or narrower columns."
        )

    cfg = bigquery.QueryJobConfig(
        maximum_bytes_billed=budget,
        use_query_cache=True,
    )
    job = client = get_client().query(clean, job_config=cfg)
    result = job.result(timeout=config.QUERY_TIMEOUT_S)

    columns = [f.name for f in result.schema]
    rows = []
    for r in result:
        rows.append({c: r[c] for c in columns})

    # serialize-safe
    rows = json.loads(json.dumps(rows, default=_json_default))

    return {
        "sql": clean,
        "columns": columns,
        "rows": rows,
        "row_count": len(rows),
        "bytes_processed": int(job.total_bytes_processed or 0),
        "bytes_billed": int(job.total_bytes_billed or 0),
        "estimated_bytes": est_bytes,
        "scan_budget_bytes": budget,
        "cost_optimizations": cost_notes,
        "cache_hit": bool(job.cache_hit),
        "est_bytes": est_bytes,
        "limit_applied": not had_outer_limit,
        "row_limit": limit,
        "truncated": bool(not had_outer_limit and len(rows) >= limit),
    }
