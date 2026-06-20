"""Comprehensive Report — multi-metric P&L style daily brief.

Recreates the Comprehensive report (Section 5 of the engineering reference):
~21 sections across logical groups, each with several metrics, rendered as a
brand-banded master table (IOH/IM3/3ID) with MTD/LMTD/LLMTD + Var/Growth%, and
YTD/YoY columns for cumulative metrics.

Approach (mirrors the reference, simplified to be self-contained):
  - SECTIONS list is the single source of truth for content + order.
  - One wide SUM() query per timeframe (MTD/LMTD/LLMTD) over the _mtd table,
    plus YTD-cumulative + LYTD-cumulative over the _mth (closed-month) table for
    sections flagged cumulative_yoy.
  - Brand model: IOH = SUM(all), IM3 = SUM(brand='IM3'), 3ID = SUM(brand='3ID').
  - network_metric: repeat IM3 value across all 3 brand cols (physical sites).
  - Mark2Market sections use a flat layout (Industry/IOH/IM3/3ID/TSEL/XL+SF rows).
"""
from __future__ import annotations

from typing import Optional

from . import config
from .bigquery_tool import run_query

_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET
_MTD = f"`{_PROJECT}.{_DATASET}.rham_mkt_highlevel_mtd`"
_MTH = f"`{_PROJECT}.{_DATASET}.rham_mkt_highlevel_mth`"
_TERR = f"`{_PROJECT}.{_DATASET}.rham_ref_territory`"

# ── SECTIONS catalog ─────────────────────────────────────────────────────────
# metric keys: code, name, unit, expr (default m.{code}); flags:
#   brand_split (default True) — emit IM3/3ID; else IOH only
#   network_metric — repeat IM3 across all brands (sites)
# section keys: title, group (optional), cumulative_yoy (optional), metrics[]
def _m(code, name, unit, expr=None, brand_split=True, network=False, snapshot=False):
    # snapshot=True → point-in-time stock metric (site/RGU/VLR/HVC balance/outlets).
    #   YoY compares MTD this year vs MTD same-month last year (NOT a YTD sum).
    # snapshot=False (default) → flow metric (revenue/GA/usage/churn) → YTD = SUM.
    return {"code": code, "name": name, "unit": unit,
            "expr": expr or f"m.{code}", "brand_split": brand_split,
            "network": network, "snapshot": snapshot}


def _ratio(code, name, num, den, pct=False, unit=None):
    """A derived metric value = num/den (optionally ×100). Computed in Python
    from already-summed base metrics, per brand & per timeframe. `num`/`den` are
    metric codes that must also be present (can be hidden) in the section set."""
    return {"code": code, "name": name, "unit": unit or ("%" if pct else "ratio"),
            "ratio": (num, den), "pct": pct, "snapshot": False, "computed": True}


# biometric across all 9 acquisition channels
_BIO_ALL = ("(m.ga_traditional_biometric + m.ga_dsf_biometric + m.ga_modern_biometric + "
            "m.ga_ola_biometric + m.ga_online_biometric + m.ga_fwa_biometric + "
            "m.ga_gerai_biometric + m.ga_bank_biometric + m.ga_h2h_biometric)")
_BIO_TRADE = "(m.ga_traditional_biometric + m.ga_dsf_biometric)"
_GA_TRADE = "(m.ga_traditional + m.ga_dsf)"
# Gross Add derived from RGU-GA components (per request: gross add dari rgu ga)
_RGU_GA = ("(m.rgu_ga_fwa + m.rgu_ga_digital_nat + m.rgu_ga_others_nat + "
           "m.rgu_ga_trad_dsf_nat + m.rgu_ga_trad_outlet_nat)")

