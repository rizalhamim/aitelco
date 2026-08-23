"""Deterministic classification of a query result into a chart render spec.

Same contract as `map_synth_agent.detect_map_spec`: the backend decides WHAT to draw,
the clients only draw it. That keeps web and mobile identical and makes the decision
testable, which a heuristic living in TypeScript and Dart never was.

The problem this solves: the clients previously split columns into "numeric" and
"not numeric" and plotted the FIRST numeric column. On real result shapes that draws
the wrong thing, because a column's type says nothing about its meaning:

    rank, kecamatan, revenue_mn, share_pct   -> plotted `rank` (1, 2, 3 ...)
    kabkota, total_revenue, growth_pct       -> billions and percents on one axis
    month_id, kabkota, revenue               -> month_id 202608 treated as a value

So the unit of work here is the column ROLE, not the column type. The vocabulary below
was derived from the output aliases of the last 400 successful production queries, not
invented: 21 percent of results carry a currency column and a percent column together,
which is why dual-axis support is a requirement rather than a nicety.
"""
from __future__ import annotations

import re
from typing import Any

# ---------------------------------------------------------------- column roles

# Order matters: the first pattern that matches wins, so the most specific
# (identifier, temporal) are tested before the broad metric families.
_IDENTIFIER = re.compile(
    r"^(rank|ranking|no|nomor|urutan|row_num|rn)$|_id$|^id$|_key$|_code$", re.I)
_TEMPORAL = re.compile(
    r"^(dt_id|date|tanggal|period|periode|month_id|mth_id|mth|month|bulan|week|week_id|"
    r"wk|minggu|day|hari|ds|datum|quarter|year|tahun)$|_(dt|date|month|week|day)$"
    # Qualified period markers: occ_month_id, avail_month_id, prev_month_id. These end
    # in _id but are periods, and spotting them is what lets a chart disclose that its
    # two sides come from differently-refreshed tables.
    r"|_(month|mth|dt|date|week|day)_id$", re.I)
_TERRITORY = re.compile(
    r"^(kabkot|kabkota|kabupaten|kota|kecamatan|kec|kel|desa|region|regional|branch|"
    r"circle|area|province|provinsi|wilayah|territory|site_nm|site_name|outlet_name|"
    r"cluster|micro_cluster)$|_(nm|name)$", re.I)
_PERCENT = re.compile(
    r"(_pct|^pct_|_percent|_persen|share|ratio|rasio|_rate$|rate_|penetration|"
    r"penetrasi|utilization|utilisasi|availability|avail_pct|tur|occupancy)", re.I)
_DELTA = re.compile(
    r"(growth|pertumbuhan|_mom|mom_|_yoy|yoy_|_qoq|qoq_|delta|diff|_chg|change|"
    r"selisih|net_add|netadd|net_churn|variance)", re.I)
_CURRENCY = re.compile(
    r"(revenue|^rev_|_rev$|_rev_|arpu|arpt|omzet|nominal|amount|_idr|_rp$|osa|"
    r"sellin|sell_in|payout|price|harga|slab)", re.I)
_COUNT = re.compile(
    r"(count|jumlah|total_site|_sites?$|^sites?$|subs|subscriber|pelanggan|outlet|"
    r"hits?$|_hit$|gross_add|^ga$|_ga$|churn|rgu|vlr|homepass|users?$|devices?$|"
    r"trx|transaksi|so_|sa_|pa_)", re.I)

ROLE_IDENTIFIER = "identifier"
ROLE_TEMPORAL = "temporal"
ROLE_TERRITORY = "territory"
ROLE_CURRENCY = "currency"
ROLE_PERCENT = "percent"
ROLE_DELTA = "delta"
ROLE_COUNT = "count"
ROLE_LABEL = "label"

# Delta is tested BEFORE percent: `revenue_growth_pct` is a change that happens to be
# expressed in percent, and what matters for rendering is that it can go negative and
# therefore needs a zero line. Its unit is still percent (see _UNIT_FOR_ROLE).
_METRIC_ORDER = (
    (ROLE_DELTA, _DELTA),
    (ROLE_PERCENT, _PERCENT),
    (ROLE_CURRENCY, _CURRENCY),
    (ROLE_COUNT, _COUNT),
)

