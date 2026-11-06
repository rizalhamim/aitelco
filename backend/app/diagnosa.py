"""Diagnosa "Kenapa?": why a KPI moved, split down to sites.

GET /api/diagnosa?metric=revenue&region=WEST%20JAVA&kabupaten=&basis=month&by=child

  total       change of the scope between the two periods
  contrib     change per child area (region > kabupaten > kecamatan), largest first,
              the rest grouped as "Lainnya" (never hidden); contributions always add up
              to the total
  effects     volume (RGU 90D), rate (metric per RGU) and mix (shift between kecamatan
              with different rates): volume + rate + mix = total
  tree        biggest path: child > grandchild > sites
  hypotheses  rule-based, labelled, with evidence for and against and a confidence level
  missing     what the dump cannot test yet

Bases: "month" compares the last complete month with the one before (full months),
"mtd" compares MTD with LMTD on the same days. No LLM is involved.
"""
from __future__ import annotations

import time
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from . import perf_dump
from .auth import get_current_user
from .database import User
from .v3_common import (METRICS, Window, complete_month, f, fmt_delta, fmt_value, growth, last_day, lower_label, month_label, norm, num,
                        pct, region_label, rp_m, seg, tables, title)

router = APIRouter(prefix="/api/diagnosa", tags=["diagnosa"])

LEVELS = ["circle", "region", "kabupaten", "kecamatan"]
LEVEL_NOUN = {"region": "region", "kabupaten": "kab/kota", "kecamatan": "kec."}
TOP_N = 6
AVAIL_OK = 99.5


def _records(t: dict, basis: str, metric: str) -> tuple[list[dict], dict]:
    """[{region, kabupaten, kecamatan, cur, prev, subs_cur, subs_prev}] and period labels."""
    col = METRICS[metric]["col"]
    kd = t.get("kab_daily") or t.get("region_daily") or []
    last = last_day(kd)
    if basis == "mtd":
        rows = t.get("kec_mtd") or []
        if not rows or not last:
            raise HTTPException(409, "Data harian belum tersedia untuk basis MTD")
        win = Window(last)
        by: dict = {}
        for r in rows:
            k = r.get("kec_id")
            rec = by.setdefault(k, {"region": r.get("region"), "kabupaten": r.get("kabupaten"), "kecamatan": r.get("kecamatan"),
                                    "cur": 0.0, "prev": 0.0, "subs_cur": 0.0, "subs_prev": 0.0})
            side = "cur" if r.get("period") == "mtd" else "prev"
            rec[side] += f(r.get(col))
            rec["subs_" + side] += f(r.get("subs"))
        labels = {"kind": "mtd", "label": win.label(), "short": win.label().replace("MTD ", "").replace("LMTD ", ""),
                  "cur": f"MTD {win.last.day} {month_label(win.month, year=False)}", "prev": "LMTD",
                  "cur_month": win.month, "prev_month": perf_dump.month_add(win.month, -1), "site_month": None}
        return list(by.values()), labels
    rows = t.get("kec_month") or []
    if not rows:
        raise HTTPException(503, "Data Performance belum tersedia")
    latest = max(int(r["month_id"]) for r in rows)
    cur_m = complete_month(latest, last)
    prev_m = perf_dump.month_add(cur_m, -1)
    by = {}
    for r in rows:
        m = int(r["month_id"])
        if m not in (cur_m, prev_m):
            continue
        k = r.get("kec_id")
        rec = by.setdefault(k, {"region": r.get("region"), "kabupaten": r.get("kabupaten"), "kecamatan": r.get("kecamatan"),
                                "cur": 0.0, "prev": 0.0, "subs_cur": 0.0, "subs_prev": 0.0})
        side = "cur" if m == cur_m else "prev"
        rec[side] += f(r.get(col))
        rec["subs_" + side] += f(r.get("subs"))
    cl, pl = month_label(cur_m), month_label(prev_m)
    labels = {"kind": "month", "label": f"{cl} vs {pl}, bulan penuh",
              "short": f"Bulan penuh {month_label(cur_m, year=False)} vs {month_label(prev_m, year=False)}",
              "cur": cl, "prev": pl, "cur_month": cur_m, "prev_month": prev_m, "site_month": cur_m}
    return list(by.values()), labels