SECTIONS: list[dict] = [
    {"title": "Site", "metrics": [
        _m("total_site", "Total Site", "Sites", network=True, snapshot=True),
        _m("addr_site", "Addressable Site", "Sites", network=True, snapshot=True),
        _m("base_site", "Base Site", "Sites", network=True, snapshot=True),
        _m("new_site", "New Site", "Sites", network=True),
    ]},
    {"title": "Acquisition · Gross Add", "cumulative_yoy": True, "metrics": [
        _m("ga_total", "Gross Add Total", "Subs"),
        _m("ga_rgu_total", "Gross Add (RGU)", "Subs", expr=_RGU_GA),
        _m("ga_trade", "GA Trade", "Subs", expr=_GA_TRADE),
        _m("ga_non_trade", "GA Non-Trade", "Subs", expr=f"(m.ga_total - {_GA_TRADE})"),
        _m("ga_bio_total", "GA Biometric Total", "Subs", expr=_BIO_ALL),
        _m("ga_bio_trade", "GA Biometric Trade", "Subs", expr=_BIO_TRADE),
        _m("ga_bio_nontrade", "GA Biometric Non-Trade", "Subs", expr=f"({_BIO_ALL} - {_BIO_TRADE})"),
        _ratio("ga_bio_pct", "GA Biometric % vs Total GA", "ga_bio_total", "ga_total", pct=True),
        _ratio("ga_bio_trade_pct", "GA Biometric Trade % vs GA Trade", "ga_bio_trade", "ga_trade", pct=True),
        _m("ga_usage_100mb_plus", "GA Usage 100MB+", "Subs"),
        _m("ga_usage_500mb_plus", "GA Usage 500MB+", "Subs"),
        _ratio("ga_usage_100_pct", "GA Usage 100MB+ % vs Total GA", "ga_usage_100mb_plus", "ga_total", pct=True),
        _ratio("ga_usage_500_pct", "GA Usage 500MB+ % vs Total GA", "ga_usage_500mb_plus", "ga_total", pct=True),
    ]},
    {"title": "Churn & Net Add", "metrics": [
        _m("gross_churn_90d", "Gross Churn 90D", "Subs"),
        _m("churn_back_90d", "Churn Back 90D", "Subs"),
        _m("net_churn_90d", "Net Churn 90D", "Subs"),
        _m("net_add_90d", "Net Add 90D", "Subs"),
        _m("net_churn_30d", "Net Churn 30D", "Subs"),
        _m("net_add_30d", "Net Add 30D", "Subs"),
    ]},
    {"title": "Subscriber", "metrics": [
        _m("rgu_90d", "RGU 90D", "Subs", snapshot=True),
        _m("rgu_30d", "RGU 30D", "Subs", snapshot=True),
        _m("avg_vlr_daily", "VLR Daily", "Subs", snapshot=True),
        _m("data_uu_30", "Data Users 30D", "Subs", snapshot=True),
        _m("data_uu_daily", "Data Users Daily", "Subs", snapshot=True),
        _m("pack_subs", "Pack Subs", "Subs", snapshot=True),
        _ratio("pack_vs_vlr", "Pack Subs % vs VLR", "pack_subs", "avg_vlr_daily", pct=True),
    ]},
    {"title": "Revenue", "cumulative_yoy": True, "metrics": [
        _m("rev_prepaid", "Revenue Prepaid", "IDR"),
        _m("rev_vsd", "Revenue VSD", "IDR"),
        _m("rev_non_vsd", "Revenue Non-VSD", "IDR", expr="(m.rev_prepaid - m.rev_vsd)"),
        _ratio("rev_vsd_pct", "VSD Cont %", "rev_vsd", "rev_prepaid", pct=True),
        _ratio("rev_nonvsd_pct", "Non-VSD Cont %", "rev_non_vsd", "rev_prepaid", pct=True),
        _m("rev_data", "Revenue Data", "IDR"),
        _m("rev_voice", "Revenue Voice", "IDR"),
        _m("rev_sms", "Revenue SMS", "IDR"),
        _m("rev_base", "Revenue Base", "IDR"),
        _m("rev_acquisition_m0", "Revenue Acquisition M0", "IDR"),
        _ratio("rev_base_pct", "Base Cont %", "rev_base", "rev_prepaid", pct=True),
        _ratio("rev_acq_pct", "Acq Cont %", "rev_acquisition_m0", "rev_prepaid", pct=True),
    ]},
    {"title": "Revenue by Channel", "cumulative_yoy": True, "metrics": [
        _m("rev_data_mobo_trade", "Revenue MOBO Trade", "IDR"),
        _m("rev_data_organic", "Revenue Organic", "IDR"),
        _m("rev_data_mobo_non_trade", "Revenue MOBO Non-Trade", "IDR"),
        _ratio("rev_mobo_pct", "Trade Cont %", "rev_data_mobo_trade", "rev_data", pct=True),
        _ratio("rev_organic_pct", "Organic Cont %", "rev_data_organic", "rev_data", pct=True),
        _ratio("rev_nontrade_pct", "Non-Trade Cont %", "rev_data_mobo_non_trade", "rev_data", pct=True),
    ]},
    {"title": "Revenue ATL/BTL", "cumulative_yoy": True, "metrics": [
        _m("rev_atl", "Revenue ATL", "IDR", expr="(m.rev_atl_gift + m.rev_atl_ori + m.rev_atl_renewal)"),
        _m("rev_atl_gift", "Revenue ATL Gift", "IDR"),
        _m("rev_atl_ori", "Revenue ATL Original", "IDR"),
        _m("rev_atl_renewal", "Revenue ATL Renewal", "IDR"),
        _m("rev_btl", "Revenue BTL", "IDR"),
        _ratio("atl_vs_btl", "ATL vs BTL (ratio)", "rev_atl", "rev_btl"),
        _ratio("atl_pct", "ATL % of (ATL+BTL)", "rev_atl", "rev_atl_btl_sum", pct=True),
        _m("rev_atl_btl_sum", "ATL+BTL", "IDR", expr="(m.rev_atl_gift + m.rev_atl_ori + m.rev_atl_renewal + m.rev_btl)"),
    ]},
    {"title": "Usage Traffic", "metrics": [
        _m("usg_data_gb", "Usage Data", "GB"),
        _m("usg_og_voice_min", "Usage Voice", "Min"),
        _m("usg_og_sms_hit", "Usage SMS", "Hits"),
        _ratio("yield_data", "Yield (Rp/GB)", "rev_data", "usg_data_gb", unit="Rp"),
        _ratio("gb_per_user", "Usage / User (GB)", "usg_data_gb", "data_uu_30", unit="GB"),
    ]},
    {"title": "Subscriber · HVC", "group": "HVC Focus", "metrics": [
        _m("subs_hvc", "Subscriber HVC", "Subs", snapshot=True),
        _m("subs_hvc_stay", "HVC Stay", "Subs", snapshot=True),
        _m("subs_hvc_in", "HVC In", "Subs"),
        _m("subs_hvc_out", "HVC Out", "Subs"),
    ]},
    {"title": "Revenue · HVC", "group": "HVC Focus", "cumulative_yoy": True, "metrics": [
        _m("hvc_rev_total", "Revenue HVC Total", "IDR"),
        _m("hvc_rev_organic", "Revenue HVC Organic", "IDR"),
        _m("hvc_rev_mobo_trade", "Revenue HVC Trade", "IDR"),
        _m("hvc_rev_digital", "Revenue HVC Digital", "IDR"),
        _ratio("hvc_organic_pct", "HVC Organic % vs Total", "hvc_rev_organic", "hvc_rev_total", pct=True),
        _ratio("hvc_trade_pct", "HVC Trade % vs Total", "hvc_rev_mobo_trade", "hvc_rev_total", pct=True),
        _ratio("hvc_digital_pct", "HVC Digital % vs Total", "hvc_rev_digital", "hvc_rev_total", pct=True),
        # HVC channel revenue vs the matching total data-channel revenue (paired)
        _ratio("hvc_organic_vs_data", "HVC Organic % vs Rev Organic", "hvc_rev_organic", "rev_data_organic_h", pct=True),
        _ratio("hvc_trade_vs_data", "HVC Trade % vs Rev Trade", "hvc_rev_mobo_trade", "rev_data_mobo_trade_h", pct=True),
        _ratio("hvc_digital_vs_data", "HVC Digital % vs Rev Digital", "hvc_rev_digital", "rev_data_mobo_non_trade_h", pct=True),
        _ratio("hvc_arpu", "HVC ARPU (Rev/HVC Subs)", "hvc_rev_total_pt", "subs_hvc_h", unit="Rp"),
        _ratio("hvc_rev_pct_prepaid", "HVC Rev % vs Rev Prepaid", "hvc_rev_total", "rev_prepaid_h", pct=True),
        # hidden denominators
        _m("subs_hvc_h", "HVC Subs", "Subs", expr="m.subs_hvc", snapshot=True),
        # point-in-time HVC revenue (snapshot) so ARPU YTD uses current-month rev
        _m("hvc_rev_total_pt", "HVC Rev (pt)", "IDR", expr="m.hvc_rev_total", snapshot=True),
        _m("rev_prepaid_h", "Revenue Prepaid", "IDR", expr="m.rev_prepaid"),
        _m("rev_data_organic_h", "Rev Organic", "IDR", expr="m.rev_data_organic"),
        _m("rev_data_mobo_trade_h", "Rev MOBO Trade", "IDR", expr="m.rev_data_mobo_trade"),
        _m("rev_data_mobo_non_trade_h", "Rev Non-Trade", "IDR", expr="m.rev_data_mobo_non_trade"),
    ]},
    {"title": "FWA", "group": "FWA", "metrics": [
        _m("fwa_rgu_ga", "FWA Gross Add", "Subs"),
        _m("fwa_rgu90", "FWA RGU 90D", "Subs", snapshot=True),
        _m("fwa_net_add", "FWA Net Add", "Subs"),
        _m("fwa_net_churn", "FWA Net Churn", "Subs"),
        _m("rev_fwa_total", "Revenue FWA Total", "IDR"),
        _m("rev_fwa_pack", "Revenue FWA Pack", "IDR"),
        _m("rev_fwa_sim", "Revenue FWA SIM", "IDR"),
        _m("rev_fwa_regular", "Revenue FWA Regular", "IDR"),
        _m("rev_fwa_non_broadband", "Revenue FWA Non-Broadband", "IDR"),
        _ratio("fwa_arpu", "FWA ARPU (Rev/RGU90)", "rev_fwa_total", "fwa_rgu90", unit="Rp"),
    ]},
    {"title": "Trade", "group": "Trade", "metrics": [
        _m("num_outlet", "Number of Outlets", "Outlets", snapshot=True),
        _m("primary_all", "Primary", "Outlets", snapshot=True),
        _m("secondary_nat", "Secondary", "Outlets", snapshot=True),
        _m("tertiary_a_nat", "Tertiary A", "Outlets", snapshot=True),
        _m("tertiary_b", "Tertiary B", "Outlets", snapshot=True),
        _m("tertiary_b_inner", "Tertiary B Inner", "Outlets", snapshot=True),
        _m("tertiary_b_outer", "Tertiary B Outer", "Outlets", snapshot=True),
        _m("trade_demand", "Trade Demand", "Subs"),
        _m("trade_demand_inner", "Trade Demand Inner", "Subs"),
        _m("trade_demand_outer", "Trade Demand Outer", "Subs"),
        _m("trade_supply", "Trade Supply", "Subs", snapshot=True),
        _ratio("ps_ratio", "P/S Ratio", "primary_all", "secondary_nat"),
        _ratio("st_ratio", "S/T Ratio", "secondary_nat", "tertiary_b"),
        _ratio("sd_ratio", "S/D Ratio", "trade_supply", "trade_demand"),
    ]},
    # Placed last (just above Mark2Market / FB MS).
    {"title": "Site Productivity", "group": "Asset Productivity", "metrics": [
        # Per-site productivity (point-in-time). Revenue/RGU/VLR per site type.
        _ratio("rev_per_addr", "Revenue / Addr Site", "site_addr_rev_h", "addr_site_h", unit="Rp"),
        _ratio("rev_per_base", "Revenue / Base Site", "site_base_rev_h", "base_site_h", unit="Rp"),
        _ratio("rev_per_new", "Revenue / New Site", "site_new_rev_h", "new_site_h", unit="Rp"),
        _ratio("rgu_per_addr", "RGU 90D / Addr Site", "site_addr_rgu_h", "addr_site_h", unit="Subs"),
        _ratio("rgu_per_base", "RGU 90D / Base Site", "site_base_rgu_h", "base_site_h", unit="Subs"),
        _ratio("rgu_per_new", "RGU 90D / New Site", "site_new_rgu_h", "new_site_h", unit="Subs"),
        _ratio("vlr_per_addr", "VLR / Addr Site", "site_addr_vlr_h", "addr_site_h", unit="Subs"),
        _ratio("vlr_per_base", "VLR / Base Site", "site_base_vlr_h", "base_site_h", unit="Subs"),
        _ratio("vlr_per_new", "VLR / New Site", "site_new_vlr_h", "new_site_h", unit="Subs"),
        # hidden numerators/denominators (network-level → same across brands).
        # Revenue numerators are flagged snapshot so per-site productivity is
        # point-in-time (YTD = current month value, NOT an accumulation).
        _m("site_addr_rev_h", "Addr Rev", "IDR", expr="m.site_addr_rev", network=True, snapshot=True),
        _m("site_base_rev_h", "Base Rev", "IDR", expr="m.site_base_rev", network=True, snapshot=True),
        _m("site_new_rev_h", "New Rev", "IDR", expr="m.site_new_rev", network=True, snapshot=True),
        _m("site_addr_rgu_h", "Addr RGU", "Subs", expr="m.site_addr_rgu_90d", network=True, snapshot=True),
        _m("site_base_rgu_h", "Base RGU", "Subs", expr="m.site_base_rgu_90d", network=True, snapshot=True),
        _m("site_new_rgu_h", "New RGU", "Subs", expr="m.site_new_rgu_90d", network=True, snapshot=True),
        _m("site_addr_vlr_h", "Addr VLR", "Subs", expr="m.site_addr_vlr_daily", network=True, snapshot=True),
        _m("site_base_vlr_h", "Base VLR", "Subs", expr="m.site_base_vlr_daily", network=True, snapshot=True),
        _m("site_new_vlr_h", "New VLR", "Subs", expr="m.site_new_vlr_daily", network=True, snapshot=True),
        _m("addr_site_h", "Addr Site", "Sites", expr="m.addr_site", network=True, snapshot=True),
        _m("base_site_h", "Base Site", "Sites", expr="m.base_site", network=True, snapshot=True),
        _m("new_site_h", "New Site", "Sites", expr="m.new_site", network=True),
    ]},
]

