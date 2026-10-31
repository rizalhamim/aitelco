"""Canonical FWA metrics for one site.

The monthly tables already contain one row per site, brand, and month. Flow
metrics and snapshot metrics are therefore both aggregated across brands for
IOH, but never across months. Ratios are calculated only after that brand
aggregation so IOH percentages remain weighted and truthful.
"""
from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from . import config, knowledge
from .bigquery_tool import run_query
from .report_metric_catalog import FWA_METRICS

_P = config.BQ_PROJECT
_D = config.BQ_DATASET
_MTD = f"`{_P}.{_D}.rham_fwa_site_wise_mtd`"
_MTH = f"`{_P}.{_D}.rham_fwa_site_wise_mth`"


def _site_metric(metric) -> dict[str, Any]:
    payload = metric.as_dict()
    payload["catalog_format"] = payload["format"]
    payload["format"] = (
        "idr" if metric.unit in {"Rp", "B Rp"}
        else "pct" if metric.unit == "%"
        else "gb" if metric.unit == "GB"
        else "num0"
    )
    return payload


FWA_SITE_METRICS: tuple[dict[str, Any], ...] = tuple(
    _site_metric(metric) for metric in FWA_METRICS
)
_PHYSICAL = tuple(
    metric.source for metric in FWA_METRICS
    if metric.kind != "ratio" and metric.source
)


def _safe_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _month_shift(month_id: str, delta: int) -> str:
    year, month = int(month_id[:4]), int(month_id[4:6])
    absolute = year * 12 + month - 1 + delta
    return f"{absolute // 12:04d}{absolute % 12 + 1:02d}"


def _derive(row: dict[str, Any] | None) -> dict[str, float | None] | None:
    if not row:
        return None
    values = {code: _safe_float(row.get(code)) for code in _PHYSICAL}
    for metric in FWA_METRICS:
        if metric.kind != "ratio":
            continue
        numerator = values.get(metric.numerator or "")
        denominator = (
            sum(values.get(term) or 0.0 for term in metric.denominator_terms)
            if metric.denominator_terms
            else values.get(metric.denominator or "")
        )
        values[metric.code] = (
            numerator / denominator * metric.scale
            if numerator is not None and denominator not in (None, 0)
            else None
        )
    return values


def _brand_clause(brand: str) -> str:
    normalized = (brand or "ioh").lower()
    if normalized == "im3":
        return " AND brand='IM3'"
    if normalized in {"3id", "id3"}:
        return " AND brand='3ID'"
    return ""


def _select(columns: Iterable[str] = _PHYSICAL, table: str = _MTD) -> str:
    name = table.strip('`').split('.')[-1]
    available = {c['name'] for c in knowledge.table_index()[name]['columns']}
    return ", ".join(f"SUM({column}) AS {column}" if column in available
                     else f"CAST(NULL AS FLOAT64) AS {column}" for column in columns)


def build_site_fwa(site_id: str, brand: str = "ioh", months: int = 6) -> dict[str, Any]:
    """Return complete site-wise FWA MTD comparisons and closed-month history."""
    sid = (site_id or "").replace("'", "")
    clause = _brand_clause(brand)
    latest_rows = run_query(
        f"SELECT CAST(MAX(month_id) AS STRING) AS month_id FROM {_MTD}",
        row_limit=2,
    )["rows"]
    current_month = str(latest_rows[0].get("month_id") or "") if latest_rows else ""
    if len(current_month) != 6:
        return {
            "schema_version": "site-fwa.v1",
            "source": "rham_fwa_site_wise_mtd/mth",
            "available": False,
            "metrics": list(FWA_SITE_METRICS),
            "categories": [],
            "history": [],
        }

    periods = {
        "mtd": current_month,
        "lmtd": _month_shift(current_month, -1),
        "llmtd": _month_shift(current_month, -2),
        "lytd": _month_shift(current_month, -12),
    }
    wanted = ",".join(f"'{period}'" for period in periods.values())
    mtd_rows = run_query(
        f"SELECT CAST(month_id AS STRING) AS month_id, {_select()} FROM {_MTD} "
        f"WHERE site_id='{sid}'{clause} AND CAST(month_id AS STRING) IN ({wanted}) "
        "GROUP BY month_id ORDER BY month_id",
        row_limit=8,
    )["rows"]
    by_month = {str(row["month_id"]): _derive(row) for row in mtd_rows}

    history_months = ",".join(f"'{_month_shift(current_month, -i)}'" for i in range(1, max(1, min(int(months), 24)) + 1))
    history_rows = run_query(
        f"SELECT CAST(month_id AS STRING) AS month_id, {_select(table=_MTH)} FROM {_MTH} "
        f"WHERE site_id='{sid}'{clause} AND CAST(month_id AS STRING) IN ({history_months}) "
        "GROUP BY month_id ORDER BY month_id DESC "
        f"LIMIT {max(1, min(int(months), 24))}",
        row_limit=30,
    )["rows"]
    history = [
        {"month_id": str(row["month_id"]), **(_derive(row) or {})}
        for row in reversed(history_rows)
    ]

    period_values = {key: by_month.get(period) for key, period in periods.items()}
    rows: list[dict[str, Any]] = []
    categories: dict[str, list[dict[str, Any]]] = {}
    for metric in FWA_SITE_METRICS:
        code = metric["code"]
        mtd = (period_values["mtd"] or {}).get(code)
        lmtd = (period_values["lmtd"] or {}).get(code)
        lytd = (period_values["lytd"] or {}).get(code)
        growth = (
            (mtd - lmtd) / abs(lmtd) * 100.0
            if mtd is not None and lmtd not in (None, 0)
            else None
        )
        yoy = (
            (mtd - lytd) / abs(lytd) * 100.0
            if mtd is not None and lytd not in (None, 0)
            else None
        )
        item = {
            **metric,
            "mtd": mtd,
            "lmtd": lmtd,
            "llmtd": (period_values["llmtd"] or {}).get(code),
            "lytd": lytd,
            "growth": growth,
            "yoy": yoy,
        }
        rows.append(item)
        categories.setdefault(metric["category"], []).append(item)

    return {
        "schema_version": "site-fwa.v1",
        "source": "rham_fwa_site_wise_mtd/mth",
        "available": True,
        "month_id": current_month,
        "periods": periods,
        "brand": brand,
        "metrics": list(FWA_SITE_METRICS),
        "rows": rows,
        "categories": [
            {"name": name, "rows": category_rows}
            for name, category_rows in categories.items()
        ],
        "history": history,
        "formula_notes": {
            "period": "MTD comparisons use the cutoff-capped MTD table. History uses closed months from MTH.",
            "ioh": "IOH sums IM3 and 3ID source values before recalculating ratios.",
            "traffic_share": "5G traffic divided by 4G plus 5G traffic.",
            "unavailable": "Legacy acquisition breakdown columns absent from the current source remain N/A, never zero or a fabricated split.",
        },
    }
