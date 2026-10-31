"""Catalog-driven FWA Performance Outlook report.

The builder uses the dedicated FWA kecamatan sources and keeps all 64 verified
metrics reachable. It has no dependency on the Technocom application.
"""
from __future__ import annotations

import calendar
from typing import Any, Optional

from . import config, knowledge
from .bigquery_tool import run_query
from .territory import scope_column
from .report_formulas import (
    comparison_values,
    merge_bags,
    months_between,
    period_bag,
    project_flow_bag,
    shift_month_id,
)
from .report_metric_catalog import (
    CATALOG_SCHEMA_VERSION,
    FWA_METRICS,
    catalog_payload,
    categories,
    metric_fields,
)

_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET
_MTD = f"`{_PROJECT}.{_DATASET}.rham_fwa_kec_wise_mtd`"
_MTH = f"`{_PROJECT}.{_DATASET}.rham_fwa_kec_wise_mth`"
_TERR = f"`{_PROJECT}.{_DATASET}.rham_ref_territory`"

BRANDS = ("IOH", "IM3", "3ID")
COLUMNS = (
    "LLMTD",
    "LMTD",
    "MTD",
    "VAR",
    "VAR_PCT",
    "LYTD",
    "YTD",
    "VAR_YOY",
    "YOY_PCT",
)
_FIELDS = metric_fields(FWA_METRICS)


def _esc(value: str) -> str:
    return (value or "").replace("'", "")


def _validate_month(month_id: int | str) -> int:
    text = str(month_id)
    if len(text) != 6 or not text.isdigit() or not 1 <= int(text[4:]) <= 12:
        raise ValueError("month_id must use YYYYMM")
    return int(text)


def _territory_clause(circle: str, filter_type: str, filter_value: str) -> str:
    clauses: list[str] = []
    if (circle or "").strip().upper() != "ALL":
        clauses.append(f"t.circle='{_esc(circle)}'")
    column = scope_column(filter_type)
    if filter_value and column:
        clauses.append(f"{column}='{_esc(filter_value)}'")
    return " AND ".join(clauses) if clauses else "1=1"


def _source_state() -> tuple[int, str | None]:
    result = run_query(
        f"""
SELECT MAX(SAFE_CAST(month_id AS INT64)) AS month_id, MAX(dt_id) AS data_as_of
FROM {_MTD}
""",
        row_limit=2,
    )
    row = result["rows"][0] if result.get("rows") else {}
    month = row.get("month_id")
    if month is None:
        raise ValueError("FWA MTD source has no available month")
    stamp = row.get("data_as_of")
    return int(month), str(stamp)[:10] if stamp is not None else None


