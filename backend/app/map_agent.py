"""Peta Agent API: map of one kabupaten (or a region) plus a rule-based map chat.

GET  /api/map/agent?region=&kabupaten=
     Projected map frame: kecamatan (or kabupaten) polygons as SVG paths, metric values per
     unit for Performance, Site productivity and Profile wilayah, every site with its
     coordinates, neighbour outlines and the metric catalogue.
POST /api/map/agent/ask      {q, region, kabupaten, shapes}
     Answers a map question with text, layers to add, stats and a focus box.
POST /api/map/agent/upload   {name, data (base64), region, kabupaten}: SHP (.zip), GeoJSON, KML or CSV
     Parsed shape with lon/lat rings, its area and the projected path for the frame.
POST /api/map/agent/export   {format: geojson|shp|csv, name, features}
     Shapefile (.zip), GeoJSON or CSV of the features the client sends.

Geometry is projected once into a FRAME_W x FRAME_H frame (equirectangular, cos(lat)
corrected, fitted to the scope with PAD), so web and Android draw the same paths and only
pick a view box. Numbers come from the Performance dump (performance._data), so the map
runs no BigQuery query when the dump is fresh.

Boundaries come from data/geo/{kecamatan,kabupaten}.geojson.gz (the same files the Android
app ships). They are large, so a compact Java-only copy (java_compact.json.gz) is built
once in a subprocess (`python -m app.map_agent --build-geo`) and loaded from there.
"""
from __future__ import annotations

import base64
import csv
import gzip
import io
import json
import math
import re
import subprocess
import sys
import zipfile
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field

from . import config, perf_dump, performance
from .auth import get_current_user
from .database import User

router = APIRouter(prefix="/api/map/agent", tags=["map-agent"])

FRAME_W, FRAME_H, PAD = 748, 824, 30
MAX_UPLOAD = 20 * 1024 * 1024
LABELS = 20
CRIT_DROP = -10.0
WIB = timezone(timedelta(hours=7))
JAVA_PROV = {"BANTEN", "DKI JAKARTA", "JAWA BARAT", "JAWA TENGAH", "DAERAH ISTIMEWA YOGYAKARTA", "JAWA TIMUR"}
PROV_NAME = {"BANTEN": "Banten", "DKI JAKARTA": "Jakarta", "JAWA BARAT": "West Java", "JAWA TENGAH": "Central Java",
             "DAERAH ISTIMEWA YOGYAKARTA": "Yogyakarta", "JAWA TIMUR": "East Java"}

# Metric catalogue. kind "div" is a diverging MoM change; "seq" is a level split into sextiles.
# scale divides the raw value for display (Rp 248.000.000 -> "Rp 248 jt").
METRICS = [
    {"key": "payload_mom", "cat": "perf", "name": "Payload MoM", "short": "Payload MoM", "kind": "div", "unit": "%", "d": 1},
    {"key": "revenue_mom", "cat": "perf", "name": "Revenue MoM", "short": "Rev. MoM", "kind": "div", "unit": "%", "d": 1},
    {"key": "availability", "cat": "perf", "name": "Availability", "short": "Availability", "kind": "seq", "unit": "%", "d": 2},
    {"key": "rev_site", "cat": "prod", "name": "Revenue / site", "short": "Rev/site", "kind": "seq", "pre": "Rp ", "unit": " jt", "d": 0, "scale": 1e6},
    {"key": "rgu_site", "cat": "prod", "name": "RGU 90D / site", "short": "RGU 90D/site", "kind": "seq", "unit": " rb", "d": 2, "scale": 1e3},
    {"key": "vlr_site", "cat": "prod", "name": "VLR / site", "short": "VLR/site", "kind": "seq", "unit": " rb", "d": 2, "scale": 1e3},
    {"key": "market_share", "cat": "prof", "name": "Market share", "short": "Market share", "kind": "seq", "unit": "%", "d": 1},
    {"key": "subs", "cat": "prof", "name": "Pelanggan aktif", "short": "Pelanggan", "kind": "seq", "unit": " rb", "d": 0, "scale": 1e3},
    {"key": "gross_add", "cat": "prof", "name": "Gross add", "short": "Gross add", "kind": "seq", "unit": "", "d": 0},
    {"key": "fwa_pen", "cat": "prof", "name": "Penetrasi FWA", "short": "Penetrasi FWA", "kind": "seq", "unit": "%", "d": 1},
]
METRIC_BY_KEY = {m["key"]: m for m in METRICS}
# Words that pick a metric in a question, most specific first.
METRIC_WORDS = [
    ("rev_site", ("revenue per site", "revenue/site", "rev/site", "rev per site", "site productivity", "produktivitas")),
    ("rgu_site", ("rgu per site", "rgu/site", "rgu 90d per site")),
    ("vlr_site", ("vlr",)),
    ("market_share", ("market share", "pangsa")),
    ("fwa_pen", ("fwa",)),
    ("gross_add", ("gross add", "ga ")),
    ("subs", ("pelanggan", "subscriber", "rgu")),
    ("availability", ("availability", "avail", "ketersediaan")),
    ("revenue_mom", ("revenue", "pendapatan")),
    ("payload_mom", ("payload", "trafik", "traffic", "data")),
]


# ── Geometry ─────────────────────────────────────────────────────────────────

def _geo_dirs() -> list[Path]:
    repo = Path(__file__).resolve().parents[2]
    return [config.DATA_DIR / "geo", repo / "mobile" / "assets" / "geo"]


