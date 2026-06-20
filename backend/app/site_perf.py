"""Site Performance: per-site profile + monthly history + channel/subs/usage/
top-products/price-slab/quota-validity slab/funnel — for the Site Performance menu.

Data sources (all keyed by site_id):
  rham_site_wise_addr_java     — site attributes (lat/long, type, branch, ...)
  rham_site_wise_monthly       — monthly performance (revenue/subs/usage/churn/HVC)
  rham_site_data_rev_product_mtd / _channel_mtd / _price_slab_mtd — data revenue detail
"""
from __future__ import annotations

from . import config
from .bigquery_tool import run_query
from .geo_locate import _haversine_sql
from .reports_data import (PRICE_SLAB_ORDER, QUOTA_BINS, VALIDITY_BINS,
                           _quota_case, _validity_case)

_P = config.BQ_PROJECT
_D = config.BQ_DATASET
_ADDR = f"`{_P}.{_D}.rham_site_wise_addr_java`"
_MON = f"`{_P}.{_D}.rham_site_wise_monthly`"
_PERF = f"`{_P}.{_D}.rham_site_wise_addr_java_perf`"
_GA = f"`{_P}.{_D}.rham_site_ga_daily`"
_PRODUCT = f"`{_P}.{_D}.rham_site_data_rev_product_mtd`"
_CHANNEL = f"`{_P}.{_D}.rham_site_data_rev_channel_mtd`"
_CHANNEL_MTH = f"`{_P}.{_D}.rham_site_data_rev_channel_mth`"
_5G = f"`{_P}.{_D}.rham_5g_site_monthly`"
_AVAIL = f"`{_P}.{_D}.rham_avail_stat_site_monthly`"
_FWA = f"`{_P}.{_D}.rham_site_fwa_daily`"
_SLAB = f"`{_P}.{_D}.rham_site_data_rev_price_slab_mtd`"


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


def _f(d, k):
    v = (d or {}).get(k)
    return float(v) if v is not None else None


# ── Search & nearest ─────────────────────────────────────────────────────────

def search_sites(q: str, n: int = 15) -> dict:
    """Find sites whose id or name matches the query (case-insensitive LIKE)."""
    safe = _esc(q).upper()
    sql = f"""
SELECT site_id, site_name, branch, kecamatan, kabupaten,
       SAFE_CAST(latitude AS FLOAT64) AS latitude,
       SAFE_CAST(longitude AS FLOAT64) AS longitude
FROM {_ADDR}
WHERE month_id = (SELECT MAX(month_id) FROM {_ADDR})
  AND (UPPER(site_id) LIKE '%{safe}%' OR UPPER(site_name) LIKE '%{safe}%')
ORDER BY (CASE WHEN UPPER(site_id)='{safe}' OR UPPER(site_name)='{safe}' THEN 0
               WHEN UPPER(site_id) LIKE '{safe}%' OR UPPER(site_name) LIKE '{safe}%' THEN 1
               ELSE 2 END), site_id
LIMIT {int(n)}
"""
    return {"sites": run_query(sql, row_limit=int(n) + 5)["rows"]}


def nearest_sites(lat: float, lon: float, n: int = 10) -> dict:
    """N nearest sites (id, name, distance) for the coordinate picker."""
    dist = _haversine_sql("SAFE_CAST(latitude AS FLOAT64)", "SAFE_CAST(longitude AS FLOAT64)", lat, lon)
    sql = f"""
SELECT site_id, site_name, branch, kecamatan, kabupaten,
       SAFE_CAST(latitude AS FLOAT64) AS latitude,
       SAFE_CAST(longitude AS FLOAT64) AS longitude,
       ROUND({dist}, 2) AS distance_km
FROM {_ADDR}
WHERE month_id = (SELECT MAX(month_id) FROM {_ADDR})
  AND SAFE_CAST(latitude AS FLOAT64) IS NOT NULL
  AND SAFE_CAST(longitude AS FLOAT64) IS NOT NULL
ORDER BY distance_km ASC
LIMIT {int(n)}
"""
    return {"sites": run_query(sql, row_limit=int(n) + 5)["rows"]}


# ── Site detail ──────────────────────────────────────────────────────────────

