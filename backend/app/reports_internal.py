"""Catalog-driven Internal network performance report.

The metric registry is a checked-in snapshot. Runtime code never imports or
reads the Technocom application. Aggregation happens from raw source columns so
ratios are always recomposed as ratio-of-sums at the requested scope.
"""
from __future__ import annotations

import ast
import json
import math
import re
from collections.abc import Iterable
from functools import lru_cache
from pathlib import Path
from typing import Any

from . import config
from .bigquery_tool import run_query

CONTRACT_VERSION = "network-report.v1"
_CATALOG_PATH = Path(__file__).resolve().parents[1] / "data" / "network_report_catalog.json"
_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET
_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_MONTH = re.compile(r"^\d{4}-\d{2}$")
_BRANDS = ("IOH", "TSEL", "XLSMART")
_SCAFFOLD_COLUMNS = (
    "total_revenue",
    "total_site_ioh",
    "rgu90d",
    "total_cell",
    "avail4g_num",
    "grossadd",
    "data_revenue",
)
_VALUE_TRANSFORMS = {
    "sum",
    "sum_coalesce",
    "sum_multi",
    "ratio_sum",
    "wavg",
    "avg",
    "derived",
    "cross_period",
    "count_distinct",
    "delta_prev",
    "ratio_prev_base",
    "mom_daily",
    "vat_window",
    "avg_mtd_cutover",
    "sum_mtd_cutover",
}


@lru_cache(maxsize=1)
def load_network_report_catalog() -> dict[str, Any]:
    """Load the immutable in-repository network report catalog."""
    payload = json.loads(_CATALOG_PATH.read_text(encoding="utf-8"))
    if payload.get("contract_version") != CONTRACT_VERSION:
        raise ValueError("unsupported network report catalog contract")
    if len(payload["pages"]["competitive"]["metrics"]) != 51:
        raise ValueError("competitive catalog must contain exactly 51 metrics")
    if len(payload["pages"]["internal"]["metrics"]) != 229:
        raise ValueError("internal catalog must contain exactly 229 metrics")
    if len(payload["pages"]["internal"]["sections"]) != 24:
        raise ValueError("internal catalog must contain 24 structural sections")
    return payload


def internal_catalog() -> dict[str, Any]:
    """Return the backend-owned metadata contract for route integration."""
    catalog = load_network_report_catalog()
    page = catalog["pages"]["internal"]
    return {
        "contract_version": catalog["contract_version"],
        "catalog_version": catalog["catalog_version"],
        "page_id": page["page_id"],
        "brands": catalog["brands"]["internal"],
        "domains": catalog["internal_domains"],
        "sections": page["sections"],
        "metrics": page["metrics"],
    }


def _safe_identifier(value: str) -> str:
    if not _IDENTIFIER.fullmatch(value):
        raise ValueError(f"unsafe identifier: {value!r}")
    return value


def _safe_text(value: str) -> str:
    return (value or "").replace("\\", "").replace("'", "").strip()


def _table(name: str) -> str:
    return f"`{_PROJECT}.{_DATASET}.{_safe_identifier(name)}`"


def _month_of(value: Any) -> str:
    text = str(value)
    if len(text) >= 7 and _MONTH.fullmatch(text[:7]):
        return text[:7]
    raise ValueError(f"invalid BigQuery period: {value!r}")


def _previous_month(month: str) -> str:
    year, number = (int(part) for part in month.split("-"))
    if number == 1:
        return f"{year - 1:04d}-12"
    return f"{year:04d}-{number - 1:02d}"


def _snapshot_map(table_name: str) -> dict[str, str]:
    sql = f"""
SELECT PARSE_DATE('%Y%m%d', partition_id) AS snapshot
FROM `{_PROJECT}.{_DATASET}.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = '{_safe_identifier(table_name)}'
  AND REGEXP_CONTAINS(partition_id, r'^\\d{{8}}$')
GROUP BY snapshot
ORDER BY snapshot
LIMIT 500
"""
    rows = run_query(sql, row_limit=500)["rows"]
    snapshots: dict[str, str] = {}
    for row in rows:
        snapshot = str(row.get("snapshot") or "")[:10]
        if len(snapshot) != 10:
            continue
        month = _month_of(snapshot)
        if month not in snapshots or snapshot > snapshots[month]:
            snapshots[month] = snapshot
    return snapshots