def _outer_rings(geom: dict) -> list[list]:
    if not geom:
        return []
    if geom["type"] == "Polygon":
        return [geom["coordinates"][0]]
    if geom["type"] == "MultiPolygon":
        return [p[0] for p in geom["coordinates"]]
    return []


def _thin(ring: list, step: float = 0.0002) -> list:
    out = [[round(ring[0][0], 5), round(ring[0][1], 5)]]
    for c in ring[1:]:
        if abs(c[0] - out[-1][0]) + abs(c[1] - out[-1][1]) >= step:
            out.append([round(c[0], 5), round(c[1], 5)])
    return out if len(out) >= 3 else []


def build_geo_cache() -> Path:
    """Java-only, thinned copy of the kecamatan and kabupaten boundaries."""
    src = next((d for d in _geo_dirs() if (d / "kecamatan.geojson.gz").exists()), None)
    if not src:
        raise FileNotFoundError("kecamatan.geojson.gz not found in data/geo")
    out: dict = {"kec": [], "kab": []}
    for level, key in (("kecamatan", "kec"), ("kabupaten", "kab")):
        with gzip.open(src / f"{level}.geojson.gz", "rt", encoding="utf-8") as fh:
            fc = json.load(fh)
        for f in fc.get("features", []):
            p = f.get("properties") or {}
            if str(p.get("provinsi", "")).upper() not in JAVA_PROV:
                continue
            rings = [r for r in (_thin(r) for r in _outer_rings(f.get("geometry"))) if r]
            if rings:
                out[key].append({"kab": p.get("kabupaten"), "prov": p.get("provinsi"), "kec": p.get("kecamatan"), "rings": rings})
        del fc
    dst = config.DATA_DIR / "geo" / "java_compact.json.gz"
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(".tmp")
    with gzip.open(tmp, "wt", encoding="utf-8") as fh:
        json.dump(out, fh, separators=(",", ":"))
    tmp.replace(dst)
    return dst


@lru_cache(maxsize=1)
def geo() -> dict:
    dst = config.DATA_DIR / "geo" / "java_compact.json.gz"
    if not dst.exists():
        # Built in a child process: the source file needs ~400 MB to parse.
        subprocess.run([sys.executable, "-m", "app.map_agent", "--build-geo"], check=True,
                       cwd=str(Path(__file__).resolve().parents[1]), timeout=300)
    with gzip.open(dst, "rt", encoding="utf-8") as fh:
        return json.load(fh)


def _bbox(rings: list[list]) -> list[float]:
    xs = [c[0] for r in rings for c in r]
    ys = [c[1] for r in rings for c in r]
    return [min(xs), min(ys), max(xs), max(ys)]


class Frame:
    """lon/lat -> frame pixels, fitted to a bbox with PAD."""

    def __init__(self, bbox: list[float]):
        lon0, lat0, lon1, lat1 = bbox
        self.lon0, self.lat1 = lon0, lat1
        self.cx = math.cos(math.radians((lat0 + lat1) / 2))
        sx = (FRAME_W - 2 * PAD) / max((lon1 - lon0) * self.cx, 1e-9)
        sy = (FRAME_H - 2 * PAD) / max(lat1 - lat0, 1e-9)
        self.s = min(sx, sy)
        self.ox = (FRAME_W - (lon1 - lon0) * self.cx * self.s) / 2
        self.oy = (FRAME_H - (lat1 - lat0) * self.s) / 2

    def p(self, lon: float, lat: float) -> tuple[float, float]:
        return self.ox + (lon - self.lon0) * self.cx * self.s, self.oy + (self.lat1 - lat) * self.s

    def inv(self, x: float, y: float) -> tuple[float, float]:
        return self.lon0 + (x - self.ox) / (self.cx * self.s), self.lat1 - (y - self.oy) / self.s

    def path(self, rings: list[list], minstep: float = 1.0) -> str:
        out = []
        for r in rings:
            pts = [self.p(c[0], c[1]) for c in r]
            keep = [pts[0]]
            for q in pts[1:]:
                if math.hypot(q[0] - keep[-1][0], q[1] - keep[-1][1]) >= minstep:
                    keep.append(q)
            if len(keep) >= 3:
                out.append("M" + " ".join(f"{x:.1f},{y:.1f}" for x, y in keep) + "Z")
        return "".join(out)

    def meta(self) -> dict:
        return {"w": FRAME_W, "h": FRAME_H, "lon0": self.lon0, "lat1": self.lat1, "cx": self.cx, "s": self.s,
                "ox": self.ox, "oy": self.oy}


def _pip(x: float, y: float, ring: list) -> bool:
    inside, n = False, len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def _in_rings(lon: float, lat: float, rings: list[list]) -> bool:
    return any(_pip(lon, lat, r) for r in rings)


def _ring_km2(ring: list) -> float:
    if len(ring) < 3:
        return 0.0
    lat0 = sum(c[1] for c in ring) / len(ring)
    lon0 = sum(c[0] for c in ring) / len(ring)
    k = math.cos(math.radians(lat0))
    pts = [((c[0] - lon0) * 111.32 * k, (c[1] - lat0) * 110.57) for c in ring]
    return abs(sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                   for i in range(len(pts)))) / 2


def _centroid(rings: list[list]) -> tuple[float, float]:
    big = max(rings, key=_ring_km2)
    try:
        from shapely.geometry import Polygon
        pt = Polygon(big).representative_point()
        return pt.x, pt.y
    except Exception:
        return sum(c[0] for c in big) / len(big), sum(c[1] for c in big) / len(big)


