"""Headline numbers for the Tanya Agent answer card (Redesign v2, mockup 02).

Deterministic, no LLM call. Given a query result and its chart spec (chart_spec.suggest),
return up to three cards:

    {"column", "label", "value", "format", "prev", "delta", "delta_unit", "vs", "spark"}

- Time series (x is a period, no series split, at least 2 rows): value is the latest
  period, delta compares it with the period before (percent change, or percentage points
  for percent metrics), spark is the last 6 values in time order.
- A single row: each metric as a plain card without delta or spark.
- Anything else (rankings, breakdowns by region): no cards. The chart and table carry it,
  and a "latest value" there would not mean anything.
"""
from __future__ import annotations

from typing import Any

from . import chart_spec

MAX_CARDS = 3
SPARK_POINTS = 6


def _num(v: Any) -> float | None:
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return None


def headline(columns: list[str], rows: list[dict], spec: dict | None) -> list[dict]:
    if not rows or not spec or spec.get("type") == "none":
        return []
    formats = spec.get("formats") or {}
    metrics = [c for c in list(spec.get("y") or []) + list(spec.get("y2") or []) if c in columns]
    if not metrics:
        return []
    metrics = metrics[:MAX_CARDS]

    if len(rows) == 1:
        out = []
        for c in metrics:
            v = _num(rows[0].get(c))
            if v is None:
                continue
            out.append({"column": c, "label": chart_spec._humanize(c), "value": v,
                        "format": formats.get(c, "number"), "prev": None, "delta": None,
                        "delta_unit": None, "vs": None, "spark": []})
        return out

    x = spec.get("x")
    if not x or spec.get("series_by") or spec.get("type") not in ("line", "area", "bar", "combo", "kpi"):
        return []
    kinds = chart_spec._classify(columns, rows)
    if kinds.get(x) != "time":
        return []
    ordered = sorted((r for r in rows if r.get(x) is not None), key=lambda r: str(r.get(x)))
    if len(ordered) < 2:
        return []
    last, prev = ordered[-1], ordered[-2]
    out = []
    for c in metrics:
        v, p = _num(last.get(c)), _num(prev.get(c))
        if v is None:
            continue
        fmt = formats.get(c, "number")
        delta, unit = None, None
        if p is not None:
            if fmt == "percent":
                scale = 100.0 if max(abs(v), abs(p)) <= 1 else 1.0
                delta, unit = round((v - p) * scale, 2), "pp"
            elif p != 0:
                delta, unit = round((v - p) / abs(p) * 100, 2), "%"
        spark = [s for s in (_num(r.get(c)) for r in ordered[-SPARK_POINTS:]) if s is not None]
        out.append({"column": c, "label": chart_spec._humanize(c), "value": v, "format": fmt,
                    "prev": p, "delta": delta, "delta_unit": unit, "vs": str(prev.get(x)),
                    "spark": spark if len(spark) >= 2 else []})
    return out


def safe_headline(columns: list[str], rows: list[dict], spec: dict | None) -> list[dict]:
    """headline() for the chat stream: a bad value must never break the answer."""
    try:
        return headline(columns, rows, spec)
    except Exception:  # noqa: BLE001
        return []