def _period_plan(
    snapshot_maps: Iterable[dict[str, str]], period_count: int
) -> tuple[list[str], str | None]:
    if period_count < 1 or period_count > 12:
        raise ValueError("period_count must be between 1 and 12")
    months = sorted({month for mapping in snapshot_maps for month in mapping})
    if not months:
        return [], None
    selected = [months[-1]]
    while len(selected) < period_count:
        selected.append(_previous_month(selected[-1]))
    selected.reverse()
    year = int(selected[-1][:4])
    december = f"{year - 1:04d}-12"
    return selected, december


def _scope_clause(
    source: str, circle: str, filter_type: str, filter_value: str
) -> str:
    aliases = {
        "rham_network_comp": {"circle": "circle", "region": "region", "kabkota": "kabkot_nm"},
        "rham_network_comp_kec": {
            "circle": "circle",
            "region": "region",
            "kabkota": "kabkot_nm",
            "kecamatan": "kec_id",
        },
        "rham_fb_network_kec_wly_wide": {
            "circle": "circle",
            "region": "region",
            "kabkota": "kabkot",
            "kecamatan": "kec_id",
        },
        "rham_network_internal": {
            "circle": "circle",
            "region": "region",
            "kabkota": "kabkot_nm",
        },
        "rham_network_internal_kec": {
            "circle": "circle",
            "region": "region",
            "kabkota": "kabkot_nm",
            "kecamatan": "kec_id",
        },
    }
    dimensions = aliases[source]
    normalized = {"kabkot": "kabkota", "all": "all", "": "all"}.get(
        filter_type or "all", filter_type
    )
    clauses: list[str] = []
    if circle and circle.strip().upper() != "ALL":
        clauses.append(f"`{dimensions['circle']}` = '{_safe_text(circle)}'")
    if normalized != "all" and filter_value:
        column = dimensions.get(normalized)
        if not column:
            raise ValueError(f"{normalized} is not supported by {source}")
        clauses.append(f"`{column}` = '{_safe_text(filter_value)}'")
    if source == "rham_network_comp":
        clauses.append("NOT (`kabkot_nm` = 'PURWAKARTA' AND `region` != 'WEST JAVA')")
    if source.startswith("rham_network_internal"):
        clauses.append("`kabkot_nm` IS NOT NULL")
    return " AND ".join(clauses) if clauses else "TRUE"


def _source_columns(metric: dict[str, Any]) -> list[str]:
    payload = metric.get("source_columns") or {}
    columns: list[str] = []
    for raw in (
        list(payload.get("columns") or [])
        + list(payload.get("numerator_columns") or [])
        + ([payload["prev_base_column"]] if payload.get("prev_base_column") else [])
    ):
        name = str(raw).lstrip("-")
        if name and name not in columns:
            columns.append(_safe_identifier(name))
    formula = payload.get("formula")
    if formula:
        _, names = _parse_formula(str(formula))
        for name in names:
            if name not in columns:
                columns.append(name)
    if metric.get("transform") in {"avg_mtd_cutover", "sum_mtd_cutover"} and columns:
        sibling = _mtd_variant(columns[0])
        if sibling not in columns:
            columns.append(sibling)
    return columns


def _mtd_variant(column: str) -> str:
    for suffix, replacement in (
        ("_ookla_lte", "_ookla_mtd_LTE"),
        ("_ookla_5G", "_ookla_mtd_5G"),
        ("_ookla", "_ookla_mtd"),
    ):
        if column.endswith(suffix):
            return column[: -len(suffix)] + replacement
    return f"{column}_mtd"


