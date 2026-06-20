"""Geo-location resolver: GPS coordinate -> kecamatan (KEC_ID) via SHP polygons,
then nearest sites & outlets from BigQuery.

SHP: /home/ubuntu/telco-ai/shp/Data Kecamatan Indonesia.{shp,dbf,...} (WGS84).
KEC_ID format in the SHP (e.g. 'GENTENG|KOTA SURABAYA') matches BigQuery kec_id.
"""
import os
import logging
from functools import lru_cache

from . import config
from .bigquery_tool import run_query

log = logging.getLogger("geo_locate")

_SHP_PATH = os.environ.get(
    "KEC_SHP_PATH", "/home/ubuntu/telco-ai/shp/Data Kecamatan Indonesia")

_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET


@lru_cache(maxsize=1)
def _shp_index():
    """Load polygons once into memory as (bbox, shapely_geom, record_dict)."""
    import shapefile
    from shapely.geometry import shape
    sf = shapefile.Reader(_SHP_PATH)
    fields = [f[0] for f in sf.fields[1:]]
    idx = {fields[i]: i for i in range(len(fields))}
    items = []
    for sr in sf.iterShapeRecords():
        try:
            bbox = sr.shape.bbox  # [minx,miny,maxx,maxy]
            geom = shape(sr.shape.__geo_interface__)
            rec = sr.record
            items.append((bbox, geom, {
                "kec_id": rec[idx.get("KEC_ID", -1)] if "KEC_ID" in idx else None,
                "kecamatan": rec[idx.get("KEC", -1)] if "KEC" in idx else None,
                "kabkota": rec[idx.get("KAB_KOT", -1)] if "KAB_KOT" in idx else None,
                "provinsi": rec[idx.get("PROV", -1)] if "PROV" in idx else None,
            }))
        except Exception:
            continue
    log.info(f"SHP index loaded: {len(items)} kecamatan polygons")
    return items


def locate_kecamatan(lat: float, lon: float) -> dict | None:
    """Return {kec_id, kecamatan, kabkota, provinsi} for a GPS point, or None."""
    try:
        from shapely.geometry import Point
    except Exception as e:
        log.error(f"shapely missing: {e}")
        return None
    pt = Point(lon, lat)  # shapely uses (x=lon, y=lat)
    nearest = None
    nearest_d = None
    for bbox, geom, rec in _shp_index():
        if not (bbox[0] <= lon <= bbox[2] and bbox[1] <= lat <= bbox[3]):
            # track nearest centroid as a fallback (point just outside borders)
            try:
                c = geom.centroid
                d = (c.x - lon) ** 2 + (c.y - lat) ** 2
                if nearest_d is None or d < nearest_d:
                    nearest_d, nearest = d, rec
            except Exception:
                pass
            continue
        if geom.contains(pt):
            return rec
    # not strictly inside any polygon -> use nearest centroid if close (<~5km)
    if nearest is not None and nearest_d is not None and nearest_d < 0.0025:
        return nearest
    return None


def _haversine_sql(col_lat: str, col_lon: str, lat: float, lon: float) -> str:
    return (
        f"(6371 * ACOS(LEAST(1.0, COS({lat}*ACOS(-1)/180) * "
        f"COS({col_lat}*ACOS(-1)/180) * COS({col_lon}*ACOS(-1)/180 - {lon}*ACOS(-1)/180) + "
        f"SIN({lat}*ACOS(-1)/180) * SIN({col_lat}*ACOS(-1)/180)))) "
    )


