"""Simulasi Target: will this month's target be reached, how big is the gap, what daily
run-rate is needed, and what moves the estimate.

GET /api/simulasi?metric=revenue&region=

Estimate: MTD plus the remaining days at the MTD run-rate, adjusted for the day-of-week
pattern of the last 8 weeks (region_daily). The P10 to P90 band combines day-to-day noise
around that pattern with the uncertainty of the run-rate itself. A back-test replays the
same method on the complete months inside the daily window and reports the mean miss.

Levers only use data the dump has (revenue per RGU, recovering a region's volume effect
from Diagnosa, new sites); the others are returned locked with the reason. The client
applies the levers itself (formulas in "levers"), so sliders answer instantly.
"""
from __future__ import annotations

import math
from datetime import date, timedelta
from statistics import mean, pstdev
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from . import perf_dump
from .auth import get_current_user
from .database import User
from .diagnosa import effects
from .v3_common import (METRICS, REGION_COLOR, REGIONS, Window, complete_month, day_label, daily_series, f,
                        load_targets, month_label, month_of, norm, pct, region_label, region_target, rp, rp_m, tables)

router = APIRouter(prefix="/api/simulasi", tags=["simulasi"])

Z80 = 1.2816  # P10 / P90
RAMP = 0.7     # a new site earns about 70% of a mature one in its first month
NEW_SITE_IDR = 25e6
SIM_METRICS = {"revenue": "Revenue", "fwa_gross_add": "Gross add FWA", "gross_add": "Gross add", "subs": "RGU 90D"}


def dow_weights(series: dict[date, float], last: date, weeks: int = 8) -> list[float]:
    days = [last - timedelta(days=i) for i in range(weeks * 7)]
    vals = [(d, series[d]) for d in days if d in series]
    if not vals:
        return [1.0] * 7
    avg = mean(v for _, v in vals) or 1.0
    w = []
    for k in range(7):
        xs = [v for d, v in vals if d.weekday() == k]
        w.append((mean(xs) / avg) if xs and avg else 1.0)
    return w


def forecast(series: dict[date, float], last: date, w: Optional[list[float]] = None) -> dict:
    """Month-end estimate from the MTD of last's month, with a P10-P90 band."""
    win = Window(last)
    w = w or dow_weights(series, last)
    cur_days = [win.cur0 + timedelta(days=i) for i in range(win.days)]
    mtd = sum(series.get(d, 0.0) for d in cur_days)
    wsum = sum(w[d.weekday()] for d in cur_days) or 1.0
    level = mtd / wsum
    rem = [last + timedelta(days=i) for i in range(1, win.remaining + 1)]
    path_mid = []
    run = mtd
    for d in rem:
        run += level * w[d.weekday()]
        path_mid.append(run)
    est = run
    # noise: daily ratio to the pattern over the last 8 weeks
    hist = [last - timedelta(days=i) for i in range(56) if (last - timedelta(days=i)) in series]
    ratios = []
    if hist:
        lv = mean(series[d] / (w[d.weekday()] or 1) for d in hist) or 1.0
        ratios = [series[d] / (lv * (w[d.weekday()] or 1)) for d in hist]
    sd = pstdev(ratios) if len(ratios) > 2 else 0.05
    band_lo, band_hi = [], []
    acc_w = acc_w2 = 0.0
    for i, d in enumerate(rem):
        acc_w += w[d.weekday()]
        acc_w2 += w[d.weekday()] ** 2
        noise = level * sd * math.sqrt(acc_w2)
        lvl_err = level * acc_w * sd / math.sqrt(max(win.days, 1))
        s = math.sqrt(noise ** 2 + lvl_err ** 2)
        band_lo.append(path_mid[i] - Z80 * s)
        band_hi.append(path_mid[i] + Z80 * s)
    return {"mtd": mtd, "estimate": est, "lo": band_lo[-1] if band_lo else est, "hi": band_hi[-1] if band_hi else est,
            "path_mid": path_mid, "path_lo": band_lo, "path_hi": band_hi, "level": level, "weights": w, "win": win,
            "actual_cum": _cum([series.get(d, 0.0) for d in cur_days])}


def _cum(xs: list[float]) -> list[float]:
    out, s = [], 0.0
    for x in xs:
        s += x
        out.append(s)
    return out


def backtest(series: dict[date, float], last: date) -> Optional[dict]:
    """Replay the method on complete months inside the window, at the same day of month."""
    if not series:
        return None
    first = min(series)
    errs = []
    m = month_of(first)
    while True:
        y, mo = divmod(m, 100)
        m0 = date(y, mo, 1)
        nxt = date(y + (mo == 12), mo % 12 + 1, 1)
        if nxt > last:
            break
        if m0 >= first and (nxt - timedelta(days=1)) in series:
            day = min(last.day, (nxt - m0).days)
            if day < (nxt - m0).days:
                cut = m0 + timedelta(days=day - 1)
                fc = forecast({d: v for d, v in series.items() if d <= cut}, cut)
                actual = sum(v for d, v in series.items() if m0 <= d < nxt)
                if actual:
                    errs.append(abs(fc["estimate"] / actual - 1) * 100)
        m = perf_dump.month_add(m, 1)
    if not errs:
        return None
    return {"months": len(errs), "mean_abs_pct": mean(errs)}