# Codes that are queried only to serve as ratio denominators (not rendered).
_HIDDEN_CODES = {"rev_atl_btl_sum", "subs_hvc_h", "hvc_rev_total_pt", "rev_prepaid_h",
                 "rev_data_organic_h", "rev_data_mobo_trade_h", "rev_data_mobo_non_trade_h",
                 "site_addr_rev_h", "site_base_rev_h", "site_new_rev_h",
                 "site_addr_rgu_h", "site_base_rgu_h", "site_new_rgu_h",
                 "site_addr_vlr_h", "site_base_vlr_h", "site_new_vlr_h",
                 "addr_site_h", "base_site_h", "new_site_h"}

# Mark2Market flat sections: actor -> column. Each actor is a brand/competitor.
M2M_SECTIONS: list[dict] = [
    {"title": "FB Market Share", "group": "Mark2Market", "unit": "%", "prefix": "fb_ms",
     "actors": [("Industry", "industry"), ("IM3", "im3"), ("3ID", "3id"),
                ("TSEL", "tsel"), ("XL", "xl"), ("SF", "sf")]},
    {"title": "FB SoGA", "group": "Mark2Market", "unit": "%", "prefix": "fb_soga",
     "actors": [("Industry", "industry"), ("IM3", "im3"), ("3ID", "3id"),
                ("TSEL", "tsel"), ("XL", "xl"), ("SF", "sf")]},
]


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