# ── Formatting ───────────────────────────────────────────────────────────────

def _idn(v: float, d: int) -> str:
    s = f"{abs(v):,.{d}f}".replace(",", "_").replace(".", ",").replace("_", ".")
    return ("-" if v < 0 else "") + s


def fmt_pct(v: Optional[float], signed: bool = True) -> str:
    if v is None:
        return "-"
    sign = ("+" if v > 0 else "−" if v < 0 else "") if signed else ""
    return f"{sign}{_idn(abs(v), 1)}%"


def fmt_rp_short(v: Optional[float]) -> str:
    if v is None:
        return "-"
    if abs(v) >= 1e12:
        return f"Rp {_idn(v / 1e12, 1)} T"
    if abs(v) >= 1e9:
        return f"Rp {_idn(v / 1e9, 1)} M"
    return f"Rp {_idn(v / 1e6, 0)} jt"


def fmt_payload(gb: Optional[float]) -> str:
    if gb is None:
        return "-"
    if gb >= 1e6:
        return f"{_idn(gb / 1e6, 1)} PB"
    if gb >= 1e3:
        return f"{_idn(gb / 1e3, 0)} TB"
    return f"{_idn(gb, 0)} GB"


def scope_name(kabupaten: str) -> str:
    n = performance.norm(kabupaten)
    if n.startswith("KOTA "):
        return "Kota " + performance.title(n[5:])
    return "Kab. " + performance.title(n)


# ── Map payload ──────────────────────────────────────────────────────────────

def _f(v) -> Optional[float]:
    return float(v) if v is not None else None


def _unit_metrics(cur: dict, prev: dict, n_sites: int, site_av: list[float]) -> dict:
    rev, pay, subs = _f(cur.get("revenue")), _f(cur.get("payload_gb")), _f(cur.get("subs"))
    av = _f(cur.get("avail"))
    if av is None and site_av:
        av = round(sum(site_av) / len(site_av), 2)
    return {
        "payload_mom": performance._pct(pay, _f(prev.get("payload_gb"))),
        "revenue_mom": performance._pct(rev, _f(prev.get("revenue"))),
        "availability": av,
        "rev_site": rev / n_sites if rev is not None and n_sites else None,
        "rgu_site": subs / n_sites if subs is not None and n_sites else None,
        "vlr_site": None,
        "market_share": None,
        "subs": subs,
        "gross_add": _f(cur.get("gross_add")),
        "fwa_pen": None,
        "revenue": rev,
        "payload_gb": pay,
        "revenue_prev": _f(prev.get("revenue")),
        "payload_gb_prev": _f(prev.get("payload_gb")),
    }


def _sum_rows(rows: list[dict]) -> dict:
    out: dict = {}
    for r in rows:
        for k in ("revenue", "payload_gb", "subs", "gross_add"):
            if r.get(k) is not None:
                out[k] = out.get(k, 0.0) + float(r[k])
    return out