def _series(t: dict, metric: str, region: str) -> dict[date, float]:
    col = METRICS[metric]["col"]
    rows = t.get("region_daily") or []
    if not any(r.get(col) is not None for r in rows[:50]):
        rows = t.get("kab_daily") or []
    return daily_series(rows, col, (lambda r: norm(r.get("region")) == norm(region)) if region else (lambda r: True))


def _prev_month_total(t: dict, metric: str, region: str, month: int) -> Optional[float]:
    col = METRICS[metric]["col"]
    rows = [r for r in (t.get("kec_month") or []) if int(r["month_id"]) == month and (not region or norm(r.get("region")) == norm(region))]
    if not rows or not any(r.get(col) is not None for r in rows):
        return None
    return sum(f(r.get(col)) for r in rows)


def build(metric: str = "revenue", region: str = "") -> dict:
    if metric not in SIM_METRICS:
        raise HTTPException(400, "Metrik tidak didukung")
    t, source = tables("region_daily", "kab_daily", "kec_month")
    region = norm(region)
    series = _series(t, metric, region)
    if not series:
        raise HTTPException(409, f"Data harian {SIM_METRICS[metric]} belum ada di Performance dump")
    last = max(series)
    targets = load_targets()
    fc = forecast(series, last)
    win: Window = fc["win"]
    scope_regions = [region] if region else REGIONS
    tvals = [region_target(targets, metric, r) for r in scope_regions]
    target = sum(tvals) if tvals and all(tvals) else None
    per_day = fc["mtd"] / win.days
    weekend = sum(1 for i in range(1, win.remaining + 1) if (last + timedelta(days=i)).weekday() >= 5)
    prev_m = perf_dump.month_add(win.month, -1)
    prev_total = _prev_month_total(t, metric, region, prev_m)
    gap = fc["estimate"] - target if target else None
    need = (target - fc["mtd"]) / win.remaining if target and win.remaining else None
    tp = target / win.dim if target else None

    path = None
    if tp:
        path = {"days": win.dim, "today": win.days,
                "act": [c - tp * (i + 1) for i, c in enumerate(fc["actual_cum"])],
                "mid": [fc["actual_cum"][-1] - tp * win.days] + [v - tp * (win.days + i + 1) for i, v in enumerate(fc["path_mid"])],
                "lo": [fc["actual_cum"][-1] - tp * win.days] + [v - tp * (win.days + i + 1) for i, v in enumerate(fc["path_lo"])],
                "hi": [fc["actual_cum"][-1] - tp * win.days] + [v - tp * (win.days + i + 1) for i, v in enumerate(fc["path_hi"])],
                "target_per_day": tp, "month_short": month_label(win.month, year=False)}

    regions = []
    for r in REGIONS if not region else [region]:  # noqa: B007
        s = _series(t, metric, r)
        if not s:
            continue
        rf = forecast(s, last)
        rt = region_target(targets, metric, r)
        regions.append({"region": r, "label": region_label(r), "color": REGION_COLOR.get(r, "#5A6B68"), "mtd": rf["mtd"],
                        "estimate": rf["estimate"], "target": rt, "gap": rf["estimate"] - rt if rt else None,
                        "per_day": rf["mtd"] / win.days, "need_per_day": (rt - rf["mtd"]) / win.remaining if rt and win.remaining else None})

    if not region and len(regions) == len(REGIONS):
        # Circle Java = sum of the regions (each with its own weekday pattern), so the
        # headline estimate and the region table always agree
        shift = sum(r["estimate"] for r in regions) - fc["estimate"]
        n = max(len(fc["path_mid"]), 1)
        for key in ("path_mid", "path_lo", "path_hi"):
            fc[key] = [v + shift * (i + 1) / n for i, v in enumerate(fc[key])]
        fc["estimate"] += shift
        fc["lo"] += shift
        fc["hi"] += shift
        gap = fc["estimate"] - target if target else None
        if path:
            for key, src in (("mid", "path_mid"), ("lo", "path_lo"), ("hi", "path_hi")):
                path[key] = [path[key][0]] + [v - tp * (win.days + i + 1) for i, v in enumerate(fc[src])]
    levers = _levers(t, metric, region, fc, win, targets)
    bt = backtest(series, last)
    unit_idr = METRICS[metric]["unit"] == "IDR"
    scope_label = region_label(region) if region else "Circle Java"
    mlabel = SIM_METRICS[metric]
    note = None
    if target is None:
        note = f"Target {mlabel} belum diisi di targets.json, jadi gap dan run-rate perlu tidak bisa dihitung."
    say = None
    if target and need is not None:
        fmt = (lambda v: rp(v)) if unit_idr else (lambda v: f"{round(v):,}".replace(",", "."))
        say = (f"{mlabel} perlu {fmt(need)} per hari sampai {win.dim} {month_label(win.month, year=False)}, "
               f"{'di atas' if need > per_day else 'di bawah'} rata-rata {win.days} hari terakhir {fmt(per_day)}. "
               f"Estimasi akhir bulan {fmt(fc['estimate'])}, gap sekitar {fmt(abs(gap))}. Ini estimasi, bukan realisasi.")
    return {
        "metric": metric, "metric_label": mlabel, "unit": METRICS[metric]["unit"], "region": region or None, "scope_label": scope_label,
        "month": win.month, "month_label": month_label(win.month), "title": f"{mlabel} {scope_label}, {month_label(win.month)}",
        "source": source,
        "basis": {"data_until": day_label(last), "remaining_days": win.remaining, "weekend_days": weekend,
                  "target_source": f"targets.json {month_label(win.month)}" if target else None},
        "days_elapsed": win.days, "days_in_month": win.dim, "mtd": fc["mtd"], "per_day": per_day,
        "estimate": {"mid": fc["estimate"], "lo": fc["lo"], "hi": fc["hi"],
                     "pct": fc["estimate"] / target * 100 if target else None,
                     "pct_lo": fc["lo"] / target * 100 if target else None, "pct_hi": fc["hi"] / target * 100 if target else None},
        "target": target, "target_vs_prev_pct": (target / prev_total - 1) * 100 if target and prev_total else None,
        "prev_month_label": month_label(prev_m, year=False),
        "gap": gap, "need_per_day": need, "path": path, "regions": regions, "levers": levers,
        "target_note": note, "agent_says": say,
        "method": "Metode: run-rate harian disesuaikan pola hari dalam seminggu 8 minggu terakhir."
                  + (f" Diuji balik {bt['months']} bulan, rata-rata meleset {pct(bt['mean_abs_pct'], sign=False)}." if bt else ""),
        "backtest": bt,
    }