class _AggregatePlan:
    def __init__(self) -> None:
        self.atoms: dict[str, str] = {}
        self.keys: dict[str, str] = {}

    def add(self, key: str, expression: str) -> str:
        alias = self.keys.get(key)
        if alias is None:
            alias = f"a{len(self.atoms):04d}"
            self.keys[key] = alias
            self.atoms[alias] = expression
        return alias

    def sum(self, column: str) -> str:
        name = _safe_identifier(column)
        return self.add(f"sum:{name}", f"SUM(`{name}`)")

    def count(self, column: str) -> str:
        name = _safe_identifier(column)
        return self.add(f"count:{name}", f"COUNT(`{name}`)")

    def product(self, left: str, right: str) -> str:
        left, right = _safe_identifier(left), _safe_identifier(right)
        return self.add(f"product:{left}:{right}", f"SUM(`{left}` * `{right}`)")

    def multi(self, columns: list[str]) -> str:
        names = [_safe_identifier(column) for column in columns]
        expression = " + ".join(f"COALESCE(`{name}`, 0)" for name in names)
        return self.add("multi:" + ":".join(names), f"SUM({expression})")

    def distinct_kabkota(self) -> str:
        empty = " AND ".join(f"`{column}` IS NULL" for column in _SCAFFOLD_COLUMNS)
        return self.add(
            "distinct:kabkot_nm",
            f"COUNT(DISTINCT IF(NOT ({empty}), `kabkot_nm`, NULL))",
        )


_BINOPS = (ast.Add, ast.Sub, ast.Mult, ast.Div)
_UNARYOPS = (ast.UAdd, ast.USub)


def _parse_formula(expression: str) -> tuple[ast.Expression, tuple[str, ...]]:
    tree = ast.parse(expression, mode="eval")
    for node in ast.walk(tree):
        if isinstance(node, (ast.Expression, ast.Load, *_BINOPS, *_UNARYOPS)):
            continue
        if isinstance(node, ast.BinOp):
            if not isinstance(node.op, _BINOPS):
                raise ValueError("unsupported formula operator")
        elif isinstance(node, ast.UnaryOp):
            if not isinstance(node.op, _UNARYOPS):
                raise ValueError("unsupported formula unary operator")
        elif isinstance(node, ast.Call):
            if not (
                isinstance(node.func, ast.Name)
                and node.func.id == "mom"
                and len(node.args) == 1
                and isinstance(node.args[0], ast.Name)
            ):
                raise ValueError("only mom(column) is allowed in formulas")
        elif isinstance(node, ast.Name):
            _safe_identifier(node.id)
        elif isinstance(node, ast.Constant):
            if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
                raise ValueError("formula constants must be numeric")
        else:
            raise ValueError(f"unsupported formula node: {type(node).__name__}")
    names = {
        node.id
        for node in ast.walk(tree)
        if isinstance(node, ast.Name) and node.id not in {"mom", "days_in_month"}
    }
    return tree, tuple(sorted(names))


def _lag(expression: str, with_brand: bool) -> str:
    partition = "PARTITION BY brand " if with_brand else ""
    return f"LAG({expression}) OVER ({partition}ORDER BY period)"


def _adjacent(expression: str, with_brand: bool) -> str:
    previous_period = _lag("period", with_brand)
    return (
        f"CASE WHEN DATE_DIFF(period, {previous_period}, MONTH) = 1 "
        f"THEN {expression} ELSE NULL END"
    )


def _formula_sql(node: ast.AST, plan: _AggregatePlan, with_brand: bool) -> str:
    if isinstance(node, ast.Constant):
        return repr(float(node.value))
    if isinstance(node, ast.Name):
        if node.id == "days_in_month":
            return "EXTRACT(DAY FROM LAST_DAY(period))"
        return plan.sum(node.id)
    if isinstance(node, ast.Call):
        current = plan.sum(node.args[0].id)  # type: ignore[union-attr]
        previous = _lag(current, with_brand)
        return _adjacent(f"SAFE_DIVIDE({current} - {previous}, {previous})", with_brand)
    if isinstance(node, ast.UnaryOp):
        value = _formula_sql(node.operand, plan, with_brand)
        return value if isinstance(node.op, ast.UAdd) else f"(-({value}))"
    if isinstance(node, ast.BinOp):
        left = _formula_sql(node.left, plan, with_brand)
        right = _formula_sql(node.right, plan, with_brand)
        if isinstance(node.op, ast.Div):
            return f"SAFE_DIVIDE({left}, {right})"
        operator = {ast.Add: "+", ast.Sub: "-", ast.Mult: "*"}[type(node.op)]
        return f"({left} {operator} {right})"
    raise ValueError("unexpected formula node")


