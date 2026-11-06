"""Klasemen: ranking of regions, kabupaten/kota and kecamatan against target.

GET /api/klasemen?level=kabupaten&metric=revenue&sort=achievement&region=

Basis is apple-to-apple: MTD (day 1 to the latest dumped day) against LMTD (the same
days last month), from kab_daily / region_daily / kec_mtd. Without daily data it falls
back to full months (last complete month vs the one before) and says so.

  achievement  month-end projection (MTD run-rate) / monthly target, in percent (estimate)
  growth       MTD vs LMTD in percent and in rupiah (always both)
  small base   LMTD revenue below Rp 1 M: flagged and its dot faded, never removed
  move         rank change against the ranking 7 days earlier

Targets come from data/targets.json per region. Kabupaten/kecamatan targets come from
targets.json "kabupaten" when present, otherwise from the region target split by each
area's share of the region in the last complete month (said in "target_note").
"""
from __future__ import annotations

import json
from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from . import perf_dump
from .auth import get_current_user
from .database import User, WatchRule, get_db
from .diagnosa import effects
from .v3_common import (METRICS, REGION_COLOR, Window, complete_month, f, growth, last_day, load_targets,
                        month_label, norm, num, pct, region_label, region_target, tables, title)

router = APIRouter(prefix="/api/klasemen", tags=["klasemen"])

SMALL_BASE_IDR = 1e9
LEVEL_NOUN = {"region": "region", "kabupaten": "kab/kota", "kecamatan": "kecamatan"}
LEVEL_TITLE = {"region": "region", "kabupaten": "kabupaten/kota", "kecamatan": "kecamatan"}
KLAS_METRICS = {
    "revenue": "Revenue", "payload": "Payload", "subs": "RGU 90D", "rev_site": "Revenue per site", "availability": "Availability",
}


def _key(level: str):
    return lambda r: norm(r.get(level)) or None


def _areas(t: dict, level: str, metric: str, last_override=None) -> tuple[dict, dict]:
    """{key: {name, region, cur, prev, subs_cur, subs_prev}} and the basis description."""
    col = METRICS.get(metric, {}).get("col", "revenue")
    flow = METRICS.get(metric, {}).get("flow", True)
    daily = t.get("kab_daily") or []
    if level == "region" and not daily:
        daily = t.get("region_daily") or []
    last = last_override or last_day(daily or t.get("region_daily") or [])
    out: dict = {}
    if last and level in ("region", "kabupaten") and daily and any(r.get(col) is not None for r in daily[:50]):
        win = Window(last)
        rows = [r for r in daily if r.get(level)]
        sums = {}
        for r in rows:
            sums.setdefault(norm(r[level]), {"region": norm(r.get("region"))})
        for k, (c, p) in _mtd(rows, win, level, col, flow).items():
            sums[k].update(cur=c, prev=p)
        for k, (c, p) in _mtd(rows, win, level, "subs", False).items():
            sums[k].update(subs_cur=c, subs_prev=p)
        for k, v in sums.items():
            out[k] = {"name": region_label(k) if level == "region" else title(k), "region": v["region"] if level != "region" else k,
                      "cur": v.get("cur", 0.0), "prev": v.get("prev", 0.0), "subs_cur": v.get("subs_cur", 0.0), "subs_prev": v.get("subs_prev", 0.0)}
        return out, {"kind": "mtd", "label": win.label(), "win": win}
    if last and level == "kecamatan" and t.get("kec_mtd") and not last_override:
        win = Window(last)
        for r in t["kec_mtd"]:
            k = norm(r.get("kecamatan")) + "|" + norm(r.get("kabupaten"))
            a = out.setdefault(k, {"name": title(r.get("kecamatan")), "kabupaten": title(r.get("kabupaten")), "region": norm(r.get("region")),
                                   "cur": 0.0, "prev": 0.0, "subs_cur": 0.0, "subs_prev": 0.0})
            side = "cur" if r.get("period") == "mtd" else "prev"
            a[side] += f(r.get(col))
            a["subs_" + side] += f(r.get("subs"))
        return out, {"kind": "mtd", "label": win.label(), "win": win}
    rows = t.get("kec_month") or []
    if not rows:
        raise HTTPException(503, "Data Performance belum tersedia")
    latest = max(int(r["month_id"]) for r in rows)
    cur_m = complete_month(latest, last)
    prev_m = perf_dump.month_add(cur_m, -1)
    for r in rows:
        m = int(r["month_id"])
        if m not in (cur_m, prev_m):
            continue
        k = norm(r.get(level)) if level != "kecamatan" else norm(r.get("kecamatan")) + "|" + norm(r.get("kabupaten"))
        if not k:
            continue
        a = out.setdefault(k, {"name": region_label(k) if level == "region" else title(r.get(level)), "region": norm(r.get("region")),
                               "kabupaten": title(r.get("kabupaten")), "cur": 0.0, "prev": 0.0, "subs_cur": 0.0, "subs_prev": 0.0})
        side = "cur" if m == cur_m else "prev"
        a[side] += f(r.get(col))
        a["subs_" + side] += f(r.get("subs"))
    return out, {"kind": "month", "label": f"{month_label(cur_m)} vs {month_label(prev_m)}, bulan penuh", "month": cur_m}


