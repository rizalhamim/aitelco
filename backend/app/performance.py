"""Performance API: KPI drill-down from Circle Java to region, kabupaten, kecamatan and site.

GET /api/performance?region=&kabupaten=&kecamatan=&status=&page=&size=
GET /api/performance/site?site_id=

Numbers come from the daily Performance dump (perf_dump.py, Parquet), so opening the
page runs no BigQuery query. A dump older than STALE_HOURS is still used but labelled
"stale"; without any dump the same dump queries run live on BigQuery once and are kept
in memory for LIVE_TTL. The payload says which in "source" (green / yellow label).

Per scope the payload carries:
  kpis      revenue, payload, pelanggan (MoM and YoY), availability (vs 99,5% target), site counts
  trend     12 months of revenue / payload / pelanggan and the same months a year earlier
  contrib   MoM revenue change per child (region, kabupaten, kecamatan or site)
  sites     site list with payload, revenue and availability MoM, status, paged
Site status is rule based: kritis when payload MoM <= -10% or availability < 99,0%,
waspada when payload MoM <= -6% or availability < 99,5%, otherwise normal.
"""
from __future__ import annotations

import re
import threading
import time
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query

from . import perf_dump
from .auth import get_current_user
from .bigquery_tool import QueryError
from .database import User

router = APIRouter(prefix="/api/performance", tags=["performance"])

MONTHS_ID = perf_dump.MONTHS_ID
AVAIL_TARGET = 99.5
LIVE_TTL = 6 * 3600
MEASURES = {"revenue": "revenue", "payload": "payload_gb", "subs": "subs"}

_live: dict = {}
_live_lock = threading.Lock()


# ── Data source ──────────────────────────────────────────────────────────────

def _live_rows() -> dict:
    """Dump tables queried live on BigQuery (no dump on disk), cached for LIVE_TTL."""
    with _live_lock:
        if _live and time.time() - _live["at"] < LIVE_TTL:
            return _live
    from .bigquery_tool import run_query
    latest = perf_dump._latest_month()
    qs = perf_dump.build_queries(latest, None, perf_dump._columns, perf_dump._column_types)
    out = {"at": time.time(), "latest": latest}
    for name in ("kec_month", "site_month", "avail_month"):
        if name in qs:
            out[name] = run_query(qs[name], row_limit=perf_dump._ROW_CAP)["rows"]
    with _live_lock:
        _live.clear()
        _live.update(out)
    return out


def _data() -> tuple[list[dict], list[dict], list[dict], dict]:
    st = perf_dump.status()
    kec = perf_dump.load("kec_month", allow_stale=True) if st.get("available") else None
    if kec:
        src = {
            "kind": "dump" if st.get("fresh") else "stale",
            "label": st.get("label"),
            "created_at": st.get("created_at"),
            "age_hours": st.get("age_hours"),
            "queries": 0,
        }
        return kec, perf_dump.load("site_month", allow_stale=True) or [], perf_dump.load("avail_month", allow_stale=True) or [], src
    live = _live_rows()
    src = {"kind": "bigquery", "label": "BigQuery langsung", "created_at": datetime.fromtimestamp(live["at"]).isoformat(), "queries": 3}
    return live.get("kec_month") or [], live.get("site_month") or [], live.get("avail_month") or [], src


# ── Helpers ──────────────────────────────────────────────────────────────────

def norm(name: Optional[str]) -> str:
    """Comparable area name: "KAB. GARUT", "Kabupaten Garut" and "garut" all become "GARUT"."""
    s = re.sub(r"\s+", " ", str(name or "").upper()).strip()
    return re.sub(r"^(KABUPATEN|KAB\.?)\s+", "", s)


def title(name: Optional[str]) -> str:
    s = " ".join(w.capitalize() for w in str(name or "").lower().split())
    return re.sub(r"\bDiy\b", "DIY", s)


def _pct(cur: Optional[float], prev: Optional[float]) -> Optional[float]:
    if cur is None or prev in (None, 0):
        return None
    return round((cur / prev - 1) * 100, 2)


def month_label(mid: int, year: bool = True) -> str:
    return f"{MONTHS_ID[mid % 100 - 1]} {mid // 100}" if year else MONTHS_ID[mid % 100 - 1]