def _circle_clause(circle: str) -> str:
    """t.circle filter; 'ALL' → no restriction."""
    if (circle or "").strip().upper() == "ALL":
        return "1=1"
    return f"t.circle='{_esc(circle)}'"


def _latest_month() -> int:
    r = run_query(f"SELECT MAX(month_id) AS m FROM {_MTD}")
    return int(r["rows"][0]["m"])


def _all_metrics() -> list[dict]:
    out = []
    for s in SECTIONS:
        out.extend(s["metrics"])
    return out


def _base_metrics() -> list[dict]:
    """Metrics that map to a real SUM-able column (exclude computed ratios).
    De-duplicated by code so a column is summed once."""
    seen, out = set(), []
    for m in _all_metrics():
        if m.get("computed"):
            continue
        if m["code"] in seen:
            continue
        seen.add(m["code"])
        out.append(m)
    return out


def _brand_cols(m: dict) -> str:
    """SUM columns for one metric at one timeframe (alias = code_ioh/_im3/_3id)."""
    code, expr = m["code"], m["expr"]
    if m.get("network"):
        im3 = f"COALESCE(SUM(CASE WHEN m.brand='IM3' THEN {expr} END),0)"
        return f"{im3} AS {code}_ioh, {im3} AS {code}_im3, {im3} AS {code}_3id"
    return (
        f"COALESCE(SUM({expr}),0) AS {code}_ioh, "
        f"COALESCE(SUM(CASE WHEN m.brand='IM3' THEN {expr} END),0) AS {code}_im3, "
        f"COALESCE(SUM(CASE WHEN m.brand='3ID' THEN {expr} END),0) AS {code}_3id"
    )


