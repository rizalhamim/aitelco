"""Deterministic, pre-formatted facts for the answer writer.

The synthesizer used to format every number itself from 50 raw rows. That is where
inconsistency came from: "Rp 1,2 M" in one sentence and "1.234.567.890" in the next,
a share printed without a decimal, a total that silently summed a ranked subset, or a
growth rate recomputed with the wrong base. It is also slow: the model spends tokens
doing arithmetic before it writes a word.

This module computes the numbers once, in Python, in Indonesian number format, and
hands them to the model as `key_facts`. The prompt tells the model to quote these
strings verbatim. The same facts drive `fallback_report()`, so an answer looks the
same even when the language model returns nothing.

Never raises: a failure here returns an empty dict and the answer is written the old
way.
"""
from __future__ import annotations

import re
from decimal import Decimal
from typing import Any

_PCT = re.compile(
    r"(pct|percent|persen|share|ratio|rasio|rate|growth|mom|yoy|wow|qoq|ach|achievement|"
    r"pencapaian|availability|avail|utili[sz]ation|util|penetra|occupancy|kontribusi|contribution)",
    re.I)
_CUR = re.compile(r"(revenue|^rev_|_rev$|_rev_|^rev$|arpu|arpt|omzet|nominal|amount|_idr|_rp$|"
                  r"price|harga|cost|biaya|payout|sellin|sell_in)", re.I)
_DELTA = re.compile(r"(growth|mom|yoy|wow|qoq|delta|diff|change|selisih|_chg|net_add|vs_)", re.I)
# Summing these across rows means nothing (a rate, an average, a point-in-time stock).
_NON_ADDITIVE = re.compile(r"(avg|average|rata|mean|median|arpu|arpt|per_|_per|index|score|"
                           r"rank|price|harga|closing|base$|_base)", re.I)
_MONTHS = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus",
           "September", "Oktober", "November", "Desember"]
_MONTHS_EN = ["January", "February", "March", "April", "May", "June", "July", "August",
              "September", "October", "November", "December"]


def _num(v: Any) -> float | None:
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float, Decimal)):
        return float(v)
    return None


def _group(int_text: str, sep: str) -> str:
    out = ""
    while len(int_text) > 3:
        out = sep + int_text[-3:] + out
        int_text = int_text[:-3]
    return int_text + out


def fmt_number(v: float, decimals: int = 0, lang: str = "id") -> str:
    """1234567.8 -> '1.234.567,8' (id) or '1,234,567.8' (en)."""
    thou, dec = (".", ",") if lang == "id" else (",", ".")
    neg = v < 0
    text = f"{abs(v):.{decimals}f}"
    whole, _, frac = text.partition(".")
    body = _group(whole, thou) + (dec + frac if frac else "")
    return ("-" if neg else "") + body


def column_format(col: str) -> str:
    if _PCT.search(col):
        return "percent"
    if _CUR.search(col):
        return "currency"
    return "number"


def _magnitude(max_abs: float, lang: str) -> tuple[float, str]:
    if lang == "id":
        table = ((1e12, "T"), (1e9, "M"), (1e6, "Jt"), (1e3, "Rb"))
    else:
        table = ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K"))
    for div, unit in table:
        if max_abs >= div:
            return div, unit
    return 1.0, ""


def formatter(col: str, values: list[float], lang: str = "id"):
    """One format per column: currency keeps ONE magnitude for every value."""
    kind = column_format(col)
    max_abs = max((abs(v) for v in values), default=0.0)
    if kind == "percent":
        return lambda v: fmt_number(v, 1, lang) + "%"
    if kind == "currency":
        div, unit = _magnitude(max_abs, lang)
        if unit in ("Rb", "K"):
            div, unit = 1.0, ""
        dec = 0 if not unit else (1 if max_abs / div < 1000 else 0)

        def cur(v: float) -> str:
            d, u, dd = div, unit, dec
            # One magnitude per column, except where it would print a real value as
            # "Rp 0,0 M": a 3,2 million value is "Rp 3,2 Jt", never zero billions.
            if v and abs(v) / d < 0.05:
                d, u = _magnitude(abs(v), lang)
                if u in ("Rb", "K"):
                    d, u = 1.0, ""
                dd = 1 if u else 0
            return "Rp " + fmt_number(v / d, dd, lang) + (f" {u}" if u else "")
        return cur
    integers = all(float(v).is_integer() for v in values)
    if max_abs >= 1e6:
        div, unit = _magnitude(max_abs, lang)
        return lambda v: fmt_number(v / div, 1, lang) + f" {unit}"
    return lambda v: fmt_number(v, 0 if integers else 1, lang)


