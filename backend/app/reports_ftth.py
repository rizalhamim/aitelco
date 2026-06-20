"""FTTH Performance Report.
Follows the FTTH KNOWLEDGE BASE for extracting FTTH Sales Funnel & Take-Up Rate.
Returns a payload compatible with ComprehensiveView (MTD/LMTD/Growth + YTD/YoY)
plus FTTH-specific sections (counts, footprint, manpower, SM->TL->AE hierarchy).

FTTH has its OWN territory vocabulary (sales_region / region_25 codes like
'04. Central Java', plus province / city / kecamatan). It does NOT align with the
IM3 rham_ref_territory hierarchy, and the shp_kabkota / shp_kecamatan columns are
NULL in the data, so filtering is done directly on FTTH-native columns.
"""
from __future__ import annotations
from typing import Optional
from . import config
from .bigquery_tool import run_query
import datetime

_P = config.BQ_PROJECT
_D = config.BQ_DATASET

_SO = f"`{_P}.{_D}.rham_ftth_so_detail`"
_SA = f"`{_P}.{_D}.rham_ftth_sa_detail`"
_PA = f"`{_P}.{_D}.rham_ftth_pa_detail`"
_SITEWISE = f"`{_P}.{_D}.rham_ftth_sitewise_monthly`"


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


def _circle_provinces(circle: str) -> list[str]:
    c = (circle or "").upper()
    if c == "JAVA":
        return ["JAWA TENGAH", "JAWA TIMUR", "DAERAH ISTIMEWA YOGYAKARTA", "BALI", "YOGYAKARTA"]
    elif c == "JAYA" or c == "JAKARTA RAYA":
        return ["JAWA BARAT", "DKI JAKARTA", "BANTEN"]
    elif c == "SUMATERA":
        return ["ACEH", "BENGKULU", "JAMBI", "LAMPUNG", "RIAU", "KEPULAUAN RIAU",
                "KEPULAUAN BANGKA BELITUNG", "SUMATERA SELATAN", "SUMATERA UTARA", "SUMATERA BARAT"]
    return []


# FTTH-native scope columns. The detail tables have no kecamatan column, so a
# kecamatan selection cannot scope the funnel sections; it falls back to the
# parent kab/kota (city). Old IM3 level names that may arrive from My Coordinate
# (region/area/branch/microcluster) have no FTTH equivalent and are ignored
# (circle scope) rather than returning an empty report.
_DETAIL_COL = {
    "ftth_region": "sales_region",
    "ftth_province": "province",
    "ftth_kabkota": "city",
    "kabkota": "city",
}
_SITEWISE_COL = {
    "ftth_region": "region_25",
    "ftth_province": "provinsi",
    "ftth_kabkota": "city",
    "ftth_kecamatan": "kecamatan",
    "kabkota": "city",
    "kecamatan": "kecamatan",
}


def _norm_kec(filter_type: str, filter_value: str) -> str:
    """My Coordinate passes a kec_id like 'ADIWERNA|BADUNG' for kecamatan, but the
    FTTH tables store the bare kecamatan name. Strip the '|kabkota' suffix."""
    if filter_type in ("kecamatan", "ftth_kecamatan") and "|" in (filter_value or ""):
        return filter_value.split("|")[0].strip()
    return filter_value


def _detail_scope_clause(filter_type: str, filter_value: str, alias: str = "f") -> str:
    if not filter_value or not filter_type or filter_type == "all":
        return ""
    col = _DETAIL_COL.get(filter_type)
    val = _norm_kec(filter_type, filter_value)
    return f" AND UPPER({alias}.{col}) = UPPER('{_esc(val)}')" if col else ""


def _sitewise_scope_clause(filter_type: str, filter_value: str, alias: str = "f") -> str:
    if not filter_value or not filter_type or filter_type == "all":
        return ""
    col = _SITEWISE_COL.get(filter_type)
    val = _norm_kec(filter_type, filter_value)
    return f" AND UPPER({alias}.{col}) = UPPER('{_esc(val)}')" if col else ""