# Units the clients know how to format.
UNIT_RP = "Rp"
UNIT_PCT = "%"
UNIT_NONE = ""

_UNIT_FOR_ROLE = {
    ROLE_CURRENCY: UNIT_RP,
    ROLE_PERCENT: UNIT_PCT,
    ROLE_COUNT: UNIT_NONE,
    ROLE_DELTA: UNIT_NONE,
}


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _looks_temporal_value(value: Any) -> bool:
    """202608 / 2026-08-01 / 20260801 style values."""
    if _is_number(value):
        return 190001 <= value <= 210012 or 19000101 <= value <= 21001231
    if isinstance(value, str):
        return bool(re.match(r"^\d{4}[-/]\d{2}|^\d{6}$|^\d{8}$", value))
    return False


def classify_column(name: str, values: list[Any]) -> str:
    """Role of one column, from its NAME first and its values as a tiebreaker.

    Name wins because `month_id` holding 202608 is numeric but is not a metric, and
    `rank` holding 1..10 is numeric but is not a quantity anyone wants plotted.
    """
    clean = [v for v in values if v is not None]
    numeric = bool(clean) and all(_is_number(v) for v in clean)

    if _TEMPORAL.search(name):
        return ROLE_TEMPORAL
    if _IDENTIFIER.search(name):
        return ROLE_IDENTIFIER
    if _TERRITORY.search(name):
        return ROLE_TERRITORY
    if not numeric:
        # Values that all look like dates make a non-numeric column temporal.
        if clean and all(_looks_temporal_value(v) for v in clean):
            return ROLE_TEMPORAL
        return ROLE_LABEL
    for role, pattern in _METRIC_ORDER:
        if pattern.search(name):
            return role
    # Numeric, unnamed family: a tight 0..100 spread is almost always a percentage.
    if clean and all(0 <= float(v) <= 100 for v in clean) and any(
            not float(v).is_integer() for v in clean):
        return ROLE_PERCENT
    return ROLE_COUNT


# ---------------------------------------------------------------- funnel shapes

_FUNNEL_GROUPS = (
    ("so", "sa", "pa"),
    ("primary", "secondary", "tertiary"),
    ("homepass", "ga", "pa"),
)


def _funnel_series(metrics: list[str]) -> list[str]:
    """Metrics that form a known conversion funnel, in funnel order."""
    lowered = {m.lower(): m for m in metrics}
    for group in _FUNNEL_GROUPS:
        found = []
        for stage in group:
            match = next(
                (orig for low, orig in lowered.items()
                 if re.search(rf"(^|_){stage}(_|$)", low)), None)
            if match:
                found.append(match)
        if len(found) == len(group):
            return found
    return []


# ---------------------------------------------------------------- the spec

MAX_BAR_CATEGORIES = 24
MAX_LINE_POINTS = 400
MAX_PIE_SLICES = 12
MAX_MATRIX_ROWS = 20


def _period_note(columns: list[str], rows: list[dict]) -> str:
    """Explicit note when the result mixes periods from differently-refreshed tables.

    Two tables in one domain can have different coverage (occupancy stops at 202512
    while availability runs to the current month), and a chart that silently blends
    them is misleading.
    """
    period_cols = [c for c in columns if _TEMPORAL.search(c)]
    seen: dict[str, set] = {}
    for col in period_cols:
        vals = {r.get(col) for r in rows if r.get(col) is not None}
        if vals:
            seen[col] = vals
    if len(seen) < 2:
        return ""
    singles = {c: next(iter(v)) for c, v in seen.items() if len(v) == 1}
    if len(singles) >= 2 and len(set(singles.values())) > 1:
        parts = ", ".join(f"{c}={v}" for c, v in sorted(singles.items()))
        return f"Periode berbeda per sumber ({parts})"
    return ""