def _mtd(rows, win, level, col, flow):
    out: dict = {}
    from .v3_common import as_date
    for r in rows:
        d = as_date(r["dt_id"])
        k = norm(r[level])
        c, p = out.get(k, (0.0, 0.0))
        v = f(r.get(col))
        if win.in_cur(d) and (flow or d == win.last):
            c += v
        elif win.in_prev(d) and (flow or d == win.lm_last):
            p += v
        out[k] = (c, p)
    return out


def _shares(t: dict, level: str, metric: str) -> dict:
    """Share of each area in its region, last complete month (for derived targets)."""
    col = METRICS.get(metric, {}).get("col", "revenue")
    rows = t.get("kec_month") or []
    if not rows:
        return {}
    latest = max(int(r["month_id"]) for r in rows)
    m = complete_month(latest, last_day(t.get("kab_daily") or t.get("region_daily") or []))
    area: dict = {}
    reg: dict = {}
    for r in rows:
        if int(r["month_id"]) != m:
            continue
        k = norm(r.get(level)) if level != "kecamatan" else norm(r.get("kecamatan")) + "|" + norm(r.get("kabupaten"))
        area[k] = area.get(k, 0.0) + f(r.get(col))
        reg[norm(r.get("region"))] = reg.get(norm(r.get("region")), 0.0) + f(r.get(col))
    return {"area": area, "region": reg, "month": m}


def _targets(t: dict, areas: dict, level: str, metric: str) -> tuple[dict, Optional[str]]:
    tg = load_targets()
    out = {}
    note = None
    if level == "region":
        for k in areas:
            out[k] = region_target(tg, metric, k)
        return out, None
    explicit = ((tg.get("kabupaten") or {}).get(metric) or {}) if level == "kabupaten" else {}
    sh = _shares(t, level, metric)
    for k, a in areas.items():
        if explicit.get(k):
            out[k] = float(explicit[k])
            continue
        rt = region_target(tg, metric, a["region"])
        share = (sh.get("area", {}).get(k, 0.0) / sh["region"][a["region"]]) if sh and sh.get("region", {}).get(a["region"]) else None
        out[k] = rt * share if rt and share else None
        if out[k]:
            note = f"Target {LEVEL_NOUN[level]} turunan dari target region, porsi {month_label(sh['month'], year=False)}"
    return out, note