def _group(recs: list[dict], level: str) -> list[dict]:
    by: dict = {}
    for r in recs:
        key = norm(r.get(level))
        if not key:
            continue
        g = by.setdefault(key, {"key": key, "name": region_label(key) if level == "region" else title(key),
                                "cur": 0.0, "prev": 0.0, "subs_cur": 0.0, "subs_prev": 0.0, "n": 0})
        for k in ("cur", "prev", "subs_cur", "subs_prev"):
            g[k] += r[k]
        g["n"] += 1
    for g in by.values():
        g["delta"] = g["cur"] - g["prev"]
    return list(by.values())


def _ranked(groups: list[dict], total_delta: float, n: int = TOP_N) -> tuple[list[dict], Optional[dict]]:
    """Top n by impact (same sign as the total first), the rest grouped."""
    sign = -1 if total_delta < 0 else 1
    by_size = sorted(groups, key=lambda g: -abs(g["delta"]))
    top, rest = by_size[:n], by_size[n:]
    top.sort(key=lambda g: (0 if g["delta"] * sign > 0 else 1, -abs(g["delta"])))
    other = None
    if rest:
        other = {"key": "_other", "name": "Lainnya", "count": len(rest), "other": True,
                 "delta": sum(g["delta"] for g in rest), "cur": sum(g["cur"] for g in rest), "prev": sum(g["prev"] for g in rest)}
    for g in top + ([other] if other else []):
        g["share_pct"] = round(g["delta"] / total_delta * 100, 1) if total_delta else None
    return top, other


def effects(recs: list[dict]) -> Optional[dict]:
    """Volume / rate / mix split of the change over the kecamatan in scope (sums to the total)."""
    s0 = sum(r["subs_prev"] for r in recs)
    s1 = sum(r["subs_cur"] for r in recs)
    r0 = sum(r["prev"] for r in recs)
    r1 = sum(r["cur"] for r in recs)
    if s0 <= 0 or s1 <= 0:
        return None
    a0 = r0 / s0
    mix_rate = 0.0  # sum w1 * a0_k
    rate = 0.0
    for r in recs:
        if r["subs_cur"] <= 0:
            continue
        w1 = r["subs_cur"] / s1
        a0k = r["prev"] / r["subs_prev"] if r["subs_prev"] > 0 else a0
        a1k = r["cur"] / r["subs_cur"]
        mix_rate += w1 * a0k
        rate += w1 * (a1k - a0k)
    volume = (s1 - s0) * a0
    mix = s1 * (mix_rate - a0)
    rate = s1 * rate
    # rows without current subscribers carry their whole change: keep the identity exact
    rest = (r1 - r0) - (volume + mix + rate)
    rate += rest
    return {"volume": volume, "rate": rate, "mix": mix, "total": r1 - r0,
            "subs_pct": growth(s1, s0), "rate_pct": growth(r1 / s1, a0)}