LEVEL_KEYS = ["region", "kabupaten", "kecamatan"]
LEVEL_NAMES = {"circle": "Circle", "region": "Region", "kabupaten": "Kabupaten", "kecamatan": "Kecamatan"}


def _status(payload_mom: Optional[float], avail: Optional[float]) -> str:
    if (payload_mom is not None and payload_mom <= -10) or (avail is not None and avail < 99.0):
        return "kritis"
    if (payload_mom is not None and payload_mom <= -6) or (avail is not None and avail < AVAIL_TARGET):
        return "waspada"
    return "normal"


def _scope_filter(region: str, kabupaten: str, kecamatan: str):
    want = [(k, norm(v)) for k, v in (("region", region), ("kabupaten", kabupaten), ("kecamatan", kecamatan)) if v]

    def ok(r: dict) -> bool:
        return all(norm(r.get(k)) == v for k, v in want)
    return ok


# ── Builders ─────────────────────────────────────────────────────────────────

def _sites(site_rows: list[dict], kec_rows: list[dict], latest: int, region: str, kabupaten: str, kecamatan: str) -> list[dict]:
    """One record per site in scope with current, previous and year-ago values."""
    prev, ago = perf_dump.month_add(latest, -1), perf_dump.month_add(latest, -12)
    provinces = None
    if region and not kabupaten:
        provinces = {norm(r.get("provinsi")) for r in kec_rows if norm(r.get("region")) == norm(region) and r.get("provinsi")}
    by: dict[str, dict] = {}
    for r in site_rows:
        if kabupaten and norm(r.get("kabupaten")) != norm(kabupaten):
            continue
        if kecamatan and norm(r.get("kecamatan")) != norm(kecamatan):
            continue
        if provinces is not None and norm(r.get("provinsi")) not in provinces:
            continue
        s = by.setdefault(str(r["site_id"]), {
            "site_id": str(r["site_id"]), "site_name": r.get("site_name"), "kecamatan": title(r.get("kecamatan")),
            "kabupaten": title(r.get("kabupaten")), "lat": r.get("lat"), "lon": r.get("lon"), "m": {}})
        s["m"][int(r["month_id"])] = r
    out = []
    for s in by.values():
        cur, pm, ya = s["m"].get(latest), s["m"].get(prev), s["m"].get(ago)
        if not cur:
            continue

        def g(row, k):
            v = (row or {}).get(k)
            return float(v) if v is not None else None
        rec = {k: v for k, v in s.items() if k != "m"}
        for key, col in (("payload_gb", "payload_gb"), ("revenue", "revenue"), ("availability", "avail")):
            rec[key] = g(cur, col)
            rec[f"{key}_prev"] = g(pm, col)
            rec[f"{key}_yoy"] = g(ya, col)
        rec["payload_mom"] = _pct(rec["payload_gb"], rec["payload_gb_prev"])
        rec["revenue_mom"] = _pct(rec["revenue"], rec["revenue_prev"])
        rec["payload_yoy_pct"] = _pct(rec["payload_gb"], rec["payload_gb_yoy"])
        rec["revenue_yoy_pct"] = _pct(rec["revenue"], rec["revenue_yoy"])
        a, ap = rec["availability"], rec["availability_prev"]
        rec["availability_mom_pp"] = round(a - ap, 2) if a is not None and ap is not None else None
        rec["status"] = _status(rec["payload_mom"], a)
        out.append(rec)
    out.sort(key=lambda r: (r["payload_mom"] if r["payload_mom"] is not None else 1e9, r["site_id"]))
    return out


def _id(v: float, d: int = 1) -> str:
    return f"{v:,.{d}f}".replace(",", "_").replace(".", ",").replace("_", ".")


def fmt_gb(v: Optional[float]) -> str:
    if v is None:
        return "–"
    if abs(v) >= 1e6:
        return f"{_id(v / 1e6, 2)} PB"
    if abs(v) >= 1e3:
        return f"{_id(v / 1e3, 1)} TB"
    return f"{_id(v, 1)} GB"