def period_label(v: Any, lang: str = "id") -> str:
    """202609 -> 'September 2026 (202609)'; '2026-09-15' -> '15 September 2026'."""
    text = str(v)
    months = _MONTHS if lang == "id" else _MONTHS_EN
    m = re.fullmatch(r"(\d{4})-?(\d{2})", text)
    if m and 1 <= int(m.group(2)) <= 12:
        return f"{months[int(m.group(2)) - 1]} {m.group(1)} ({m.group(1)}{m.group(2)})"
    m = re.match(r"^(\d{4})-?(\d{2})-?(\d{2})", text)
    if m and 1 <= int(m.group(2)) <= 12:
        return f"{int(m.group(3))} {months[int(m.group(2)) - 1]} {m.group(1)}"
    return text


def _is_time_col(col: str) -> bool:
    return bool(re.search(
        r"(^|_)(month|bulan|mth|dt|date|tanggal|week|minggu|period|periode|year|tahun)(_|$)|"
        r"^(month_id|dt_id|mth_id)$", col, re.I))


def build(columns: list[str], rows: list[dict], chart: dict | None = None,
          result_profile: dict | None = None, lang: str = "id") -> dict:
    """Pre-computed facts for the answer. Empty dict when there is nothing to say."""
    try:
        return _build(list(columns or []), list(rows or []), chart or {}, result_profile or {}, lang)
    except Exception:
        return {}


def _label_of(row: dict, label_cols: list[str]) -> str:
    parts = [str(row.get(c)) for c in label_cols if row.get(c) not in (None, "")]
    return " / ".join(parts) if parts else "-"


