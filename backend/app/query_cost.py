"""Semantics-preserving partition filters shared by every BigQuery consumer."""
import threading
import time
from datetime import date

import sqlglot
from sqlglot import exp
from sqlglot.optimizer.scope import traverse_scope

from . import config, knowledge

_cache = {}
_lock = threading.Lock()


def _parse(sql):
    return sqlglot.parse_one(sql, read="bigquery")


def _constant(node):
    return node is not None and not any(node.find_all(exp.Column, exp.Subquery, exp.Select, exp.AggFunc))


def _date_literal(value):
    return _parse(f"SELECT DATE '{value}'").expressions[0]


def _column(node):
    while isinstance(node, (exp.Cast, exp.Paren)):
        node = node.this
    return node if isinstance(node, exp.Column) else None


def _month(value):
    if not isinstance(value, exp.Literal):
        return None
    raw = str(value.this)
    if len(raw) != 6 or not raw.isdigit():
        return None
    try:
        return date(int(raw[:4]), int(raw[4:]), 1)
    except ValueError:
        return None


def _next_month(d):
    return date(d.year + (d.month == 12), d.month % 12 + 1, 1)


def _scope_nodes(scope, kind):
    return [n for n in scope.expression.find_all(kind) if n.find_ancestor(exp.Select) is scope.expression]


def _has_partition_filter(scope, alias, partition):
    """Each OR branch must contain a finite, constant period predicate."""
    where = scope.expression.args.get("where")
    physical = [s for s in scope.sources.values() if isinstance(s, exp.Table) and s.db]
    def matches(node):
        col = _column(node)
        return col is not None and col.name == partition and (
            col.table == alias or not col.table and len(physical) == 1)
    def bounded(node):
        if isinstance(node, exp.Paren):
            return bounded(node.this)
        if isinstance(node, exp.And):
            return bounded(node.this) or bounded(node.expression)
        if isinstance(node, exp.Or):
            return bounded(node.this) and bounded(node.expression)
        if isinstance(node, (exp.EQ, exp.GT, exp.GTE, exp.LT, exp.LTE)):
            return (matches(node.this) and _constant(node.expression) and not isinstance(node.expression, exp.Null)
                    or matches(node.expression) and _constant(node.this) and not isinstance(node.this, exp.Null))
        if isinstance(node, exp.Between):
            return matches(node.this) and all(_constant(node.args[k]) for k in ("low", "high"))
        if isinstance(node, exp.In) and not node.args.get("query"):
            return matches(node.this) and bool(node.expressions) and all(_constant(v) for v in node.expressions)
        return False
    return where is not None and bounded(where.this)


def _partition_bounds(scope, alias, table):
    """Derive a conservative partition range from an existing month predicate.

    The original month predicate remains, including OR/IN logic. Adding its
    outer date envelope cannot add rows or change the requested time window.
    """
    names = {c["name"] for c in table.get("columns", [])}
    partition = next((c["name"] for c in table.get("columns", []) if c.get("partition")), None)
    # A view has no partition of its own, yet a literal mth_dt still prunes the
    # partitioned base table it reads (33MB vs 4MB on the HVC serving views).
    if not partition and table.get("object_type") == "VIEW" and "mth_dt" in names:
        partition = "mth_dt"
    if not partition or partition == "month_id":
        return None
    period_column = next((c for c in ("month_id", "perf_month_id", "mth_id") if c in names), None)
    if not period_column or partition not in {"mth_dt", "month_start", "mth_date", "month_dt", "dt_id", "perf_dt_id"}:
        return None
    where = scope.expression.args.get("where")
    if where is None:
        return None
    def matching(node):
        col = _column(node)
        physical = [s for s in scope.sources.values() if isinstance(s, exp.Table) and s.db]
        return col is not None and col.name == period_column and (col.table == alias or not col.table and len(physical) == 1)
    def months(node):
        if isinstance(node, exp.Paren):
            return months(node.this)
        if isinstance(node, exp.And):
            return months(node.this) or months(node.expression)
        if isinstance(node, exp.Or):
            a, b = months(node.this), months(node.expression)
            return a + b if a and b else []
        if isinstance(node, exp.EQ):
            v = _month(node.expression) if matching(node.this) else _month(node.this) if matching(node.expression) else None
            return [v] if v else []
        if isinstance(node, exp.In) and matching(node.this) and not node.args.get("query"):
            vals = [_month(v) for v in node.expressions]
            return vals if vals and all(vals) else []
        if isinstance(node, exp.Between) and matching(node.this):
            vals = [_month(node.args["low"]), _month(node.args["high"])]
            return vals if all(vals) else []
        return []
    vals = months(where.this)
    col = exp.column(partition, table=alias if alias else None)
    if not vals:
        def range_bound(node):
            if isinstance(node, exp.Paren):
                return range_bound(node.this)
            if isinstance(node, exp.And):
                a, b = range_bound(node.this), range_bound(node.expression)
                if not a: return b
                if not b: return a
                return (max(v for v in (a[0], b[0]) if v) if a[0] or b[0] else None,
                        min(v for v in (a[1], b[1]) if v) if a[1] or b[1] else None)
            if isinstance(node, exp.Or):
                a, b = range_bound(node.this), range_bound(node.expression)
                if not a or not b: return None
                return (min(a[0], b[0]) if a[0] and b[0] else None,
                        max(a[1], b[1]) if a[1] and b[1] else None)
            if isinstance(node, (exp.GTE, exp.GT, exp.LTE, exp.LT)) and matching(node.this):
                value = _month(node.expression)
                if value:
                    return (value, None) if isinstance(node, (exp.GTE, exp.GT)) else (None, _next_month(value))
            return None
        limits = range_bound(where.this)
        if not limits or not any(limits):
            return None
        predicates = []
        if limits[0]: predicates.append(exp.GTE(this=col.copy(), expression=_date_literal(limits[0].isoformat())))
        if limits[1]: predicates.append(exp.LT(this=col.copy(), expression=_date_literal(limits[1].isoformat())))
        return exp.and_(*predicates)
    return exp.and_(exp.GTE(this=col.copy(), expression=_date_literal(min(vals).isoformat())),
                    exp.LT(this=col.copy(), expression=_date_literal(_next_month(max(vals)).isoformat())))


