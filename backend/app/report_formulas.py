"""Pure report arithmetic shared by catalog-driven report builders."""
from __future__ import annotations

import math
from collections.abc import Iterable, Mapping, Sequence
from typing import Any

from .report_metric_catalog import MetricSpec, metric_fields


def shift_month_id(month_id: int | str, offset: int) -> int:
    """Shift a YYYYMM value without breaking at year boundaries."""
    text = str(month_id)
    if len(text) != 6 or not text.isdigit() or not 1 <= int(text[4:]) <= 12:
        raise ValueError("month_id must use YYYYMM")
    year, month = int(text[:4]), int(text[4:])
    index = year * 12 + month - 1 + offset
    return (index // 12) * 100 + index % 12 + 1


def months_between(start: int | str, end: int | str) -> list[int]:
    first, last = int(start), int(end)
    if first > last:
        return []
    months: list[int] = []
    cursor = first
    while cursor <= last:
        months.append(cursor)
        cursor = shift_month_id(cursor, 1)
    return months


def finite_number(value: Any) -> float | None:
    if value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def safe_div(numerator: Any, denominator: Any, scale: float = 1.0) -> float | None:
    top, bottom = finite_number(numerator), finite_number(denominator)
    if top is None or bottom in (None, 0.0):
        return None
    value = top / bottom * scale
    return value if math.isfinite(value) else None


def safe_growth(current: Any, previous: Any) -> float | None:
    current_value, previous_value = finite_number(current), finite_number(previous)
    if current_value is None or previous_value in (None, 0.0):
        return None
    value = (current_value - previous_value) / abs(previous_value) * 100.0
    return value if math.isfinite(value) else None


def merge_bags(
    bags: Iterable[Mapping[str, Any]],
    fields: Iterable[str] | None = None,
) -> dict[str, float]:
    """Sum raw values while preserving a field that is missing everywhere."""
    materialized = list(bags)
    field_names = tuple(fields) if fields is not None else tuple(
        dict.fromkeys(field for bag in materialized for field in bag)
    )
    result: dict[str, float] = {}
    for field in field_names:
        values = [finite_number(bag.get(field)) for bag in materialized]
        present = [value for value in values if value is not None]
        if present:
            result[field] = sum(present)
    return result


def metric_value(metric: MetricSpec, bag: Mapping[str, Any]) -> float | None:
    if not bag:
        return None
    if metric.weight and metric.source:
        weighted = finite_number(bag.get(f"__weighted_{metric.code}"))
        return safe_div(weighted, bag.get(metric.weight), metric.scale)
    if metric.numerator:
        if metric.denominator_terms:
            terms = [finite_number(bag.get(field)) for field in metric.denominator_terms]
            denominator = None if not any(value is not None for value in terms) else sum(
                value or 0.0 for value in terms
            )
        else:
            denominator = bag.get(metric.denominator or "")
        return safe_div(bag.get(metric.numerator), denominator, metric.scale)
    if metric.source:
        value = finite_number(bag.get(metric.source))
        return value * metric.scale if value is not None else None
    return None


def period_bag(
    by_month: Mapping[int, Mapping[str, Any]],
    months: Sequence[int],
    metric: MetricSpec,
    fields: Iterable[str],
) -> dict[str, float]:
    available = [by_month[month] for month in months if month in by_month]
    if not available:
        return {}
    if metric.temporal == "last":
        return dict(available[-1])
    return merge_bags(available, fields)


def project_flow_bag(
    bag: Mapping[str, Any],
    metrics: Sequence[MetricSpec],
    factor: float,
) -> dict[str, float]:
    result = {
        field: value
        for field in metric_fields(metrics)
        if (value := finite_number(bag.get(field))) is not None
    }
    flow_fields = {
        metric.source
        for metric in metrics
        if metric.kind == "flow" and metric.source
    }
    for field in flow_fields:
        if field in result:
            result[field] *= factor
    return result


def comparison_values(
    metric: MetricSpec,
    llmtd: Mapping[str, Any],
    lmtd: Mapping[str, Any],
    mtd: Mapping[str, Any],
    lytd: Mapping[str, Any],
    ytd: Mapping[str, Any],
) -> dict[str, float | None]:
    ll_value = metric_value(metric, llmtd)
    lm_value = metric_value(metric, lmtd)
    current_value = metric_value(metric, mtd)
    lytd_value = metric_value(metric, lytd)
    ytd_value = metric_value(metric, ytd)
    variance = (
        current_value - lm_value
        if current_value is not None and lm_value is not None
        else None
    )
    yoy_variance = (
        ytd_value - lytd_value
        if ytd_value is not None and lytd_value is not None
        else None
    )
    growth = safe_growth(current_value, lm_value)
    yoy = safe_growth(ytd_value, lytd_value)
    return {
        "LLMTD": ll_value,
        "LMTD": lm_value,
        "MTD": current_value,
        "VAR": variance,
        "VAR_PCT": growth,
        "Growth": growth,
        "LYTD": lytd_value,
        "YTD": ytd_value,
        "VAR_YOY": yoy_variance,
        "YOY_PCT": yoy,
        "YoY": yoy,
    }