def _sites(site_rows: list[dict], kab: str, kec: str, month: Optional[int], col: str, sign: float, n: int = 6) -> Optional[dict]:
    if not month or not site_rows:
        return None
    prev = perf_dump.month_add(month, -1)
    by: dict = {}
    for r in site_rows:
        if norm(r.get("kecamatan")) != kec or (kab and norm(r.get("kabupaten")) != kab):
            continue
        s = by.setdefault(str(r["site_id"]), {"site_id": str(r["site_id"]), "m": {}})
        s["m"][int(r["month_id"])] = r
    items = []
    for s in by.values():
        c, p = s["m"].get(month), s["m"].get(prev)
        if not c or not p or c.get(col) is None or p.get(col) is None:
            continue
        items.append({"site_id": s["site_id"], "delta": f(c.get(col)) - f(p.get(col)), "avail": c.get("avail")})
    if not items:
        return None
    items.sort(key=lambda i: i["delta"] * sign, reverse=True)
    shown = items[:n]
    av = [float(i["avail"]) for i in shown if i.get("avail") is not None]
    return {"count": len(items), "items": [{"site_id": i["site_id"], "delta": i["delta"]} for i in shown],
            "avail_min": min(av) if av else None, "avail_max": max(av) if av else None,
            "below": sum(1 for a in av if a < AVAIL_OK)}


def _coverage(site_rows: list[dict], scope: dict, month: Optional[int]) -> Optional[float]:
    m = month or (max((int(r["month_id"]) for r in site_rows), default=None) if site_rows else None)
    if not m:
        return None
    ss = [r for r in site_rows if int(r["month_id"]) == m and _in_scope_site(r, scope)]
    if not ss:
        return None
    return round(sum(1 for r in ss if r.get("lat") is not None and r.get("lon") is not None) / len(ss) * 100, 1)


def _in_scope_site(r: dict, scope: dict) -> bool:
    if scope.get("kabupaten"):
        return norm(r.get("kabupaten")) == scope["kabupaten"]
    if scope.get("provinces") is not None:
        return norm(r.get("provinsi")) in scope["provinces"]
    return True