def _resolve_max(select, client):
    """Resolve only an independent single MAX aggregate, retaining its filters.

    Restrict the probe to the last populated physical partition only when the
    MAX is an unfiltered date/month field. Filtered MAX queries retain their
    complete original meaning and are allowed only within the metadata budget.
    """
    from google.cloud import bigquery
    from .bigquery_tool import QueryError

    if select.args.get("group") or select.args.get("having"):
        return None
    if len(select.expressions) > 1:
        items = []
        for item in select.expressions:
            clone = select.copy()
            clone.set("expressions", [item.copy()])
            resolved = _resolve_max(clone, client)
            if resolved is None:
                return None
            items.extend(resolved.expressions)
        return exp.select(*items)
    if not select.expressions:
        return None
    item = select.expressions[0]
    expression = item.this if isinstance(item, exp.Alias) else item
    outer_cast = expression if isinstance(expression, exp.Cast) else None
    aggregate = expression.this if outer_cast else expression
    if not isinstance(aggregate, exp.Max):
        return None
    col = _column(aggregate.this)
    tables = list(select.find_all(exp.Table))
    if not col or len(tables) != 1 or not tables[0].db or select.args.get("joins"):
        return None
    table = knowledge.table_index().get(tables[0].name, {})
    columns = {c["name"]: c for c in table.get("columns", [])}
    if col.name not in columns or not (col.name.endswith("dt") or col.name.startswith("dt_id") or "month" in col.name or col.name in ("mth_id", "mth_dt", "end_dt", "wk_end_dt")):
        return None
    if any(c.table and c.table != tables[0].alias_or_name for c in select.find_all(exp.Column)):
        return None  # correlated subquery
    key = select.sql(dialect="bigquery")
    with _lock:
        cached = _cache.get(key)
    if cached and cached[0] > time.monotonic():
        return cached[1].copy()
    probe = select.copy()
    partition = next((c["name"] for c in columns.values() if c.get("partition")), None)
    if partition and not select.args.get("where"):
        name = tables[0].name
        meta = f"SELECT MAX(partition_id) AS p FROM `{config.BQ_PROJECT}.{config.BQ_DATASET}.INFORMATION_SCHEMA.PARTITIONS` WHERE table_name='{name}' AND total_rows>0 AND partition_id NOT IN ('__NULL__','__UNPARTITIONED__')"
        job = client.query(meta, job_config=bigquery.QueryJobConfig(maximum_bytes_billed=config.METADATA_SCAN_BUDGET_BYTES, use_query_cache=True))
        rows = list(job.result(timeout=config.QUERY_TIMEOUT_S))
        pid = rows[0]["p"] if rows else None
        if pid and str(pid).isdigit() and len(str(pid)) in (6, 8):
            raw = str(pid)
            d = date(int(raw[:4]), int(raw[4:6]), int(raw[6:8]) if len(raw) == 8 else 1)
            from datetime import timedelta
            high = d + timedelta(days=1) if len(raw) == 8 else _next_month(d)
            probe.where(exp.and_(exp.GTE(this=exp.column(partition, table=tables[0].alias or None), expression=_date_literal(d.isoformat())),
                exp.LT(this=exp.column(partition, table=tables[0].alias or None), expression=_date_literal(high.isoformat()))), copy=False)
    probe_sql = probe.sql(dialect="bigquery")
    dry = client.query(probe_sql, job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False))
    if int(dry.total_bytes_processed or 0) > config.METADATA_SCAN_BUDGET_BYTES:
        raise QueryError(f"Latest-period lookup for {tables[0].name} exceeds the metadata scan budget. Supply a literal bounded partition filter.")
    job = client.query(probe_sql, job_config=bigquery.QueryJobConfig(maximum_bytes_billed=config.METADATA_SCAN_BUDGET_BYTES, use_query_cache=True))
    rows = list(job.result(timeout=config.QUERY_TIMEOUT_S))
    value = rows[0][0] if rows else None
    literal = exp.Null() if value is None else _date_literal(value.isoformat()) if isinstance(value, date) else exp.convert(value)
    if isinstance(aggregate.this, exp.Cast):
        literal = exp.Cast(this=literal, to=aggregate.this.args["to"].copy())
    if outer_cast:
        literal = exp.Cast(this=literal, to=outer_cast.args["to"].copy())
    result = exp.select(exp.alias_(literal, item.alias) if item.alias else literal)
    with _lock:
        _cache[key] = (time.monotonic() + config.LATEST_PERIOD_CACHE_TTL_S, result.copy())
    return result