def build(region: str = "", kabupaten: str = "") -> dict:
    kec_rows, site_rows, avail_rows, source = performance._data()
    if not kec_rows:
        raise HTTPException(503, "Data performance belum tersedia")
    latest = max(int(r["month_id"]) for r in kec_rows)
    prev = perf_dump.month_add(latest, -1)
    g = geo()
    if not kabupaten and not region:
        # Default scope: the kabupaten with the most sites keeps the map readable.
        counts: dict[str, int] = {}
        for r in site_rows:
            if int(r["month_id"]) == latest:
                counts[performance.norm(r.get("kabupaten"))] = counts.get(performance.norm(r.get("kabupaten")), 0) + 1
        kabupaten = max(counts, key=counts.get) if counts else ""
    kab_n = performance.norm(kabupaten)

    if kab_n:
        kab_feats = [f for f in g["kab"] if performance.norm(f["kab"]) == kab_n]
        if not kab_feats:
            raise HTTPException(404, f"Kabupaten {kabupaten} tidak ada di peta")
        prov = kab_feats[0]["prov"]
        frame_rings = [r for f in kab_feats for r in f["rings"]]
        units_geo = [f for f in g["kec"] if performance.norm(f["kab"]) == kab_n and f["prov"] == prov]
        unit_level, unit_key = "kecamatan", "kec"
        in_scope = lambda r: performance.norm(r.get("kabupaten")) == kab_n  # noqa: E731
        scope = {"level": "kabupaten", "kabupaten": kab_n, "name": scope_name(kab_n),
                 "province": PROV_NAME.get(prov, performance.title(prov)), "region": ""}
    else:
        provs = {performance.norm(r.get("provinsi")) for r in kec_rows if performance.norm(r.get("region")) == performance.norm(region)}
        units_geo = [f for f in g["kab"] if performance.norm(f["prov"]) in provs]
        if not units_geo:
            raise HTTPException(404, f"Region {region} tidak ada di peta")
        frame_rings = [r for f in units_geo for r in f["rings"]]
        unit_level, unit_key = "kabupaten", "kab"
        in_scope = lambda r: performance.norm(r.get("provinsi")) in provs  # noqa: E731
        scope = {"level": "region", "kabupaten": "", "name": performance.title(region), "province": "", "region": performance.norm(region)}

    bbox = _bbox(frame_rings)
    fr = Frame(bbox)
    ukey = (lambda r: performance.norm(r.get("kecamatan"))) if unit_key == "kec" else (lambda r: performance.norm(r.get("kabupaten")))

    cur_rows: dict[str, list] = {}
    prev_rows: dict[str, list] = {}
    for r in kec_rows:
        if not in_scope(r):
            continue
        m = int(r["month_id"])
        if m == latest:
            cur_rows.setdefault(ukey(r), []).append(r)
        elif m == prev:
            prev_rows.setdefault(ukey(r), []).append(r)
    unit_avail = {performance.norm(r.get("name")): _f(r.get("avail")) for r in avail_rows
                  if int(r.get("month_id") or 0) == latest and str(r.get("level", "")).lower() == unit_level}

    sites = performance._sites(site_rows, kec_rows, latest, "", kab_n, "") if kab_n else [
        s for s in performance._sites(site_rows, kec_rows, latest, region, "", "")]
    by_unit_sites: dict[str, list] = {}
    out_sites = []
    no_coord = 0
    for s in sites:
        uk = performance.norm(s["kecamatan"] if unit_key == "kec" else s["kabupaten"])
        by_unit_sites.setdefault(uk, []).append(s)
        if s.get("lat") is None or s.get("lon") is None:
            no_coord += 1
            continue
        x, y = fr.p(float(s["lon"]), float(s["lat"]))
        crit = s["payload_mom"] is not None and s["payload_mom"] <= CRIT_DROP
        out_sites.append({"id": s["site_id"], "name": s.get("site_name"), "k": s["kecamatan"], "kab": s["kabupaten"],
                          "x": round(x, 1), "y": round(y, 1), "lat": round(float(s["lat"]), 6), "lon": round(float(s["lon"]), 6),
                          "crit": crit, "status": s["status"], "payload_mom": s["payload_mom"], "revenue_mom": s["revenue_mom"],
                          "availability": s["availability"], "payload_gb": s["payload_gb"], "revenue": s["revenue"],
                          "payload_gb_prev": s["payload_gb_prev"], "revenue_prev": s["revenue_prev"]})

    units = []
    for f in units_geo:
        name = performance.norm(f[unit_key])
        cur = _sum_rows(cur_rows.get(name, []))
        pv = _sum_rows(prev_rows.get(name, []))
        us = by_unit_sites.get(name, [])
        av = unit_avail.get(name)
        if av is not None:
            cur["avail"] = av
        m = _unit_metrics(cur, pv, len(us), [s["availability"] for s in us if s.get("availability") is not None])
        cx, cy = fr.p(*_centroid(f["rings"]))
        title = performance.title(name) if unit_key == "kec" else scope_name(name)
        units.append({"n": title, "d": fr.path(f["rings"]), "cx": round(cx, 1), "cy": round(cy, 1), "sites": len(us),
                      "crit": sum(1 for s in us if s["payload_mom"] is not None and s["payload_mom"] <= CRIT_DROP),
                      "status": performance._status(m["payload_mom"], m["availability"]), "label": False, "m": m})
    for u in sorted(units, key=lambda u: (-u["sites"], u["n"]))[:LABELS]:
        u["label"] = True
    units.sort(key=lambda u: u["n"])

    pad_x, pad_y = (bbox[2] - bbox[0]) * 0.6, (bbox[3] - bbox[1]) * 0.6
    near = [bbox[0] - pad_x, bbox[1] - pad_y, bbox[2] + pad_x, bbox[3] + pad_y]
    neighbors = []
    for f in g["kab"]:
        if kab_n and performance.norm(f["kab"]) == kab_n:
            continue
        if not kab_n and f in units_geo:
            continue
        b = _bbox(f["rings"])
        if b[0] < near[2] and b[2] > near[0] and b[1] < near[3] and b[3] > near[1]:
            neighbors.append({"n": scope_name(f["kab"]), "d": fr.path(f["rings"], 1.5)})

    metrics = [{**m, "available": any(u["m"].get(m["key"]) is not None for u in units)} for m in METRICS]
    return {
        "scope": scope,
        "frame": fr.meta(),
        "bbox": bbox,
        "month": latest,
        "month_label": performance.month_label(latest),
        "month_short": performance.month_label(latest, year=False),
        "unit_level": unit_level,
        "units": units,
        "sites": out_sites,
        "sites_without_coord": no_coord,
        "neighbors": neighbors,
        "outline": fr.path(frame_rings) if kab_n else "",
        "metrics": metrics,
        "source": source,
    }


@lru_cache(maxsize=16)
def _cached(region: str, kabupaten: str, stamp: str) -> dict:
    return build(region, kabupaten)


def map_payload(region: str = "", kabupaten: str = "") -> dict:
    st = perf_dump.status()
    stamp = f"{st.get('created_at')}|{int(datetime.now().timestamp() // performance.LIVE_TTL)}"
    return _cached(performance.norm(region), performance.norm(kabupaten), stamp)


# ── Map chat ─────────────────────────────────────────────────────────────────

def _metric_from(q: str) -> Optional[str]:
    for key, words in METRIC_WORDS:
        if any(w in q for w in words):
            return key
    return None


def _threshold(q: str) -> Optional[float]:
    m = re.search(r"(?:lebih dari|>|di atas|melebihi|lebih dalam dari)\s*(\d+(?:[.,]\d+)?)\s*%", q)
    if not m and re.search(r"turun|drop|kritis", q):
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*%", q)
    return float(m.group(1).replace(",", ".")) if m else None


def _coords(q: str) -> Optional[tuple[float, float]]:
    m = re.search(r"(-?\d{1,2}[.,]\d+)\s*[,; ]\s*(-?\d{2,3}[.,]\d+)", q)
    if not m:
        return None
    a, b = float(m.group(1).replace(",", ".")), float(m.group(2).replace(",", "."))
    lat, lon = (a, b) if abs(a) <= 15 else (b, a)
    return lat, lon


