"""Peta & Site API — kabupaten choropleth for Circle Java and a kabupaten panel.

GET /api/map/kabupaten?metric=revenue|payload|availability&region=
    one row per kabupaten/kota: kabkot_id ("KAB|PROV", the key of
    data/geo/kabupaten.geojson), MoM change (or availability level) and labels.
GET /api/map/kabupaten/detail?kabupaten=&provinsi=
    KPI tiles, kecamatan/site counts, the sites that need attention and an
    agent explanation written from those numbers.
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Query

from . import config, reports_cache
from .auth import get_current_user
from .bigquery_tool import QueryError, run_query
from .dashboard import month_add, month_label
from .database import User

router = APIRouter(prefix="/api/map", tags=["map"])

_P, _D = config.BQ_PROJECT, config.BQ_DATASET
_MTD = f"`{_P}.{_D}.rham_mkt_highlevel_mtd`"
_TERR = f"`{_P}.{_D}.rham_ref_territory`"
_ZZ = f"`{_P}.{_D}.zz_territory_kecamatan`"
_AVAIL = f"`{_P}.{_D}.rham_avail_stat_territory_monthly`"
_ADDR = f"`{_P}.{_D}.rham_site_wise_addr_java`"
_SITE = f"`{_P}.{_D}.rham_site_wise_monthly`"
_SITE_AV = f"`{_P}.{_D}.rham_avail_stat_site_monthly`"

METRICS = {
    "revenue": {"label": "Revenue MoM", "expr": "x.rev_prepaid", "unit": "%"},
    "payload": {"label": "Payload MoM", "expr": "x.usg_data_gb", "unit": "%"},
    "availability": {"label": "Availability 4G", "expr": None, "unit": "%"},
}
SLA = 99.0


def _esc(v: str) -> str:
    return (v or "").replace("'", "").replace("\\", "")


def _core(expr: str) -> str:
    """Kabupaten name without its KABUPATEN/KAB. prefix, for joins across tables."""
    return f"TRIM(REGEXP_REPLACE(UPPER({expr}), r'^(KABUPATEN|KAB\\.?)\\s+', ''))"


def _pct(cur: Optional[float], prev: Optional[float]) -> Optional[float]:
    if cur is None or not prev:
        return None
    return (cur - prev) / abs(prev) * 100


def _latest() -> int:
    return int(run_query(f"SELECT MAX(month_id) AS m FROM {_MTD}")["rows"][0]["m"])


def build_kabupaten(metric: str, region: str = "") -> dict:
    cur = _latest()
    prev = month_add(cur, -1)
    expr = METRICS[metric]["expr"] or "x.rev_prepaid"
    reg = f" AND UPPER(t.region) = UPPER('{_esc(region)}')" if region else ""
    rows = run_query(f"""
SELECT UPPER(z.kabkota) || '|' || UPPER(z.province) AS kabkot_id,
  ANY_VALUE(z.kabkota) AS kabupaten, ANY_VALUE(z.province) AS provinsi, ANY_VALUE(t.region) AS region,
  SUM(IF(x.month_id = {cur}, {expr}, 0)) AS cur, SUM(IF(x.month_id = {prev}, {expr}, 0)) AS prev,
  COUNT(DISTINCT z.kec_id) AS kecamatan
FROM {_MTD} x
JOIN {_ZZ} z ON x.kec_id = z.kec_id
JOIN {_TERR} t ON x.kec_id = t.kec_id
WHERE t.circle = 'JAVA' AND x.month_id IN ({cur}, {prev}){reg}
GROUP BY kabkot_id
""", row_limit=1000)["rows"]
    items = []
    for r in rows:
        c, p = float(r["cur"] or 0), float(r["prev"] or 0)
        items.append({
            "kabkot_id": r["kabkot_id"], "kabupaten": r["kabupaten"], "provinsi": r["provinsi"], "region": r["region"],
            "kecamatan": int(r["kecamatan"] or 0), "cur": c, "prev": p, "value": _pct(c, p),
        })
    if metric == "availability":
        av = run_query(f"""
SELECT {_core('territory_name')} AS k, CAST(month_id AS INT64) AS m, AVG(mean_avg_avail_pct_4g) AS v,
  SUM(sites_below_sla99_4g) AS below