def rank_rows(t: dict, level: str, metric: str, region: str = "", last_override=None) -> tuple[list[dict], dict, Optional[str]]:
    if metric in ("rev_site", "availability"):
        return _month_metric_rows(t, level, metric, region)
    areas, basis = _areas(t, level, metric, last_override)
    if region:
        areas = {k: a for k, a in areas.items() if a["region"] == norm(region)}
    targets, note = _targets(t, areas, level, metric)
    flow = METRICS.get(metric, {}).get("flow", True)
    win = basis.get("win")
    rows = []
    prevs = sorted(a["prev"] for a in areas.values())
    p10 = prevs[len(prevs) // 10] if prevs else 0
    for k, a in areas.items():
        proj = a["cur"] / win.days * win.dim if (win and flow) else a["cur"]
        tg = targets.get(k)
        small = (a["prev"] < SMALL_BASE_IDR) if metric == "revenue" else (a["prev"] <= p10 and len(prevs) > 10)
        rows.append({"key": k, "name": a["name"], "region": a["region"], "region_label": region_label(a["region"]),
                     "region_color": REGION_COLOR.get(a["region"], "#5A6B68"), "kabupaten": a.get("kabupaten"),
                     "cur": a["cur"], "prev": a["prev"], "growth_pct": growth(a["cur"], a["prev"]), "growth_abs": a["cur"] - a["prev"],
                     "projection": proj, "target": tg, "achievement_pct": proj / tg * 100 if tg else None, "small_base": small,
                     "subs_cur": a.get("subs_cur"), "subs_prev": a.get("subs_prev")})
    return rows, basis, note


def _month_metric_rows(t: dict, level: str, metric: str, region: str):
    """Revenue per site and availability: monthly, latest complete month vs the one before."""
    site_rows = t.get("site_month") or []
    rows_k = t.get("kec_month") or []
    latest = max((int(r["month_id"]) for r in rows_k), default=None)
    if latest is None:
        raise HTTPException(503, "Data Performance belum tersedia")
    cur_m = complete_month(latest, last_day(t.get("kab_daily") or t.get("region_daily") or []))
    prev_m = perf_dump.month_add(cur_m, -1)
    basis = {"kind": "month", "label": f"{month_label(cur_m)} vs {month_label(prev_m)}, bulan penuh", "month": cur_m}
    reg_of = {}
    for r in rows_k:
        reg_of[norm(r.get("kabupaten"))] = norm(r.get("region"))
    out = []
    if metric == "availability":
        lvl = {"region": "region", "kabupaten": "kabkot"}.get(level)
        if not lvl:
            raise HTTPException(400, "Availability tersedia per region dan kab/kota")
        vals: dict = {}
        for r in t.get("avail_month") or []:
            if r.get("level") == lvl and int(r["month_id"]) in (cur_m, prev_m) and r.get("avail") is not None:
                vals.setdefault(norm(r["name"]), {})[int(r["month_id"])] = float(r["avail"])
        for k, v in vals.items():
            rg = k if level == "region" else reg_of.get(k)
            if not rg or (region and rg != norm(region)):
                continue
            c, p = v.get(cur_m), v.get(prev_m)
            out.append({"key": k, "name": region_label(k) if level == "region" else title(k), "region": rg, "region_label": region_label(rg),
                        "region_color": REGION_COLOR.get(rg, "#5A6B68"), "cur": c, "prev": p,
                        "growth_pct": (c - p) if c is not None and p is not None else None, "growth_unit": "pp", "growth_abs": None,
                        "projection": c, "target": 99.5, "achievement_pct": c / 99.5 * 100 if c else None, "small_base": False})
        return out, basis, "Target availability 99,5%"
    # revenue per site
    acc: dict = {}
    for r in site_rows:
        m = int(r["month_id"])
        if m not in (cur_m, prev_m) or r.get("revenue") is None:
            continue
        kab = norm(r.get("kabupaten"))
        k = kab if level == "kabupaten" else reg_of.get(kab)
        if level == "kecamatan":
            k = norm(r.get("kecamatan")) + "|" + kab
        if not k:
            continue
        a = acc.setdefault(k, {m2: [0.0, 0] for m2 in (cur_m, prev_m)} | {"kab": kab, "kec": r.get("kecamatan")})
        a[m][0] += f(r["revenue"])
        a[m][1] += 1
    for k, a in acc.items():
        rg = reg_of.get(a["kab"])
        if not rg or (region and rg != norm(region)):
            continue
        c = a[cur_m][0] / a[cur_m][1] if a[cur_m][1] else None
        p = a[prev_m][0] / a[prev_m][1] if a[prev_m][1] else None
        name = region_label(k) if level == "region" else (title(a["kec"]) if level == "kecamatan" else title(k))
        out.append({"key": k, "name": name, "region": rg, "region_label": region_label(rg), "region_color": REGION_COLOR.get(rg, "#5A6B68"),
                    "cur": c, "prev": p, "growth_pct": growth(c, p), "growth_abs": (c - p) if c is not None and p is not None else None,
                    "projection": c, "target": None, "achievement_pct": None, "small_base": False})
    return out, basis, None


def _order(rows: list[dict], sort: str) -> list[dict]:
    if sort == "achievement" and any(r["achievement_pct"] is not None for r in rows):
        key = lambda r: (r["achievement_pct"] is None, -(r["achievement_pct"] or 0), -(r["growth_pct"] or 0))
    else:
        key = lambda r: (r["growth_pct"] is None, -(r["growth_pct"] or 0))
    rows = sorted(rows, key=key)
    for i, r in enumerate(rows):
        r["rank"] = i + 1
    return rows


def _watched(db: Optional[Session], user: Optional[User], level: str) -> Optional[str]:
    """Area the user watches: preferences "klasemen_area", else the first kab/kota watch rule."""
    if not user:
        return None
    try:
        prefs = json.loads(user.preferences or "{}")
    except (TypeError, ValueError):
        prefs = {}
    area = (prefs.get("klasemen_area") or {}).get(level) if isinstance(prefs.get("klasemen_area"), dict) else None
    if area:
        return norm(area)
    if db is not None and level == "kabupaten":
        r = db.query(WatchRule).filter(WatchRule.user_id == user.id, WatchRule.scope_level == "kabkota").order_by(WatchRule.id).first()
        if r:
            return norm(r.scope_value)
    if db is not None and level == "region":
        r = db.query(WatchRule).filter(WatchRule.user_id == user.id, WatchRule.scope_level == "region").order_by(WatchRule.id).first()
        if r:
            return norm(r.scope_value)
    return None


def build(level: str = "kabupaten", metric: str = "revenue", sort: str = "achievement", region: str = "",
          db: Optional[Session] = None, user: Optional[User] = None) -> dict:
    if level not in LEVEL_NOUN or metric not in KLAS_METRICS:
        raise HTTPException(400, "Level atau metrik tidak didukung")
    t, source = tables("kab_daily", "region_daily", "kec_mtd", "kec_month", "site_month", "avail_month")
    rows, basis, note = rank_rows(t, level, metric, region)
    rows = _order(rows, sort)
    # rank movement against 7 days earlier (daily bases only)
    win = basis.get("win")
    if win and level in ("region", "kabupaten"):
        earlier, _, _ = rank_rows(t, level, metric, region, last_override=win.last - timedelta(days=7))
        before = {r["key"]: r["rank"] for r in _order(earlier, sort)}
        for r in rows:
            r["move"] = before[r["key"]] - r["rank"] if r["key"] in before else None
    total = len(rows)
    mine_key = _watched(db, user, level)
    mine = None
    for r in rows:
        r["mine"] = r["key"] == mine_key or (level == "kecamatan" and mine_key and r["key"].startswith(mine_key + "|"))
        if r["mine"] and not mine:
            mine = _mine(r, rows, t, level, metric, basis)
    regions_rows, _, _ = rank_rows(t, "region", metric if metric not in ("rev_site",) else "revenue", "")
    regions = _order(regions_rows, sort)
    month = win.month if win else basis.get("month")
    noun = LEVEL_NOUN[level]
    return {
        "level": level, "metric": metric, "metric_label": KLAS_METRICS[metric], "sort": sort,
        "unit": METRICS.get(metric, {}).get("unit", "%" if metric == "availability" else "IDR"),
        "month_label": month_label(month, long=True) if month else "",
        "title": f"Klasemen {LEVEL_TITLE[level]}, {month_label(month, long=True) if month else ''}".strip(", "),
        "basis": {"kind": basis["kind"], "label": basis["label"]},
        "source": source,
        "small_base_label": "Basis kecil: revenue LMTD di bawah Rp 1 M" if metric == "revenue" else "Basis kecil: 10% basis terkecil",
        "target_note": note, "has_targets": any(r["achievement_pct"] is not None for r in rows),
        "total": total, "noun": noun,
        "rows": rows, "best": rows[:3], "worst": list(reversed(rows[-3:])) if total > 3 else [],
        "mine": mine,
        "regions": [{"rank": r["rank"], "key": r["key"], "name": r["name"], "color": REGION_COLOR.get(r["key"], "#5A6B68"),
                     "achievement_pct": r["achievement_pct"], "growth_pct": r["growth_pct"], "growth_abs": r["growth_abs"]} for r in regions],
        "badges": _badges(rows, t, level),
    }


def _mine(r: dict, rows: list[dict], t: dict, level: str, metric: str, basis: dict) -> dict:
    total = len(rows)
    goal = 100 if total > 100 and r["rank"] > 100 else max(1, r["rank"] - 1)
    need = None
    need_label = None
    if r["rank"] > goal and r.get("target") and r.get("achievement_pct") is not None:
        ref = rows[goal - 1]
        if ref.get("achievement_pct") is not None:
            need = max(0.0, ref["achievement_pct"] / 100 * r["target"] - r["projection"])
            need_label = "untuk masuk 100 besar" if goal == 100 else f"untuk naik ke peringkat {goal}"
    cause = None
    if r.get("subs_prev") and r.get("subs_cur"):
        e = effects([{"cur": r["cur"], "prev": r["prev"], "subs_cur": r["subs_cur"], "subs_prev": r["subs_prev"]}])
        if e:
            if abs(e["rate"]) >= abs(e["volume"]):
                cause = f"{'revenue' if metric == 'revenue' else METRICS.get(metric, {}).get('label', metric).lower()} per RGU {pct(e['rate_pct'])}"
            else:
                cause = f"RGU 90D {pct(e['subs_pct'])}"
    mv = r.get("move")
    move_label = None
    if mv is not None:
        move_label = "tetap minggu ini" if mv == 0 else f"{'naik' if mv > 0 else 'turun'} {abs(mv)} peringkat minggu ini"
    return {"rank": r["rank"], "total": total, "name": r["name"], "key": r["key"], "region": r["region"], "move": mv, "move_label": move_label,
            "need": need, "need_label": need_label, "cause": cause, "growth_pct": r["growth_pct"], "achievement_pct": r["achievement_pct"]}


def _badges(rows: list[dict], t: dict, level: str) -> list[dict]:
    out = []
    moved = [r for r in rows if r.get("move")]
    climbers = [r for r in moved if r["rank"] <= 10 and not r["small_base"] and r["move"] > 0]
    if climbers:
        c = max(climbers, key=lambda r: r["move"])
        out.append({"kind": "climber", "icon": "up", "title": "Pendaki", "text": f"{_short(c['name'])} naik {c['move']}"})
    if level in ("kabupaten", "region"):
        lvl = "kabkot" if level == "kabupaten" else "region"
        av = [r for r in (t.get("avail_month") or []) if r.get("level") == lvl and r.get("avail") is not None]
        if av:
            m = max(int(r["month_id"]) for r in av)
            keys = {r["key"] for r in rows}
            best = max((r for r in av if int(r["month_id"]) == m and norm(r["name"]) in keys), key=lambda r: float(r["avail"]), default=None)
            if best:
                out.append({"kind": "network", "icon": "tower", "title": "Jaringan prima", "text": f"{_short(title(best['name']) if level != 'region' else region_label(best['name']))} {num(float(best['avail']), 1)}%"})
    risers = [r for r in moved if r["move"] > 0]
    if risers:
        b = max(risers, key=lambda r: (r["move"], r.get("growth_pct") or 0))
        if not climbers or b["key"] != max(climbers, key=lambda r: r["move"])["key"]:
            out.append({"kind": "rise", "icon": "spark", "title": "Bangkit", "text": f"{_short(b['name'])} +{b['move']}"})
    return out


def _short(name: str) -> str:
    return name[5:] if name.startswith("Kota ") else name


@router.get("")
def klasemen(level: str = Query("kabupaten"), metric: str = Query("revenue"), sort: str = Query("achievement", pattern="^(achievement|growth)$"),
             region: str = Query(""), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return build(level, metric, sort, region, db, user)
