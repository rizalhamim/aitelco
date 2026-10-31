"""Site Performance: per-site profile + monthly history + channel/subs/usage/
top-products/price-slab/quota-validity slab/funnel - for the Site Performance menu.

Data sources (site KPI keyed by site_id, commercial detail by kec_id):
  rham_site_wise_addr_java     - site attributes (lat/long, type, branch, ...)
  rham_site_wise_monthly       - monthly performance (revenue/subs/usage/churn/HVC)
  rham_kec_data_rev_product_mtd / _channel_mtd / _price_slab_mtd - data revenue detail
"""
from __future__ import annotations

from . import config
from .bigquery_tool import run_query
from .geo_locate import _haversine_sql
from .reports_data import (PRICE_SLAB_ORDER, QUOTA_BINS, VALIDITY_BINS,
                           _quota_case, _validity_case)
from .site_fwa import build_site_fwa
from .reports_comprehensive import shift_month_id as _shift_month
from .report_metric_catalog import HVC_UNRELIABLE_NOTE, hvc_unreliable

_P = config.BQ_PROJECT
_D = config.BQ_DATASET
_ADDR = f"`{_P}.{_D}.rham_site_wise_addr_java`"
_MON = f"`{_P}.{_D}.rham_site_wise_monthly`"
_PERF = f"`{_P}.{_D}.rham_site_wise_addr_java_perf`"
_GA = f"`{_P}.{_D}.rham_site_ga_daily`"
_PRODUCT = f"`{_P}.{_D}.rham_kec_data_rev_product_mtd`"
_CHANNEL = f"`{_P}.{_D}.rham_kec_data_rev_channel_mtd`"
_CHANNEL_MTH = f"`{_P}.{_D}.rham_kec_data_rev_channel_mth`"
_5G = f"`{_P}.{_D}.rham_5g_site_monthly`"
_AVAIL = f"`{_P}.{_D}.rham_avail_stat_site_monthly`"
_FWA = f"`{_P}.{_D}.rham_fwa_site_wise_daily`"
_SLAB = f"`{_P}.{_D}.rham_kec_data_rev_price_slab_mtd`"


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
_HVC_KEYS = ("subs_hvc", "subs_hvc_stay", "subs_hvc_in", "subs_hvc_out")


def _hvc_clean(row: dict, month_id) -> bool:
    """Blank site HVC that the source never populated (subs_hvc 0 for the whole
    site month) or whose flow is broken from 202609. Returns True when blanked."""
    blanked = False
    unpopulated = not row.get("subs_hvc")
    for k in _HVC_KEYS:
        if k in row and (unpopulated or hvc_unreliable(k, month_id)):
            row[k] = None
            blanked = True
    return blanked


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
       circle, region, branch AS area, branch, micro_cluster AS district, micro_cluster,
       kecamatan_unik AS kec_id, kecamatan, kabupaten, provinsi,
       site_type, category, addressable, profitability_status_m1,
       rgs_category, traffic_category, project_new_site, date_on_air_new_site
FROM {_ADDR} WHERE month_id=(SELECT MAX(month_id) FROM {_ADDR}) AND {cond} LIMIT 1
""", row_limit=2)
    if not attr["rows"]:
        return {"error": "Site tidak ditemukan", "kind": "not_found"}
    a = attr["rows"][0]
    detail_cond = f"kec_id = '{_esc(a.get('kec_id') or '')}'"

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
    hvc_na = False
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
            hrow = {hk: _f(hvc[0], hk) for hk in _HVC_KEYS}
            hvc_na = _hvc_clean(hrow, cur_month)
            for hk in _HVC_KEYS:
                perf[hk] = hrow[hk]
                metrics.append({"code": hk, "lmtd": None, "mtd": hrow[hk], "growth": None})

    # 3. Full-month history (closed months) from monthly table. The current MTD
    #    month is partial, so the Monthly view shows the `months` FULL closed
    #    months BEFORE it (e.g. MTD=202606 → 202605..202512).
    sums = ",\n  ".join(f"SUM({m}) AS {m}" for m in _MON_METRICS)
    mtd_i = int(cur_month) if cur_month else None
    history_months = ",".join(f"'{_shift_month(mtd_i, -i)}'" for i in range(1, int(months) + 1)) if mtd_i else "''"
    hist_sql = f"""