def _focus(points: list[tuple[float, float]], min_size: float = 120.0, pad: float = 1.25) -> Optional[list[float]]:
    if not points:
        return None
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    w = max((max(xs) - min(xs)) * pad, min_size)
    h = max((max(ys) - min(ys)) * pad, min_size * 0.88)
    return [round(cx - w / 2, 2), round(cy - h / 2, 2), round(cx + w / 2, 2), round(cy + h / 2, 2)]


def _now_label() -> str:
    return datetime.now(WIB).strftime("%H.%M")


def _list_names(names: list[str], partial: list[str]) -> str:
    parts = names + [f"sebagian {n}" for n in partial]
    if not parts:
        return ""
    if len(parts) == 1:
        return parts[0]
    return ", ".join(parts[:-1]) + ", dan " + parts[-1]


def _area_answer(data: dict, shape: dict) -> dict:
    rings = shape.get("rings") or []
    inside = [s for s in data["sites"] if _in_rings(s["lon"], s["lat"], rings)]
    area = sum(_ring_km2(r) for r in rings)
    fr = data["frame"]
    frame = Frame(data["bbox"])
    # Coverage per unit by the share of the area's sample grid points inside each unit.
    cover: dict[str, int] = {}
    b = _bbox(rings)
    grid = 24
    hits = 0
    for i in range(grid):
        for j in range(grid):
            lon = b[0] + (b[2] - b[0]) * (i + .5) / grid
            lat = b[1] + (b[3] - b[1]) * (j + .5) / grid
            if not _in_rings(lon, lat, rings):
                continue
            hits += 1
            x, y = frame.p(lon, lat)
            for u in data["units"]:
                if _in_path(x, y, u["d"]):
                    cover[u["n"]] = cover.get(u["n"], 0) + 1
                    break
    full = [n for n, c in sorted(cover.items(), key=lambda kv: -kv[1]) if hits and c / hits >= 0.2]
    partial = [n for n, c in sorted(cover.items(), key=lambda kv: -kv[1]) if hits and 0.02 <= c / hits < 0.2]
    rev = sum(s["revenue"] or 0 for s in inside)
    rev_p = sum(s["revenue_prev"] or 0 for s in inside)
    pay = sum(s["payload_gb"] or 0 for s in inside)
    pay_p = sum(s["payload_gb_prev"] or 0 for s in inside)
    rmom, pmom = performance._pct(rev, rev_p), performance._pct(pay, pay_p)
    crit = sum(1 for s in inside if s["crit"])
    mon = data["month_short"]

    def chg(v):
        if v is None:
            return None, ""
        return ("▼ " if v < 0 else "▲ ") + fmt_pct(abs(v), signed=False) + " MoM", ("down" if v < 0 else "up")
    rs, rt = chg(rmom)
    ps, pt = chg(pmom)
    where = _list_names(full, partial)
    text = f"Area seluas **{_idn(area, 1)} km²** ini" + (f" mencakup {where}." if where else " tidak memotong kecamatan mana pun di peta ini.")
    short_where = ", ".join(full + [f"sebagian {n}" for n in partial])
    text_short = f"Area **{_idn(area, 1)} km\u00b2**" + (f": {short_where}." if short_where else ".")
    pts = [frame.p(c[0], c[1]) for r in rings for c in r]
    return {
        "time": _now_label(), "text": text, "text_short": text_short,
        "layers": [],
        "stats": [
            {"label": "Site di area", "short": "Site", "value": str(len(inside)), "sub": f"{crit} kritis", "tone": "down" if crit else ""},
            {"label": f"Revenue {mon}", "short": "Revenue", "value": fmt_rp_short(rev), "sub": rs, "tone": rt},
            {"label": f"Payload {mon}", "short": "Payload", "value": fmt_payload(pay), "sub": ps, "tone": pt},
        ],
        "actions": ["sites", "geojson", "png"],
        "site_ids": [s["id"] for s in inside],
        "focus": _focus(pts, pad=1.6),
        "suggestions": ["Site productivity per kecamatan", f"Profile Kec. {full[0]}" if full else "Profile wilayah", "Revenue MoM di area ini"],
        "suggestions_short": ["Site productivity", "Profile area", "Revenue MoM"],
        "frame": fr,
    }


def _in_path(x: float, y: float, d: str) -> bool:
    for ring in d.split("M")[1:]:
        pts = [tuple(map(float, p.split(","))) for p in ring.rstrip("Z").split()]
        if len(pts) >= 3 and _pip(x, y, pts):
            return True
    return False