def nearest_sites(lat: float, lon: float, n: int = 10) -> dict:
    """10 nearest cell sites with basic info + revenue + distance."""
    t = f"`{_PROJECT}.{_DATASET}"
    dist = _haversine_sql("a.lat", "a.lon", lat, lon)
    sql = f"""
WITH addr AS (
  SELECT site_id, site_name,
         SAFE_CAST(latitude AS FLOAT64) AS lat,
         SAFE_CAST(longitude AS FLOAT64) AS lon,
         kecamatan, kabupaten, site_type, category, profitability_status_m1
  FROM {t}.rham_site_wise_addr_java`
  WHERE month_id = (SELECT MAX(month_id) FROM {t}.rham_site_wise_addr_java`)
    AND SAFE_CAST(latitude AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(longitude AS FLOAT64) IS NOT NULL
),
perf AS (
  SELECT site_id, SUM(rev_prepaid) AS revenue, SUM(subs_rgu_90d) AS subs_rgu_90d
  FROM {t}.rham_site_wise_monthly`
  WHERE month_id = (SELECT MAX(month_id) FROM {t}.rham_site_wise_monthly`)
  GROUP BY site_id
)
SELECT a.site_id, a.site_name, a.lat AS latitude, a.lon AS longitude,
       a.kecamatan, a.kabupaten, a.site_type, a.profitability_status_m1,
       p.revenue, p.subs_rgu_90d,
       ROUND({dist}, 2) AS distance_km
FROM addr a LEFT JOIN perf p ON a.site_id = p.site_id
ORDER BY distance_km ASC
LIMIT {n}
""".strip()
    return run_query(sql)


def nearest_sites_perf(lat: float, lon: float, n: int = 100, months: int = 6) -> dict:
    """Up to `n` nearest sites ("Fix mode"): full site attributes from
    rham_site_wise_addr_java + latest-month performance + a per-site monthly
    history (last `months`) from rham_site_wise_monthly for rich tooltips."""
    t = f"`{_PROJECT}.{_DATASET}"
    dist = _haversine_sql("SAFE_CAST(latitude AS FLOAT64)", "SAFE_CAST(longitude AS FLOAT64)", lat, lon)

    # 1. nearest N sites with attributes (single cheap scan of the addr table)
    addr_sql = f"""
SELECT site_id, site_name,
       SAFE_CAST(latitude AS FLOAT64) AS latitude,
       SAFE_CAST(longitude AS FLOAT64) AS longitude,
       circle, region, area, branch, micro_cluster, kecamatan, kabupaten, provinsi,
       site_type, category, addressable, profitability_status_m1,
       rgs_category, traffic_category, project_new_site,
       ROUND({dist}, 2) AS distance_km
FROM {t}.rham_site_wise_addr_java`
WHERE month_id = (SELECT MAX(month_id) FROM {t}.rham_site_wise_addr_java`)
  AND SAFE_CAST(latitude AS FLOAT64) IS NOT NULL
  AND SAFE_CAST(longitude AS FLOAT64) IS NOT NULL
ORDER BY distance_km ASC
LIMIT {int(n)}
""".strip()
    addr = run_query(addr_sql, row_limit=int(n) + 5)
    rows = addr["rows"]
    if not rows:
        return {"sites": [], "month_id": None}
    ids = [r["site_id"] for r in rows if r.get("site_id")]
    id_list = ",".join("'" + str(s).replace("'", "") + "'" for s in ids)

    # 2. latest month performance (brand-summed) for those sites
    perf_sql = f"""
SELECT site_id,
  SUM(rev_prepaid) AS rev_prepaid, SUM(rev_data) AS rev_data,
  SUM(rev_voice) AS rev_voice, SUM(rev_sms) AS rev_sms,
  SUM(rev_trade) AS rev_trade, SUM(rev_organic) AS rev_organic, SUM(rev_nontrade) AS rev_nontrade,
  SUM(subs_rgu_90d) AS rgu_90d, SUM(subs_rgu_30d) AS rgu_30d,
  SUM(subs_gross_add) AS gross_add, SUM(net_add_90d) AS net_add_90d,
  SUM(gross_churn_90d) AS gross_churn_90d, SUM(subs_hvc) AS subs_hvc,
  SUM(usg_data_gb) AS usg_data_gb, SUM(avg_subs_vlr_daily) AS vlr_daily
FROM {t}.rham_site_wise_monthly`
WHERE month_id = (SELECT MAX(month_id) FROM {t}.rham_site_wise_monthly`)
  AND site_id IN ({id_list})
GROUP BY site_id
""".strip()
    perf = {r["site_id"]: r for r in run_query(perf_sql, row_limit=int(n) + 5)["rows"]}

    # 3. monthly history (rev + rgu) for those sites, last `months`
    hist_sql = f"""
WITH mx AS (SELECT MAX(month_id) m FROM {t}.rham_site_wise_monthly`)
SELECT site_id, month_id,
  SUM(rev_prepaid) AS rev_prepaid, SUM(rev_data) AS rev_data,
  SUM(subs_rgu_90d) AS rgu_90d, SUM(net_add_90d) AS net_add_90d,
  SUM(usg_data_gb) AS usg_data_gb
FROM {t}.rham_site_wise_monthly`, mx
WHERE site_id IN ({id_list})
  AND CAST(month_id AS INT64) > CAST(mx.m AS INT64) - {int(months)}
GROUP BY site_id, month_id
ORDER BY site_id, month_id
""".strip()
    hist: dict = {}
    for r in run_query(hist_sql, row_limit=int(n) * (int(months) + 2))["rows"]:
        hist.setdefault(r["site_id"], []).append({
            "month_id": r.get("month_id"),
            "rev_prepaid": float(r.get("rev_prepaid") or 0),
            "rev_data": float(r.get("rev_data") or 0),
            "rgu_90d": float(r.get("rgu_90d") or 0),
            "net_add_90d": float(r.get("net_add_90d") or 0),
            "usg_data_gb": float(r.get("usg_data_gb") or 0),
        })

    def fnum(d, k):
        v = (d or {}).get(k)
        return float(v) if v is not None else None

    sites = []
    for r in rows:
        sid = r.get("site_id")
        p = perf.get(sid, {})
        sites.append({
            **r,
            "perf": {k: fnum(p, k) for k in (
                "rev_prepaid", "rev_data", "rev_voice", "rev_sms", "rev_trade",
                "rev_organic", "rev_nontrade", "rgu_90d", "rgu_30d", "gross_add",
                "net_add_90d", "gross_churn_90d", "subs_hvc", "usg_data_gb", "vlr_daily")},
            "history": hist.get(sid, []),
        })
    mm = run_query(f"SELECT MAX(month_id) m FROM {t}.rham_site_wise_monthly`")["rows"][0]["m"]
    return {"sites": sites, "month_id": mm}