SELECT month_id, {sums}
FROM {_MON}
WHERE {cond}{bmon}
  AND month_id IN ({history_months})
GROUP BY month_id ORDER BY month_id
""" if mtd_i else None
    history = []
    if hist_sql:
        for r in run_query(hist_sql, row_limit=int(months) + 5)["rows"]:
            row = {k: (_f(r, k) if k != "month_id" else r.get("month_id")) for k in (["month_id"] + _MON_METRICS)}
            hvc_na = _hvc_clean(row, row["month_id"]) or hvc_na
            history.append(row)

    # 4. Acquisition by channel (rham_site_ga_daily, current month, brand-filtered)
    ga_sel = ", ".join(f"SUM({c}) AS {c}" for c, _l in _GA_CHANNELS) + ", SUM(ga_total) AS ga_total"
    yr_mo = str(cur_month)[:6] if cur_month else None
    period_start = f"{yr_mo[:4]}-{yr_mo[4:6]}-01" if yr_mo else None
    next_month = str(_shift_month(int(yr_mo), 1)) if yr_mo else None
    period_end = f"{next_month[:4]}-{next_month[4:6]}-01" if next_month else None
    ga_rows = []
    if yr_mo:
        ga = run_query(f"""
SELECT {ga_sel} FROM {_GA}
WHERE {cond}{bmon} AND dt_id >= DATE '{period_start}' AND dt_id < DATE '{period_end}'
""", row_limit=2)["rows"]
        if ga:
            g = ga[0]
            tot = _f(g, "ga_total") or 0
            for c, lbl in _GA_CHANNELS:
                v = _f(g, c) or 0
                ga_rows.append({"channel": lbl, "ga": v, "pct": (v / tot * 100) if tot else None})
            ga_rows.sort(key=lambda x: x["ga"], reverse=True)

    # 5. data-revenue channel - detail list (current month) + group-level
    #    LMTD/MTD/growth (from _mtd) + 6-month history (from _mth).
    channels = run_query(f"""
SELECT channel_group, channel_detail, COALESCE(SUM(revenue),0) AS revenue
FROM {_CHANNEL}
WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_CHANNEL})
GROUP BY channel_group, channel_detail ORDER BY revenue DESC
""", row_limit=200)["rows"]

    # LMTD / MTD per channel group, using explicit calendar-month literals.
    ch_month = str(run_query(f"SELECT MAX(month_id) AS mx FROM {_CHANNEL}", row_limit=2)["rows"][0]["mx"] or cur_month)
    ch_prev = str(_shift_month(int(ch_month), -1))
    ch_mtd = run_query(f"""
SELECT channel_group,
  SUM(CASE WHEN month_id='{ch_month}' THEN revenue END) AS mtd,
  SUM(CASE WHEN month_id='{ch_prev}' THEN revenue END) AS lmtd
FROM {_CHANNEL}
WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA'
  AND month_id IN ('{ch_month}','{ch_prev}')
GROUP BY channel_group
""", row_limit=20)["rows"]
    ch_metrics = []
    for r in ch_mtd:
        mtd, lmtd = _f(r, "mtd"), _f(r, "lmtd")
        ch_metrics.append({"channel": r.get("channel_group"), "lmtd": lmtd, "mtd": mtd,
                           "growth": ((mtd - lmtd) / abs(lmtd) * 100) if lmtd and mtd is not None else None})
    ch_metrics.sort(key=lambda x: x["mtd"] or 0, reverse=True)

    # Full-month history per channel group - `months` closed months BEFORE the
    # current MTD month (same window as the metric history).
    ch_hist_rows = run_query(f"""
SELECT month_id, channel_group, COALESCE(SUM(revenue),0) AS revenue
FROM {_CHANNEL_MTH}
WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA'
  AND month_id IN ({history_months})
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
WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_SLAB})
GROUP BY price_slab
""", row_limit=50)["rows"]}
    price_slabs = [{"slab": s, "revenue": _f(slab_raw.get(s, {}), "revenue") or 0,
                    "hit": _f(slab_raw.get(s, {}), "hit") or 0} for s in PRICE_SLAB_ORDER]

    qcase, vcase = _quota_case(), _validity_case()
    q_rows = {r["q"]: r for r in run_query(f"""
