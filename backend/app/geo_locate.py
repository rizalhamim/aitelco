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

_CHANNEL_MTD = f"`{_PROJECT}.{_DATASET}.rham_kec_data_rev_channel_mtd`"
_CHANNEL_MTH = f"`{_PROJECT}.{_DATASET}.rham_kec_data_rev_channel_mth`"


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
    for bbox, geom, rec in _shp_index():
        if not (bbox[0] <= lon <= bbox[2] and bbox[1] <= lat <= bbox[3]):
            continue
        if geom.covers(pt):
            return {**rec, "location_method": "polygon", "boundary": geom.boundary.covers(pt)}
    return None


def _haversine_sql(col_lat: str, col_lon: str, lat: float, lon: float) -> str:
    return (
        f"(6371 * ACOS(GREATEST(-1.0, LEAST(1.0, COS({lat}*ACOS(-1)/180) * "
        f"COS({col_lat}*ACOS(-1)/180) * COS({col_lon}*ACOS(-1)/180 - {lon}*ACOS(-1)/180) + "
        f"SIN({lat}*ACOS(-1)/180) * SIN({col_lat}*ACOS(-1)/180))))) "
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
    AND SAFE_CAST(latitude AS FLOAT64) BETWEEN -90 AND 90
    AND SAFE_CAST(longitude AS FLOAT64) BETWEEN -180 AND 180
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


def nearest_sites_perf(lat: float, lon: float, n: int = 100, months: int = 12) -> dict:
    """Up to `n` nearest sites ("Fix mode"): full site attributes from
    rham_site_wise_addr_java + latest-month performance + MoM (prev month) +
    YoY (same month last year) + per-channel revenue profile + a per-site monthly
    history (last `months`) from rham_site_wise_monthly for rich tooltips/charts."""
    t = f"`{_PROJECT}.{_DATASET}"
    dist = _haversine_sql("SAFE_CAST(latitude AS FLOAT64)", "SAFE_CAST(longitude AS FLOAT64)", lat, lon)

    # 1. nearest N sites with attributes (single cheap scan of the addr table)
    addr_sql = f"""
SELECT site_id, site_name,
       SAFE_CAST(latitude AS FLOAT64) AS latitude,
       SAFE_CAST(longitude AS FLOAT64) AS longitude,
       circle, region, branch AS area, branch, micro_cluster AS district, micro_cluster,
       kecamatan_unik AS kec_id, kecamatan, kabupaten, provinsi,
       site_type, category, addressable, profitability_status_m1,
       rgs_category, traffic_category, project_new_site,
       ROUND({dist}, 2) AS distance_km
FROM {t}.rham_site_wise_addr_java`
WHERE month_id = (SELECT MAX(month_id) FROM {t}.rham_site_wise_addr_java`)
  AND SAFE_CAST(latitude AS FLOAT64) BETWEEN -90 AND 90
  AND SAFE_CAST(longitude AS FLOAT64) BETWEEN -180 AND 180
ORDER BY distance_km ASC
LIMIT {int(n)}
""".strip()
    addr = run_query(addr_sql, row_limit=int(n) + 5)
    rows = addr["rows"]
    if not rows:
        return {"sites": [], "month_id": None}
    ids = [r["site_id"] for r in rows if r.get("site_id")]
    id_list = ",".join("'" + str(s).replace("'", "") + "'" for s in ids)

    # resolve the comparison months (current / prev / same-month-last-year)
    mm = run_query(f"SELECT MAX(month_id) m FROM {t}.rham_site_wise_monthly`")["rows"][0]["m"]
    cur_m = int(mm)
    def _prev_month(m: int) -> int:
        return m - 1 if m % 100 > 1 else (m // 100 - 1) * 100 + 12
    prev_m = _prev_month(cur_m)            # MoM (LMTD)
    prev2_m = _prev_month(prev_m)          # 2 months ago (LLMTD)
    yoy_m = cur_m - 100  # same month last year
    yoy_prev_m = prev_m - 100  # prev month last year (kept for completeness)

    _PERF_COLS = (
        "rev_prepaid", "rev_data", "rev_voice", "rev_sms", "rev_trade",
        "rev_organic", "rev_nontrade", "rev_vsd", "rgu_90d", "rgu_30d", "gross_add",
        "net_add_90d", "gross_churn_90d", "subs_hvc", "usg_data_gb", "vlr_daily")

    # Column projection shared by the monthly + MTD tables (same schema).
    _PERF_SELECT = """
  SUM(rev_prepaid) AS rev_prepaid, SUM(rev_data) AS rev_data,
  SUM(rev_voice) AS rev_voice, SUM(rev_sms) AS rev_sms,
  SUM(rev_trade) AS rev_trade, SUM(rev_organic) AS rev_organic, SUM(rev_nontrade) AS rev_nontrade,
  SUM(rev_vsd) AS rev_vsd,
  SUM(subs_rgu_90d) AS rgu_90d, SUM(subs_rgu_30d) AS rgu_30d,
  SUM(subs_gross_add) AS gross_add, SUM(net_add_90d) AS net_add_90d,
  SUM(gross_churn_90d) AS gross_churn_90d, NULLIF(SUM(subs_hvc), 0) AS subs_hvc,
  SUM(usg_data_gb) AS usg_data_gb, SUM(avg_subs_vlr_daily) AS vlr_daily""".strip()

    def _perf_for(table: str, month_filter: str) -> dict:
        """Brand-summed performance for a month (or set of months) per site."""
        sql = f"""
SELECT site_id,
  {_PERF_SELECT}
FROM {t}.{table}`
WHERE {month_filter}
  AND site_id IN ({id_list})
GROUP BY site_id
""".strip()
        return {r["site_id"]: r for r in run_query(sql, row_limit=int(n) + 5)["rows"]}

    # Full-month absolute (closed-month table) — the requested monthly absolute.
    perf = _perf_for("rham_site_wise_monthly", f"month_id = '{cur_m}'")
    perf_mom = _perf_for("rham_site_wise_monthly", f"month_id = '{prev_m}'")  # full prev month (MoM on full-month)
    perf_yoy = _perf_for("rham_site_wise_monthly", f"month_id = '{yoy_m}'")   # same month last year (full-month)

    # MTD vs LMTD vs LLMTD (cutoff-capped MTD table), apple-to-apple within the month.
    perf_mtd = _perf_for("rham_site_wise_mtd", f"month_id = '{cur_m}'")
    perf_lmtd = _perf_for("rham_site_wise_mtd", f"month_id = '{prev_m}'")
    perf_llmtd = _perf_for("rham_site_wise_mtd", f"month_id = '{prev2_m}'")   # 2 months ago

    # YTD / LYTD / LLYTD (apple-to-apple): prior full months + current month MTD.
    def _months_jan_to(m_end_excl: int) -> list[int]:
        """Jan..(m_end_excl-1) within the same year as m_end_excl."""
        y, mo = m_end_excl // 100, m_end_excl % 100
        return [y * 100 + i for i in range(1, mo)]
    yy2_m = cur_m - 200  # current month MTD two years ago (for LLYTD)
    ytd_prior = _months_jan_to(cur_m)            # Jan..cur-1 this year
    lytd_prior = _months_jan_to(yoy_m)           # Jan..cur-1 last year
    llytd_prior = _months_jan_to(yy2_m)          # Jan..cur-1 two years ago
    ytd_prior_list = ",".join(f"'{x}'" for x in ytd_prior) if ytd_prior else "''"
    lytd_prior_list = ",".join(f"'{x}'" for x in lytd_prior) if lytd_prior else "''"
    llytd_prior_list = ",".join(f"'{x}'" for x in llytd_prior) if llytd_prior else "''"
    perf_ytd_prior = _perf_for("rham_site_wise_monthly", f"month_id IN ({ytd_prior_list})") if ytd_prior else {}
    perf_lytd_prior = _perf_for("rham_site_wise_monthly", f"month_id IN ({lytd_prior_list})") if lytd_prior else {}
    perf_llytd_prior = _perf_for("rham_site_wise_monthly", f"month_id IN ({llytd_prior_list})") if llytd_prior else {}
    perf_mtd_yoy = _perf_for("rham_site_wise_mtd", f"month_id = '{yoy_m}'")  # current month MTD last year
    perf_mtd_yy2 = _perf_for("rham_site_wise_mtd", f"month_id = '{yy2_m}'")  # current month MTD two years ago

    # last `months` calendar months ending at cur_m (handles year rollover).
    def _back_months(end_int: int, k: int) -> list[int]:
        y, mo = end_int // 100, end_int % 100
        out = []
        for _ in range(k):
            out.append(y * 100 + mo)
            mo -= 1
            if mo == 0:
                mo = 12
                y -= 1
        return sorted(out)
    hist_months = _back_months(cur_m, int(months))
    hist_month_list = ",".join(f"'{x}'" for x in hist_months)

    # monthly history (rev channels + rgu + VLR) for those sites, last `months` (for trend charts)
    hist_sql = f"""
SELECT site_id, month_id,
  SUM(rev_prepaid) AS rev_prepaid, SUM(rev_data) AS rev_data,
  SUM(rev_trade) AS rev_trade, SUM(rev_organic) AS rev_organic,
  SUM(subs_rgu_90d) AS rgu_90d, SUM(net_add_90d) AS net_add_90d,
  SUM(usg_data_gb) AS usg_data_gb, SUM(avg_subs_vlr_daily) AS vlr_daily
FROM {t}.rham_site_wise_monthly`
WHERE site_id IN ({id_list})
  AND month_id IN ({hist_month_list})
GROUP BY site_id, month_id
ORDER BY site_id, month_id
""".strip()
    hist: dict = {}
    for r in run_query(hist_sql, row_limit=int(n) * (int(months) + 2))["rows"]:
        hist.setdefault(r["site_id"], []).append({
            "month_id": r.get("month_id"),
            "rev_prepaid": float(r.get("rev_prepaid") or 0),
            "rev_data": float(r.get("rev_data") or 0),
            "rev_trade": float(r.get("rev_trade") or 0),
            "rev_organic": float(r.get("rev_organic") or 0),
            "rgu_90d": float(r.get("rgu_90d") or 0),
            "net_add_90d": float(r.get("net_add_90d") or 0),
            "usg_data_gb": float(r.get("usg_data_gb") or 0),
            "vlr_daily": float(r.get("vlr_daily") or 0),
        })

    # ── Data-revenue sales channels per site (grouped by channel_group ->
    #    channel_detail), apple-to-apple Full Month / LLMTD-LMTD-MTD / LLYTD-LYTD-YTD. ──
    #    YTD   = prior full months (Jan..cur-1, _mth) + current month MTD (_mtd).
    #    LYTD  = last-year prior months + last-year current-month MTD.
    #    LLYTD = two-years-ago prior months + two-years-ago current-month MTD.
    def _chan_sum(table: str, month_filter: str) -> dict:
        """{(site_id, channel_group, channel_detail): revenue} for a month set."""
        sql = f"""
SELECT kec_id, channel_group, channel_detail, COALESCE(SUM(revenue),0) AS revenue
FROM {table}
WHERE kec_id IN ({kec_list}) AND kpi_group='REVENUE DATA' AND {month_filter}
GROUP BY kec_id, channel_group, channel_detail
""".strip()
        out: dict = {}
        for r in run_query(sql, row_limit=int(n) * 60)["rows"]:
            key = (r.get("kec_id"), r.get("channel_group"), r.get("channel_detail"))
            out[key] = float(r.get("revenue") or 0)
        return out

    kec_list = ",".join("'" + str(r.get("kec_id", "")).replace("'", "") + "'" for r in rows) or "''"
    ch_full = _chan_sum(_CHANNEL_MTH, f"month_id = '{cur_m}'")          # current full month
    ch_mtd = _chan_sum(_CHANNEL_MTD, f"month_id = '{cur_m}'")           # MTD this year
    ch_lmtd = _chan_sum(_CHANNEL_MTD, f"month_id = '{prev_m}'")         # LMTD
    ch_llmtd = _chan_sum(_CHANNEL_MTD, f"month_id = '{prev2_m}'")       # LLMTD (2 months ago)
    ch_mtd_yoy = _chan_sum(_CHANNEL_MTD, f"month_id = '{yoy_m}'")       # MTD last year
    ch_mtd_yy2 = _chan_sum(_CHANNEL_MTD, f"month_id = '{yy2_m}'")       # MTD two years ago
    ch_ytd_prior = _chan_sum(_CHANNEL_MTH, f"month_id IN ({ytd_prior_list})") if ytd_prior else {}
    ch_lytd_prior = _chan_sum(_CHANNEL_MTH, f"month_id IN ({lytd_prior_list})") if lytd_prior else {}
    ch_llytd_prior = _chan_sum(_CHANNEL_MTH, f"month_id IN ({llytd_prior_list})") if llytd_prior else {}

    def _channel_block(sid: str) -> list:
        """Grouped channel rows for one site: [{channel_group, total{..}, details:[{..}]}]."""
        keys = {k for k in (set(ch_full) | set(ch_mtd) | set(ch_lmtd) | set(ch_llmtd)
                            | set(ch_ytd_prior) | set(ch_lytd_prior) | set(ch_llytd_prior)) if k[0] == sid}
        groups: dict = {}
        for (_s, grp, det) in keys:
            k = (sid, grp, det)
            full = ch_full.get(k, 0.0)
            mtd = ch_mtd.get(k, 0.0)
            lmtd = ch_lmtd.get(k, 0.0)
            llmtd = ch_llmtd.get(k, 0.0)
            ytd = ch_ytd_prior.get(k, 0.0) + mtd
            lytd = ch_lytd_prior.get(k, 0.0) + ch_mtd_yoy.get(k, 0.0)
            llytd = ch_llytd_prior.get(k, 0.0) + ch_mtd_yy2.get(k, 0.0)
            row = {"detail": det, "full_month": full, "llmtd": llmtd, "lmtd": lmtd, "mtd": mtd,
                   "mtd_growth": _growth(mtd, lmtd), "mtd_abs": mtd - lmtd,
                   "llytd": llytd, "lytd": lytd, "ytd": ytd,
                   "yoy_growth": _growth(ytd, lytd), "yoy_abs": ytd - lytd}
            g = groups.setdefault(grp, {"channel_group": grp, "details": [],
                                        "full_month": 0.0, "llmtd": 0.0, "lmtd": 0.0, "mtd": 0.0,
                                        "llytd": 0.0, "lytd": 0.0, "ytd": 0.0})
            g["details"].append(row)
            for kk in ("full_month", "llmtd", "lmtd", "mtd", "llytd", "lytd", "ytd"):
                g[kk] += row[kk]
        out = []
        for g in groups.values():
            g["mtd_growth"] = _growth(g["mtd"], g["lmtd"])
            g["mtd_abs"] = g["mtd"] - g["lmtd"]
            g["yoy_growth"] = _growth(g["ytd"], g["lytd"])
            g["yoy_abs"] = g["ytd"] - g["lytd"]
            g["details"].sort(key=lambda d: d["full_month"], reverse=True)
            out.append(g)
        out.sort(key=lambda x: x["full_month"], reverse=True)
        return out

    def fnum(d, k):
        v = (d or {}).get(k)
        return float(v) if v is not None else None

    def _growth(cur, base):
        if cur is None or base is None or base == 0:
            return None
        return round((cur - base) / abs(base) * 100, 1)

    # revenue channels shown in the per-channel profile (label, key)
    _CHANNELS = [
        ("Prepaid", "rev_prepaid"), ("Data", "rev_data"), ("Voice", "rev_voice"),
        ("SMS", "rev_sms"), ("Trade", "rev_trade"), ("Organic", "rev_organic"),
        ("Non-Trade", "rev_nontrade"), ("VSD", "rev_vsd")]

    def _add(*ds):
        """Element-wise sum of per-metric dicts (for YTD = prior + current MTD)."""
        out = {}
        for k in _PERF_COLS:
            tot = None
            for d in ds:
                v = fnum(d, k)
                if v is not None:
                    tot = (tot or 0) + v
            out[k] = tot
        return out

    sites = []
    for r in rows:
        sid = r.get("site_id")
        p = perf.get(sid, {})
        pm = perf_mom.get(sid, {})
        py = perf_yoy.get(sid, {})
        perf_cur = {k: fnum(p, k) for k in _PERF_COLS}          # full-month absolute (current)
        # MoM / YoY growth on full-month absolute (kept for the channel profile)
        mom = {k: _growth(perf_cur.get(k), fnum(pm, k)) for k in _PERF_COLS}
        yoy = {k: _growth(perf_cur.get(k), fnum(py, k)) for k in _PERF_COLS}

        # MTD vs LMTD vs LLMTD (cutoff-capped)
        mtd_cur = {k: fnum(perf_mtd.get(sid, {}), k) for k in _PERF_COLS}
        lmtd_cur = {k: fnum(perf_lmtd.get(sid, {}), k) for k in _PERF_COLS}
        llmtd_cur = {k: fnum(perf_llmtd.get(sid, {}), k) for k in _PERF_COLS}

        # YTD / LYTD / LLYTD apple-to-apple: prior full months + current MTD
        ytd_cur = _add(perf_ytd_prior.get(sid, {}), perf_mtd.get(sid, {}))
        lytd_cur = _add(perf_lytd_prior.get(sid, {}), perf_mtd_yoy.get(sid, {}))
        llytd_cur = _add(perf_llytd_prior.get(sid, {}), perf_mtd_yy2.get(sid, {}))

        def _abs(cur, base):
            if cur is None or base is None:
                return None
            return cur - base

        # Per-metric rich block: full_month, LLMTD/LMTD/MTD/growth/abs, LLYTD/LYTD/YTD/growth/abs.
        metrics = {}
        for k in _PERF_COLS:
            metrics[k] = {
                "full_month": perf_cur.get(k),
                "llmtd": llmtd_cur.get(k),
                "lmtd": lmtd_cur.get(k),
                "mtd": mtd_cur.get(k),
                "mtd_growth": _growth(mtd_cur.get(k), lmtd_cur.get(k)),
                "mtd_abs": _abs(mtd_cur.get(k), lmtd_cur.get(k)),
                "llytd": llytd_cur.get(k),
                "lytd": lytd_cur.get(k),
                "ytd": ytd_cur.get(k),
                "yoy_growth": _growth(ytd_cur.get(k), lytd_cur.get(k)),
                "yoy_abs": _abs(ytd_cur.get(k), lytd_cur.get(k)),
            }

        # per-channel revenue profile (full-month value + MoM/YoY + share of total rev)
        ch_total = sum((perf_cur.get(k) or 0) for _lbl, k in _CHANNELS) or 0
        channels = []
        for lbl, k in _CHANNELS:
            v = perf_cur.get(k)
            channels.append({
                "label": lbl, "key": k, "value": v,
                "share_pct": (round((v or 0) / ch_total * 100, 1) if ch_total else None),
                "mom_pct": mom.get(k), "yoy_pct": yoy.get(k),
            })
        sites.append({
            **r,
            "perf": perf_cur,
            "mom": mom,
            "yoy": yoy,
            "metrics": metrics,
            "channels": channels,
            "channel_groups": _channel_block(r.get("kec_id")),
            "channel_grain": "kecamatan",
            "channel_scope": r.get("kec_id"),
            "history": hist.get(sid, []),
        })
    return {"sites": sites, "month_id": mm, "prev_month_id": str(prev_m),
            "yoy_month_id": str(yoy_m), "mtd_month_id": str(cur_m), "lmtd_month_id": str(prev_m),
            "llmtd_month_id": str(prev2_m), "llytd_month_id": str(yy2_m)}


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
  AND SAFE_CAST(outlet_latitude AS FLOAT64) BETWEEN -90 AND 90
  AND SAFE_CAST(outlet_longitude AS FLOAT64) BETWEEN -180 AND 180
ORDER BY distance_km ASC
LIMIT {n}
""".strip()
    return run_query(sql)


def kec_profile(kec_id: str) -> dict:
    """High-level KPI profile for a kecamatan (latest MTD): sites, revenue, subs, etc."""
    t = f"`{_PROJECT}.{_DATASET}"
    safe = kec_id.replace("'", "")
    sql = f"""
WITH mx AS (SELECT MAX(month_id) AS m FROM {t}.rham_hvc_highlevel_mtd_serving`)
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
FROM {t}.rham_hvc_highlevel_mtd_serving`, mx
WHERE kec_id = '{safe}' AND month_id = mx.m
GROUP BY month_id
""".strip()
    return run_query(sql)
