"""Additive FTTH executive summary from the verified kecamatan sources."""
from __future__ import annotations

from typing import Any, Optional

from . import config
from .bigquery_tool import run_query
from .report_formulas import (
    comparison_values,
    months_between,
    period_bag,
    shift_month_id,
)
from .report_metric_catalog import (
    CATALOG_SCHEMA_VERSION,
    FTTH_METRICS,
    catalog_payload,
    categories,
    metric_fields,
)

_P = config.BQ_PROJECT
_D = config.BQ_DATASET
_MTD = f"`{_P}.{_D}.rham_ftth_kec_wise_mtd`"
_MTH = f"`{_P}.{_D}.rham_ftth_kec_wise_mth`"
_FIELDS = metric_fields(FTTH_METRICS)


def _esc(value: str) -> str:
    return (value or "").replace("'", "")


def _scope_clause(circle: str, filter_type: str, filter_value: str) -> str:
    clauses: list[str] = []
    if (circle or "").strip().upper() != "ALL":
        clauses.append(f"UPPER(circle)=UPPER('{_esc(circle)}')")
    value = _esc(filter_value)
    if value:
        column = {
            "region": "region_circle",
            "ftth_region": "region_circle",
            "area": "area",
            "branch": "branch",
            "kabkota": "kabkot",
            "ftth_kabkota": "kabkot",
        }.get(filter_type)
        if column:
            clauses.append(f"UPPER({column})=UPPER('{value}')")
        elif filter_type in {"kecamatan", "ftth_kecamatan"}:
            bare = value.split("|", 1)[0]
            clauses.append(
                f"(UPPER(kec_id)=UPPER('{value}') OR "
                f"UPPER(kecamatan)=UPPER('{bare}'))"
            )
    return " AND ".join(clauses) if clauses else "1=1"


def _selections() -> str:
    fields = [
        f"SUM(SAFE_CAST({field} AS FLOAT64)) AS {field}"
        for field in _FIELDS
    ]
    fields.extend(
        f"SUM(SAFE_CAST({metric.source} AS FLOAT64) * "
        f"SAFE_CAST({metric.weight} AS FLOAT64)) AS __weighted_{metric.code}"
        for metric in FTTH_METRICS
        if metric.source and metric.weight
    )
    return ",\n  ".join(fields)


def _query(table: str, month_ids: list[int], circle: str,
           filter_type: str, filter_value: str) -> list[dict[str, Any]]:
    if not month_ids:
        return []
    months_sql = ",".join(str(month) for month in sorted(set(month_ids)))
    result = run_query(
        f"""
SELECT SAFE_CAST(month_id AS INT64) AS month_id,
  MAX(dt_id) AS snapshot,
  {_selections()}
FROM {table}
WHERE SAFE_CAST(month_id AS INT64) IN ({months_sql})
  AND {_scope_clause(circle, filter_type, filter_value)}
GROUP BY 1
ORDER BY 1
""",
        row_limit=max(20, len(month_ids) + 5),
    )
    return result.get("rows", [])


def _index(rows: list[dict[str, Any]]) -> tuple[dict[int, dict[str, float]], str | None]:
    by_month: dict[int, dict[str, float]] = {}
    latest: str | None = None
    bag_fields = list(_FIELDS) + [
        f"__weighted_{metric.code}"
        for metric in FTTH_METRICS
        if metric.weight
    ]
    for row in rows:
        month = row.get("month_id")
        if month is None:
            continue
        bag: dict[str, float] = {}
        for field in bag_fields:
            value = row.get(field)
            if value is not None:
                bag[field] = float(value)
        by_month[int(month)] = bag
        if row.get("snapshot") is not None:
            stamp = str(row["snapshot"])[:10]
            latest = max(latest or stamp, stamp)
    return by_month, latest


def _latest_month() -> tuple[int, str | None]:
    result = run_query(
        f"SELECT MAX(SAFE_CAST(month_id AS INT64)) AS month_id, "
        f"MAX(dt_id) AS snapshot FROM {_MTD}",
        row_limit=2,
    )
    row = result.get("rows", [{}])[0]
    if row.get("month_id") is None:
        raise ValueError("FTTH summary source has no available month")
    return int(row["month_id"]), (
        str(row["snapshot"])[:10] if row.get("snapshot") is not None else None
    )


def build_ftth_summary(
    circle: str,
    month_id: Optional[int] = None,
    filter_type: str = "all",
    filter_value: str = "",
) -> dict[str, Any]:
    """Build all 14 FTTH Summary metrics without changing the legacy report."""
    latest, source_as_of = _latest_month()
    current = int(month_id or latest)
    previous = shift_month_id(current, -1)
    previous_two = shift_month_id(current, -2)
    last_year = shift_month_id(current, -12)
    current_year = current // 100
    closed_current = months_between(current_year * 100 + 1, previous)
    closed_last_year = months_between((current_year - 1) * 100 + 1,
                                      shift_month_id(last_year, -1))
    monthly_rows = _query(
        _MTH,
        closed_current + closed_last_year,
        circle,
        filter_type,
        filter_value,
    )
    partial_rows = _query(
        _MTD,
        [current, previous, previous_two, last_year],
        circle,
        filter_type,
        filter_value,
    )
    monthly, monthly_as_of = _index(monthly_rows)
    partial, mtd_as_of = _index(partial_rows)
    ytd_source = dict(monthly)
    if current in partial:
        ytd_source[current] = partial[current]
    if last_year in partial:
        ytd_source[last_year] = partial[last_year]
    ytd_months = closed_current + [current]
    lytd_months = closed_last_year + [last_year]

    rows: list[dict[str, Any]] = []
    for metric in FTTH_METRICS:
        values = comparison_values(
            metric,
            partial.get(previous_two, {}),
            partial.get(previous, {}),
            partial.get(current, {}),
            period_bag(ytd_source, lytd_months, metric, _FIELDS),
            period_bag(ytd_source, ytd_months, metric, _FIELDS),
        )
        rows.append({
            **metric.as_dict(),
            **values,
            "brands": {"FTTH": values},
        })

    return {
        "schema_version": f"ftth-summary.v{CATALOG_SCHEMA_VERSION}",
        "title": "FTTH Executive Summary",
        "source": "rham_ftth_kec_wise_mtd/mth",
        "month_id": current,
        "data_as_of": mtd_as_of or monthly_as_of or source_as_of,
        "scope": {
            "circle": circle,
            "filter_type": filter_type,
            "filter_value": filter_value,
        },
        "columns": [
            "LLMTD", "LMTD", "MTD", "VAR", "VAR_PCT",
            "LYTD", "YTD", "VAR_YOY", "YOY_PCT",
        ],
        "brands": ["FTTH"],
        "catalog": catalog_payload("ftth"),
        "rows": rows,
        "sections": [
            {
                "title": category,
                "rows": [row for row in rows if row["category"] == category],
            }
            for category in categories(FTTH_METRICS)
        ],
        "formula_notes": {
            "flow": "YTD uses closed full months plus current MTD.",
            "snapshot": "Snapshot metrics use the latest point in each comparison window.",
            "weighted": "Rates and ARPU are weighted from numerator support fields and are never summed.",
        },
    }