def _metric_sql(metric: dict[str, Any], plan: _AggregatePlan, with_brand: bool) -> str | None:
    transform = str(metric.get("transform") or "")
    if transform not in _VALUE_TRANSFORMS:
        return None
    payload = metric.get("source_columns") or {}
    columns = [str(column).lstrip("-") for column in payload.get("columns") or []]
    if transform in {"sum", "sum_coalesce"}:
        return plan.sum(columns[0])
    if transform == "sum_multi":
        return plan.multi(columns)
    if transform == "ratio_sum":
        return f"SAFE_DIVIDE({plan.sum(columns[0])}, {plan.sum(columns[1])})"
    if transform == "wavg":
        return f"SAFE_DIVIDE({plan.product(columns[0], columns[1])}, {plan.sum(columns[1])})"
    if transform == "avg":
        return f"SAFE_DIVIDE({plan.sum(columns[0])}, {plan.count(columns[0])})"
    if transform == "count_distinct":
        return plan.distinct_kabkota()
    if transform in {"derived", "cross_period"}:
        formula = payload.get("formula")
        if not formula:
            return None
        tree, _ = _parse_formula(str(formula))
        return _formula_sql(tree.body, plan, with_brand)
    if transform == "delta_prev":
        current = plan.sum(columns[0])
        return _adjacent(f"{current} - {_lag(current, with_brand)}", with_brand)
    if transform == "ratio_prev_base":
        terms: list[str] = []
        for raw in payload.get("numerator_columns") or []:
            signed = str(raw)
            atom = plan.sum(signed.lstrip("-"))
            terms.append(f"- {atom}" if signed.startswith("-") else f"+ {atom}")
        numerator = " ".join(terms).lstrip("+ ") or "NULL"
        base = plan.sum(str(payload["prev_base_column"]))
        return _adjacent(f"SAFE_DIVIDE({numerator}, {_lag(base, with_brand)})", with_brand)
    if transform == "mom_daily":
        current = plan.sum(columns[0])
        current_daily = f"SAFE_DIVIDE({current}, EXTRACT(DAY FROM LAST_DAY(period)))"
        previous_daily = (
            f"SAFE_DIVIDE({_lag(current, with_brand)}, "
            f"EXTRACT(DAY FROM LAST_DAY({_lag('period', with_brand)})))"
        )
        return _adjacent(
            f"SAFE_DIVIDE({current_daily} - {previous_daily}, {previous_daily})",
            with_brand,
        )
    if transform == "vat_window":
        current = plan.sum(columns[0])
        start = str(payload.get("vat_from") or "")
        end = str(payload.get("vat_until") or "")
        if not (_MONTH.fullmatch(start) and _MONTH.fullmatch(end)):
            return current
        rate = float(payload.get("vat_rate") or 1.0)
        value = (
            f"CASE WHEN FORMAT_DATE('%Y-%m', period) BETWEEN '{start}' AND '{end}' "
            f"THEN SAFE_DIVIDE({current}, {rate!r}) ELSE {current} END"
        )
        if payload.get("per_day"):
            value = f"SAFE_DIVIDE({value}, EXTRACT(DAY FROM LAST_DAY(period)))"
        return value
    if transform in {"avg_mtd_cutover", "sum_mtd_cutover"}:
        base = columns[0]
        mtd = _mtd_variant(base)
        start = str(payload.get("mtd_from") or "")
        if not _MONTH.fullmatch(start):
            return None
        base_value = plan.sum(base)
        mtd_value = plan.sum(mtd)
        if transform == "avg_mtd_cutover":
            base_value = f"SAFE_DIVIDE({base_value}, {plan.count(base)})"
            mtd_value = f"SAFE_DIVIDE({mtd_value}, {plan.count(mtd)})"
        return (
            f"CASE WHEN FORMAT_DATE('%Y-%m', period) >= '{start}' "
            f"THEN {mtd_value} ELSE {base_value} END"
        )
    return None


