"""Catalog-driven three-operator Competitive network report.

Kabkota values come from ``rham_network_comp``. Kecamatan queries are routed
per metric to the verified Facebook or OpenSignal source. Ookla and unsupported
Facebook measures remain present in the contract with null values and a clear
reason instead of being silently estimated.
"""
from __future__ import annotations

from typing import Any

from .bigquery_tool import run_query
from .reports_internal import (
    _BRANDS,
    _DATASET,
    _PROJECT,
    _VALUE_TRANSFORMS,
    _month_of,
    _number,
    _period_plan,
    _safe_identifier,
    _scope_clause,
    _sections_payload,
    _snapshot_map,
    _snapshots_to_fetch,
    _standard_query,
    _table,
    load_network_report_catalog,
)


def competitive_catalog() -> dict[str, Any]:
    """Return the backend-owned metadata contract for route integration."""
    catalog = load_network_report_catalog()
    page = catalog["pages"]["competitive"]
    return {
        "contract_version": catalog["contract_version"],
        "catalog_version": catalog["catalog_version"],
        "page_id": page["page_id"],
        "brands": catalog["brands"]["competitive"],
        "sections": page["sections"],
        "metrics": page["metrics"],
    }


def _fb_metric_shape(metric: dict[str, Any]) -> tuple[list[str], str | None]:
    section = int(metric["section_order"])
    order = int(metric["metric_order"])
    techs = ["4g", "5g"] if section == 1 else ["4g"] if section == 2 else ["5g"]
    if order == 1:
        return techs, "sample"
    if order == 2:
        return techs, "dl_speed"
    if order == 3:
        return techs, "latency"
    signal_order = 5 if section == 3 else 6
    if order == signal_order:
        return techs, "signal"
    return techs, None


def _fb_value_expression(metric: dict[str, Any], operators: tuple[str, ...]) -> str | None:
    techs, measure = _fb_metric_shape(metric)
    if measure is None:
        return None
    sample_columns = [f"sample_{operator}_{tech}" for operator in operators for tech in techs]
    if measure == "sample":
        return "SUM(" + " + ".join(
            f"COALESCE(`{_safe_identifier(column)}`, 0)" for column in sample_columns
        ) + ")"
    numerator: list[str] = []
    denominator: list[str] = []
    for operator in operators:
        for tech in techs:
            value = _safe_identifier(f"{measure}_{operator}_{tech}")
            sample = _safe_identifier(f"sample_{operator}_{tech}")
            numerator.append(
                f"IF(`{value}` IS NULL OR `{sample}` IS NULL, NULL, `{value}` * `{sample}`)"
            )
            denominator.append(f"IF(`{value}` IS NULL, NULL, `{sample}`)")
    return (
        "SAFE_DIVIDE(SUM(" + " + ".join(numerator) + "), SUM(" + " + ".join(denominator) + "))"
    )


def _facebook_query(
    metrics: list[dict[str, Any]], snapshots: list[str], scope_clause: str
) -> dict[tuple[str, str, str], float | None]:
    if not snapshots or not metrics:
        return {}
    operators = {
        "IOH": ("im3", "tri"),
        "TSEL": ("tsel",),
        "XLSMART": ("xl", "sf"),
    }
    fields = {"wk_end_dt"}
    for metric in metrics:
        techs, measure = _fb_metric_shape(metric)
        if measure is None:
            continue
        for members in operators.values():
            for operator in members:
                for tech in techs:
                    fields.add(f"sample_{operator}_{tech}")
                    if measure != "sample":
                        fields.add(f"{measure}_{operator}_{tech}")
    dates = ", ".join(f"DATE '{snapshot}'" for snapshot in snapshots)
    projection = ", ".join(f"`{_safe_identifier(field)}`" for field in sorted(fields))
    blocks: list[str] = []
    for brand, members in operators.items():
        metric_columns = []
        for metric in metrics:
            expression = _fb_value_expression(metric, members)
            if expression:
                metric_columns.append(
                    f"CAST({expression} AS FLOAT64) AS `{_safe_identifier(metric['metric_id'])}`"
                )
        blocks.append(
            "SELECT DATE_TRUNC(`wk_end_dt`, MONTH) AS period, "
            f"'{brand}' AS brand, "
            + ", ".join(metric_columns)
            + " FROM source GROUP BY period"
        )
    sql = f"""
WITH source AS (
  SELECT {projection}
  FROM {_table('rham_fb_network_kec_wly_wide')}
  WHERE `wk_end_dt` IN ({dates})
    AND {scope_clause}
)
{chr(10).join('UNION ALL\n' + block if index else block for index, block in enumerate(blocks))}
ORDER BY period, brand
LIMIT 100
"""
    rows = run_query(sql, row_limit=100)["rows"]
    output: dict[tuple[str, str, str], float | None] = {}
    for row in rows:
        period = _month_of(row.get("period"))
        brand = str(row.get("brand") or "")
        if brand not in _BRANDS:
            continue
        for metric in metrics:
            value = _number(row.get(metric["metric_id"]))
            if value is not None:
                value *= float(metric.get("unit_scale") or 1.0)
            output[(metric["metric_id"], brand, period)] = value
    return output