def fmt_rp(v: Optional[float]) -> str:
    if v is None:
        return "–"
    for div, unit, d in ((1e12, "T", 2), (1e9, "M", 1), (1e6, "jt", 0)):
        if abs(v) >= div:
            return f"Rp {_id(v / div, d)} {unit}"
    return f"Rp {_id(v, 0)}"


def _chg(v: Optional[float], unit: str = "%", what: str = "YoY") -> tuple[str, Optional[str]]:
    if v is None:
        return "tanpa pembanding", None
    return f"{'▲' if v >= 0 else '▼'} {_id(abs(v), 1)}{' pp' if unit == 'pp' else '%'} {what}", "up" if v >= 0 else "down"


def _detail(s: dict, prev_label: str, yoy_label: str) -> list[dict]:
    """Up to four small cards for the inline site detail, from numbers the dump has."""
    out = []
    note, tone = _chg(s.get("payload_yoy_pct"))
    out.append({"label": f"Payload {yoy_label}", "value": fmt_gb(s.get("payload_gb_yoy")), "note": note, "tone": tone})
    note, tone = _chg(s.get("revenue_yoy_pct"))
    out.append({"label": f"Revenue {yoy_label}", "value": fmt_rp(s.get("revenue_yoy")), "note": note, "tone": tone})
    ap = s.get("availability_prev")
    note, tone = _chg(s.get("availability_mom_pp"), "pp", "MoM")
    out.append({"label": f"Availability {prev_label}", "value": f"{_id(ap, 2)}%" if ap is not None else "–", "note": note, "tone": tone})
    if s.get("lat") is not None and s.get("lon") is not None:
        out.append({"label": "Koordinat", "value": f"{_id(s['lat'], 4)}, {_id(s['lon'], 4)}", "note": f"Kec. {s.get('kecamatan') or '-'}", "tone": None})
    return out


def _note(s: dict) -> str:
    """Plain reading of the site's numbers for the detail panel (no LLM call)."""
    parts = []
    pm, rm, a = s.get("payload_mom"), s.get("revenue_mom"), s.get("availability")

    def pc(v):
        return f"{abs(v):.1f}".replace(".", ",") + "%"
    if pm is not None:
        parts.append(f"Payload {'turun' if pm < 0 else 'naik'} {pc(pm)} MoM")
    if rm is not None:
        parts.append(f"revenue {'turun' if rm < 0 else 'naik'} {pc(rm)}")
    text = (", ".join(parts) + ".") if parts else ""
    if a is not None:
        av = f"{a:.2f}".replace(".", ",")
        text += f" Availability {av}% {'di bawah' if a < AVAIL_TARGET else 'memenuhi'} target 99,5%."
    if pm is not None and pm < -6 and a is not None and a >= AVAIL_TARGET:
        text += " Jaringan stabil, jadi penurunan kemungkinan dari sisi permintaan atau kompetisi."
    elif a is not None and a < AVAIL_TARGET:
        text += " Penurunan sejalan dengan gangguan jaringan; cek tiket gangguan site ini."
    return text.strip()