def build(metric: str = "revenue", region: str = "", kabupaten: str = "", basis: str = "month", by: str = "child") -> dict:
    t0 = time.time()
    if metric not in ("revenue", "payload", "subs"):
        raise HTTPException(400, "Metrik tidak didukung")
    t, source = tables("kec_month", "kec_mtd", "kab_daily", "region_daily", "site_month", "avail_month")
    recs, per = _records(t, basis, metric)
    region, kabupaten = norm(region), norm(kabupaten)
    if kabupaten:
        recs = [r for r in recs if norm(r.get("kabupaten")) == kabupaten]
        level, child, name = "kabupaten", "kecamatan", title(kabupaten)
        if not region and recs:
            region = norm(recs[0].get("region"))
    elif region:
        recs = [r for r in recs if norm(r.get("region")) == region]
        level, child, name = "region", "kabupaten", region_label(region)
    else:
        level, child, name = "circle", "region", "Circle Java"
    if not recs:
        raise HTTPException(404, "Wilayah tidak ditemukan di data Performance")
    if by == "kecamatan" and level != "kabupaten":
        child = "kecamatan"
    steps = 1
    cur, prev = sum(r["cur"] for r in recs), sum(r["prev"] for r in recs)
    delta = cur - prev
    g_pct = growth(cur, prev)
    groups = _group(recs, child)
    top, other = _ranked(groups, delta)
    steps += 1
    eff = effects(recs) if metric != "subs" else None
    steps += 1
    m = METRICS[metric]
    sign = -1.0 if delta < 0 else 1.0
    site_rows = t.get("site_month") or []
    provinces = None
    if level == "region":
        provinces = {norm(r.get("provinsi")) for r in (t.get("kec_month") or []) if norm(r.get("region")) == region and r.get("provinsi")}
    scope = {"level": level, "name": name, "region": region or None, "kabupaten": kabupaten or None, "provinces": provinces}

    # Tree: child > grandchild > sites, following the biggest change in the direction of the total
    same = [g for g in sorted(groups, key=lambda g: g["delta"] * sign, reverse=True) if g["delta"] * sign > 0]
    tree: dict = {"level1": [], "level2": [], "sites": None}
    path_kab, path_kec = (kabupaten or None), None
    if same:
        lvl1 = same[:2]
        tree["level1"] = [{"key": g["key"], "name": g["name"], "delta": g["delta"], "share_pct": round(g["delta"] / delta * 100) if delta else None,
                           "on": i == 0} for i, g in enumerate(lvl1)]
        first = lvl1[0]
        nxt = {"region": "kabupaten", "kabupaten": "kecamatan", "kecamatan": None}[child]
        if nxt:
            sub = [r for r in recs if norm(r.get(child)) == first["key"]]
            g2 = sorted(_group(sub, nxt), key=lambda g: g["delta"] * sign, reverse=True)
            shown, rest = g2[:3], g2[3:]
            tree["level2"] = [{"key": g["key"], "name": g["name"], "delta": g["delta"], "on": i == 0} for i, g in enumerate(shown)]
            if rest:
                tree["level2_other"] = {"count": len(rest), "delta": sum(g["delta"] for g in rest), "noun": LEVEL_NOUN[nxt]}
            if child == "kabupaten":
                path_kab = first["key"]
            if nxt == "kecamatan" and shown:
                path_kec = shown[0]["key"]
                if child == "kabupaten":
                    path_kab = first["key"]
        elif child == "kecamatan":
            path_kec = first["key"]
        if path_kec:
            col = "revenue" if metric == "revenue" else "payload_gb"
            sites = _sites(site_rows, path_kab or "", path_kec, per["site_month"], col, sign)
            if sites:
                sites["kecamatan"] = title(path_kec)
                # level-2 nodes show their site counts when known
                for nd in tree["level2"]:
                    nd["sites"] = _site_count(site_rows, path_kab or "", nd["key"], per["site_month"])
                tree["sites"] = sites
    steps += 1

    # Hypotheses (rule based)
    hyps = _hypotheses(metric, eff, recs, tree, child, delta, sign, t.get("avail_month") or [], scope, per)
    steps += 1

    top2 = [g for g in top if g["delta"] * sign > 0][:2]
    share2 = sum(g["delta"] for g in top2) / delta * 100 if delta and top2 else None
    verb = "turun" if delta < 0 else "naik"
    chg_word = "penurunan" if delta < 0 else "kenaikan"
    mlabel = m["label"] if metric != "subs" else "Pelanggan aktif (RGU 90D)"
    names2 = " dan ".join(g["name"] for g in top2)
    parts: list = [f"{mlabel} {verb} ", ("e", fmt_delta(metric, abs(delta)).lstrip("+")), f" ke {fmt_value(metric, cur)}. "]
    short: list = []
    if share2 is not None and names2 and share2 > 100:
        parts += [("b", f"{names2} menyumbang lebih dari seluruh {chg_word}"), ", wilayah lain bergerak berlawanan. "]
        short += [("b", f"{names2} melebihi total {chg_word}."), " "]
    elif share2 is not None and names2:
        parts += [("b", f"{round(share2)}% {chg_word} datang dari {names2}"), ". "]
        short += [("b", f"{round(share2)}% dari {names2}."), " "]
    if eff:
        big = min(("volume", "rate", "mix"), key=lambda k: eff[k] * sign * -1)
        net_ok = not any(h["key"] == "network" and h["confidence"] >= 2 for h in hyps)
        if big == "volume":
            why = "jumlah pelanggan aktif " + verb
            clause = f" (efek volume {rp_m(eff['volume'], sign=True) if metric == 'revenue' else fmt_delta(metric, eff['volume'])})"
        elif big == "rate":
            why = f"{m['label'].lower()} per pelanggan {verb}"
            clause = f" (efek rate {rp_m(eff['rate'], sign=True) if metric == 'revenue' else fmt_delta(metric, eff['rate'])})"
        else:
            why = "pergeseran ke area dengan rate berbeda"
            clause = f" (efek mix {rp_m(eff['mix'], sign=True) if metric == 'revenue' else fmt_delta(metric, eff['mix'])})"
        calm = big == "volume" and abs(eff["rate"]) < abs(eff["volume"]) * .5 and net_ok
        tail = (", bukan karena harga atau kualitas jaringan" if metric == "revenue" else ", bukan karena kualitas jaringan") if calm else ""
        parts += ["Sebagian besar karena ", ("b", why), clause + tail + "."]
        short += [f"Penyebab utama {why}{clause.replace(' (efek volume ', ' (').replace(' (efek rate ', ' (').replace(' (efek mix ', ' (')}"
                  + ((", bukan harga atau jaringan" if metric == "revenue" else ", bukan jaringan") if tail else "") + "."]
    steps += 0
    follow = []
    if len(top2) > 1:
        follow.append({"label": f"Bandingkan dengan {top2[1]['name']}", "question": f"Bandingkan {m['label'].lower()} {top2[0]['name']} dengan {top2[1]['name']}, {per['label']}"})
    target_node = (tree["level2"][0]["name"] if tree["level2"] else (tree["level1"][0]["name"] if tree["level1"] else name))
    follow.append({"label": f"Tren 6 bulan {target_node}", "question": f"Tren {m['label'].lower()} 6 bulan terakhir {target_node}"})

    contrib = [{"key": g["key"], "name": g["name"], "delta": g["delta"], "share_pct": g.get("share_pct")} for g in top]
    if other:
        contrib.append({"key": "_other", "name": "Lainnya", "count": other["count"], "noun": LEVEL_NOUN.get(child, ""),
                        "delta": other["delta"], "share_pct": other.get("share_pct"), "other": True})
    return {
        "metric": metric, "metric_label": mlabel, "unit": m["unit"],
        "scope": {k: v for k, v in scope.items() if k != "provinces"},
        "child_level": child, "child_noun": {"region": "region", "kabupaten": "kabupaten/kota", "kecamatan": "kecamatan"}[child],
        "basis": per | {"cur_month": per["cur_month"], "prev_month": per["prev_month"]},
        "source": source,
        "coverage_pct": _coverage(site_rows, scope, per["site_month"]),
        "title": f"Kenapa {lower_label(metric) if metric != 'subs' else 'pelanggan aktif'} {name} {verb} {num(abs(g_pct or 0), 1)}%?",
        "total": {"prev": prev, "cur": cur, "delta": delta, "pct": g_pct},
        "summary": seg(*parts), "summary_short": seg(*short),
        "contrib": contrib, "effects": eff, "tree": tree, "hypotheses": hyps,
        "missing": "distribusi voucher dan outlet. Data channel belum ada di Performance dump.",
        "follow_ups": follow,
        "steps": steps, "elapsed_s": round(time.time() - t0, 1),
        "task_prefill": {"title": f"Cek {tree['sites']['count']} site {tree['sites']['kecamatan']}" if tree.get("sites") else f"Tindak lanjut {m['label'].lower()} {name}",
                         "origin": "diagnosa", "region": region or None, "kabupaten": path_kab, "metric": metric,
                         "impact": tree["level1"][0]["delta"] if tree["level1"] else delta},
    }