def _served_page(page: dict[str, Any], grain: str) -> dict[str, Any]:
    metrics: list[dict[str, Any]] = []
    for source in page["metrics"]:
        metric = dict(source)
        capability = metric.get("capabilities", {}).get(grain, {})
        available = bool(capability.get("available"))
        metric["_served_availability"] = "available" if available else "unsupported"
        metric["_served_source"] = capability.get("source")
        metric["_unavailable_reason"] = capability.get("reason")
        metrics.append(metric)
    return {**page, "metrics": metrics}


def build_competitive(
    circle: str,
    filter_type: str = "all",
    filter_value: str = "",
    period_count: int = 3,
) -> dict[str, Any]:
    """Build the 51-metric Competitive report with per-metric grain truth.

    Route-ready call signature:
    ``build_competitive(circle, filter_type='all', filter_value='', period_count=3)``.
    """
    catalog = load_network_report_catalog()
    source_page = catalog["pages"]["competitive"]
    grain = "kecamatan" if filter_type == "kecamatan" else "kabkota"
    page = _served_page(source_page, grain)
    values: dict[tuple[str, str, str], float | None] = {}
    data_as_of: dict[str, str | None] = {}

    if grain == "kabkota":
        source = "rham_network_comp"
        snapshots = _snapshot_map(source)
        periods, basis = _period_plan([snapshots], period_count)
        values.update(
            _standard_query(
                source,
                "dt_id",
                [metric for metric in page["metrics"] if metric["_served_availability"] == "available"],
                _snapshots_to_fetch(snapshots, periods, basis),
                _scope_clause(source, circle, filter_type, filter_value),
                with_brand=True,
                distinct_source=True,
            )
        )
        data_as_of[source] = max(snapshots.values()) if snapshots else None
    else:
        facebook = [
            metric
            for metric in page["metrics"]
            if metric.get("_served_source") == "rham_fb_network_kec_wly_wide"
        ]
        opensignal = [
            metric
            for metric in page["metrics"]
            if metric.get("_served_source") == "rham_network_comp_kec"
        ]
        fb_snapshots = _snapshot_map("rham_fb_network_kec_wly_wide")
        os_snapshots = _snapshot_map("rham_network_comp_kec")
        periods, basis = _period_plan([fb_snapshots, os_snapshots], period_count)
        values.update(
            _facebook_query(
                facebook,
                _snapshots_to_fetch(fb_snapshots, periods, basis),
                _scope_clause(
                    "rham_fb_network_kec_wly_wide", circle, filter_type, filter_value
                ),
            )
        )
        values.update(
            _standard_query(
                "rham_network_comp_kec",
                "dt_id",
                opensignal,
                _snapshots_to_fetch(os_snapshots, periods, basis),
                _scope_clause("rham_network_comp_kec", circle, filter_type, filter_value),
                with_brand=True,
            )
        )
        data_as_of["rham_fb_network_kec_wly_wide"] = (
            max(fb_snapshots.values()) if fb_snapshots else None
        )
        data_as_of["rham_network_comp_kec"] = (
            max(os_snapshots.values()) if os_snapshots else None
        )

    return {
        "contract_version": catalog["contract_version"],
        "catalog_version": catalog["catalog_version"],
        "report": "competitive",
        "page_id": page["page_id"],
        "scope": {
            "circle": circle,
            "filter_type": filter_type,
            "filter_value": filter_value,
            "served_grain": grain,
        },
        "brands": list(_BRANDS),
        "periods": periods,
        "comparison": {"kind": "previous_december_level", "basis_period": basis},
        "data_as_of": data_as_of,
        "sections": _sections_payload(page, values, periods, basis, _BRANDS),
    }