def nearest_outlets(lat: float, lon: float, n: int = 10) -> dict:
    """10 nearest outlets (NBS) with basic info + distance."""
    t = f"`{_PROJECT}.{_DATASET}"
    dist = _haversine_sql("SAFE_CAST(outlet_latitude AS FLOAT64)",
                          "SAFE_CAST(outlet_longitude AS FLOAT64)", lat, lon)
    sql = f"""
SELECT outlet_id, outlet_name, site_id,
       SAFE_CAST(outlet_latitude AS FLOAT64) AS latitude,
       SAFE_CAST(outlet_longitude AS FLOAT64) AS longitude,
       organization_category,
       ROUND({dist}, 2) AS distance_km
FROM {t}.rham_outlet_nbs`
WHERE month_id = (SELECT MAX(month_id) FROM {t}.rham_outlet_nbs`)
  AND SAFE_CAST(outlet_latitude AS FLOAT64) IS NOT NULL
  AND SAFE_CAST(outlet_longitude AS FLOAT64) IS NOT NULL
ORDER BY distance_km ASC
LIMIT {n}
""".strip()
    return run_query(sql)


def kec_profile(kec_id: str) -> dict:
    """High-level KPI profile for a kecamatan (latest MTD): sites, revenue, subs, etc."""
    t = f"`{_PROJECT}.{_DATASET}"
    safe = kec_id.replace("'", "")
    sql = f"""
WITH mx AS (SELECT MAX(month_id) AS m FROM {t}.rham_mkt_highlevel_mtd`)
SELECT
  ANY_VALUE(kecamatan) AS kecamatan,
  ANY_VALUE(kabkot) AS kabkota,
  month_id AS period,
  SUM(total_site) AS total_site,
  SUM(addr_site) AS addressable_site,
  SUM(num_outlet) AS total_outlet,
  SUM(rev_prepaid) AS revenue_prepaid,
  SUM(rgu_90d) AS rgu_90d,
  SUM(gross_add) AS gross_add,
  SUM(net_add_90d) AS net_add_90d,
  SUM(pack_subs) AS pack_subs,
  SUM(subs_hvc) AS subs_hvc
FROM {t}.rham_mkt_highlevel_mtd`, mx
WHERE kec_id = '{safe}' AND month_id = mx.m
GROUP BY month_id
""".strip()
    return run_query(sql)