def _site_count(site_rows: list[dict], kab: str, kec: str, month: Optional[int]) -> Optional[int]:
    if not month:
        return None
    ids = {str(r["site_id"]) for r in site_rows if int(r["month_id"]) == month and norm(r.get("kecamatan")) == kec
           and (not kab or norm(r.get("kabupaten")) == kab)}
    return len(ids) or None


def _hypotheses(metric, eff, recs, tree, child, delta, sign, avail_rows, scope, per) -> list[dict]:
    out = []
    verb = "turun" if delta < 0 else "naik"
    if eff and metric in ("revenue", "payload"):
        lvl2 = {n["key"] for n in tree.get("level2") or []}
        key = "kecamatan" if child in ("kabupaten", "kecamatan") else "kabupaten"
        sub = [r for r in recs if norm(r.get(key)) in lvl2] if lvl2 else recs
        sp = growth(sum(r["subs_cur"] for r in sub), sum(r["subs_prev"] for r in sub))
        pay = None
        if metric == "revenue":
            pay = eff.get("rate_pct")
        ev = []
        if sp is not None and sp * sign > 0:
            where = f" di {len(lvl2)} kecamatan teratas" if lvl2 and key == "kecamatan" else (f" di {len(lvl2)} kab/kota teratas" if lvl2 else "")
            ev.append({"kind": "p", "text": f"RGU 90D {verb} {num(abs(sp), 1)}%{where}"})
        rate_pct = eff.get("rate_pct")
        if rate_pct is not None and abs(rate_pct) < 2:
            ev.append({"kind": "p", "text": f"{'Revenue' if metric == 'revenue' else 'Payload'} per RGU relatif tetap ({pct(rate_pct)}), bukan soal harga"})
        ev.append({"kind": "n", "text": "Market share belum tersedia di dump untuk konfirmasi"})
        conf = min(2, sum(1 for e in ev if e["kind"] == "p"))
        if delta < 0 and abs(eff["volume"]) >= abs(eff["rate"]):
            out.append({"key": "volume", "title": "Pelanggan pindah ke kompetitor", "short_title": "Pindah ke kompetitor", "confidence": max(conf, 1), "evidence": ev})
        elif delta < 0 and pay is not None:
            out.append({"key": "rate", "title": "Harga atau komposisi paket berubah", "short_title": "Harga atau paket", "confidence": 2,
                        "evidence": [{"kind": "p", "text": f"Revenue per RGU {pct(pay)}"},
                                     {"kind": "n", "text": "ARPU per paket belum tersedia di dump"}]})
    # network
    sites = tree.get("sites")
    av_min, av_max, below = (sites or {}).get("avail_min"), (sites or {}).get("avail_max"), (sites or {}).get("below", 0)
    if av_min is None:
        name = scope.get("kabupaten") or scope.get("region") or "JAVA"
        lvl = "kabkot" if scope.get("kabupaten") else ("region" if scope.get("region") else "circle")
        vals = [float(r["avail"]) for r in avail_rows if r.get("level") == lvl and norm(r.get("name")) == norm(name)
                and int(r["month_id"]) == (per.get("cur_month") or 0) and r.get("avail") is not None]
        if vals:
            av_min = av_max = vals[0]
            below = 1 if vals[0] < AVAIL_OK else 0
    if av_min is not None:
        rng = f"{num(av_min, 1)}% sd {num(av_max, 1)}%" if av_max is not None and round(av_max, 1) != round(av_min, 1) else f"{num(av_min, 1)}%"
        if below:
            out.append({"key": "network", "title": "Gangguan jaringan", "short_title": "Gangguan jaringan", "confidence": 3 if below > 2 else 2,
                        "evidence": [{"kind": "p", "text": f"Availability {rng}, {below} site di bawah ambang {num(AVAIL_OK, 1)}%"}]})
        else:
            out.append({"key": "network", "title": "Gangguan jaringan", "short_title": "Gangguan jaringan", "confidence": 1,
                        "evidence": [{"kind": "m", "text": f"Availability {rng}, tidak ada site di bawah ambang"}]})
    out.sort(key=lambda h: -h["confidence"])
    labels = {1: "Rendah", 2: "Sedang", 3: "Tinggi"}
    for i, h in enumerate(out):
        h["n"] = i + 1
        h["confidence_label"] = labels[h["confidence"]]
        h["text"] = ". ".join(e["text"] for e in h["evidence"]) + "."
    return out


@router.get("")
def diagnosa(metric: str = Query("revenue"), region: str = Query(""), kabupaten: str = Query(""),
             basis: str = Query("month", pattern="^(month|mtd)$"), by: str = Query("child", pattern="^(child|kecamatan)$"),
             user: User = Depends(get_current_user)):
    return build(metric, region, kabupaten, basis, by)