def ask(q: str, region: str = "", kabupaten: str = "", shapes: Optional[list[dict]] = None) -> dict:
    data = map_payload(region, kabupaten)
    ql = " " + q.lower().strip() + " "
    shapes = shapes or []
    units = data["units"]
    unit_word = "kecamatan" if data["unit_level"] == "kecamatan" else "kabupaten"

    if shapes and re.search(r"\barea\b|poligon|polygon|di dalam|wilayah ini|shp", ql):
        return _area_answer(data, shapes[-1])

    co = _coords(ql)
    if co:
        lat, lon = co
        fr = Frame(data["bbox"])
        x, y = fr.p(lon, lat)
        near = sorted(data["sites"], key=lambda s: (s["lat"] - lat) ** 2 + ((s["lon"] - lon) * math.cos(math.radians(lat))) ** 2)[:5]
        unit = next((u for u in units if _in_path(x, y, u["d"])), None)
        km = lambda s: math.hypot((s["lat"] - lat) * 110.57, (s["lon"] - lon) * 111.32 * math.cos(math.radians(lat)))  # noqa: E731
        lines = ", ".join(f"**{s['id']}** ({_idn(km(s), 1)} km)" for s in near[:3])
        where = f"di {unit_word} **{unit['n']}**" if unit else "di luar wilayah peta ini"
        return {
            "time": _now_label(),
            "text": f"Titik {_idn(lat, 5)}, {_idn(lon, 5)} berada {where}. Site terdekat: {lines}." if near else f"Titik {_idn(lat, 5)}, {_idn(lon, 5)} berada {where}.",
            "layers": [{"kind": "point", "label": f"Titik {_idn(lat, 4)}, {_idn(lon, 4)}", "x": round(x, 1), "y": round(y, 1), "lat": lat, "lon": lon}],
            "stats": [], "actions": ["sites", "geojson"], "site_ids": [s["id"] for s in near],
            "select": unit["n"] if unit else None,
            "focus": _focus([(x, y)] + [(s["x"], s["y"]) for s in near]),
            "suggestions": [f"Profile {unit_word} {unit['n']}" if unit else "Site productivity per kecamatan"],
        }

    named = next((u for u in sorted(units, key=lambda u: -len(u["n"])) if " " + u["n"].lower() + " " in ql
                  or u["n"].lower().replace("kab. ", "").replace("kota ", "") in ql), None)
    if named and re.search(r"profil|profile|ringkas|detail|kartu", ql):
        m = named["m"]
        bits = [f"payload {fmt_pct(m['payload_mom'])} MoM", f"revenue {fmt_pct(m['revenue_mom'])} MoM"]
        if m.get("availability") is not None:
            bits.append(f"availability {_idn(m['availability'], 2)}%")
        return {
            "time": _now_label(),
            "text": f"{unit_word.capitalize()} **{named['n']}**: {named['sites']} site, " + ", ".join(bits) + ". Kartunya saya buka di peta.",
            "layers": [], "stats": [], "actions": [], "select": named["n"],
            "focus": _focus([(named["cx"], named["cy"])], min_size=140),
            "suggestions": ["Site productivity per kecamatan", "Revenue MoM per kecamatan"],
        }

    key = _metric_from(ql)
    thr = _threshold(ql)
    if key or thr is not None:
        key = key or "payload_mom"
        meta = METRIC_BY_KEY[key]
        layers = [{"kind": "chor", "metric": key, "label": f"Choropleth {len(units)} {unit_word}"}]
        vals = [(u, u["m"].get(key)) for u in units if u["m"].get(key) is not None]
        sel = []
        if meta["kind"] == "div":
            src_key = "payload_gb" if key == "payload_mom" else "revenue"
            cur_t = sum(u["m"].get(src_key) or 0 for u in units)
            prev_t = sum(u["m"].get(src_key + "_prev") or 0 for u in units)
            tot = performance._pct(cur_t, prev_t) if prev_t else None
            worst = sorted(vals, key=lambda t: t[1])[:2]
            verb = "turun" if (tot or 0) < 0 else "naik"
            text = f"{meta['name'].split()[0]} {data['scope']['name']} {verb} **{fmt_pct(abs(tot), signed=False)} MoM**." if tot is not None else f"{meta['name']} per {unit_word}."
            if worst and worst[0][1] < 0:
                text += " Paling dalam di " + " dan ".join(f"**{u['n']} ({fmt_pct(v)})**" for u, v in worst if v < 0) + "."
        else:
            best = sorted(vals, key=lambda t: -t[1])[:2]
            text = f"{meta['name']} per {unit_word} di {data['scope']['name']}." + (
                " Tertinggi di " + " dan ".join(f"**{u['n']}**" for u, _ in best) + "." if best else " Datanya belum tersedia di dump.")
        if thr is not None or key == "payload_mom":
            t = -(thr if thr is not None else abs(CRIT_DROP))
            mk = "revenue_mom" if key == "revenue_mom" else "payload_mom"
            sel = [s for s in data["sites"] if s.get(mk) is not None and s[mk] <= t]
            layers.append({"kind": "sites", "metric": mk, "threshold": t,
                           "label": f"{len(sel)} site turun > {_idn(abs(t), 0)}%"})
        n = len(layers)
        text += f" {'Dua layer' if n == 2 else 'Satu layer'} saya tambahkan ke peta:"
        pts = [(s["x"], s["y"]) for s in sel] or [(u["cx"], u["cy"]) for u, v in sorted(vals, key=lambda t: t[1])[:4]]
        return {
            "time": _now_label(), "text": text, "layers": layers, "stats": [], "actions": [],
            "site_ids": [s["id"] for s in sel], "metric": key,
            "focus": _focus(pts),
            "suggestions": ["Site productivity per kecamatan", "Profile wilayah", "Upload SHP area"],
        }

    return {
        "time": _now_label(),
        "text": ("Saya bisa mewarnai peta per " + unit_word + " (payload, revenue, availability, revenue per site, "
                 "pelanggan, gross add), menandai site yang turun lebih dari batas tertentu, membaca koordinat "
                 "(contoh: -7,2 107,9), dan menghitung site serta revenue di dalam area SHP, GeoJSON, KML, atau CSV yang kamu upload."),
        "layers": [], "stats": [], "actions": [], "focus": None,
        "suggestions": ["Payload MoM per kecamatan", "Site productivity per kecamatan", "Profile wilayah"],
    }


