"""Deterministic result profiling for grounded synthesis and QA."""
from __future__ import annotations

import re
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from .knowledge_graph import extract_sql_tables


_PERIOD_COLUMNS = (
    "dt_id", "as_of_date", "date", "month_start", "mth_dt", "month_id",
    "mth_id", "period", "snapshot_date", "dt_id_snapshot",
)


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float, Decimal)) and not isinstance(value, bool)


def _safe_min_max(values: list[Any]) -> dict[str, Any] | None:
    clean = [value for value in values if value is not None]
    if not clean:
        return None
    try:
        return {"min": min(clean), "max": max(clean)}
    except TypeError:
        text = [str(value) for value in clean]
        return {"min": min(text), "max": max(text)}


def profile_result(
    result: dict[str, Any],
    question: str = "",
    selected_tables: list[str] | None = None,
    table_contracts: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    rows = result.get("rows") or []
    columns = result.get("columns") or []
    row_count = int(result.get("row_count") or len(rows))
    truncated = bool(result.get("truncated"))
    sql = result.get("sql") or ""
    source_tables = sorted(extract_sql_tables(sql))
    if not source_tables:
        source_tables = sorted(set(selected_tables or []))

    null_counts: dict[str, int] = {}
    numeric_ranges: dict[str, dict[str, Any]] = {}
    period_cutoff: dict[str, Any] = {}
    for column in columns:
        values = [row.get(column) for row in rows]
        null_counts[column] = sum(value is None for value in values)
        numeric = [value for value in values if _is_number(value)]
        if numeric:
            limits = _safe_min_max(numeric)
            if limits:
                numeric_ranges[column] = limits
        if column.lower() in _PERIOD_COLUMNS:
            limits = _safe_min_max(values)
            if limits:
                period_cutoff[column] = limits.get("max")

    contracts = table_contracts or {}
    grains = sorted({
        str(contracts.get(name, {}).get("grain"))
        for name in source_tables
        if contracts.get(name, {}).get("grain")
    })
    period_bases = sorted({
        str(contracts.get(name, {}).get("period_semantics"))
        for name in source_tables
        if contracts.get(name, {}).get("period_semantics")
    })
    source_kinds = sorted({
        str(contracts.get(name, {}).get("source_kind"))
        for name in source_tables
        if contracts.get(name, {}).get("source_kind")
    })
    warning_columns = sorted({
        warning
        for name in source_tables
        for warning in (contracts.get(name, {}).get("warning_columns") or [])
        if warning in columns
    })

    warnings: list[str] = []
    if row_count == 0:
        status = "empty"
        warnings.append("Query returned no rows.")
    elif truncated:
        status = "warning"
        warnings.append("Result reached the row limit and may be incomplete.")
    else:
        status = "verified"
    if any(kind in {"modelled", "recommendation", "proxy"} for kind in source_kinds):
        status = "warning"
        warnings.append("Source includes proxy, modelled, or recommendation output.")
    if warning_columns:
        status = "warning"
        warnings.append("Interpretation warning columns are present and must remain visible.")

    # Only an OUTER ORDER BY establishes a verified ranking. An ORDER BY inside a CTE
    # or subquery says nothing about the order of the returned rows, and the synthesizer
    # is allowed to make ranking claims when this flag is true, so a false positive here
    # becomes a wrong "top N" in the answer.
    ranking_verified = bool(_has_outer_order_by(sql) and rows and not truncated)
    ordered_top = rows[:5] if ranking_verified else []
    ordered_bottom = rows[-5:] if ranking_verified and len(rows) > 5 else []

    # A result can be non-empty and still answer nothing: every metric column NULL, or
    # the ranking column NULL across the leading rows (BigQuery sorts NULLs first on
    # ASC, so a "worst N" query happily returns N rows of nothing). Treat both as
    # degenerate so the pipeline can refine instead of narrating emptiness.
    degenerate: list[str] = []
    if rows:
        metric_columns = [c for c in columns if c in numeric_ranges or null_counts.get(c, 0)]
        all_null = [c for c in metric_columns if null_counts.get(c, 0) == len(rows)]
        if all_null and len(all_null) == len(metric_columns):
            degenerate.append("every metric column is NULL in all returned rows")
        elif all_null:
            degenerate.append("all values are NULL in: " + ", ".join(sorted(all_null)[:6]))
        order_col = _order_by_column(sql)
        if order_col and order_col in columns:
            lead = rows[: min(5, len(rows))]
            if lead and all(r.get(order_col) is None for r in lead):
                degenerate.append(
                    f"the ranking column '{order_col}' is NULL in the leading rows, so the "
                    "ordering is meaningless")
                ranking_verified = False
                ordered_top = []
                ordered_bottom = []
    if degenerate:
        status = "warning" if status == "verified" else status
        warnings.extend(degenerate)

    return {
        "source_tables": source_tables,
        "source_kinds": source_kinds,
        "period_cutoff": period_cutoff or None,
        "grain": grains or None,
        "period_basis": period_bases or None,
        "row_count": row_count,
        "returned_rows": len(rows),
        "truncated": truncated,
        "profile": {
            "numeric_ranges": numeric_ranges,
            "null_counts": null_counts,
            "ranking_verified": ranking_verified,
            "ordered_top": ordered_top,
            "ordered_bottom": ordered_bottom,
        },
        "qa": {
            "status": status,
            "warnings": warnings,
            "warning_columns": warning_columns,
            "degenerate": degenerate,
        },
    }


def _strip_sql_noise(sql: str) -> str:
    """Blank out comments and string/backtick literals, preserving offsets.

    Keeps the text length identical so paren depth and match positions stay aligned
    with the original SQL.
    """
    out = list(sql)
    i = 0
    n = len(sql)
    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""
        if ch == "-" and nxt == "-":
            j = sql.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if ch == "/" and nxt == "*":
            j = sql.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                out[k] = " "
            i = j
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
            j = min(j, n - 1)
            for k in range(i, min(j + 1, n)):
                out[k] = " "
            i = j + 1
            continue
        i += 1
    return "".join(out)


def _outer_order_by_match(sql: str) -> re.Match | None:
    """The ORDER BY that actually orders the returned rows, or None.

    An ORDER BY nested inside a CTE or subquery does not determine the order of the
    final result, so only a match at paren depth zero counts.
    """
    clean = _strip_sql_noise(sql)
    depth = 0
    positions: dict[int, int] = {}
    for index, ch in enumerate(clean):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        positions[index] = depth
    last: re.Match | None = None
    for match in re.finditer(r"\border\s+by\s+", clean, re.IGNORECASE):
        if positions.get(match.start(), 0) == 0:
            last = match
    return last


def _has_outer_order_by(sql: str) -> bool:
    return _outer_order_by_match(sql) is not None


def _order_by_column(sql: str) -> str | None:
    """Name of the first OUTER ORDER BY column (None for positional ORDER BY 2)."""
    match = _outer_order_by_match(sql)
    if not match:
        return None
    tail = _strip_sql_noise(sql)[match.end():]
    name = re.match(r"([A-Za-z_][A-Za-z0-9_]*)", tail)
    return name.group(1) if name else None


def empty_result_hint(profile: dict, question: str = "") -> str | None:
    """A targeted retry instruction when a result is empty or degenerate.

    Returned to the SQL writer as a refine hint so the pipeline gets one grounded
    correction attempt instead of narrating a non-answer to the user.
    """
    qa = profile.get("qa") or {}
    degenerate = qa.get("degenerate") or []
    if profile.get("row_count", 0) == 0:
        return (
            "The previous query returned ZERO rows. Do not repeat it unchanged. Check, in "
            "this order: (1) the territory column and its vocabulary (a sales/region column "
            "is not the same as a province or kabkota column, and codes may carry a numeric "
            "prefix), (2) filter VALUES against the schema facts, including case and exact "
            "spelling, (3) the period filter (use the latest available period, not a "
            "hardcoded one). Rewrite the SQL with the corrected column or filter."
        )
    if degenerate:
        return (
            "The previous query returned rows but they do not answer the question: "
            + "; ".join(degenerate)
            + ". Rewrite the SQL so the metric is computed on rows that actually have data: "
              "join the funnel or component tables on their shared key, exclude rows where "
              "the ranking metric is NULL (or use a HAVING/WHERE guard on the denominator), "
              "and keep the ordering meaningful."
        )
    return None