_MON_METRICS = [
    "rev_prepaid", "rev_vsd", "rev_nonvsd", "rev_data", "rev_voice", "rev_sms",
    "rev_trade", "rev_organic", "rev_nontrade", "rev_acquisition_m0",
    "subs_rgu_90d", "subs_rgu_30d", "subs_gross_add", "net_add_90d", "net_add_30d",
    "gross_churn_90d", "gross_churn_30d", "churn_back_90d", "subs_net_churn_90d",
    "subs_vlr_30d", "subs_avg_vlr_daily", "datauu", "datauu30d",
    "subs_hvc", "subs_hvc_stay", "subs_hvc_in", "subs_hvc_out",
    "usg_data_gb", "usg_og_voice_min", "usg_og_sms_cnt",
    "ga_m1s", "ga_m2s", "ga_p1m", "ga_p2m",
]

# Metrics present in the perf table (with _lmtd/_mtd/_mtd_growth). HVC is excluded.
_PERF_METRICS = [m for m in _MON_METRICS if not m.startswith("subs_hvc")]


# Brand filter applied to the perf table (which carries IOH/IM3/3ID rows).
def _brand_db(brand: str) -> str:
    b = (brand or "ioh").lower()
    return {"ioh": "IOH", "im3": "IM3", "3id": "3ID", "id3": "3ID"}.get(b, "IOH")


def _brand_clause_mon(brand: str) -> str:
    """For monthly/data tables that have IM3/3ID rows only (no IOH). IOH=both."""
    b = (brand or "ioh").lower()
    if b == "im3":
        return " AND brand='IM3'"
    if b in ("3id", "id3"):
        return " AND brand='3ID'"
    return ""  # ioh = both brands summed


# GA channels (rham_site_ga_daily)
_GA_CHANNELS = [
    ("ga_traditional", "Traditional"), ("ga_dsf", "DSF"), ("ga_modern", "Modern"),
    ("ga_ola", "OLA"), ("ga_online", "Online"), ("ga_gerai", "Gerai"),
    ("ga_bank", "Bank"), ("ga_h2h", "H2H"), ("ga_fwa", "FWA"),
]