def build_chart_spec(
    columns: list[str],
    rows: list[dict],
    question: str = "",
    result_profile: dict | None = None,
    sql: str = "",
) -> dict[str, Any]:
    """Classify a result into a render spec. Never raises; returns mode 'none' instead."""
    columns = list(columns or [])
    rows = list(rows or [])
    if not columns or not rows:
        return {"mode": "none", "reason": "empty_result"}

    sample = rows[:50]
    roles = {c: classify_column(c, [r.get(c) for r in sample]) for c in columns}

    metrics = [c for c in columns
               if roles[c] in (ROLE_CURRENCY, ROLE_PERCENT, ROLE_COUNT, ROLE_DELTA)]
    if not metrics:
        return {"mode": "none", "reason": "no_plottable_metric", "roles": roles}

    temporal = next((c for c in columns if roles[c] == ROLE_TEMPORAL), None)
    territory = next((c for c in columns if roles[c] == ROLE_TERRITORY), None)
    label = territory or next((c for c in columns if roles[c] == ROLE_LABEL), None)

    # A temporal column is the x-axis only when it actually varies; a single constant
    # month is context, not a trend. Prefer a territory label when both are present,
    # so "revenue per kabkota for 202608" plots kabkota rather than one flat point.
    if temporal and (len({r.get(temporal) for r in rows}) <= 1 or (label and len(rows) > 1
                     and len({r.get(label) for r in rows}) > len({r.get(temporal) for r in rows}))):
        temporal = None

    category = temporal or label
    if not category:
        return {"mode": "none", "reason": "no_category_axis", "roles": roles}

    truncated = bool((result_profile or {}).get("truncated"))
    row_count = int((result_profile or {}).get("row_count") or len(rows))
    ranked_subset = False

    series = _build_series(metrics, roles)
    funnel = _funnel_series(metrics)

    if temporal:
        mode = "line" if len(rows) <= MAX_LINE_POINTS else "none"
        if mode == "none":
            return {"mode": "none", "reason": "too_many_points", "roles": roles}
    elif funnel and len(rows) <= MAX_BAR_CATEGORIES:
        mode = "funnel"
        series = [s for s in series if s["column"] in funnel] or series
    elif len(rows) > MAX_BAR_CATEGORIES:
        # More categories than fit as readable bars. Still draw something: a ranked bar
        # of the top N is far more useful than no chart at all, which is what the user
        # got before. The caption states that it is a subset, so it stays honest.
        if len(rows) > MAX_BAR_CATEGORIES * 4:
            return {"mode": "none", "reason": "too_many_categories", "roles": roles}
        mode = "bar"
        primary = series[0]["column"]
        rows = sorted(
            rows,
            key=lambda r: (r.get(primary) is None, -(r.get(primary) or 0)
                           if _is_number(r.get(primary)) else 0),
        )[:MAX_BAR_CATEGORIES]
        ranked_subset = True
    elif _pie_is_honest(
            series, rows, truncated,
            has_dropped_period=any(roles[c] == ROLE_TEMPORAL for c in columns),
            ranked_top_n=_is_ranked_top_n(sql, question)):
        mode = "pie"
        series = series[:1]
    else:
        mode = "bar"

    axes = _build_axes(series)
    spec = {
        "mode": mode,
        "category": category,
        "category_role": roles[category],
        "series": series,
        "axes": axes,
        "dual_axis": len(axes) > 1,
        "roles": roles,
        "title": _title(series, category, mode),
        "caption": _caption(category, rows, row_count, truncated,
                            _period_note(columns, rows), ranked_subset,
                            roles[category]),
        "truncated": truncated,
    }
    if ranked_subset:
        # The client must plot the same subset the caption describes, in this order.
        spec["rows"] = rows
        spec["ranked_subset"] = True
    return spec


def _build_series(metrics: list[str], roles: dict[str, str]) -> list[dict[str, Any]]:
    out = []
    for name in metrics[:6]:
        role = roles[name]
        # A delta carries the unit of whatever it measures: `revenue_growth_pct` is a
        # percentage, `net_add_90` is a plain count. Share the percent axis in the
        # first case so the scales stay comparable.
        if role == ROLE_DELTA:
            unit = UNIT_PCT if _PERCENT.search(name) else UNIT_NONE
        else:
            unit = _UNIT_FOR_ROLE.get(role, UNIT_NONE)
        out.append({
            "column": name,
            "role": role,
            "unit": unit,
            "axis": unit,
            "can_be_negative": role == ROLE_DELTA,
            "label": _humanise(name),
        })
    return out