def _terr_filter(filter_type: str, filter_value: str) -> str:
    if not filter_value:
        return ""
    col = {"region": "t.region", "area": "t.area_im3", "branch": "t.branch_im3",
           "kabkota": "t.kabkot", "kecamatan": "t.kec_id",
           "microcluster": "t.micro_cluster_im3",
           "supergtm": "t.super_gtm", "island": "t.island"}.get(filter_type)
    return f" AND {col} = '{_esc(filter_value)}'" if col else ""


def _wide_one_month(table: str, metrics: list[dict], circle: str, month_id: int,
                    fc: str, extra_select: str = "") -> dict:
    sel = ",\n  ".join(_brand_cols(m) for m in metrics)
    if extra_select:
        sel += ",\n  " + extra_select
    sql = f"""
SELECT
  {sel}
FROM {table} m
LEFT JOIN {_TERR} t ON m.kec_id = t.kec_id
WHERE {_circle_clause(circle)}{fc} AND m.month_id={month_id}
"""
    return run_query(sql, row_limit=10)


def _wide_cumulative(table: str, metrics: list[dict], circle: str,
                     month_ids: list[int], fc: str) -> dict:
    """SUM across a list of months (Jan..MTD) for YTD/LYTD cumulative, per brand
    (IOH/IM3/3ID) so YoY can be shown for all brands. network_metric repeats the
    IM3 value across brands (physical sites)."""
    months = ",".join(str(x) for x in month_ids)
    sel = ",\n  ".join(_brand_cols(m) for m in metrics)
    sql = f"""
SELECT
  {sel}
FROM {table} m
LEFT JOIN {_TERR} t ON m.kec_id = t.kec_id
WHERE {_circle_clause(circle)}{fc} AND m.month_id IN ({months})
"""
    return run_query(sql, row_limit=10)