SELECT {qcase} AS q, COALESCE(SUM(revenue),0) AS revenue
FROM {_PRODUCT} WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_PRODUCT})
GROUP BY q
""", row_limit=50)["rows"]}
    v_rows = {r["v"]: r for r in run_query(f"""
SELECT {vcase} AS v, COALESCE(SUM(revenue),0) AS revenue
FROM {_PRODUCT} WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_PRODUCT})
GROUP BY v
""", row_limit=50)["rows"]}
    quota_slabs = [{"slab": b[0], "revenue": _f(q_rows.get(b[0], {}), "revenue") or 0} for b in QUOTA_BINS]
    validity_slabs = [{"slab": b[0], "revenue": _f(v_rows.get(b[0], {}), "revenue") or 0} for b in VALIDITY_BINS]

    top_products = run_query(f"""
SELECT product_group, family_group,
  COALESCE(SUM(revenue),0) AS revenue, COALESCE(SUM(hit),0) AS hit
FROM {_PRODUCT}
WHERE {detail_cond}{bmon} AND kpi_group='REVENUE DATA' AND month_id=(SELECT MAX(month_id) FROM {_PRODUCT})
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
        net_latest = run_query(f"SELECT MAX(mth_id) AS mx FROM {_5G}", row_limit=2)["rows"][0]["mx"]
        net_months = ",".join(f"'{_shift_month(int(net_latest), -i)}'" for i in range(int(months) + 1))
        rows5 = run_query(f"""
SELECT mth_id, {net_sel} FROM {_5G}
WHERE {cond}{bmon} AND mth_id IN ({net_months}) GROUP BY mth_id ORDER BY mth_id
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
        av_latest = run_query(f"SELECT MAX(month_id) AS mx FROM {_AVAIL}", row_limit=2)["rows"][0]["mx"]
        av_months = ",".join(f"'{_shift_month(int(av_latest), -i)}'" for i in range(int(months) + 1))
        rowsa = run_query(f"""
SELECT month_id, {av_sel} FROM {_AVAIL}
WHERE {cond}{bmon} AND month_id IN ({av_months}) GROUP BY month_id ORDER BY month_id
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

    # Canonical monthly FWA keeps snapshot stocks at one point in time.
    # Never sum daily RGU/VLR snapshots across a month.
    try:
        fwa_summary = build_site_fwa(sid, brand=brand, months=months)
    except Exception as exc:
        fwa_summary = {
            "schema_version": "site-fwa.v1",
            "source": "rham_fwa_site_wise_mtd/mth",
            "available": False,
            "error": str(exc)[:300],
            "categories": [],
            "history": [],
        }

    legacy_fwa = {
        "rev_fwa_total": "fwa_rev_total", "rev_fwa_pack": "fwa_rev_fwa_pack",
        "rev_fwa_sim": "fwa_rev_sim", "rev_fwa_regular": "fwa_rev_regular",
        "fwa_rgu90": "fwa_rgu90", "fwa_grosschurn90": "fwa_gc90",
        "fwa_churnback90": "fwa_cb90", "fwa_net_add_90_closing": "fwa_net_add_subs",
        "vlr_fwa_less_90d": "fwa_vlr_less_90d", "vlr_fwa_91_180d": "fwa_vlr_91d_180d",
        "vlr_fwa_above_181d": "fwa_vlr_above_180d",
    }
    canonical_rows = {r["code"]: r for r in fwa_summary.get("rows", [])}
    fwa = {
        period: {old: canonical_rows.get(new, {}).get(period) for old, new in legacy_fwa.items()}
        if fwa_summary.get("available") else None for period in ("mtd", "lmtd")
    }
    fwa["history"] = [{"month_id": r["month_id"], **{old: r.get(new) for old, new in legacy_fwa.items()}}
                      for r in fwa_summary.get("history", [])]

    return {
        "attributes": a,
        "detail_grain": "kecamatan",
        "detail_scope": a.get("kec_id"),
        "detail_month_id": ch_month,
        "detail_note": "Channel, product and price-slab detail measures the site's Kecamatan, not the individual site.",
        "notes": ([HVC_UNRELIABLE_NOTE + " Site HVC is also N/A for months the site source left unpopulated."]
                  if hvc_na else []),
        "brand": brand,
        "month_id": cur_month,
        "metrics": metrics,
        "network": network,
        "availability": availability,
        "fwa": fwa,
        "fwa_summary": fwa_summary,
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
