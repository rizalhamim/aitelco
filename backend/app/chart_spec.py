"""Pick a chart for a query result.

Deterministic heuristics (no LLM call) that turn `columns` + `rows` into a
render-ready chart spec. Web (ECharts) and Android (fl_chart) both draw from
the same spec, so a given answer looks the same on every client.

Spec shape (all keys always present):
    {
      "type": "kpi" | "line" | "area" | "bar" | "hbar" | "stacked_bar"
              | "donut" | "scatter" | "combo" | "none",
      "x": str | None,            # category / time column
      "y": [str],                 # measure columns on the main axis
      "y2": [str],                # measures on a secondary axis (combo)
      "series_by": str | None,    # long-format column that splits series
      "label": str | None,        # point label column (scatter)
      "formats": {col: "currency" | "percent" | "number"},
      "sort": "desc" | None,
      "top_n": int | None,        # clients show the top N, rest behind "show all"
      "map_key": str | None,      # territory column → offer a map drill-down
      "alternatives": [type],     # other sensible types for the type switcher
      "title": str,
    }
"""
from __future__ import annotations

import re
from datetime import date, datetime

_TIME_NAME = re.compile(
    r"(^|_)(date|dt|tanggal|tgl|day|hari|week|minggu|month|bulan|bln|mon|periode|period|"
    r"yyyymm|yearmonth|year|tahun|thn|quarter|kuartal|qtr|time|waktu|hour|jam)(_|$)", re.I)
_PCT_NAME = re.compile(
    r"(pct|percent|persen|%|rate|ratio|share|growth|mom|yoy|wow|ach|achievement|pencapaian|"
    r"availability|avail|utili[sz]ation|util|churn|conversion|kontribusi|contribution)", re.I)
_CUR_NAME = re.compile(r"(revenue|rev|arpu|rp|idr|amount|nilai|value_sales|sales_value|cost|biaya|price|harga)", re.I)
_SHARE_NAME = re.compile(r"(share|kontribusi|contribution|porsi|komposisi|mix|proportion)", re.I)
_GEO_NAME = re.compile(
    r"(kabupaten|kab|kota|city|kecamatan|kec|district|regency|province|provinsi|prov|region|area|"
    r"cluster|branch|territory|wilayah|circle)", re.I)

_MAX_SERIES = 8
_TOP_N = 15


def _is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _looks_time_value(v) -> bool:
    if isinstance(v, (date, datetime)):
        return True
    if _is_num(v):
        iv = int(v)
        return v == iv and (190001 <= iv <= 210012 or 19000101 <= iv <= 21001231)
    if isinstance(v, str):
        return bool(re.match(r"^\d{4}[-/]\d{1,2}([-/]\d{1,2})?([ T].*)?$", v.strip())
                    or re.match(r"^\d{6}$|^\d{8}$", v.strip()))
    return False


def _values(rows: list, col: str) -> list:
    return [r.get(col) for r in rows if r.get(col) is not None]


def _classify(columns: list[str], rows: list[dict]) -> dict[str, str]:
    kinds = {}
    for c in columns:
        vals = _values(rows, c)
        if not vals:
            kinds[c] = "empty"
            continue
        time_vals = all(_looks_time_value(v) for v in vals)
        if _TIME_NAME.search(c) and (time_vals or not all(_is_num(v) for v in vals)):
            kinds[c] = "time"
        elif time_vals and not all(_is_num(v) for v in vals):
            kinds[c] = "time"
        elif all(_is_num(v) for v in vals):
            # YYYYMM integers in a column named like a period are time, not a measure.
            kinds[c] = "time" if (time_vals and _TIME_NAME.search(c)) else "num"
        else:
            kinds[c] = "cat"
    return kinds


def _fmt(col: str, rows: list) -> str:
    if _PCT_NAME.search(col):
        return "percent"
    if _CUR_NAME.search(col):
        return "currency"
    return "number"


def _empty(title: str = "") -> dict:
    return {"type": "none", "x": None, "y": [], "y2": [], "series_by": None, "label": None,
            "formats": {}, "sort": None, "top_n": None, "map_key": None,
            "alternatives": [], "title": title}


def _magnitude(rows: list, col: str) -> float:
    vals = [abs(v) for v in _values(rows, col) if _is_num(v)]
    return max(vals) if vals else 0.0


_ACRONYMS = {"mom": "MoM", "yoy": "YoY", "wow": "WoW", "qoq": "QoQ", "pct": "%", "arpu": "ARPU",
             "fwa": "FWA", "ftth": "FTTH", "ga": "GA", "rgb": "RGB", "kpi": "KPI", "id": "ID", "pb": "PB",
             "gb": "GB", "tb": "TB", "bts": "BTS", "im3": "IM3", "5g": "5G", "4g": "4G"}


def _humanize(col: str) -> str:
    words = [w for w in col.replace("_", " ").split() if w]
    out = [_ACRONYMS.get(w.lower(), w.capitalize() if w.islower() else w) for w in words]
    return " ".join(out).replace(" %", " (%)") if out else col