# ── Upload and export ────────────────────────────────────────────────────────

def _close(r: list) -> list:
    return r if r and r[0] == r[-1] else r + r[:1]


def parse_upload(name: str, raw: bytes) -> dict:
    """SHP (.zip), GeoJSON, KML or CSV lat/long -> {kind, polygons (lon/lat rings), points}."""
    low = name.lower()
    polys: list[list] = []
    points: list[list] = []
    if low.endswith(".zip") or low.endswith(".shp"):
        import shapefile  # pyshp
        if low.endswith(".zip"):
            z = zipfile.ZipFile(io.BytesIO(raw))
            names = z.namelist()
            shp = next((n for n in names if n.lower().endswith(".shp")), None)
            if not shp:
                raise ValueError("ZIP tidak berisi file .shp")
            base = shp[:-4]
            part = lambda ext: next((io.BytesIO(z.read(n)) for n in names if n.lower() == (base + ext).lower()), None)  # noqa: E731
            reader = shapefile.Reader(shp=io.BytesIO(z.read(shp)), shx=part(".shx"), dbf=part(".dbf"))
        else:
            reader = shapefile.Reader(shp=io.BytesIO(raw))
        kind = "SHP"
        for sh in reader.shapes():
            gi = sh.__geo_interface__
            if gi["type"] in ("Polygon", "MultiPolygon"):
                polys += [[list(c[:2]) for c in r] for r in _outer_rings(gi)]
            elif gi["type"] == "Point":
                points.append(list(gi["coordinates"][:2]))
            elif gi["type"] == "MultiPoint":
                points += [list(c[:2]) for c in gi["coordinates"]]
    elif low.endswith(".geojson") or low.endswith(".json"):
        kind = "GeoJSON"
        gj = json.loads(raw.decode("utf-8-sig"))
        feats = gj.get("features") if gj.get("type") == "FeatureCollection" else [gj if gj.get("type") == "Feature" else {"geometry": gj}]
        for f in feats or []:
            geom = f.get("geometry") or {}
            if geom.get("type") in ("Polygon", "MultiPolygon"):
                polys += [[list(c[:2]) for c in r] for r in _outer_rings(geom)]
            elif geom.get("type") == "Point":
                points.append(list(geom["coordinates"][:2]))
    elif low.endswith(".kml"):
        kind = "KML"
        txt = raw.decode("utf-8-sig", errors="replace")
        for blk in re.findall(r"<Polygon>.*?</Polygon>", txt, flags=re.S | re.I):
            m = re.search(r"<outerBoundaryIs>.*?<coordinates>(.*?)</coordinates>", blk, flags=re.S | re.I)
            if m:
                polys.append([[float(v) for v in c.split(",")[:2]] for c in m.group(1).split()])
        for blk in re.findall(r"<Point>.*?<coordinates>(.*?)</coordinates>.*?</Point>", txt, flags=re.S | re.I):
            points.append([float(v) for v in blk.strip().split(",")[:2]])
    elif low.endswith(".csv") or low.endswith(".txt"):
        kind = "CSV"
        rows = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig", errors="replace"))))
        if not rows:
            raise ValueError("CSV kosong")
        cols = {c.lower().strip(): c for c in rows[0].keys() if c}
        la = next((cols[c] for c in ("lat", "latitude", "y") if c in cols), None)
        lo = next((cols[c] for c in ("lon", "long", "lng", "longitude", "x") if c in cols), None)
        if not la or not lo:
            raise ValueError("CSV butuh kolom lat dan long")
        for r in rows:
            try:
                points.append([float(str(r[lo]).replace(",", ".")), float(str(r[la]).replace(",", "."))])
            except (TypeError, ValueError):
                continue
    else:
        raise ValueError("Format belum didukung. Pakai SHP (.zip), GeoJSON, KML, atau CSV lat/long")
    polys = [_close(p) for p in polys if len(p) >= 3]
    if not polys and not points:
        raise ValueError("File tidak berisi poligon atau titik")
    return {"kind": kind, "polygons": polys, "points": points}


def upload_payload(name: str, raw: bytes, region: str, kabupaten: str) -> dict:
    parsed = parse_upload(name, raw)
    data = map_payload(region, kabupaten)
    fr = Frame(data["bbox"])
    pts = [list(fr.p(*p)) for p in parsed["points"]]
    area = sum(_ring_km2(r) for r in parsed["polygons"])
    np_, nt = len(parsed["polygons"]), len(parsed["points"])
    desc = {"SHP": "Shapefile", "GeoJSON": "GeoJSON", "KML": "KML", "CSV": "CSV"}[parsed["kind"]]
    count = f"{np_} poligon" if np_ else f"{nt} titik"
    size_kb = max(1, round(len(raw) / 1024))
    label = re.sub(r"\.zip$", ".shp", name, flags=re.I) if parsed["kind"] == "SHP" else name
    return {
        "name": name, "label": label, "kind": parsed["kind"], "desc": desc, "size_kb": size_kb,
        "count": count, "polygons": np_, "points_count": nt, "area_km2": round(area, 1),
        "rings": parsed["polygons"], "d": fr.path(parsed["polygons"], 0.5) if np_ else "",
        "points": [[round(x, 1), round(y, 1)] for x, y in pts],
        "sub": f"{desc} · {count} · {size_kb} KB",
    }