def _standard_query(
    source: str,
    date_column: str,
    metrics: list[dict[str, Any]],
    snapshots: list[str],
    scope_clause: str,
    *,
    with_brand: bool,
    distinct_source: bool = False,
) -> dict[tuple[str, str, str], float | None]:
    if not snapshots or not metrics:
        return {}
    plan = _AggregatePlan()
    expressions: dict[str, str] = {}
    for metric in metrics:
        expression = _metric_sql(metric, plan, with_brand)
        if expression:
            expressions[metric["metric_id"]] = expression
    if not expressions:
        return {}
    columns = sorted({column for metric in metrics for column in _source_columns(metric)})
    projected = {date_column, "kabkot_nm", *columns}
    if any(metric.get("transform") == "count_distinct" for metric in metrics):
        projected.update(_SCAFFOLD_COLUMNS)
    if with_brand:
        projected.add("brand")
    projection = ", ".join(f"`{_safe_identifier(column)}`" for column in sorted(projected))
    dates = ", ".join(f"DATE '{snapshot}'" for snapshot in snapshots)
    source_select = "SELECT DISTINCT" if distinct_source else "SELECT"
    brand_select = ", `brand` AS brand" if with_brand else ""
    brand_group = ", brand" if with_brand else ""
    atom_select = ",\n    ".join(f"{sql} AS {alias}" for alias, sql in plan.atoms.items())
    metric_select = ",\n  ".join(
        f"CAST({expression} AS FLOAT64) AS `{metric_id}`"
        for metric_id, expression in expressions.items()
    )
    sql = f"""
WITH source AS (
  {source_select} {projection}
  FROM {_table(source)}
  WHERE `{_safe_identifier(date_column)}` IN ({dates})
    AND {scope_clause}
), grouped AS (
  SELECT DATE_TRUNC(`{_safe_identifier(date_column)}`, MONTH) AS period{brand_select},
    {atom_select}
  FROM source
  GROUP BY period{brand_group}
)
SELECT period{brand_group},
  {metric_select}
FROM grouped
ORDER BY period{brand_group}
LIMIT 100
"""
    rows = run_query(sql, row_limit=100)["rows"]
    output: dict[tuple[str, str, str], float | None] = {}
    by_id = {metric["metric_id"]: metric for metric in metrics}
    for row in rows:
        period = _month_of(row.get("period"))
        brand = str(row.get("brand") or "IOH")
        if with_brand and brand not in _BRANDS:
            continue
        for metric_id, metric in by_id.items():
            value = _number(row.get(metric_id))
            scales = (metric.get("source_columns") or {}).get("brand_scale") or {}
            if value is not None:
                value *= float(scales.get(brand, 1.0))
                value *= float(metric.get("unit_scale") or 1.0)
            output[(metric_id, brand, period)] = value
    return output


def _number(value: Any) -> float | None:
    if value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _ranks(
    values: dict[tuple[str, str, str], float | None],
    metric: dict[str, Any],
    period: str,
) -> dict[str, int | None]:
    direction = metric.get("direction")
    if direction == "na":
        return {brand: None for brand in _BRANDS}
    present = {
        brand: values.get((metric["metric_id"], brand, period)) for brand in _BRANDS
    }
    ordered = sorted(
        ((brand, value) for brand, value in present.items() if value is not None),
        key=lambda item: (
            item[1] if direction == "lower_is_better" else -item[1],
            item[0],
        ),
    )
    result: dict[str, int | None] = {brand: None for brand in _BRANDS}
    previous: float | None = None
    previous_rank = 0
    for position, (brand, value) in enumerate(ordered, start=1):
        if previous is None or value != previous:
            previous_rank = position
            previous = value
        result[brand] = previous_rank
    return result


