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

_FORBIDDEN = re.compile(
    r"\b(insert|update|delete|merge|drop|create|alter|truncate|grant|revoke|"
    r"call|export|load|replace)\b",
    re.IGNORECASE,
)
_MULTI_STMT = re.compile(r";\s*\S")  # semicolon followed by more content

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


def validate_sql(sql: str) -> str:
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
    return s


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


def run_query(sql: str, row_limit: int | None = None) -> dict:
    """Validate -> dry-run cost check -> execute. Returns dict with rows/columns/meta."""
    limit = row_limit or config.DEFAULT_ROW_LIMIT
    clean = validate_sql(sql)
    clean = _ensure_limit(clean, limit)

    # Cost estimate
    est_bytes = dry_run(clean)
    if est_bytes > config.MAX_BYTES_BILLED:
        raise QueryError(
            f"Query would scan {est_bytes/1024**3:.1f} GB, exceeding the "
            f"{config.MAX_BYTES_BILLED/1024**3:.0f} GB safety cap. "
            f"Add a tighter dt_id/month_id filter or narrower columns."
        )

    cfg = bigquery.QueryJobConfig(
        maximum_bytes_billed=config.MAX_BYTES_BILLED,
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
        "cache_hit": bool(job.cache_hit),
        "est_bytes": est_bytes,
    }