def build(region: str = "", kabupaten: str = "", kecamatan: str = "", status: str = "", page: int = 1, size: int = 7) -> dict:
    kec_rows, site_rows, avail_rows, source = _data()
    if not kec_rows:
        return {"error": "Data Performance belum tersedia. Jalankan dump Performance terlebih dahulu.", "kind": "empty", "source": source}
    latest = max(int(r["month_id"]) for r in kec_rows)
    prev, ago = perf_dump.month_add(latest, -1), perf_dump.month_add(latest, -12)
    months = [perf_dump.month_add(latest, -i) for i in range(11, -1, -1)]
    months_ly = [perf_dump.month_add(m, -12) for m in months]

    ok = _scope_filter(region, kabupaten, kecamatan)
    scoped = [r for r in kec_rows if ok(r)]
    level = "kecamatan" if kecamatan else "kabupaten" if kabupaten else "region" if region else "circle"
    child_key = {"circle": "region", "region": "kabupaten", "kabupaten": "kecamatan", "kecamatan": None}[level]

    tot: dict[int, dict] = {}
    kids: dict[str, dict[int, float]] = {}
    kec_ids: set = set()
    for r in scoped:
        m = int(r["month_id"])
        t = tot.setdefault(m, {k: 0.0 for k in MEASURES})
        for k, col in MEASURES.items():
            t[k] += float(r.get(col) or 0)
        if m == latest:
            kec_ids.add(r.get("kec_id"))
        if child_key and m in (latest, prev):
            kids.setdefault(str(r.get(child_key) or "-"), {}).setdefault(m, 0.0)
            kids[str(r.get(child_key) or "-")][m] += float(r.get("revenue") or 0)

    sites = _sites(site_rows, kec_rows, latest, region, kabupaten, kecamatan)
    counts = {k: sum(1 for s in sites if s["status"] == k) for k in ("kritis", "waspada", "normal")}

    # availability: territory table for circle / region / kabupaten, site average below that
    lvl_name = {"circle": ("circle", "JAVA"), "region": ("region", norm(region)), "kabupaten": ("kabkot", norm(kabupaten))}.get(level)
    av = {}
    if lvl_name:
        for r in avail_rows:
            if r.get("level") == lvl_name[0] and norm(r.get("name")) == lvl_name[1]:
                av[int(r["month_id"])] = r.get("avail")
    if latest not in av:
        vals = [s["availability"] for s in sites if s["availability"] is not None]
        pv = [s["availability_prev"] for s in sites if s["availability_prev"] is not None]
        yv = [s["availability_yoy"] for s in sites if s["availability_yoy"] is not None]
        av = {latest: sum(vals) / len(vals) if vals else None, prev: sum(pv) / len(pv) if pv else None, ago: sum(yv) / len(yv) if yv else None}

    def kpi(key, label, fmt):
        cur, p, y = (tot.get(m, {}).get(key) for m in (latest, prev, ago))
        return {"key": key, "label": label, "format": fmt, "value": cur, "prev": p, "yoy": y,
                "mom_pct": _pct(cur, p), "yoy_pct": _pct(cur, y)}
    a_cur, a_prev, a_yoy = av.get(latest), av.get(prev), av.get(ago)
    kpis = [
        kpi("revenue", "Revenue", "currency"),
        kpi("payload", "Payload", "gb"),
        kpi("subs", "Pelanggan", "number"),
        {"key": "availability", "label": "Availability", "format": "percent", "value": a_cur, "prev": a_prev, "yoy": a_yoy,
         "mom_pp": round(a_cur - a_prev, 2) if a_cur is not None and a_prev is not None else None,
         "yoy_pp": round(a_cur - a_yoy, 2) if a_cur is not None and a_yoy is not None else None, "target": AVAIL_TARGET},
        {"key": "sites", "label": "Site", "format": "number", "value": len(sites), **counts},
    ]

    contrib = sorted(
        ({"name": title(n), "key": n, "value": v.get(latest, 0.0), "delta": v.get(latest, 0.0) - v.get(prev, 0.0)} for n, v in kids.items()),
        key=lambda c: c["delta"])
    if level == "kecamatan":
        contrib = sorted(
            ({"name": s["site_id"], "key": s["site_id"], "value": s["revenue"] or 0.0,
              "delta": (s["revenue"] or 0.0) - (s["revenue_prev"] or 0.0)} for s in sites if s["revenue"] is not None),
            key=lambda c: c["delta"])
    total_delta = (tot.get(latest, {}).get("revenue") or 0.0) - (tot.get(prev, {}).get("revenue") or 0.0)

    shown = [s for s in sites if not status or s["status"] == status]
    size = max(1, min(size, 100))
    pages = max(1, -(-len(shown) // size))
    page = max(1, min(page, pages))
    rows = shown[(page - 1) * size: page * size]
    for s in rows:
        s["note"] = _note(s)
        s["detail"] = _detail(s, month_label(prev, False), month_label(ago))

    name = {"circle": "Circle Java", "region": title(region), "kabupaten": f"Kab. {title(kabupaten)}",
            "kecamatan": f"Kec. {title(kecamatan)}"}[level]
    path = [{"level": "circle", "name": "Circle Java", "value": ""}]
    if region:
        path.append({"level": "region", "name": title(region), "value": region})
    if kabupaten:
        path.append({"level": "kabupaten", "name": title(kabupaten), "value": kabupaten})
    if kecamatan:
        path.append({"level": "kecamatan", "name": title(kecamatan), "value": kecamatan})
    return {
        "level": level, "child_level": child_key or "site", "name": name, "path": path,
        "month_id": latest, "month_label": month_label(latest), "prev_label": month_label(prev), "yoy_label": month_label(ago),
        "kecamatan_count": len({k for k in kec_ids if k}), "site_count": len(sites),
        "kpis": kpis,
        "trend": {
            "months": months, "labels": [month_label(m, False) for m in months], "titles": [month_label(m) for m in months],
            "current": {k: [tot.get(m, {}).get(k) for m in months] for k in MEASURES},
            "previous": {k: [tot.get(m, {}).get(k) for m in months_ly] for k in MEASURES},
        },
        "contrib": contrib, "contrib_total": total_delta,
        "sites": {"rows": rows, "total": len(shown), "page": page, "pages": pages, "size": size, "counts": counts},
        "source": source,
    }


def site_detail(site_id: str) -> dict:
    kec_rows, site_rows, _, source = _data()
    if not kec_rows:
        return {"error": "Data Performance belum tersedia.", "kind": "empty"}
    latest = max(int(r["month_id"]) for r in kec_rows)
    one = [r for r in site_rows if str(r.get("site_id")) == site_id]
    if not one:
        return {"error": f"Site {site_id} tidak ada di dump Performance.", "kind": "not_found"}
    s = _sites(one, kec_rows, latest, "", "", "")
    if not s:
        return {"error": f"Site {site_id} tidak punya data bulan {month_label(latest)}.", "kind": "not_found"}
    s[0]["note"] = _note(s[0])
    s[0]["detail"] = _detail(s[0], month_label(perf_dump.month_add(latest, -1), False), month_label(perf_dump.month_add(latest, -12)))
    return {**s[0], "month_label": month_label(latest), "source": source}


def search(q: str, limit: int = 12) -> list[dict]:
    """Areas and sites whose name or id contains q, for the search box."""
    kec_rows, site_rows, _, _ = _data()
    needle = norm(q)
    if len(needle) < 2:
        return []
    out, seen = [], set()
    for r in kec_rows:
        for lvl in ("kabupaten", "kecamatan"):
            n = r.get(lvl)
            if n and needle in norm(n) and (lvl, norm(n)) not in seen:
                seen.add((lvl, norm(n)))
                out.append({"type": lvl, "name": title(n), "region": r.get("region"), "kabupaten": r.get("kabupaten"),
                            "kecamatan": r.get("kecamatan") if lvl == "kecamatan" else None})
    for r in site_rows:
        sid = str(r.get("site_id") or "")
        if sid and (needle in sid.upper() or needle in norm(r.get("site_name"))) and ("site", sid) not in seen:
            seen.add(("site", sid))
            out.append({"type": "site", "name": sid, "site_name": r.get("site_name"), "kabupaten": r.get("kabupaten"),
                        "kecamatan": r.get("kecamatan")})
    order = {"kabupaten": 0, "kecamatan": 1, "site": 2}
    out.sort(key=lambda o: (order[o["type"]], not norm(o["name"]).startswith(needle), o["name"]))
    return out[:limit]


@router.get("")
def performance(
    region: str = Query(""),
    kabupaten: str = Query(""),
    kecamatan: str = Query(""),
    status: str = Query("", pattern="^(|kritis|waspada|normal)$"),
    page: int = Query(1, ge=1),
    size: int = Query(7, ge=1, le=100),
    user: User = Depends(get_current_user),
):
    try:
        return build(region, kabupaten, kecamatan, status, page, size)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}


@router.get("/search")
def performance_search(q: str = Query(..., min_length=1, max_length=60), user: User = Depends(get_current_user)):
    try:
        return {"results": search(q)}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution", "results": []}


@router.get("/site")
def performance_site(site_id: str = Query(..., min_length=1, max_length=40), user: User = Depends(get_current_user)):
    try:
        return site_detail(site_id)
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