def _metric_payload(
    metric: dict[str, Any],
    values: dict[tuple[str, str, str], float | None],
    periods: list[str],
    basis: str | None,
    brands: tuple[str, ...],
) -> dict[str, Any]:
    series: dict[str, list[dict[str, Any]]] = {}
    comparison: dict[str, dict[str, Any]] = {}
    latest_period = periods[-1] if periods else None
    rank_by_period = {
        period: _ranks(values, metric, period) if len(brands) > 1 else {"IOH": None}
        for period in periods
    }
    for brand in brands:
        series[brand] = [
            {
                "period": period,
                "value": values.get((metric["metric_id"], brand, period)),
                "rank": rank_by_period[period].get(brand),
            }
            for period in periods
        ]
        latest = values.get((metric["metric_id"], brand, latest_period)) if latest_period else None
        base = values.get((metric["metric_id"], brand, basis)) if basis else None
        absolute = latest - base if latest is not None and base is not None else None
        percent = (
            absolute / abs(base) * 100
            if absolute is not None and base not in (None, 0)
            else None
        )
        comparison[brand] = {
            "basis_period": basis,
            "latest_period": latest_period,
            "basis_value": base,
            "latest_value": latest,
            "absolute": absolute,
            "percent": percent,
        }
    return {
        "metric_id": metric["metric_id"],
        "display_name": metric["display_name"],
        "uom": metric.get("uom"),
        "value_format": metric.get("value_format"),
        "direction": metric.get("direction"),
        "definition": metric.get("definition"),
        "transform": metric.get("transform"),
        "capabilities": metric.get("capabilities"),
        "availability": metric.get(
            "_served_availability",
            "available" if metric.get("transform") in _VALUE_TRANSFORMS else "unsupported",
        ),
        "served_source": metric.get("_served_source"),
        "unavailable_reason": metric.get("_unavailable_reason"),
        "series": series,
        "previous_december": comparison,
    }


def _sections_payload(
    page: dict[str, Any],
    values: dict[tuple[str, str, str], float | None],
    periods: list[str],
    basis: str | None,
    brands: tuple[str, ...],
) -> list[dict[str, Any]]:
    by_section: dict[str, list[dict[str, Any]]] = {}
    for metric in page["metrics"]:
        by_section.setdefault(metric["section_id"], []).append(metric)
    sections: list[dict[str, Any]] = []
    for section in page["sections"]:
        sections.append(
            {
                **section,
                "metrics": [
                    _metric_payload(metric, values, periods, basis, brands)
                    for metric in by_section.get(section["section_id"], [])
                ],
            }
        )
    return sections


def _snapshots_to_fetch(
    snapshots: dict[str, str], periods: list[str], basis: str | None
) -> list[str]:
    needed = set(periods)
    if basis:
        needed.add(basis)
    for period in list(needed):
        needed.add(_previous_month(period))
    return [snapshots[month] for month in sorted(needed) if month in snapshots]


def build_internal(
    circle: str,
    filter_type: str = "all",
    filter_value: str = "",
    period_count: int = 3,
) -> dict[str, Any]:
    """Build all 229 Internal metrics in 24 structural sections.

    Route-ready call signature:
    ``build_internal(circle, filter_type='all', filter_value='', period_count=3)``.
    Missing source periods and registry-unmapped metrics remain null.
    """
    catalog = load_network_report_catalog()
    source_page = catalog["pages"]["internal"]
    grain = "kecamatan" if filter_type == "kecamatan" else "kabkota"
    source = "rham_network_internal_kec" if grain == "kecamatan" else "rham_network_internal"
    page = {
        **source_page,
        "metrics": [
            {
                **metric,
                "_served_source": (
                    source if metric.get("transform") in _VALUE_TRANSFORMS else None
                ),
                "_served_availability": (
                    "available"
                    if metric.get("transform") in _VALUE_TRANSFORMS
                    else "unsupported"
                ),
                "_unavailable_reason": (
                    None
                    if metric.get("transform") in _VALUE_TRANSFORMS
                    else "Metric has no registry formula"
                ),
            }
            for metric in source_page["metrics"]
        ],
    }
    snapshots = _snapshot_map(source)
    periods, basis = _period_plan([snapshots], period_count)
    serveable = [
        metric for metric in page["metrics"] if metric.get("transform") in _VALUE_TRANSFORMS
    ]
    values = _standard_query(
        source,
        "dt_id",
        serveable,
        _snapshots_to_fetch(snapshots, periods, basis),
        _scope_clause(source, circle, filter_type, filter_value),
        with_brand=False,
    )
    return {
        "contract_version": catalog["contract_version"],
        "catalog_version": catalog["catalog_version"],
        "report": "internal",
        "page_id": page["page_id"],
        "scope": {
            "circle": circle,
            "filter_type": filter_type,
            "filter_value": filter_value,
            "served_grain": grain,
        },
        "brands": ["IOH"],
        "periods": periods,
        "comparison": {"kind": "previous_december_level", "basis_period": basis},
        "data_as_of": max(snapshots.values()) if snapshots else None,
        "domains": catalog["internal_domains"],
        "sections": _sections_payload(page, values, periods, basis, ("IOH",)),
    }