def _m2m_latest_closed_month(circle: str, fc: str, upto: int) -> Optional[int]:
    """Market-share columns are only populated for CLOSED months in _mth (the
    current month is NULL). Find the most recent month <= upto with data."""
    sql = f"""
SELECT MAX(m.month_id) AS mm
FROM {_MTH} m
LEFT JOIN {_TERR} t ON m.kec_id = t.kec_id
WHERE {_circle_clause(circle)}{fc} AND m.month_id <= {upto}
  AND m.brand='IM3' AND m.fb_ms_industry IS NOT NULL
"""
    r = run_query(sql, row_limit=2)
    mm = r["rows"][0].get("mm") if r["rows"] else None
    return int(mm) if mm is not None else None


def _m2m_query(circle: str, fc: str, upto: int) -> tuple[dict, Optional[int]]:
    """Pull fb_ms_* / fb_soga_* actor columns from _mth (closed-month, dedup to
    IM3 rows). Returns (summed row, the month used) — share% computed downstream."""
    mm = _m2m_latest_closed_month(circle, fc, upto)
    if mm is None:
        return {}, None
    cols = []
    for sec in M2M_SECTIONS:
        for _label, key in sec["actors"]:
            c = f"{sec['prefix']}_{key}"
            cols.append(f"SUM(CASE WHEN m.brand='IM3' THEN m.{c} END) AS {c}")
    # churn absolutes per actor (no industry churn column exists)
    for key in ("im3", "3id", "tsel", "xl", "sf"):
        c = f"fb_churn_{key}"
        cols.append(f"SUM(CASE WHEN m.brand='IM3' THEN m.{c} END) AS {c}")
    sel = ",\n  ".join(cols)
    sql = f"""
SELECT
  {sel}
FROM {_MTH} m
LEFT JOIN {_TERR} t ON m.kec_id = t.kec_id
WHERE {_circle_clause(circle)}{fc} AND m.month_id={mm}
"""
    return run_query(sql, row_limit=10)["rows"][0], mm


def _year_months(month_id: int) -> tuple[list[int], list[int]]:
    """Return (ytd_months Jan..month_id this year, lytd_months Jan..same month last year)."""
    year = month_id // 100
    mm = month_id % 100
    ytd = [year * 100 + i for i in range(1, mm + 1)]
    lytd = [(year - 1) * 100 + i for i in range(1, mm + 1)]
    return ytd, lytd