def _levers(t: dict, metric: str, region: str, fc: dict, win: Window, targets: dict) -> list[dict]:
    rest = fc["estimate"] - fc["mtd"]
    out = []
    if metric == "revenue":
        out.append({"key": "rate", "kind": "slider", "label": "Revenue per RGU", "unit": "%", "min": 0, "max": 3, "step": 0.1, "value": 0,
                    "note": f"Dari program paket atau upsell, untuk {win.remaining} hari tersisa",
                    "effect": {"type": "pct_of", "base": rest}})
        # recover the region with the deepest volume loss (Diagnosa, full months)
        rows = t.get("kec_month") or []
        if rows:
            latest = max(int(r["month_id"]) for r in rows)
            cur_m = complete_month(latest, win.last)
            prev_m = perf_dump.month_add(cur_m, -1)
            worst = None
            for rg in ([region] if region else REGIONS):
                recs: dict = {}
                for r in rows:
                    m = int(r["month_id"])
                    if m in (cur_m, prev_m) and norm(r.get("region")) == rg:
                        a = recs.setdefault(r.get("kec_id"), {"cur": 0.0, "prev": 0.0, "subs_cur": 0.0, "subs_prev": 0.0})
                        side = "cur" if m == cur_m else "prev"
                        a[side] += f(r.get("revenue"))
                        a["subs_" + side] += f(r.get("subs"))
                e = effects(list(recs.values()))
                if e and e["volume"] < 0 and (worst is None or e["volume"] < worst[1]):
                    worst = (rg, e["volume"])
            if worst:
                eff = -worst[1] * win.remaining / win.dim
                out.append({"key": "recover", "kind": "toggle", "label": f"Pulihkan RGU {region_label(worst[0])}",
                            "value_label": f"Level {month_label(prev_m, year=False)}", "value": 0,
                            "note": f"Mengembalikan efek volume {rp_m(worst[1], sign=True)} per bulan dari Diagnosa",
                            "effect": {"type": "fixed", "amount": eff}})
        per_site = float(targets.get("new_site_revenue") or NEW_SITE_IDR)
        out.append({"key": "sites", "kind": "slider", "label": "Site baru on air", "unit": "site", "min": 0, "max": 40, "step": 1, "value": 0,
                    "note": f"Rata-rata site baru {rp(per_site)} per bulan, prorata",
                    "effect": {"type": "per_unit", "amount": per_site * win.remaining / win.dim * RAMP}})
        out.append({"key": "churn", "kind": "locked", "label": "Churn dan ARPU paket",
                    "note": "Belum tersedia di Performance dump. Akan aktif saat data masuk."})
    else:
        lvl = fc["level"]
        out.append({"key": "uplift", "kind": "slider", "label": "Tambahan per hari", "unit": "%", "min": 0, "max": 30, "step": 1, "value": 0,
                    "note": f"Program penjualan untuk {win.remaining} hari tersisa", "effect": {"type": "pct_of", "base": rest}})
        out.append({"key": "locked", "kind": "locked", "label": "Kanal dan outlet", "note": "Belum tersedia di Performance dump. Akan aktif saat data masuk.",
                    "level": lvl})
    return out


@router.get("")
def simulasi(metric: str = Query("revenue"), region: str = Query(""), user: User = Depends(get_current_user)):
    return build(metric, region)