def site_detail(site_id: str, brand: str = "ioh", months: int = 6) -> dict:
    sid = _esc(site_id)
    cond = f"site_id = '{sid}'"
    bdb = _brand_db(brand)            # IOH / IM3 / 3ID  (perf table)
    bmon = _brand_clause_mon(brand)   # monthly/data tables

    # 1. attributes
    attr = run_query(f"""
SELECT site_id, site_name, SAFE_CAST(latitude AS FLOAT64) AS latitude,
       SAFE_CAST(longitude AS FLOAT64) AS longitude,
       circle, region, area, branch, micro_cluster, kecamatan, kabupaten, provinsi,
       site_type, category, addressable, profitability_status_m1,
       rgs_category, traffic_category, project_new_site, date_on_air_new_site
FROM {_ADDR} WHERE month_id=(SELECT MAX(month_id) FROM {_ADDR}) AND {cond} LIMIT 1
""", row_limit=2)
    if not attr["rows"]:
        return {"error": "Site tidak ditemukan", "kind": "not_found"}
    a = attr["rows"][0]

    # 2. LMTD / MTD / Growth from the perf table (latest perf_month_id, this brand).
    #    HVC metrics are not in the perf table → pulled from the monthly table.
    perf_cols = []
    for m in _PERF_METRICS:
        perf_cols += [f"{m}_lmtd", f"{m}_mtd", f"{m}_mtd_growth"]
    sel = ", ".join(f"ANY_VALUE({c}) AS {c}" for c in perf_cols)
    pr = run_query(f"""
SELECT {sel}, ANY_VALUE(perf_month_id) AS perf_month_id
FROM {_PERF}
WHERE {cond} AND brand='{bdb}'
  AND perf_month_id=(SELECT MAX(perf_month_id) FROM {_PERF} WHERE {cond})
""", row_limit=2)
    pf = pr["rows"][0] if pr["rows"] else {}
    cur_month = pf.get("perf_month_id")
    metrics = []
    for m in _PERF_METRICS:
        metrics.append({"code": m, "lmtd": _f(pf, f"{m}_lmtd"),
                        "mtd": _f(pf, f"{m}_mtd"), "growth": _f(pf, f"{m}_mtd_growth")})
    perf = {m: _f(pf, f"{m}_mtd") for m in _PERF_METRICS}
    # HVC (mtd only) from monthly table at the same month
    if cur_month:
        hvc = run_query(f"""
SELECT SUM(subs_hvc) AS subs_hvc, SUM(subs_hvc_stay) AS subs_hvc_stay,
       SUM(subs_hvc_in) AS subs_hvc_in, SUM(subs_hvc_out) AS subs_hvc_out
FROM {_MON} WHERE {cond}{bmon} AND month_id='{cur_month}'
""", row_limit=2)["rows"]
        if hvc:
            for hk in ("subs_hvc", "subs_hvc_stay", "subs_hvc_in", "subs_hvc_out"):
                perf[hk] = _f(hvc[0], hk)
                metrics.append({"code": hk, "lmtd": None, "mtd": _f(hvc[0], hk), "growth": None})

    # 3. Full-month history (closed months) from monthly table. The current MTD
    #    month is partial, so the Monthly view shows the `months` FULL closed
    #    months BEFORE it (e.g. MTD=202606 → 202605..202512).
    sums = ",\n  ".join(f"SUM({m}) AS {m}" for m in _MON_METRICS)
    mtd_i = int(cur_month) if cur_month else None
    hist_sql = f"""
WITH lastfull AS (
  SELECT MAX(month_id) m FROM {_MON} WHERE {cond} AND CAST(month_id AS INT64) < {mtd_i}
)
SELECT month_id, {sums}
FROM {_MON}, lastfull
WHERE {cond}{bmon}
  AND CAST(month_id AS INT64) <= CAST(lastfull.m AS INT64)
  AND CAST(month_id AS INT64) > CAST(lastfull.m AS INT64) - {int(months)}
GROUP BY month_id ORDER BY month_id
""" if mtd_i else None
    history = []
    if hist_sql:
        for r in run_query(hist_sql, row_limit=int(months) + 5)["rows"]:
            history.append({k: (_f(r, k) if k != "month_id" else r.get("month_id")) for k in (["month_id"] + _MON_METRICS)})

    # 4. Acquisition by channel (rham_site_ga_daily, current month, brand-filtered)
    ga_sel = ", ".join(f"SUM({c}) AS {c}" for c, _l in _GA_CHANNELS) + ", SUM(ga_total) AS ga_total"
    yr_mo = str(cur_month)[:6] if cur_month else None
    ga_rows = []
    if yr_mo:
        ga = run_query(f"""
SELECT {ga_sel} FROM {_GA}
WHERE {cond}{bmon} AND FORMAT_DATE('%Y%m', dt_id)='{yr_mo}'
""", row_limit=2)["rows"]
        if ga:
            g = ga[0]
            tot = _f(g, "ga_total") or 0
            for c, lbl in _GA_CHANNELS:
                v = _f(g, c) or 0
                ga_rows.append({"channel": lbl, "ga": v, "pct": (v / tot * 100) if tot else None})
            ga_rows.sort(key=lambda x: x["ga"], reverse=True)

    # 5. data-revenue channel — detail list (current month) + group-level
    #    LMTD/MTD/growth (from _mtd) + 6-month history (from _mth).
    channels = run_query(f"""
SELECT channel_group, channel_detail, COALESCE(SUM(revenue),0) AS revenue
FROM {_CHANNEL}
WHERE {cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_CHANNEL})
GROUP BY channel_group, channel_detail ORDER BY revenue DESC
""", row_limit=200)["rows"]

    # LMTD / MTD per channel group (latest two MTD months)
    ch_mtd = run_query(f"""
WITH mx AS (SELECT MAX(month_id) m FROM {_CHANNEL}),
     lm AS (SELECT MAX(month_id) m FROM {_CHANNEL} WHERE month_id < (SELECT m FROM mx))
SELECT channel_group,
  COALESCE(SUM(CASE WHEN month_id=(SELECT m FROM mx) THEN revenue END),0) AS mtd,
  COALESCE(SUM(CASE WHEN month_id=(SELECT m FROM lm) THEN revenue END),0) AS lmtd
FROM {_CHANNEL}
WHERE {cond}{bmon} AND kpi_group='REVENUE DATA'
  AND month_id IN ((SELECT m FROM mx),(SELECT m FROM lm))
GROUP BY channel_group
""", row_limit=20)["rows"]
    ch_metrics = []
    for r in ch_mtd:
        mtd, lmtd = _f(r, "mtd") or 0, _f(r, "lmtd") or 0
        ch_metrics.append({"channel": r.get("channel_group"), "lmtd": lmtd, "mtd": mtd,
                           "growth": ((mtd - lmtd) / lmtd * 100) if lmtd else None})
    ch_metrics.sort(key=lambda x: x["mtd"], reverse=True)

    # Full-month history per channel group — `months` closed months BEFORE the
    # current MTD month (same window as the metric history).
    ch_hist_rows = run_query(f"""
WITH lastfull AS (
  SELECT MAX(month_id) m FROM {_CHANNEL_MTH}
  WHERE {cond} AND kpi_group='REVENUE DATA' AND CAST(month_id AS INT64) < {mtd_i}
)
SELECT month_id, channel_group, COALESCE(SUM(revenue),0) AS revenue
FROM {_CHANNEL_MTH}, lastfull
WHERE {cond}{bmon} AND kpi_group='REVENUE DATA'
  AND CAST(month_id AS INT64) <= CAST(lastfull.m AS INT64)
  AND CAST(month_id AS INT64) > CAST(lastfull.m AS INT64) - {int(months)}
GROUP BY month_id, channel_group ORDER BY month_id
""", row_limit=200)["rows"] if mtd_i else []
    ch_groups = ["ORGANIC", "DIGITAL DISTRIBUTION", "MOBO TRADE"]
    ch_hist: dict = {}
    for r in ch_hist_rows:
        m = r.get("month_id")
        ch_hist.setdefault(m, {})[r.get("channel_group")] = _f(r, "revenue") or 0
    channel_history = [{"month_id": m, **{g: ch_hist[m].get(g, 0) for g in ch_groups}}
                       for m in sorted(ch_hist.keys())]

    slab_raw = {r["price_slab"]: r for r in run_query(f"""
SELECT price_slab, COALESCE(SUM(revenue),0) AS revenue, COALESCE(SUM(hit),0) AS hit
FROM {_SLAB}
WHERE {cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_SLAB})
GROUP BY price_slab
""", row_limit=50)["rows"]}
    price_slabs = [{"slab": s, "revenue": _f(slab_raw.get(s, {}), "revenue") or 0,
                    "hit": _f(slab_raw.get(s, {}), "hit") or 0} for s in PRICE_SLAB_ORDER]

    qcase, vcase = _quota_case(), _validity_case()
    q_rows = {r["q"]: r for r in run_query(f"""
SELECT {qcase} AS q, COALESCE(SUM(revenue),0) AS revenue
FROM {_PRODUCT} WHERE {cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_PRODUCT})
GROUP BY q
""", row_limit=50)["rows"]}
    v_rows = {r["v"]: r for r in run_query(f"""
SELECT {vcase} AS v, COALESCE(SUM(revenue),0) AS revenue
FROM {_PRODUCT} WHERE {cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_PRODUCT})
GROUP BY v
""", row_limit=50)["rows"]}
    quota_slabs = [{"slab": b[0], "revenue": _f(q_rows.get(b[0], {}), "revenue") or 0} for b in QUOTA_BINS]
    validity_slabs = [{"slab": b[0], "revenue": _f(v_rows.get(b[0], {}), "revenue") or 0} for b in VALIDITY_BINS]

    top_products = run_query(f"""
SELECT product_group, family_group,
  COALESCE(SUM(revenue),0) AS revenue, COALESCE(SUM(hit),0) AS hit
FROM {_PRODUCT}
WHERE {cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_PRODUCT})
  AND product_group IS NOT NULL
GROUP BY product_group, family_group ORDER BY revenue DESC LIMIT 10
""", row_limit=20)["rows"]

    # ── Network (5G) : data UU / traffic / device by tech + ratios ──
    # mth_id is STRING. MTD = latest, LMTD = previous; monthly = `months` before MTD.
    _5G_COLS = ["data_uu30_all", "data_uu30_dev_2g", "data_uu30_dev_4g", "data_uu30_dev_5g",
                "data_uu30_traffic_2g", "data_uu30_traffic_4g", "data_uu30_traffic_5g",
                "traffic_2g", "traffic_4g", "traffic_5g", "traffic_total",
                "dev_all", "dev5g_total", "dev5g_with_traffic"]
    net_sel = ", ".join(f"COALESCE(SUM({c}),0) AS {c}" for c in _5G_COLS)
    net_by_month = {}
    try:
        rows5 = run_query(f"""
SELECT mth_id, {net_sel} FROM {_5G}
WHERE {cond}{bmon} GROUP BY mth_id ORDER BY mth_id
""", row_limit=40)["rows"]
        net_by_month = {r["mth_id"]: r for r in rows5}
    except Exception:
        net_by_month = {}

    def _derived_net(row):
        d = {c: _f(row, c) or 0 for c in _5G_COLS}
        d["dev5g_pct"] = (d["dev5g_total"] / d["dev_all"] * 100) if d["dev_all"] else None
        d["dev5g_traffic_pct"] = (d["dev5g_with_traffic"] / d["dev5g_total"] * 100) if d["dev5g_total"] else None
        return d

    nmonths = sorted(net_by_month.keys())
    net_mtd_m = nmonths[-1] if nmonths else None
    net_lmtd_m = nmonths[-2] if len(nmonths) >= 2 else None
    network = {
        "mtd": _derived_net(net_by_month.get(net_mtd_m, {})) if net_mtd_m else None,
        "lmtd": _derived_net(net_by_month.get(net_lmtd_m, {})) if net_lmtd_m else None,
        "history": [{"month_id": m, **_derived_net(net_by_month[m])}
                    for m in nmonths[-(int(months) + 1):]],
    }

    # ── Availability (2G/4G/5G %) ──
    av_cols = ["avg_avail_pct_2g", "avg_avail_pct_4g", "avg_avail_pct_5g",
               "days_down_2g", "days_down_4g", "days_down_5g"]
    av_sel = ", ".join(
        (f"AVG({c}) AS {c}" if c.startswith("avg_") else f"SUM({c}) AS {c}") for c in av_cols)
    av_by_month = {}
    try:
        rowsa = run_query(f"""
SELECT month_id, {av_sel} FROM {_AVAIL}
WHERE {cond}{bmon} GROUP BY month_id ORDER BY month_id
""", row_limit=40)["rows"]
        av_by_month = {str(r["month_id"]): r for r in rowsa}
    except Exception:
        av_by_month = {}
    amonths = sorted(av_by_month.keys())
    av_mtd_m = amonths[-1] if amonths else None
    av_lmtd_m = amonths[-2] if len(amonths) >= 2 else None
    def _av(row):
        return {c: _f(row, c) for c in av_cols}
    availability = {
        "mtd": _av(av_by_month.get(av_mtd_m, {})) if av_mtd_m else None,
        "lmtd": _av(av_by_month.get(av_lmtd_m, {})) if av_lmtd_m else None,
        "history": [{"month_id": m, **_av(av_by_month[m])} for m in amonths[-int(months):]],
    }

    # ── FWA (daily → monthly aggregate) ──
    _FWA_COLS = ["rev_fwa_total", "rev_fwa_pack", "rev_fwa_sim", "rev_fwa_regular",
                 "rev_fwa_non_broadband", "fwa_rgu90", "fwa_rgu_ga", "fwa_grosschurn90",
                 "fwa_churnback90", "fwa_net_add_90_closing", "fwa_pack_hits",
                 "vlr_fwa_less_90d", "vlr_fwa_91_180d", "vlr_fwa_above_181d"]
    fwa_sel = ", ".join(f"COALESCE(SUM({c}),0) AS {c}" for c in _FWA_COLS)
    fwa_by_month = {}
    try:
        rowsf = run_query(f"""
SELECT FORMAT_DATE('%Y%m', dt_id) AS month_id, {fwa_sel} FROM {_FWA}
WHERE {cond}{bmon} GROUP BY month_id ORDER BY month_id
""", row_limit=40)["rows"]
        fwa_by_month = {r["month_id"]: r for r in rowsf}
    except Exception:
        fwa_by_month = {}
    fmonths = sorted(fwa_by_month.keys())
    fwa_mtd_m = fmonths[-1] if fmonths else None
    fwa_lmtd_m = fmonths[-2] if len(fmonths) >= 2 else None
    def _fwa(row):
        return {c: _f(row, c) or 0 for c in _FWA_COLS}
    fwa = {
        "mtd": _fwa(fwa_by_month.get(fwa_mtd_m, {})) if fwa_mtd_m else None,
        "lmtd": _fwa(fwa_by_month.get(fwa_lmtd_m, {})) if fwa_lmtd_m else None,
        "history": [{"month_id": m, **_fwa(fwa_by_month[m])} for m in fmonths[-(int(months) + 1):]],
    }

    return {
        "attributes": a,
        "brand": brand,
        "month_id": cur_month,
        "metrics": metrics,
        "network": network,
        "availability": availability,
        "fwa": fwa,
        "performance": perf,
        "funnel": {"m1s": _f(pf, "ga_m1s_mtd"), "m2s": _f(pf, "ga_m2s_mtd"),
                   "p1m": _f(pf, "ga_p1m_mtd"), "p2m": _f(pf, "ga_p2m_mtd"),
                   "gross_add": _f(pf, "subs_gross_add_mtd")},
        "ga_channels": ga_rows,
        "history": history,
        "channels": [{"channel": r.get("channel_group"), "detail": r.get("channel_detail"),
                      "revenue": _f(r, "revenue") or 0} for r in channels],
        "channel_metrics": ch_metrics,
        "channel_history": channel_history,
        "price_slabs": price_slabs,
        "quota_slabs": quota_slabs,
        "validity_slabs": validity_slabs,
        "top_products": [{"product": r.get("product_group"), "family": r.get("family_group"),
                          "revenue": _f(r, "revenue") or 0, "hit": _f(r, "hit") or 0} for r in top_products],
    }