def _build_funnel_sql(table: str, date_col: str, cur_dt: str, lmtd_dt: str, llmtd_dt: str,
                      cur_start: str, lmtd_start: str, llmtd_start: str, cutoff_day: int, circle: str,
                      filter_type: str, filter_value: str) -> dict:
    provs = _circle_provinces(circle)
    prov_filter = "1=1" if circle.upper() == "ALL" else ("UPPER(f.province) IN (" + ",".join(f"'{p}'" for p in provs) + ")")
    scope = _detail_scope_clause(filter_type, filter_value)

    sql = f"""
SELECT
  COUNTIF({date_col} >= '{cur_start}' AND {date_col} <= '{cur_dt}') as cnt_mtd,
  SUM(IF({date_col} >= '{cur_start}' AND {date_col} <= '{cur_dt}', price, 0)) as rev_mtd,

  COUNTIF({date_col} >= '{lmtd_start}' AND {date_col} <= '{lmtd_dt}' AND EXTRACT(DAY FROM {date_col}) <= {cutoff_day}) as cnt_lmtd,
  SUM(IF({date_col} >= '{lmtd_start}' AND {date_col} <= '{lmtd_dt}' AND EXTRACT(DAY FROM {date_col}) <= {cutoff_day}, price, 0)) as rev_lmtd,

  COUNTIF({date_col} >= '{llmtd_start}' AND {date_col} <= '{llmtd_dt}' AND EXTRACT(DAY FROM {date_col}) <= {cutoff_day}) as cnt_llmtd,
  SUM(IF({date_col} >= '{llmtd_start}' AND {date_col} <= '{llmtd_dt}' AND EXTRACT(DAY FROM {date_col}) <= {cutoff_day}, price, 0)) as rev_llmtd,

  COUNTIF({date_col} >= '{cur_start[:4]}-01-01' AND {date_col} <= '{cur_dt}') as cnt_ytd,
  SUM(IF({date_col} >= '{cur_start[:4]}-01-01' AND {date_col} <= '{cur_dt}', price, 0)) as rev_ytd,

  COUNTIF({date_col} >= DATE_SUB(DATE '{cur_start[:4]}-01-01', INTERVAL 1 YEAR) AND {date_col} <= DATE_SUB(DATE '{cur_dt}', INTERVAL 1 YEAR)) as cnt_lytd,
  SUM(IF({date_col} >= DATE_SUB(DATE '{cur_start[:4]}-01-01', INTERVAL 1 YEAR) AND {date_col} <= DATE_SUB(DATE '{cur_dt}', INTERVAL 1 YEAR), price, 0)) as rev_lytd

FROM {table} f
WHERE {prov_filter} {scope}
"""
    try:
        return run_query(sql)["rows"][0]
    except Exception:
        return {"cnt_mtd": 0, "rev_mtd": 0, "cnt_lmtd": 0, "rev_lmtd": 0, "cnt_llmtd": 0,
                "rev_llmtd": 0, "cnt_ytd": 0, "rev_ytd": 0, "cnt_lytd": 0, "rev_lytd": 0}