def _build(columns, rows, chart, profile, lang) -> dict:
    if not rows or not columns:
        return {}
    plot_rows = chart.get("rows") or rows
    time_cols = [c for c in columns if _is_time_col(c)]
    measures = [c for c in (chart.get("y") or []) + (chart.get("y2") or []) if c in columns]
    if not measures:
        measures = [c for c in columns if c not in time_cols
                    and not re.search(r"(^|_)(id|rank|no|urutan|key|code)$", c, re.I)
                    and sum(1 for r in rows if _num(r.get(c)) is not None) >= max(1, len(rows) // 2)]
    measures = measures[:3]
    label_cols = [c for c in columns if c not in measures and c not in time_cols
                  and any(isinstance(r.get(c), str) for r in rows)][:2]

    facts: dict[str, Any] = {
        "rows": int(profile.get("row_count") or len(rows)),
        "truncated": bool(profile.get("truncated")),
    }
    # Period: what time the numbers cover.
    for c in time_cols:
        vals = sorted({str(r.get(c)) for r in rows if r.get(c) is not None})
        if vals:
            facts["period"] = (period_label(vals[0], lang) if len(vals) == 1
                               else f"{period_label(vals[0], lang)} - {period_label(vals[-1], lang)}")
            facts["period_count"] = len(vals)
            break
    if label_cols:
        distinct = {str(r.get(label_cols[0])) for r in rows if r.get(label_cols[0]) is not None}
        facts["coverage"] = f"{len(distinct)} {label_cols[0]}"
    if chart.get("caption"):
        facts["chart_caption"] = chart["caption"]

    is_series = bool(chart.get("time_axis")) and not chart.get("series_by")
    out_measures = []
    for col in measures:
        series = [(r, _num(r.get(col))) for r in plot_rows]
        series = [(r, v) for r, v in series if v is not None]
        if not series:
            continue
        values = [v for _, v in series]
        f = formatter(col, values, lang)
        entry: dict[str, Any] = {"column": col, "format": column_format(col)}
        if len(values) == 1:
            entry["value"] = f(values[0])
            out_measures.append(entry)
            continue
        if is_series:
            last, prev = series[-1], series[-2]
            entry["latest"] = f"{f(last[1])} ({period_label(last[0].get(chart.get('x')), lang)})"
            entry["previous"] = f"{f(prev[1])} ({period_label(prev[0].get(chart.get('x')), lang)})"
            if column_format(col) == "percent":
                entry["change"] = fmt_number(last[1] - prev[1], 1, lang) + " pp"
            elif prev[1]:
                entry["change"] = fmt_number((last[1] - prev[1]) / abs(prev[1]) * 100, 1, lang) + "%"
            first = series[0]
            if len(series) > 2 and first[1]:
                entry["change_from_first"] = (
                    fmt_number(last[1] - first[1], 1, lang) + " pp" if column_format(col) == "percent"
                    else fmt_number((last[1] - first[1]) / abs(first[1]) * 100, 1, lang) + "%")
        hi = max(series, key=lambda t: t[1])
        lo = min(series, key=lambda t: t[1])
        hi_label = _label_of(hi[0], label_cols) if label_cols else period_label(hi[0].get(chart.get("x")), lang) if chart.get("x") else "-"
        lo_label = _label_of(lo[0], label_cols) if label_cols else period_label(lo[0].get(chart.get("x")), lang) if chart.get("x") else "-"
        entry["highest"] = f"{hi_label}: {f(hi[1])}"
        entry["lowest"] = f"{lo_label}: {f(lo[1])}"
        entry["average"] = f(sum(values) / len(values))
        additive = (column_format(col) != "percent" and not _DELTA.search(col)
                    and not _NON_ADDITIVE.search(col) and not is_series
                    and not chart.get("series_by"))
        if additive and all(v >= 0 for v in values):
            total = sum(values)
            entry["sum_of_rows"] = f(total)
            if total > 0 and len(values) >= 3:
                top_share = hi[1] / total * 100
                entry["top_share_of_rows"] = fmt_number(top_share, 1, lang) + "%"
        negatives = sum(1 for v in values if v < 0)
        if negatives:
            entry["negative_rows"] = negatives
        out_measures.append(entry)
    if out_measures:
        facts["measures"] = out_measures
    return facts if out_measures else {}


def fallback_report(question: str, facts: dict, lang: str = "id") -> str:
    """The answer template, filled from facts only, for when the model returns nothing."""
    if not facts or not facts.get("measures"):
        return ""
    id_ = lang == "id"
    m = facts["measures"][0]
    name = m["column"].replace("_", " ")
    if "value" in m:
        head = f"**{name}: {m['value']}**"
    elif "latest" in m:
        head = f"**{name} terakhir {m['latest']}**" if id_ else f"**Latest {name}: {m['latest']}**"
    else:
        head = (f"**{name} tertinggi di {m['highest']}**" if id_
                else f"**Highest {name}: {m['highest']}**")
    ctx = " · ".join(x for x in (facts.get("period"), facts.get("chart_caption") or facts.get("coverage")) if x)
    lines = [head]
    if ctx:
        lines.append(ctx)
    lines += ["", "### Temuan utama" if id_ else "### Key findings"]
    for item in facts["measures"]:
        n = item["column"].replace("_", " ")
        for key, lab_id, lab_en in (("value", "nilai", "value"), ("latest", "terakhir", "latest"),
                                    ("change", "perubahan", "change"),
                                    ("highest", "tertinggi", "highest"), ("lowest", "terendah", "lowest"),
                                    ("average", "rata-rata", "average"),
                                    ("sum_of_rows", "jumlah baris", "sum of rows")):
            if key in item:
                lines.append(f"- {n} {lab_id if id_ else lab_en}: **{item[key]}**")
    if facts.get("truncated"):
        lines += ["", "> Catatan data: hasil dibatasi, tidak semua baris ditampilkan." if id_
                  else "> Data note: the result is limited, not every row is shown."]
    return "\n".join(lines)