def prepare_query(sql: str, client) -> tuple[str, list[str]]:
    """Add only proven equivalent bounds; reject expensive unbounded facts."""
    from .bigquery_tool import QueryError
    try:
        tree = _parse(sql)
    except sqlglot.errors.SqlglotError as exc:
        raise QueryError(f"Invalid BigQuery SQL: {exc}") from exc
    notes = []
    for select in reversed(list(tree.find_all(exp.Select))):
        resolved = _resolve_max(select, client)
        if resolved is not None:
            if select is tree:
                tree = resolved
            else:
                select.replace(resolved)
            notes.append("latest period resolved separately and cached")
    # Propagate constants from single-row CTEs, so MAX joins no longer force a
    # dynamic partition predicate. Keep the CTE and join cardinality unchanged.
    for _ in range(3):
        for scope in traverse_scope(tree):
            constants = {}
            for alias, source in scope.sources.items():
                if not isinstance(source, exp.Table) and isinstance(source.expression, exp.Select) and not source.expression.args.get("from_"):
                    constants[alias] = {e.alias_or_name: e.this if isinstance(e, exp.Alias) else e for e in source.expression.expressions if _constant(e.this if isinstance(e, exp.Alias) else e)}
            for col in _scope_nodes(scope, exp.Column):
                source = constants.get(col.table, {}) if col.table else next(iter(constants.values()), {}) if len(scope.sources) == 1 else {}
                if col.name in source:
                    col.replace(source[col.name].copy())
            if not scope.expression.args.get("from_") and len(scope.expression.expressions) == 1:
                e = scope.expression.expressions[0]
                e = e.this if isinstance(e, exp.Alias) else e
                sub = scope.expression.parent
                # Only a scalar operand may become a literal; a derived table
                # in FROM/JOIN must stay a relation, and IN takes a value list.
                if _constant(e) and isinstance(sub, exp.Subquery) and not isinstance(sub.parent, (exp.From, exp.Join)):
                    if isinstance(sub.parent, exp.In) and sub.parent.args.get("query") is sub:
                        sub.parent.set("query", None)
                        sub.parent.set("expressions", [e.copy()])
                    else:
                        sub.replace(e.copy())
    for scope in traverse_scope(tree):
        if not isinstance(scope.expression, exp.Select):
            continue
        # Constant predicates on inner joins are equivalent WHERE predicates.
        # Never push an outer-join predicate into WHERE: that would drop rows.
        for join in scope.expression.args.get("joins", []):
            if join.side or not join.args.get("on"):
                continue
            def atoms(node):
                if isinstance(node, exp.And):
                    return atoms(node.this) + atoms(node.expression)
                return [node]
            for atom in atoms(join.args["on"]):
                if isinstance(atom, exp.EQ) and (
                    _column(atom.this) is not None and _constant(atom.expression)
                    or _column(atom.expression) is not None and _constant(atom.this)
                ):
                    scope.expression.where(atom.copy(), append=True, copy=False)
        for alias, (_, source) in scope.selected_sources.items():
            if not isinstance(source, exp.Table) or not source.db:
                continue
            table = knowledge.table_index().get(source.name, {})
            bounds = _partition_bounds(scope, alias, table)
            if bounds is not None:
                if not source.alias:
                    source.set("alias", exp.TableAlias(this=exp.to_identifier(alias)))
                scope.expression.where(bounds, append=True, copy=False)
                notes.append(f"{source.name}: literal partition bounds")
            partition = next((c["name"] for c in table.get("columns", []) if c.get("partition")), None)
            # Static/small reference tables remain cheap. Large facts require
            # a period predicate on their own scan, even below the byte cap.
            if partition and table.get("cost_tier") in ("medium", "high", "very_high"):
                if not _has_partition_filter(scope, alias, partition):
                    raise QueryError(f"{source.name} needs a bounded WHERE filter on partition column {partition}. Use literal dates for the requested period; LIMIT does not reduce scan cost.")
    return tree.sql(dialect="bigquery"), list(dict.fromkeys(notes))