def _build_axes(series: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One axis per distinct unit, capped at two.

    Plotting rupiah in the billions against a percentage on one scale flattens the
    percentage into the baseline, which is the single most common way these charts
    misled: 21 percent of production results carry both.
    """
    axes: list[dict[str, Any]] = []
    for unit in [UNIT_RP, UNIT_PCT, UNIT_NONE]:
        members = [s["column"] for s in series if s["axis"] == unit]
        if not members:
            continue
        axes.append({
            "unit": unit,
            "side": "left" if not axes else "right",
            "columns": members,
            "zero_line": any(s["can_be_negative"] for s in series
                             if s["column"] in members),
        })
        if len(axes) == 2:
            break
    for spec in series:
        spec["axis_side"] = next(
            (a["side"] for a in axes if spec["column"] in a["columns"]), "left")
    return axes


def _is_ranked_top_n(sql: str, question: str) -> bool:
    """True when the result is the top N of a larger set rather than a whole.

    `ORDER BY ... LIMIT 10` returns ten of many kecamatan, so the ten values do not sum
    to anything meaningful. The BigQuery `truncated` flag does NOT cover this: the query
    asked for ten rows and got exactly ten, so nothing was truncated. Without this check
    a "top 10" question was drawn as a pie, implying the slices were a complete
    composition.
    """
    text = (sql or "")
    if re.search(r"\border\s+by\b", text, re.I) and re.search(r"\blimit\s+\d+", text, re.I):
        return True
    return bool(re.search(r"\b(top|teratas|terbesar|tertinggi|terendah|terburuk|"
                          r"paling|bottom|ranking|peringkat)\b", question or "", re.I))


def _pie_is_honest(series: list[dict[str, Any]], rows: list[dict], truncated: bool,
                   has_dropped_period: bool = False, ranked_top_n: bool = False) -> bool:
    """A pie is only honest for a complete, non-negative composition of one metric.

    A top-N is a comparison, not a composition: drawing it as a pie implies the slices
    add up to the whole when they do not. A result that also carries a period column is
    a slice of time rather than a self-contained whole, so it reads more honestly as
    bars.
    """
    if (truncated or has_dropped_period or ranked_top_n
            or len(series) != 1 or len(rows) > MAX_PIE_SLICES):
        return False
    column = series[0]["column"]
    values = [r.get(column) for r in rows]
    if any(v is None or not _is_number(v) or v < 0 for v in values):
        return False
    return series[0]["role"] in (ROLE_CURRENCY, ROLE_COUNT)


def _humanise(name: str) -> str:
    pretty = re.sub(r"[_]+", " ", name).strip()
    return pretty[:1].upper() + pretty[1:] if pretty else name


def _title(series: list[dict[str, Any]], category: str, mode: str) -> str:
    metric_names = ", ".join(s["label"] for s in series[:3])
    if mode == "line":
        return f"Tren {metric_names}"
    if mode == "funnel":
        return f"Funnel {metric_names}"
    if mode == "pie":
        return f"Komposisi {metric_names}"
    return f"{metric_names} per {_humanise(category)}"


def _caption(category: str, rows: list[dict], row_count: int, truncated: bool,
             period_note: str, ranked_subset: bool = False,
             category_role: str = "") -> str:
    label = _humanise(category).lower()
    if category_role == ROLE_TEMPORAL:
        # A time axis is described by its span, not by a count of rows: "3 month id"
        # tells the user nothing, "202606 sampai 202608" tells them what they are seeing.
        values = sorted({str(r.get(category)) for r in rows if r.get(category) is not None})
        if values:
            span = values[0] if len(values) == 1 else f"{values[0]} sampai {values[-1]}"
            parts = [f"{len(values)} periode ({span})"]
        else:
            parts = [f"{len(rows)} {label}"]
    elif ranked_subset:
        parts = [f"{len(rows)} teratas dari {row_count} {label}"]
    else:
        parts = [f"{len(rows)} {label}"]
        if truncated or row_count > len(rows):
            parts.append(f"dari {row_count} baris (dipotong)")
    if period_note:
        parts.append(period_note)
    return " · ".join(parts)