def suggest(columns: list[str], rows: list[dict], question: str = "") -> dict:
    """Return a chart spec for this result (type "none" when no chart fits)."""
    if not columns or not rows:
        return _empty()

    kinds = _classify(columns, rows)
    nums = [c for c in columns if kinds[c] == "num"]
    cats = [c for c in columns if kinds[c] == "cat"]
    times = [c for c in columns if kinds[c] == "time"]
    spec = _empty()
    spec["formats"] = {c: _fmt(c, rows) for c in nums}
    geo = next((c for c in cats if _GEO_NAME.search(c)), None)
    spec["map_key"] = geo

    if not nums:
        return spec

    # One row of measures → KPI tiles.
    if len(rows) == 1:
        spec.update(type="kpi", y=nums[:6], title="Ringkasan")
        return spec

    # Time series.
    if times:
        x = times[0]
        spec["x"] = x
        split = next((c for c in cats if 1 < len(set(_values(rows, c))) <= _MAX_SERIES), None)
        if split and len(nums) >= 1:
            spec.update(type="line", y=[nums[0]], series_by=split,
                        alternatives=["area", "stacked_bar", "bar"],
                        title=f"{_humanize(nums[0])} per {_humanize(split)}")
            return spec
        pct = [c for c in nums if spec["formats"][c] == "percent"]
        absolute = [c for c in nums if c not in pct]
        if absolute and pct:
            spec.update(type="combo", y=absolute[:2], y2=pct[:2],
                        alternatives=["line", "bar"],
                        title=f"{_humanize(absolute[0])} & {_humanize(pct[0])}")
            return spec
        measures = nums[:4]
        # Mixed magnitudes on one axis flatten the small series: split them.
        if len(measures) >= 2:
            mags = sorted((_magnitude(rows, c), c) for c in measures)
            if mags[0][0] and mags[-1][0] / mags[0][0] > 50:
                spec.update(type="combo", y=[mags[-1][1]], y2=[m[1] for m in mags[:-1]][:2],
                            alternatives=["line"], title=_humanize(mags[-1][1]))
                return spec
        spec.update(type="area" if len(measures) == 1 else "line", y=measures,
                    alternatives=["line", "bar"] if len(measures) == 1 else ["area", "bar"],
                    title=_humanize(measures[0]) if len(measures) == 1
                    else f"{_humanize(measures[0])} vs {_humanize(measures[1])}" if len(measures) == 2
                    else f"Tren {_humanize(measures[0])}")
        return spec

    # Category vs measures.
    if cats:
        x = geo or cats[0]
        spec["x"] = x
        labels = [str(v) for v in _values(rows, x)]
        n = len(labels)
        long_labels = n and sum(len(s) for s in labels) / n > 12

        # Long format: two categoricals + one measure → stacked bars.
        split = next((c for c in cats if c != x and 1 < len(set(_values(rows, c))) <= _MAX_SERIES), None)
        if split and len(nums) == 1:
            spec.update(type="stacked_bar", y=[nums[0]], series_by=split,
                        alternatives=["bar"], sort="desc",
                        top_n=_TOP_N if len(set(labels)) > _TOP_N else None,
                        title=f"{_humanize(nums[0])} per {_humanize(x)}")
            return spec

        # Two measures on territories with nothing else → relationship view.
        if len(nums) == 2 and n >= 8 and re.search(r"korelasi|correlat|hubungan|vs\b|versus", question, re.I):
            spec.update(type="scatter", x=None, y=nums, label=x,
                        alternatives=["bar"], title=f"{_humanize(nums[0])} vs {_humanize(nums[1])}")
            return spec

        first = nums[0]
        vals = [v for v in _values(rows, first) if _is_num(v)]
        positive = vals and all(v >= 0 for v in vals)
        is_share = bool(_SHARE_NAME.search(first) or re.search(r"komposisi|porsi|share|kontribusi|proporsi", question, re.I))
        if is_share and positive and n <= 8 and len(nums) == 1:
            spec.update(type="donut", y=[first], alternatives=["bar", "hbar"],
                        title=_humanize(first))
            return spec

        pct = [c for c in nums if spec["formats"][c] == "percent"]
        absolute = [c for c in nums if c not in pct]
        if absolute and pct and n <= 30:
            spec.update(type="combo", y=absolute[:1], y2=pct[:1], sort="desc",
                        top_n=_TOP_N if n > _TOP_N else None,
                        alternatives=["bar", "hbar"],
                        title=f"{_humanize(absolute[0])} & {_humanize(pct[0])}")
            return spec

        spec.update(type="hbar" if (long_labels or n > 8) else "bar",
                    y=nums[:3], sort="desc",
                    top_n=_TOP_N if n > _TOP_N else None,
                    alternatives=["bar", "hbar"] + (["donut"] if positive and n <= 8 and len(nums) == 1 else []),
                    title=_humanize(first) + (f" per {_humanize(x)}" if x else ""))
        spec["alternatives"] = [a for a in spec["alternatives"] if a != spec["type"]]
        return spec

    # Only measures, many rows → scatter of the first two.
    if len(nums) >= 2:
        spec.update(type="scatter", y=nums[:2], alternatives=[],
                    title=f"{_humanize(nums[0])} vs {_humanize(nums[1])}")
        return spec
    return spec