def _query_months(
    table: str,
    months: list[int],
    circle: str,
    filter_type: str,
    filter_value: str,
) -> list[dict[str, Any]]:
    if not months:
        return []
    available = {c['name'] for c in knowledge.table_index()[table.strip('`').split('.')[-1]]['columns']}
    selections = ",\n  ".join(
        f"SUM(SAFE_CAST(m.{field} AS FLOAT64)) AS {field}" if field in available
        else f"CAST(NULL AS FLOAT64) AS {field}" for field in _FIELDS
    )
    unique_months = sorted(set(months))
    month_values = ",".join(str(month) for month in unique_months)
    first_month, last_month = unique_months[0], unique_months[-1]
    start_date = f"{first_month // 100:04d}-{first_month % 100:02d}-01"
    last_day = calendar.monthrange(last_month // 100, last_month % 100)[1]
    end_date = f"{last_month // 100:04d}-{last_month % 100:02d}-{last_day:02d}"
    where = _territory_clause(circle, filter_type, filter_value)
    result = run_query(
        f"""
SELECT
  SAFE_CAST(m.month_id AS INT64) AS month_id,
  UPPER(m.brand) AS brand,
  MAX(m.dt_id) AS snapshot,
  {selections}
FROM {table} m
LEFT JOIN {_TERR} t ON m.kec_id=t.kec_id
WHERE SAFE_CAST(m.month_id AS INT64) IN ({month_values})
  AND m.mth_dt BETWEEN DATE('{start_date}') AND DATE('{end_date}')
  AND UPPER(m.brand) IN ('IM3','3ID')
  AND {where}
GROUP BY 1,2
ORDER BY 1,2
""",
        row_limit=max(20, len(months) * 3),
    )
    return result.get("rows", [])


def _index(rows: list[dict[str, Any]]) -> tuple[dict[str, dict[int, dict[str, float]]], str | None]:
    data: dict[str, dict[int, dict[str, float]]] = {"IM3": {}, "3ID": {}}
    latest: str | None = None
    for row in rows:
        brand = str(row.get("brand") or "").upper()
        month = row.get("month_id")
        if brand not in data or month is None:
            continue
        bag: dict[str, float] = {}
        for field in _FIELDS:
            value = row.get(field)
            if value is not None:
                bag[field] = float(value)
        data[brand][int(month)] = bag
        stamp = row.get("snapshot")
        if stamp is not None:
            stamp_text = str(stamp)[:10]
            latest = max(latest or stamp_text, stamp_text)
    return data, latest


def _with_ioh(data: dict[str, dict[int, dict[str, float]]]) -> None:
    month_ids = set(data.get("IM3", {})) | set(data.get("3ID", {}))
    data["IOH"] = {
        month: merge_bags(
            [data.get("IM3", {}).get(month, {}), data.get("3ID", {}).get(month, {})],
            _FIELDS,
        )
        for month in month_ids
    }


def _snapshot_day(stamp: str | None, month_id: int) -> int:
    if not stamp:
        return calendar.monthrange(month_id // 100, month_id % 100)[1]
    digits = "".join(character for character in stamp if character.isdigit())
    try:
        if len(digits) >= 8 and int(digits[:6]) == month_id:
            return int(digits[6:8])
    except ValueError:
        pass
    return calendar.monthrange(month_id // 100, month_id % 100)[1]


def _copy_data(
    source: dict[str, dict[int, dict[str, float]]],
) -> dict[str, dict[int, dict[str, float]]]:
    return {
        brand: {month: dict(bag) for month, bag in by_month.items()}
        for brand, by_month in source.items()
    }


def build_fwa(
    circle: str,
    month_id: Optional[int] = None,
    filter_type: str = "all",
    filter_value: str = "",
    basis: str = "mtd",
) -> dict[str, Any]:
    """Build the additive 64-metric FWA summary.

    Route call signature:
      build_fwa(circle, month_id, filter_type, filter_value, basis)

    ``basis='mtd'`` uses same-cutoff MTD comparison months. ``basis='monthly'``
    uses closed months and projects only flow fields when the selected month is
    still open.
    """
    if basis not in {"mtd", "monthly"}:
        raise ValueError("basis must be mtd or monthly")
    latest_month, source_as_of = _source_state()
    current = _validate_month(month_id if month_id is not None else latest_month)
    previous = shift_month_id(current, -1)
    previous_two = shift_month_id(current, -2)
    last_year = shift_month_id(current, -12)

    current_year = current // 100
    current_number = current % 100
    ytd_months = months_between(current_year * 100 + 1, current)
    lytd_months = months_between((current_year - 1) * 100 + 1, last_year)
    monthly_months = sorted(set(ytd_months + lytd_months + [previous, previous_two]))
    mtd_months = sorted({current, previous, previous_two, last_year})

    monthly_rows = _query_months(_MTH, monthly_months, circle, filter_type, filter_value)
    mtd_rows = _query_months(_MTD, mtd_months, circle, filter_type, filter_value)
    monthly, monthly_as_of = _index(monthly_rows)
    partial, mtd_as_of = _index(mtd_rows)
    _with_ioh(monthly)
    _with_ioh(partial)

    days_in_month = calendar.monthrange(current_year, current_number)[1]
    snapshot_day = _snapshot_day(mtd_as_of or source_as_of, current)
    is_open = current == latest_month and 0 < snapshot_day < days_in_month
    projection_factor = (
        days_in_month / snapshot_day
        if basis == "monthly" and is_open
        else 1.0
    )

    rows: list[dict[str, Any]] = []
    for metric in FWA_METRICS:
        brand_values: dict[str, dict[str, float | None]] = {}
        for brand in BRANDS:
            period_data = _copy_data({brand: monthly.get(brand, {})}).get(brand, {})
            partial_data = partial.get(brand, {})
            if basis == "mtd":
                comparison_data = partial_data
                current_bag = partial_data.get(current, {})
                prior_year_bag = partial_data.get(last_year, {})
                if current_bag:
                    period_data[current] = dict(current_bag)
                else:
                    period_data.pop(current, None)
                if prior_year_bag:
                    period_data[last_year] = dict(prior_year_bag)
                else:
                    period_data.pop(last_year, None)
                ytd_bag = (
                    period_bag(period_data, ytd_months, metric, _FIELDS)
                    if current_bag
                    else {}
                )
                lytd_bag = (
                    period_bag(period_data, lytd_months, metric, _FIELDS)
                    if prior_year_bag
                    else {}
                )
            else:
                if is_open and partial_data.get(current):
                    period_data[current] = project_flow_bag(
                        partial_data[current], FWA_METRICS, projection_factor
                    )
                comparison_data = period_data
                current_bag = period_data.get(current, {})
                ytd_bag = (
                    period_bag(period_data, ytd_months, metric, _FIELDS)
                    if current_bag
                    else {}
                )
                lytd_bag = period_bag(period_data, lytd_months, metric, _FIELDS)

            brand_values[brand] = comparison_values(
                metric,
                comparison_data.get(previous_two, {}),
                comparison_data.get(previous, {}),
                current_bag,
                lytd_bag,
                ytd_bag,
            )
        rows.append(
            {
                "id": metric.code,
                "code": metric.code,
                "label": metric.label,
                "name": metric.label,
                "category": metric.category,
                "unit": metric.unit,
                "kind": metric.kind,
                "format": metric.format,
                "temporal": metric.temporal,
                "source_grain": metric.source_grain,
                "brands": brand_values,
            }
        )

    section_rows = {
        category: [row for row in rows if row["category"] == category]
        for category in categories(FWA_METRICS)
    }
    latest_stamp = max(
        (stamp for stamp in (source_as_of, monthly_as_of, mtd_as_of) if stamp),
        default=None,
    )
    displayed_days = snapshot_day if basis == "mtd" else days_in_month
    return {
        "schema_version": CATALOG_SCHEMA_VERSION,
        "product": "fwa",
        "title": "FWA Summary",
        "basis": basis,
        "month_id": current,
        "columns": list(COLUMNS),
        "column_labels": {"VAR_PCT": "Growth", "YOY_PCT": "YoY"},
        "brands": list(BRANDS),
        "categories": list(section_rows),
        "catalog": catalog_payload("fwa"),
        "rows": rows,
        "sections": [
            {
                "title": category,
                "group": "FWA",
                "layout": "grid",
                "metrics": metrics,
            }
            for category, metrics in section_rows.items()
        ],
        "scope": {
            "circle": circle,
            "month_id": current,
            "filter_type": filter_type,
            "filter_value": filter_value,
            "source_grain": "kecamatan",
            "data_as_of": latest_stamp or "",
        },
        "day_count": {
            "MTD": displayed_days,
            "LMTD": displayed_days,
            "LLMTD": displayed_days,
            "YTD": sum(
                calendar.monthrange(current_year, month)[1]
                for month in range(1, current_number)
            ) + displayed_days,
            "LYTD": sum(
                calendar.monthrange(current_year - 1, month)[1]
                for month in range(1, current_number)
            ) + displayed_days,
        },
        "projection": {
            "factor": projection_factor,
            "snapshot_day": snapshot_day,
            "days_in_month": days_in_month,
            "is_partial": is_open,
        },
        "source": "rham_fwa_kec_wise_mth/mtd",
    }