FROM {_AVAIL}
WHERE territory_level = 'kabkot' AND CAST(month_id AS INT64) IN ({cur}, {prev})
GROUP BY k, m
""", row_limit=2000)["rows"]
        by = {(r["k"], int(r["m"])): r for r in av}
        for it in items:
            k = it["kabupaten"].upper().replace("KABUPATEN ", "").replace("KAB. ", "").strip()
            c, p = by.get((k, cur)), by.get((k, prev))
            it["cur"] = float(c["v"]) if c and c["v"] is not None else None
            it["prev"] = float(p["v"]) if p and p["v"] is not None else None
            it["value"] = it["cur"]
            it["change"] = (it["cur"] - it["prev"]) if it["cur"] is not None and it["prev"] is not None else None
            it["below_sla"] = int(c["below"] or 0) if c else None
    return {
        "metric": metric, "label": METRICS[metric]["label"], "month_id": cur,
        "month_label": month_label(cur, True), "prev_label": month_label(prev),
        "region": region or None, "regions": sorted({i["region"] for i in items if i["region"]}),
        "items": items,
    }


def build_detail(kabupaten: str, provinsi: str) -> dict:
    cur = _latest()
    prev = month_add(cur, -1)
    kab, prov = _esc(kabupaten).upper(), _esc(provinsi).upper()
    k = run_query(f"""
SELECT ANY_VALUE(t.region) AS region, COUNT(DISTINCT z.kec_id) AS kecamatan,
  SUM(IF(x.month_id = {cur}, x.rev_prepaid, 0)) AS rev, SUM(IF(x.month_id = {prev}, x.rev_prepaid, 0)) AS rev_p,
  SUM(IF(x.month_id = {cur}, x.usg_data_gb, 0)) AS pay, SUM(IF(x.month_id = {prev}, x.usg_data_gb, 0)) AS pay_p,
  SUM(IF(x.month_id = {cur}, x.gross_add, 0)) AS ga, SUM(IF(x.month_id = {prev}, x.gross_add, 0)) AS ga_p
FROM {_MTD} x
JOIN {_ZZ} z ON x.kec_id = z.kec_id
JOIN {_TERR} t ON x.kec_id = t.kec_id
WHERE UPPER(z.kabkota) = '{kab}' AND UPPER(z.province) = '{prov}' AND x.month_id IN ({cur}, {prev})
""")["rows"][0]
    core = kab.replace("KABUPATEN ", "").replace("KAB. ", "").strip()
    try:
        av = {int(r["m"]): r for r in run_query(f"""
SELECT CAST(month_id AS INT64) AS m, AVG(mean_avg_avail_pct_4g) AS v, SUM(sites_below_sla99_4g) AS below
FROM {_AVAIL}
WHERE territory_level = 'kabkot' AND {_core('territory_name')} = '{core}' AND CAST(month_id AS INT64) IN ({cur}, {prev})
GROUP BY m
""")["rows"]}
    except QueryError:
        av = {}
    a_cur = float(av[cur]["v"]) if cur in av and av[cur]["v"] is not None else None
    a_prev = float(av[prev]["v"]) if prev in av and av[prev]["v"] is not None else None

    sites = _sites(core, prov, cur, prev)
    kpis = [
        {"key": "revenue", "label": "Revenue", "format": "currency", "icon": "wallet", "value": k["rev"], "pct_change": _pct(k["rev"], k["rev_p"])},
        {"key": "payload", "label": "Payload", "format": "gb", "icon": "database", "value": k["pay"], "pct_change": _pct(k["pay"], k["pay_p"])},
        {"key": "availability", "label": "Availability", "format": "percent", "icon": "radio", "value": a_cur,
         "pct_change": (a_cur - a_prev) if a_cur is not None and a_prev is not None else None, "change_unit": "pp"},
        {"key": "gross_add", "label": "Gross add", "format": "number", "icon": "user-plus", "value": k["ga"], "pct_change": _pct(k["ga"], k["ga_p"])},
    ]
    worst = [s for s in sites["items"] if s["status"] == "bad"]
    status = "kritis" if any((x["pct_change"] or 0) <= -5 for x in kpis[:2]) or (a_cur is not None and a_cur < SLA) \
        else "perhatian" if any((x["pct_change"] or 0) < 0 for x in kpis) else "normal"
    return {
        "kabupaten": kabupaten, "provinsi": provinsi, "region": k["region"], "month_id": cur,
        "month_label": month_label(cur, True), "prev_label": month_label(prev),
        "kecamatan": int(k["kecamatan"] or 0), "site_count": sites["total"], "status": status,
        "kpis": kpis, "sites": sites["items"][:8],
        "explanation": _explain(kabupaten, kpis, worst, a_cur, month_label(prev)),
    }


def _sites(core: str, prov: str, cur: int, prev: int) -> dict:
    """Sites in a kabupaten with the latest payload change and 4G availability, worst first."""
    try:
        rows = run_query(f"""