def build_ftth(circle: str, filter_type: str = "all", filter_value: str = "", month_id: Optional[int] = None) -> dict:
    try:
        if month_id:
            year, mo = str(month_id)[:4], str(month_id)[4:6]
            import calendar
            last_day = datetime.date(int(year), int(mo), calendar.monthrange(int(year), int(mo))[1])
            max_dt = last_day.strftime("%Y-%m-%d")
        else:
            mx_res = run_query(f"SELECT MAX(date_so) as m FROM {_SO}")
            max_dt = mx_res["rows"][0]["m"]
            if "T" in max_dt:
                max_dt = max_dt.split("T")[0]

        dt = datetime.datetime.strptime(max_dt, "%Y-%m-%d").date()
        cutoff_day = dt.day

        cur_start = dt.replace(day=1).strftime("%Y-%m-%d")
        dt_lmtd = dt.replace(day=1) - datetime.timedelta(days=1)
        lmtd_dt = dt_lmtd.strftime("%Y-%m-%d")
        lmtd_start = dt_lmtd.replace(day=1).strftime("%Y-%m-%d")

        dt_llmtd = dt_lmtd.replace(day=1) - datetime.timedelta(days=1)
        llmtd_dt = dt_llmtd.strftime("%Y-%m-%d")
        llmtd_start = dt_llmtd.replace(day=1).strftime("%Y-%m-%d")

    except Exception as e:
        return {"error": f"Failed to determine max date for FTTH: {str(e)}"}

    so_data = _build_funnel_sql(_SO, "date_so", max_dt, lmtd_dt, llmtd_dt, cur_start, lmtd_start, llmtd_start, cutoff_day, circle, filter_type, filter_value)
    sa_data = _build_funnel_sql(_SA, "date_sa", max_dt, lmtd_dt, llmtd_dt, cur_start, lmtd_start, llmtd_start, cutoff_day, circle, filter_type, filter_value)
    pa_data = _build_funnel_sql(_PA, "date_pa", max_dt, lmtd_dt, llmtd_dt, cur_start, lmtd_start, llmtd_start, cutoff_day, circle, filter_type, filter_value)

    cur_mth = dt.strftime("%Y%m")
    lmtd_mth = datetime.datetime.strptime(lmtd_dt, "%Y-%m-%d").strftime("%Y%m")
    llmtd_mth = datetime.datetime.strptime(llmtd_dt, "%Y-%m-%d").strftime("%Y%m")

    sw_provs = _circle_provinces(circle)
    sw_prov_filter = "1=1" if circle.upper() == "ALL" else ("UPPER(f.provinsi) IN (" + ",".join(f"'{p}'" for p in sw_provs) + ")")
    sw_scope = _sitewise_scope_clause(filter_type, filter_value)
    det_scope = _detail_scope_clause(filter_type, filter_value)
    det_prov_filter = "1=1" if circle.upper() == "ALL" else ("UPPER(f.province) IN (" + ",".join(f"'{p}'" for p in sw_provs) + ")")

    # ── Sitewise: infrastructure + coverage counts (current/prev/prev2 months) ──
    sw_sql = f"""
SELECT
  f.month_id,
  SUM(f.homepass) as hp,
  SUM(f.pa) as pa_cum,
  SUM(f.pa_net_latest) as net_add,
  SUM(f.ga) as ga,
  SUM(f.available_hp) as avail_hp,
  COUNT(DISTINCT IF(f.homepass > 0, f.kecamatan, NULL)) as kec_with_hp,
  COUNT(DISTINCT IF(f.homepass > 0, f.city, NULL)) as kabkot_with_hp,
  COUNT(DISTINCT IF(f.homepass > 0 AND SAFE_DIVIDE(f.pa, f.homepass) < 0.2, f.site_id, NULL)) as low_tur_sites
FROM {_SITEWISE} f
WHERE {sw_prov_filter} {sw_scope}
  AND f.month_id IN ('{cur_mth}', '{lmtd_mth}', '{llmtd_mth}')
GROUP BY f.month_id
"""
    try:
        sw_rows = run_query(sw_sql)["rows"]
    except Exception:
        sw_rows = []

    sw_map = {str(r["month_id"]): r for r in sw_rows}

    def get_sw(mth, col):
        return float(sw_map.get(mth, {}).get(col, 0) or 0)

    # ── Man power productivity (AE = sales_code) ──
    mp_sql = f"""
SELECT
  COUNT(DISTINCT f.sales_code) as ae_so,
  COUNT(DISTINCT IF(sa.bill_acc IS NOT NULL, f.sales_code, NULL)) as ae_sa,
  COUNT(DISTINCT IF(pa.bill_acc IS NOT NULL, f.sales_code, NULL)) as ae_pa
FROM {_SO} f
LEFT JOIN {_SA} sa ON f.bill_acc = sa.bill_acc AND sa.date_sa >= '{cur_start}' AND sa.date_sa <= '{max_dt}'
LEFT JOIN {_PA} pa ON f.bill_acc = pa.bill_acc AND pa.date_pa >= '{cur_start}' AND pa.date_pa <= '{max_dt}'
WHERE {det_prov_filter} {det_scope}
  AND f.date_so >= '{cur_start}' AND f.date_so <= '{max_dt}'
  AND f.sales_code IS NOT NULL AND f.sales_code != ''
"""
    try:
        mp_data = run_query(mp_sql)["rows"][0]
    except Exception:
        mp_data = {"ae_so": 0, "ae_sa": 0, "ae_pa": 0}

    ae_5pa_sql = f"""
WITH ae_pa_cnt AS (
    SELECT f.sales_code, COUNT(pa.bill_acc) as pa_cnt
    FROM {_SO} f
    JOIN {_PA} pa ON f.bill_acc = pa.bill_acc AND pa.date_pa >= '{cur_start}' AND pa.date_pa <= '{max_dt}'
    WHERE {det_prov_filter} {det_scope}
      AND f.sales_code IS NOT NULL AND f.sales_code != ''
    GROUP BY f.sales_code
)
SELECT COUNT(*) as c FROM ae_pa_cnt WHERE pa_cnt >= 5
"""
    try:
        ae_5pa = run_query(ae_5pa_sql)["rows"][0]["c"]
    except Exception:
        ae_5pa = 0

    # ── SM -> TL -> AE nested hierarchy (SO/SA/PA MTD, sorted MTD desc) ──
    hier_sql = f"""
SELECT
  f.sales_manager as sm,
  f.sales_tl as tl,
  f.sales_code as ae,
  ANY_VALUE(f.sales_name) as ae_name,
  COUNT(f.bill_acc) as so_mtd,
  COUNT(sa.bill_acc) as sa_mtd,
  COUNT(pa.bill_acc) as pa_mtd
FROM {_SO} f
LEFT JOIN {_SA} sa ON f.bill_acc = sa.bill_acc AND sa.date_sa >= '{cur_start}' AND sa.date_sa <= '{max_dt}'
LEFT JOIN {_PA} pa ON f.bill_acc = pa.bill_acc AND pa.date_pa >= '{cur_start}' AND pa.date_pa <= '{max_dt}'
WHERE {det_prov_filter} {det_scope}
  AND f.date_so >= '{cur_start}' AND f.date_so <= '{max_dt}'
GROUP BY sm, tl, ae
"""
    try:
        hier_rows = run_query(hier_sql, row_limit=100000)["rows"]
    except Exception:
        hier_rows = []

    sm_tree = _build_hierarchy(hier_rows)

    # ── Product mix (SO MTD) ──
    pmix_sql = f"""
SELECT
  CASE WHEN REGEXP_CONTAINS(f.product, r'^(AP|Super ?)[0-9]+') THEN 'Advance Payment' ELSE 'Regular' END as p_mix,
  COUNT(f.bill_acc) as so_mtd
FROM {_SO} f
WHERE {det_prov_filter} {det_scope}
  AND f.date_so >= '{cur_start}' AND f.date_so <= '{max_dt}'
GROUP BY p_mix
ORDER BY so_mtd DESC
"""
    try:
        pmix = run_query(pmix_sql)["rows"]
    except Exception:
        pmix = []

    # ── Footprint by project (homepass + subs, current month) ──
    fp_sql = f"""
SELECT
  CASE
    WHEN LOWER(f.project_awal) LIKE '%mplay%' THEN 'ORBIT'
    WHEN LOWER(f.project_awal) LIKE '%seahawk%' OR LOWER(f.project_awal) LIKE '%spartan%' THEN 'NON-ORBIT'
    WHEN LOWER(f.project_awal) LIKE '%iforte%' OR LOWER(f.project_awal) LIKE '%i-forte%' OR LOWER(f.project_awal) LIKE '%i_forte%' THEN 'IFORTE'
    ELSE 'OTHER'
  END as project,
  SUM(f.homepass) as hp,
  SUM(f.pa) as pa_cum
FROM {_SITEWISE} f
WHERE {sw_prov_filter} {sw_scope}
  AND f.month_id = '{cur_mth}'
GROUP BY project
ORDER BY hp DESC
"""
    try:
        fp_rows = run_query(fp_sql)["rows"]
    except Exception:
        fp_rows = []

    # ── metric helpers ──
    def create_metric(code, name, unit, mtd_val, lmtd_val, llmtd_val, ytd_val=None, lytd_val=None):
        def safe_growth(cur, prev):
            if cur is None or prev is None or prev == 0:
                return None
            return (cur - prev) / abs(prev) * 100

        m = {
            "code": code, "name": name, "unit": unit,
            "network": False, "snapshot": False, "computed": False,
            "ioh": {
                "mtd": mtd_val, "lmtd": lmtd_val, "llmtd": llmtd_val,
                "var_mom": (mtd_val - lmtd_val) if (mtd_val is not None and lmtd_val is not None) else None,
                "growth_mom_pct": safe_growth(mtd_val, lmtd_val),
                "ytd": ytd_val, "lytd": lytd_val,
                "var_yoy": (ytd_val - lytd_val) if (ytd_val is not None and lytd_val is not None) else None,
                "growth_yoy_pct": safe_growth(ytd_val, lytd_val),
            },
        }
        m["im3"] = {k: None for k in m["ioh"]}
        m["3id"] = {k: None for k in m["ioh"]}
        return m

    def calc_ratio(n_mtd, d_mtd, n_lmtd, d_lmtd, n_llmtd, d_llmtd):
        return (
            (n_mtd / d_mtd * 100) if d_mtd else None,
            (n_lmtd / d_lmtd * 100) if d_lmtd else None,
            (n_llmtd / d_llmtd * 100) if d_llmtd else None,
        )

    sections = []

    # ── 1. FTTH Infrastructure & Utilization (TOP) ──
    hp_mtd = get_sw(cur_mth, "hp"); hp_lmtd = get_sw(lmtd_mth, "hp"); hp_llmtd = get_sw(llmtd_mth, "hp")
    pa_cum_mtd = get_sw(cur_mth, "pa_cum"); pa_cum_lmtd = get_sw(lmtd_mth, "pa_cum"); pa_cum_llmtd = get_sw(llmtd_mth, "pa_cum")
    avail_mtd = get_sw(cur_mth, "avail_hp"); avail_lmtd = get_sw(lmtd_mth, "avail_hp"); avail_llmtd = get_sw(llmtd_mth, "avail_hp")
    ga_sw_mtd = get_sw(cur_mth, "ga"); ga_sw_lmtd = get_sw(lmtd_mth, "ga"); ga_sw_llmtd = get_sw(llmtd_mth, "ga")

    tur_mtd, tur_lmtd, tur_llmtd = calc_ratio(pa_cum_mtd, hp_mtd, pa_cum_lmtd, hp_lmtd, pa_cum_llmtd, hp_llmtd)
    ext_mtd, ext_lmtd, ext_llmtd = calc_ratio(ga_sw_mtd, avail_mtd, ga_sw_lmtd, avail_lmtd, ga_sw_llmtd, avail_llmtd)

    infra = {
        "title": "FTTH Infrastructure & Utilization",
        "layout": "grid",
        "cumulative_yoy": True,
        "metrics": [
            create_metric("ftth_hp", "Total Homepass", "Homes", hp_mtd, hp_lmtd, hp_llmtd, hp_mtd, None),
            create_metric("ftth_avail", "Available Homepass", "Homes", avail_mtd, avail_lmtd, avail_llmtd, avail_mtd, None),
            create_metric("ftth_pa_cum", "Total Active Subs", "Subs", pa_cum_mtd, pa_cum_lmtd, pa_cum_llmtd, pa_cum_mtd, None),
            create_metric("ftth_netadd", "Net Add", "Subs", get_sw(cur_mth, "net_add"), get_sw(lmtd_mth, "net_add"), get_sw(llmtd_mth, "net_add"), get_sw(cur_mth, "net_add"), None),
            create_metric("ftth_ga", "Gross Add (Site)", "Subs", ga_sw_mtd, ga_sw_lmtd, ga_sw_llmtd, ga_sw_mtd, None),
            create_metric("ftth_tur", "Take-Up Rate (TUR)", "%", tur_mtd, tur_lmtd, tur_llmtd, tur_mtd, None),
            create_metric("ftth_ext", "Extraction Rate", "%", ext_mtd, ext_lmtd, ext_llmtd, ext_mtd, None),
        ],
    }
    for i in range(0, 5):
        infra["metrics"][i]["snapshot"] = True
    for i in range(5, 7):
        infra["metrics"][i]["computed"] = True
    sections.append(infra)

    # ── 2. Infrastructure Coverage (counts) ──
    sections.append({
        "title": "Infrastructure Coverage",
        "layout": "ftth_counts",
        "columns": ["Count"],
        "rows": [
            {"label": "Kecamatan with Homepass", "cells": [get_sw(cur_mth, "kec_with_hp")]},
            {"label": "Kab/Kota with Homepass", "cells": [get_sw(cur_mth, "kabkot_with_hp")]},
            {"label": "Low TUR Sites (< 20%)", "cells": [get_sw(cur_mth, "low_tur_sites")]},
        ],
    })

    # ── 3. Footprint by Project ──
    if fp_rows:
        sections.append({
            "title": "Footprint by Project",
            "layout": "ftth_counts",
            "columns": ["Homepass", "Active Subs"],
            "rows": [{"label": x["project"], "cells": [x["hp"] or 0, x["pa_cum"] or 0]} for x in fp_rows],
        })

    # ── 4. Sales Funnel (Indosat HiFi) ──
    so_sa_mtd, so_sa_lmtd, so_sa_llmtd = calc_ratio(sa_data["cnt_mtd"], so_data["cnt_mtd"], sa_data["cnt_lmtd"], so_data["cnt_lmtd"], sa_data["cnt_llmtd"], so_data["cnt_llmtd"])
    sa_pa_mtd, sa_pa_lmtd, sa_pa_llmtd = calc_ratio(pa_data["cnt_mtd"], sa_data["cnt_mtd"], pa_data["cnt_lmtd"], sa_data["cnt_lmtd"], pa_data["cnt_llmtd"], sa_data["cnt_llmtd"])
    so_pa_mtd, so_pa_lmtd, so_pa_llmtd = calc_ratio(pa_data["cnt_mtd"], so_data["cnt_mtd"], pa_data["cnt_lmtd"], so_data["cnt_lmtd"], pa_data["cnt_llmtd"], so_data["cnt_llmtd"])

    rev_per_pa_mtd = (pa_data["rev_mtd"] / pa_data["cnt_mtd"]) if pa_data["cnt_mtd"] else None
    rev_per_pa_lmtd = (pa_data["rev_lmtd"] / pa_data["cnt_lmtd"]) if pa_data["cnt_lmtd"] else None
    rev_per_pa_llmtd = (pa_data["rev_llmtd"] / pa_data["cnt_llmtd"]) if pa_data["cnt_llmtd"] else None

    funnel = {
        "title": "Sales Funnel (Indosat HiFi)",
        "group": "FTTH Performance",
        "layout": "grid",
        "cumulative_yoy": True,
        "metrics": [
            create_metric("ftth_so", "Service Order (SO)", "Orders", so_data["cnt_mtd"], so_data["cnt_lmtd"], so_data["cnt_llmtd"], so_data["cnt_ytd"], so_data["cnt_lytd"]),
            create_metric("ftth_sa", "Service Active (SA)", "Orders", sa_data["cnt_mtd"], sa_data["cnt_lmtd"], sa_data["cnt_llmtd"], sa_data["cnt_ytd"], sa_data["cnt_lytd"]),
            create_metric("ftth_pa", "Permanent Active (PA)", "Orders", pa_data["cnt_mtd"], pa_data["cnt_lmtd"], pa_data["cnt_llmtd"], pa_data["cnt_ytd"], pa_data["cnt_lytd"]),
            create_metric("ftth_rev", "PA Revenue", "IDR", pa_data["rev_mtd"], pa_data["rev_lmtd"], pa_data["rev_llmtd"], pa_data["rev_ytd"], pa_data["rev_lytd"]),
            create_metric("ftth_avg_rev", "Avg Rev per PA", "IDR", rev_per_pa_mtd, rev_per_pa_lmtd, rev_per_pa_llmtd, rev_per_pa_mtd, rev_per_pa_lmtd),
            create_metric("ftth_conv_sosa", "Conversion SO to SA", "%", so_sa_mtd, so_sa_lmtd, so_sa_llmtd),
            create_metric("ftth_conv_sapa", "Conversion SA to PA", "%", sa_pa_mtd, sa_pa_lmtd, sa_pa_llmtd),
            create_metric("ftth_conv_sopa", "Conversion SO to PA", "%", so_pa_mtd, so_pa_lmtd, so_pa_llmtd),
        ],
    }
    funnel["metrics"][4]["computed"] = True
    for i in range(5, 8):
        funnel["metrics"][i]["computed"] = True
    sections.append(funnel)

    # ── 5. Product Mix ──
    if pmix:
        sections.append({
            "title": "Product Mix (SO MTD)",
            "layout": "ftth_counts",
            "group": "FTTH Performance",
            "columns": ["Orders"],
            "rows": [{"label": x["p_mix"], "cells": [x["so_mtd"]]} for x in pmix],
        })

    # ── 6. Man Power Productivity ──
    sections.append({
        "title": "Man Power Productivity",
        "layout": "ftth_counts",
        "group": "FTTH Performance",
        "columns": ["AE"],
        "rows": [
            {"label": "AE Generated SO", "cells": [mp_data.get("ae_so", 0)]},
            {"label": "AE Generated SA", "cells": [mp_data.get("ae_sa", 0)]},
            {"label": "AE Generated PA", "cells": [mp_data.get("ae_pa", 0)]},
            {"label": "AE Hit >= 5 PA", "cells": [ae_5pa]},
        ],
    })

    # ── 7. SM -> TL -> AE hierarchy (drilldown) ──
    if sm_tree:
        sections.append({
            "title": "Sales Hierarchy (SM to TL to AE)",
            "layout": "hierarchy",
            "group": "FTTH Performance",
            "columns": ["SO", "SA", "PA"],
            "rows": sm_tree,
        })

    return {
        "scope": {"circle": circle, "filter_type": filter_type, "filter_value": filter_value,
                  "data_as_of": max_dt, "month_id": cur_mth},
        "sections": sections,
    }