def build_comprehensive(circle: str, month_id: Optional[int],
                        filter_type: str = "all", filter_value: str = "") -> dict:
    fc = _terr_filter(filter_type, filter_value)
    mid = int(month_id) if month_id else _latest_month()
    lmtd, llmtd = mid - 1, mid - 2
    base = _base_metrics()  # only real SUM-able columns

    # 3 timeframe wide rows from the MTD table
    r_mtd = _wide_one_month(_MTD, base, circle, mid, fc)["rows"][0]
    r_lmtd = _wide_one_month(_MTD, base, circle, lmtd, fc)["rows"][0]
    r_llmtd = _wide_one_month(_MTD, base, circle, llmtd, fc)["rows"][0]

    # YoY inputs. flow → cumulative YTD sums; snapshot → point-in-time last year.
    #
    # Apple-to-apple YTD vs LYTD: both mix closed full months with a PARTIAL
    # current month capped at the same data cutoff day.
    #   YTD  = SUM(_mth, Jan..mid-1 this year)        + MTD(this year, mid)
    #   LYTD = SUM(_mth, Jan..(mid-1) last year)      + MTD(last year, mid-100)
    # The current month (this year & last year) ALWAYS comes from the _MTD table
    # (which is itself capped at the same cutoff day-of-month), never from _MTH
    # (full closed month) — otherwise YTD's partial month would be compared
    # against a full prior-year month.
    mid_ly = mid - 100  # same month, previous year
    ytd_months, lytd_months = _year_months(mid)
    flow_m = [m for m in base if not m.get("snapshot")]
    snap_m = [m for m in base if m.get("snapshot")]
    r_ytd_flow = r_lytd_flow = {}
    r_lytd_cur_mtd = {}
    if flow_m:
        prior_months = [x for x in ytd_months if x != mid]      # Jan..mid-1 (this year)
        prior_months_ly = [x for x in lytd_months if x != mid_ly]  # Jan..mid-1 (last year)
        r_ytd_flow = _wide_cumulative(_MTH, flow_m, circle, prior_months, fc)["rows"][0] if prior_months else {}
        r_lytd_flow = _wide_cumulative(_MTH, flow_m, circle, prior_months_ly, fc)["rows"][0] if prior_months_ly else {}
        # MTD-equivalent of the current month last year, from the (cutoff-capped) _MTD table.
        try:
            r_lytd_cur_mtd = _wide_one_month(_MTD, flow_m, circle, mid_ly, fc)["rows"][0]
        except Exception:
            r_lytd_cur_mtd = {}
    r_lytd_point = {}
    if snap_m:
        try:
            r_lytd_point = _wide_one_month(_MTH, snap_m, circle, mid - 100, fc)["rows"][0]
        except Exception:
            r_lytd_point = {}

    def num(d, k):
        v = d.get(k)
        return float(v) if v is not None else 0.0

    # Build a value-map for every base metric: vals[code][brand] = {timeframes}
    snap_codes = {m["code"] for m in snap_m}
    vals: dict[str, dict] = {}
    for m in base:
        code = m["code"]
        is_snap = code in snap_codes
        vals[code] = {}
        for brand in ("ioh", "im3", "3id"):
            mtd = num(r_mtd, f"{code}_{brand}")
            lm = num(r_lmtd, f"{code}_{brand}")
            llm = num(r_llmtd, f"{code}_{brand}")
            if is_snap:
                ytd, lytd = mtd, num(r_lytd_point, f"{code}_{brand}")
            else:
                ytd = num(r_ytd_flow, f"{code}_{brand}") + mtd
                # LYTD = prior full months last year + MTD of current month last year
                # (both partial-current-month parts use the cutoff-capped _MTD table).
                lytd = num(r_lytd_flow, f"{code}_{brand}") + num(r_lytd_cur_mtd, f"{code}_{brand}")
            vals[code][brand] = {"llmtd": llm, "lmtd": lm, "mtd": mtd, "ytd": ytd, "lytd": lytd}

    def _rec_base(m):
        code = m["code"]
        rec = {"code": code, "name": m["name"], "unit": m["unit"],
               "network": bool(m.get("network")), "snapshot": code in snap_codes, "computed": False}
        for brand in ("ioh", "im3", "3id"):
            v = vals[code][brand]
            mtd, lm = v["mtd"], v["lmtd"]
            ytd, lytd = v["ytd"], v["lytd"]
            rec[brand] = {
                "llmtd": v["llmtd"], "lmtd": lm, "mtd": mtd,
                "var_mom": mtd - lm,
                "growth_mom_pct": ((mtd - lm) / lm * 100) if lm else None,
                "ytd": ytd, "lytd": lytd,
                "var_yoy": ytd - lytd,
                "growth_yoy_pct": ((ytd - lytd) / lytd * 100) if lytd else None,
            }
        return rec

    def _rec_ratio(m):
        num_code, den_code = m["ratio"]
        scale = 100.0 if m.get("pct") else 1.0
        rec = {"code": m["code"], "name": m["name"], "unit": m["unit"],
               "network": False, "snapshot": False, "computed": True}
        for brand in ("ioh", "im3", "3id"):
            n = vals.get(num_code, {}).get(brand, {})
            d = vals.get(den_code, {}).get(brand, {})
            def r(tf):
                dv = d.get(tf) or 0.0
                return (n.get(tf, 0.0) / dv * scale) if dv else None
            mtd_r, lm_r = r("mtd"), r("lmtd")
            ytd_r, lytd_r = r("ytd"), r("lytd")
            rec[brand] = {
                "llmtd": r("llmtd"), "lmtd": lm_r, "mtd": mtd_r,
                "var_mom": (mtd_r - lm_r) if (mtd_r is not None and lm_r is not None) else None,
                "growth_mom_pct": ((mtd_r - lm_r) / lm_r * 100) if (mtd_r is not None and lm_r) else None,
                "ytd": ytd_r, "lytd": lytd_r,
                "var_yoy": (ytd_r - lytd_r) if (ytd_r is not None and lytd_r is not None) else None,
                "growth_yoy_pct": ((ytd_r - lytd_r) / lytd_r * 100) if (ytd_r is not None and lytd_r) else None,
            }
        return rec

    out_sections = []
    for s in SECTIONS:
        rows = []
        for m in s["metrics"]:
            if m["code"] in _HIDDEN_CODES:
                continue
            rows.append(_rec_ratio(m) if m.get("computed") else _rec_base(m))
        out_sections.append({"title": s["title"], "group": s.get("group"),
                             "cumulative_yoy": True, "layout": "grid",
                             "snapshot": all((mm.get("snapshot") or mm.get("computed")) for mm in s["metrics"]),
                             "metrics": rows})

    # Mark2Market flat (closed-month). Each actor row carries multiple columns:
    #   FB SoGA: SoGA%, FB GA Abs (=soga), FB Churn Abs, FB Net Add (=ga-churn)
    #   FB MS:   MS%, MS Abs
    m2m_row, m2m_month = _m2m_query(circle, fc, mid)
    for sec in M2M_SECTIONS:
        ind = num(m2m_row, f"{sec['prefix']}_industry") if m2m_row else 0.0
        is_soga = sec["prefix"] == "fb_soga"
        if is_soga:
            columns = ["SoGA %", "FB GA Abs", "FB Churn Abs", "FB Net Add"]
        else:
            columns = ["MS %", "MS Abs"]
        flat_rows = []
        for label, key in sec["actors"]:
            raw = num(m2m_row, f"{sec['prefix']}_{key}") if m2m_row else 0.0
            share = round(raw / ind * 100, 2) if ind else None
            if is_soga:
                churn = num(m2m_row, f"fb_churn_{key}") if (m2m_row and key != "industry") else None
                ga = raw
                net = (ga - churn) if (churn is not None) else None
                cells = [share, round(ga), (round(churn) if churn is not None else None),
                         (round(net) if net is not None else None)]
            else:
                cells = [share, round(raw)]
            flat_rows.append({"actor": label, "value": share, "cells": cells})
        out_sections.append({"title": sec["title"], "group": sec["group"],
                             "layout": "flat", "unit": sec["unit"], "columns": columns,
                             "month_used": m2m_month, "rows": flat_rows})

    return {
        "scope": {"circle": circle, "month_id": mid,
                  "filter_type": filter_type, "filter_value": filter_value,
                  "data_as_of": _data_as_of()},
        "sections": out_sections,
    }


def _data_as_of() -> str:
    """Freshness marker (dt_id_snapshot) of the highlevel source table."""
    try:
        r = run_query(f"SELECT MAX(dt_id_snapshot) AS m FROM {_MTD}", row_limit=2)
        v = r["rows"][0].get("m") if r["rows"] else None
        return str(v) if v is not None else ""
    except Exception:
        return ""