def export_file(fmt: str, name: str, features: list[dict]) -> tuple[bytes, str, str]:
    base = re.sub(r"[^A-Za-z0-9_-]+", "_", name or "peta_agent").strip("_") or "peta_agent"
    if fmt == "geojson":
        body = json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False).encode("utf-8")
        return body, "application/geo+json", f"{base}.geojson"
    if fmt == "csv":
        buf = io.StringIO()
        keys: list[str] = []
        for f in features:
            for k in (f.get("properties") or {}):
                if k not in keys:
                    keys.append(k)
        w = csv.writer(buf)
        w.writerow(keys + ["lat", "lon"])
        for f in features:
            geom = f.get("geometry") or {}
            if geom.get("type") != "Point":
                continue
            lon, lat = geom["coordinates"][:2]
            w.writerow([(f.get("properties") or {}).get(k, "") for k in keys] + [lat, lon])
        return buf.getvalue().encode("utf-8-sig"), "text/csv", f"{base}.csv"
    if fmt == "shp":
        import shapefile
        points = [f for f in features if (f.get("geometry") or {}).get("type") == "Point"]
        polys = [f for f in features if (f.get("geometry") or {}).get("type") in ("Polygon", "MultiPolygon")]
        zbuf = io.BytesIO()
        with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as z:
            for kind, group in (("titik", points), ("area", polys)):
                if not group:
                    continue
                shp, shx, dbf = io.BytesIO(), io.BytesIO(), io.BytesIO()
                w = shapefile.Writer(shp=shp, shx=shx, dbf=dbf, shapeType=shapefile.POINT if kind == "titik" else shapefile.POLYGON)
                keys: list[str] = []
                for f in group:
                    for k in (f.get("properties") or {}):
                        if k not in keys:
                            keys.append(k)
                fields = [k[:10] for k in keys]
                for k in fields:
                    w.field(k, "C", size=80)
                for f in group:
                    geom = f["geometry"]
                    if kind == "titik":
                        w.point(*geom["coordinates"][:2])
                    else:
                        w.poly([[list(c[:2]) for c in r] for r in _outer_rings(geom)])
                    w.record(*[str((f.get("properties") or {}).get(k, ""))[:80] for k in keys])
                w.close()
                for ext, b in (("shp", shp), ("shx", shx), ("dbf", dbf)):
                    z.writestr(f"{base}_{kind}.{ext}", b.getvalue())
                z.writestr(f"{base}_{kind}.prj", 'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]')
        return zbuf.getvalue(), "application/zip", f"{base}_shp.zip"
    raise ValueError("format harus geojson, shp, atau csv")


# ── Endpoints ────────────────────────────────────────────────────────────────

class AskReq(BaseModel):
    q: str = Field(min_length=1, max_length=500)
    region: str = ""
    kabupaten: str = ""
    shapes: list[dict] = []


class UploadReq(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    data: str = Field(min_length=1, max_length=MAX_UPLOAD * 4 // 3 + 16)
    region: str = ""
    kabupaten: str = ""


class ExportReq(BaseModel):
    format: str = "geojson"
    name: str = "peta_agent"
    features: list[dict] = Field(default_factory=list, max_length=50000)


def site_kabupaten(site_id: str) -> str:
    """Kabupaten of one site, so /map?focus=<site>&level=site opens the right frame."""
    _, site_rows, _, _ = performance._data()
    sid = site_id.strip().upper()
    row = next((r for r in site_rows if str(r.get("site_id", "")).upper() == sid), None)
    return performance.norm(row.get("kabupaten")) if row else ""


@router.get("")
def map_agent(region: str = Query("", max_length=60), kabupaten: str = Query("", max_length=60),
              site: str = Query("", max_length=40), user: User = Depends(get_current_user)):
    if site and not kabupaten:
        kabupaten = site_kabupaten(site)
    return map_payload(region, kabupaten)


@router.get("/scopes")
def map_agent_scopes(user: User = Depends(get_current_user)):
    """Java kabupaten/kota with boundaries, grouped by province, for the scope picker."""
    out: dict[str, list] = {}
    for f in geo()["kab"]:
        out.setdefault(PROV_NAME.get(f["prov"], f["prov"]), []).append({"kabupaten": performance.norm(f["kab"]), "name": scope_name(f["kab"])})
    return [{"province": p, "items": sorted(v, key=lambda x: x["name"])} for p, v in out.items()]


@router.post("/ask")
def map_agent_ask(req: AskReq, user: User = Depends(get_current_user)):
    out = ask(req.q, req.region, req.kabupaten, req.shapes)
    out.pop("frame", None)
    return out


@router.post("/upload")
def map_agent_upload(req: UploadReq, user: User = Depends(get_current_user)):
    try:
        raw = base64.b64decode(req.data, validate=False)
    except (ValueError, TypeError):
        raise HTTPException(400, "Isi file tidak terbaca")
    if len(raw) > MAX_UPLOAD:
        raise HTTPException(413, "File lebih dari 20 MB")
    try:
        return upload_payload(req.name, raw, req.region, req.kabupaten)
    except (ValueError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as e:
        raise HTTPException(400, str(e)[:200])


@router.post("/export")
def map_agent_export(req: ExportReq, user: User = Depends(get_current_user)):
    try:
        body, mime, fname = export_file(req.format, req.name, req.features)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return Response(content=body, media_type=mime, headers={"Content-Disposition": f'attachment; filename="{fname}"'})


if __name__ == "__main__":
    if "--build-geo" in sys.argv:
        print(build_geo_cache())