def _clean(v: str) -> str:
    s = (v or "").strip()
    low = s.lower()
    if not s or low in ("null", "unknown", "n/a", "-", "unidentified", "unknown sales", "unknonwn sales"):
        return ""
    return s


def _build_hierarchy(rows: list[dict], top_sm: int = 20, top_tl: int = 20, top_ae: int = 50) -> list[dict]:
    """Assemble flat (sm, tl, ae) rows into a nested SM -> TL -> AE tree, each
    level sorted by SO MTD desc and capped to keep the payload bounded."""
    sm_map: dict[str, dict] = {}
    for r in rows:
        sm = _clean(r.get("sm")) or "Unidentified"
        tl = _clean(r.get("tl")) or "Unidentified"
        ae = _clean(r.get("ae")) or "Unidentified"
        ae_name = _clean(r.get("ae_name"))
        so = int(r.get("so_mtd") or 0)
        sa = int(r.get("sa_mtd") or 0)
        pa = int(r.get("pa_mtd") or 0)

        smn = sm_map.setdefault(sm, {"label": sm, "cells": [0, 0, 0], "_tl": {}})
        smn["cells"][0] += so; smn["cells"][1] += sa; smn["cells"][2] += pa
        tln = smn["_tl"].setdefault(tl, {"label": tl, "cells": [0, 0, 0], "_ae": {}})
        tln["cells"][0] += so; tln["cells"][1] += sa; tln["cells"][2] += pa
        aelabel = f"{ae} - {ae_name}" if ae_name and ae_name != ae else ae
        aen = tln["_ae"].setdefault(ae, {"label": aelabel, "cells": [0, 0, 0]})
        aen["cells"][0] += so; aen["cells"][1] += sa; aen["cells"][2] += pa

    def srt(nodes):
        return sorted(nodes, key=lambda n: n["cells"][0], reverse=True)

    out = []
    for sm in srt(sm_map.values())[:top_sm]:
        tls = []
        for tl in srt(sm.pop("_tl").values())[:top_tl]:
            aes = srt(tl.pop("_ae").values())[:top_ae]
            tl["children"] = aes
            tls.append(tl)
        sm["children"] = tls
        out.append(sm)
    return out