WITH addr AS (
  SELECT site_id, ANY_VALUE(site_name) AS site_name, ANY_VALUE(kecamatan) AS kecamatan,
    ANY_VALUE(SAFE_CAST(latitude AS FLOAT64)) AS lat, ANY_VALUE(SAFE_CAST(longitude AS FLOAT64)) AS lon
  FROM {_ADDR}
  WHERE month_id = (SELECT MAX(month_id) FROM {_ADDR})
    AND {_core('kabupaten')} = '{core}' AND UPPER(provinsi) = '{prov}'
  GROUP BY site_id
), perf AS (
  SELECT site_id, SUM(IF(month_id = {cur}, usg_data_gb, 0)) AS pay, SUM(IF(month_id = {prev}, usg_data_gb, 0)) AS pay_p
  FROM {_SITE} WHERE month_id IN ({cur}, {prev}) AND site_id IN (SELECT site_id FROM addr)
  GROUP BY site_id
), av AS (
  SELECT site_id, AVG(avg_avail_pct_4g) AS avail
  FROM {_SITE_AV} WHERE CAST(month_id AS INT64) = {cur} AND site_id IN (SELECT site_id FROM addr)
  GROUP BY site_id
)
SELECT a.site_id, a.site_name, a.kecamatan, a.lat, a.lon, p.pay, p.pay_p, v.avail
FROM addr a LEFT JOIN perf p USING (site_id) LEFT JOIN av v USING (site_id)
""", row_limit=3000)["rows"]
    except QueryError:
        return {"total": 0, "items": []}
    items = []
    for r in rows:
        pc = _pct(r.get("pay"), r.get("pay_p"))
        avail = float(r["avail"]) if r.get("avail") is not None else None
        bad = (avail is not None and avail < SLA) or (pc is not None and pc <= -8)
        items.append({
            "site_id": r["site_id"], "site_name": r.get("site_name"), "kecamatan": (r.get("kecamatan") or "").title(),
            "lat": r.get("lat"), "lon": r.get("lon"), "availability": avail, "payload_pct": pc,
            "status": "bad" if bad else "ok",
        })
    items.sort(key=lambda s: (s["status"] != "bad", s["payload_pct"] if s["payload_pct"] is not None else 0))
    return {"total": len(items), "items": items}


def _f1(v: float) -> str:
    return f"{abs(v):.1f}".replace(".", ",")


def _explain(kab: str, kpis: list[dict], worst: list[dict], avail: Optional[float], prev_label: str) -> dict:
    name = kab.title()
    rev, pay = kpis[0]["pct_change"], kpis[1]["pct_change"]
    parts, actions = [], []
    if rev is not None:
        parts.append(f"Revenue {name} {'turun' if rev < 0 else 'naik'} {_f1(rev)}% dibanding {prev_label}")
    if pay is not None:
        parts.append(f"payload {'turun' if pay < 0 else 'naik'} {_f1(pay)}%")
    text = (", ".join(parts) + ".") if parts else f"Data {name} bulan ini belum lengkap."
    if worst:
        kec = sorted({w["kecamatan"] for w in worst if w["kecamatan"]})[:3]
        low = [w["availability"] for w in worst if w["availability"] is not None]
        text += f" Penurunan terkonsentrasi di {len(worst)} site" + (f" ({', '.join(kec)})" if kec else "")
        if low:
            text += f" dengan availability rata-rata {_f1(sum(low) / len(low))}%"
        text += "."
        down = [w for w in worst if w["availability"] is not None and w["availability"] < SLA]
        if down:
            actions.append(f"Pulihkan {len(down)} site dengan availability di bawah {SLA:g}%")
        if kec:
            actions.append(f"Cek aktivitas kompetitor dan program retensi di {len(kec)} kecamatan terdampak")
    elif avail is not None and avail < SLA:
        actions.append(f"Availability 4G {_f1(avail)}% di bawah SLA {SLA:g}%, cek site yang sering down")
    return {"text": text, "actions": actions}


@router.get("/kabupaten")
def kabupaten(metric: str = Query("revenue", pattern="^(revenue|payload|availability)$"), region: str = "",
              refresh: bool = False, user: User = Depends(get_current_user)):
    try:
        return reports_cache.get_or_build("map", f"{metric}|{_esc(region)}", lambda: build_kabupaten(metric, region), force=refresh)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}


@router.get("/kabupaten/detail")
def kabupaten_detail(kabupaten: str, provinsi: str, user: User = Depends(get_current_user)):
    try:
        return reports_cache.get_or_build("map", f"detail|{_esc(kabupaten)}|{_esc(provinsi)}", lambda: build_detail(kabupaten, provinsi))
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
