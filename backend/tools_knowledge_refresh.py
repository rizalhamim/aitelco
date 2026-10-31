#!/usr/bin/env python3
"""Audit java_precalc and promote reviewed tables into the runtime knowledge KB.

Discovery is report-only by default. It never promotes a table automatically.
Use ``--bootstrap-governance`` once to create explicit lifecycle decisions, then
``--promote-reviewed`` to apply only entries marked approved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app import config  # noqa: E402
from app.knowledge_graph import write_graph_atomic  # noqa: E402


TOOL_VERSION = "1.0"
REVIEW_ID = "five-agent-panel-2026-08-19"

APPROVED_NEW: dict[str, str] = {
    # 5G rollout and competitive experience
    "rham_5g_nr2600": "5g",
    "rham_fb_network_5g": "network_benchmark",
    "rham_network_comp": "network_benchmark",
    "rham_network_comp_kec": "network_benchmark",
    # Internal network and commercial performance
    "rham_network_internal": "network",
    "rham_network_internal_kec": "network",
    # FTTH observed operational summaries
    "rham_ftth_kec_wise_daily": "ftth",
    "rham_ftth_kec_wise_mtd": "ftth",
    "rham_ftth_kec_wise_mth": "ftth",
    "rham_ftth_site_wise_daily": "ftth",
    "rham_ftth_site_wise_mtd": "ftth",
    "rham_ftth_site_wise_mth": "ftth",
    # FWA observed aggregate performance
    "rham_fwa_kec_wise_daily": "fwa",
    "rham_fwa_kec_wise_mtd": "fwa",
    "rham_fwa_kec_wise_mth": "fwa",
    "rham_fwa_monthly": "fwa",
    "rham_fwa_monthly_kpi": "fwa",
    "rham_fwa_site_wise_daily": "fwa",
    "rham_fwa_site_wise_mtd": "fwa",
    "rham_fwa_site_wise_mth": "fwa",
    # Aggregate demand and digital behavior
    "rham_cohort_voucher_mobotrade": "customer_demand",
    "rham_data_rev_digicommerce_daily": "customer_demand",
    "rham_demand_inner_outer": "customer_demand",
    "rham_demand_inner_outer_mtd": "customer_demand",
    "rham_demand_inner_outer_mth": "customer_demand",
    "rham_game_daily": "customer_demand",
    "rham_game_mtd": "customer_demand",
    "rham_game_mth": "customer_demand",
    "rham_ssd_details_mtd": "customer_demand",
    "rham_ssd_details_mth": "customer_demand",
    "rham_subs_traffic_agg_geo_mtd_lmtd": "customer_demand",
    "rham_subs_traffic_agg_migration_matrix_monthly": "customer_demand",
    "rham_subs_traffic_agg_segment_mtd_lmtd": "customer_demand",
    # Outlet and distribution intelligence
    "rham_outlet_junction_java": "sales_distribution",
    "rham_outlet_population_java": "sales_distribution",
    "rham_outlet_road_java": "sales_distribution",
    "rham_outlet_spacing_java": "sales_distribution",
    "rham_outlet_transaction_java": "sales_distribution",
    "rham_outlet_wise_mtd": "sales_distribution",
    "rham_outlet_wise_mth": "sales_distribution",
    "rham_outletwise_daily_pjp": "sales_distribution",
    "rham_snd_kpi_highlevel_mtd": "sales_distribution",
    "rham_snd_kpi_highlevel_mth": "sales_distribution",
    # Aggregate acquisition intelligence
    "rham_sellin_ga_location": "acquisition",
    "rham_site_acquisition_rev": "acquisition",
}

PREVIOUSLY_REJECTED = {
    "rham_fb_ms_kabkota_v2": "Deprecated market-share source. Use rham_report_fb_ms_*.",
    "rham_fb_ms_kecamatan_v2": "Deprecated market-share source. Use rham_report_fb_ms_*.",
    "rham_site_wise_daily_raw": "Oversized raw source. Use approved daily or monthly aggregates.",
    "rham_ref_territory2": "Alternate territory reference rejected in favor of canonical references.",
    "rham_ref_territory_3id_static": "Duplicate static territory reference.",
    "rham_ref_territory_zz": "Experimental or legacy territory reference.",
    "rham_ref_super88": "Previously deferred because the semantics were not verified.",
    "rham_project_desa_java": "Previously deferred because the semantics were not verified.",
}

QUARANTINE_EXACT = {
    "rham_fwa_site_raw": "Raw FWA source superseded by governed aggregate summaries.",
    "rham_fwa_lead_scores": "Customer-level lead scoring is unavailable to general chat.",
    "rham_fwa_subscriber_base": "Customer-level FWA base is unavailable to general chat.",
    "rham_fwa_integrity_flags": "Detailed integrity records require a separate reviewed use case.",
    "rham_ga_recharge": "Contains GA subscriber identifiers. Use aggregate acquisition tables.",
    "rham_msisdn_ucg_program": "Subscriber-level program membership is unavailable to general chat.",
    "rham_subs_traffic_dim_subs_segment_monthly": "Subscriber-grain table is unavailable to general chat.",
    "rham_subs_traffic_fact_subs_mtd_lmtd": "Subscriber-grain table is unavailable to general chat.",
    "rham_subs_traffic_raw_purchase_txn": "Raw customer transaction data is unavailable to general chat.",
    "rham_subs_traffic_raw_subs_daily": "Raw customer daily data is unavailable to general chat.",
    "rham_hvc_revenue": "Very large source requires a reviewed aggregate contract before use.",
}

DOMAIN_METADATA = {
    "customer_demand": {
        "label": "Customer Demand & Digital Behavior",
        "description": (
            "Aggregate origin-destination demand, product and channel migration, "
            "gaming, SSD, voucher cohorts, digicommerce, and subscriber traffic segments."
        ),
        "agent": {
            "name": "Customer Demand Analyst",
            "persona": (
                "Analyze only aggregate customer behavior. Separate movement, purchase, "
                "traffic, revenue, cohort, and channel metrics. Never infer an individual."
            ),
            "key_facts": [
                "Use only aggregate tables in this domain. Customer or MSISDN-level sources are blocked.",
                "Demand inner/outer is an origin-to-destination flow. Keep source_kec_id and dest_kec_id distinct.",
                "Migration matrices describe movement between pack or channel buckets, not customer causality.",
                "For MTD comparisons use the aligned MTD and LMTD columns already supplied by aggregate tables.",
                "Revenue, traffic, transaction, subscriber, and quota metrics have different units and must not be mixed.",
            ],
        },
    }
}

DESCRIPTIONS = {
    "rham_5g_nr2600": "5G NR2600 rollout inventory by site, program, vendor, geography, and rollout status.",
    "rham_fb_network_5g": "Facebook-derived 5G customer and experience benchmark by date, brand, and kabkota.",
    "rham_network_comp": "Competitive 4G and 5G network experience by date, brand, and kabkota.",
    "rham_network_comp_kec": "Competitive network experience summary at kecamatan grain.",
    "rham_network_internal": "Internal commercial and network driver metrics by date and kabkota.",
    "rham_network_internal_kec": "Internal commercial and network driver metrics at kecamatan grain.",
    "rham_ftth_kec_wise_daily": "Observed FTTH daily performance at kecamatan grain.",
    "rham_ftth_kec_wise_mtd": "Observed FTTH cutoff-aligned MTD snapshot at kecamatan grain.",
    "rham_ftth_kec_wise_mth": "Observed FTTH monthly snapshot at kecamatan grain.",
    "rham_ftth_site_wise_daily": "Observed FTTH daily performance at site grain.",
    "rham_ftth_site_wise_mtd": "Observed FTTH cutoff-aligned MTD snapshot at site grain.",
    "rham_ftth_site_wise_mth": "Observed FTTH monthly snapshot at site grain.",
    "rham_fwa_kec_wise_daily": "Observed FWA daily performance at kecamatan grain.",
    "rham_fwa_kec_wise_mtd": "Observed FWA MTD performance at kecamatan grain.",
    "rham_fwa_kec_wise_mth": "Observed FWA monthly performance at kecamatan grain.",
    "rham_fwa_monthly": "Observed FWA monthly performance by operational area.",
    "rham_fwa_monthly_kpi": "FWA acquisition, retention, productivity, and quality KPIs by month and area.",
    "rham_fwa_site_wise_daily": "Observed FWA daily performance at site grain.",
    "rham_fwa_site_wise_mtd": "Observed FWA MTD performance at site grain.",
    "rham_fwa_site_wise_mth": "Observed FWA monthly performance at site grain.",
    "rham_cohort_voucher_mobotrade": "Aggregate voucher and MOBO cohort retention and revenue by activity month.",
    "rham_data_rev_digicommerce_daily": "Daily digicommerce data revenue and transaction hits by channel and outlet.",
    "rham_demand_inner_outer": "Daily aggregate origin-destination demand flow by kecamatan and category.",
    "rham_demand_inner_outer_mtd": "MTD aggregate origin-destination demand flow by kecamatan and category.",
    "rham_demand_inner_outer_mth": "Monthly aggregate origin-destination demand flow by kecamatan and category.",
    "rham_game_daily": "Daily game voucher revenue and hits by brand and kecamatan territory (source ioh_rev).",
    "rham_game_mtd": "MTD game voucher revenue and hits by brand and kecamatan territory (source ioh_rev).",
    "rham_game_mth": "Monthly game voucher revenue and hits by brand and kecamatan territory (source ioh_rev).",
    "rham_ssd_details_mtd": "MTD SSD product demand, hits, and net revenue at kecamatan grain.",
    "rham_ssd_details_mth": "Monthly SSD product demand, hits, and net revenue at kecamatan grain.",
    "rham_subs_traffic_agg_geo_mtd_lmtd": "Aggregate MTD versus LMTD subscriber traffic and revenue by serving geography segment.",
    "rham_subs_traffic_agg_migration_matrix_monthly": "Aggregate monthly migration between pack and channel buckets.",
    "rham_subs_traffic_agg_segment_mtd_lmtd": "Aggregate MTD, LMTD, and LYTD traffic and revenue by subscriber segment.",
    "rham_outlet_junction_java": "Outlet-to-road-junction proximity reference for outlet access analysis.",
    "rham_outlet_population_java": "Outlet population coverage reference.",
    "rham_outlet_road_java": "Outlet road-access classification and distance reference.",
    "rham_outlet_spacing_java": "Outlet spacing, nearest-neighbor, density, and coordinate-quality metrics.",
    "rham_outlet_transaction_java": "Aggregate outlet transaction and location attributes.",
    "rham_outlet_wise_mtd": "MTD outlet-level sales and distribution performance.",
    "rham_outlet_wise_mth": "Monthly outlet-level sales and distribution performance.",
    "rham_outletwise_daily_pjp": "Daily outlet PJP and distribution performance.",
    "rham_snd_kpi_highlevel_mtd": "MTD SND distribution KPI aggregate at kecamatan and brand grain.",
    "rham_snd_kpi_highlevel_mth": "Monthly SND distribution KPI aggregate at kecamatan and brand grain.",
    "rham_sellin_ga_location": "Aggregate sell-in to gross-add location relationship by month and territory.",
    "rham_site_acquisition_rev": "Daily site acquisition revenue and hits by product and channel.",
    # java-precalc-review-2026-09-17
    "rham_ga_new_imei_mtd": "MTD gross adds split by new versus old device IMEI, including 5G devices, at site and brand grain.",
    "rham_ga_new_imei_mth": "Closed-month gross adds split by new versus old device IMEI, including 5G devices, at site and brand grain.",
    "rham_outlet_ga_quality": "Outlet acquisition QUALITY by acquisition date, channel and device: gross adds, eSIM and 5G uptake, M1 to M3 survival, and acquisition revenue.",
    "rham_outlet_ga_quality_dtu": "Outlet acquisition quality split by DTU versus NON-DTU source, with outlet mapping status.",
    "rham_outlet_ga_quality_mtd": "Cutoff-aligned MTD outlet acquisition quality: gross adds, device mix, M1 to M3 survival, revenue and usage thresholds.",
    "rham_outlet_ga_quality_mth": "Closed-month outlet acquisition quality: gross adds, device mix, M1 to M3 survival, revenue and usage thresholds.",
    "rham_outlet_low_stock": "Outlet stock availability by KPI, with MTD, LMTD, LLMTD and W-0 to W-6 comparison columns.",
    "rham_outlet_secondary_daily": "Daily outlet secondary sales value and transactions by price point and transaction type.",
    "rham_outlet_secondary_mtd": "Cutoff-aligned MTD outlet secondary sales value and transactions by price point and transaction type.",
    "rham_outlet_secondary_mth": "Closed-month outlet secondary sales value and transactions by price point and transaction type.",
    "rham_postpaid_ga_daily": "Daily POSTPAID gross adds, acquisition revenue and guaranteed revenue by store, channel, order type and package.",
    "rham_report_fb_device_5g": "Facebook-derived market share, gross-add share and churn among owners of a 5G-CAPABLE DEVICE, per operator and territory level.",
    "rham_report_fb_network_5g": "Facebook-derived market share, gross-add share and churn among subscribers USING THE 5G NETWORK, per operator and territory level.",
    "rham_site_ga_quality_daily": "Daily site acquisition quality: gross adds, device mix, quality-subscriber thresholds and survival.",
    "rham_site_ga_quality_mtd": "Cutoff-aligned MTD site acquisition quality: gross adds, device and eSIM mix, QSC thresholds, M1 to M3 survival.",
    "rham_site_ga_quality_mth": "Closed-month site acquisition quality: gross adds, device and eSIM mix, QSC thresholds, M1 to M3 survival.",
    "rham_site_traffic_usage_mtd": "MTD traffic and revenue by site and commercial segment, with LMTD comparison, daily run rate and full-month projection.",
    "rham_site_traffic_usage_mth": "Closed-month traffic, revenue, transactions, quota utilisation and burning behaviour by site and commercial segment.",
    "rham_kec_wise_tnr_mtd": "MTD kecamatan KPI cube by brand and TENURE GROUP: revenue, traffic, RGU, churn, gross adds, VLR and PAU.",
    "rham_kec_wise_tnr_mth": "Closed-month kecamatan KPI cube by brand and TENURE GROUP: revenue, traffic, RGU, churn, gross adds, VLR and PAU.",
    "rham_ftth_tt_mttr": "FTTH trouble-ticket restoration time: ticket counts and mean time to repair per duration bucket, weekly and monthly.",
    "rham_mkt_kpi_highlevel_dly": "DAILY kecamatan KPI by brand (dt_id): revenue, data/voice/SMS usage, RGU, gross adds, churn, net adds and VLR. Use for day-by-day trends.",
    # additional-sources-2026-10-04
    "rham_hvc_highlevel_mth_serving": "Closed-month kecamatan KPI view with RECOVERED HVC revenue and HVC subscribers. Authoritative HVC source.",
    "rham_hvc_highlevel_mtd_serving": "Cutoff-aligned MTD kecamatan KPI view with RECOVERED HVC revenue and HVC subscribers.",
    "rham_outlet_ga_5g_mtd": "MTD outlet gross adds on 5G-capable devices (has_5g), with 5G traffic uptake and M1 to M3 survival.",
    "rham_outlet_ga_5g_mth": "Closed-month outlet gross adds on 5G-capable devices (has_5g), with 5G traffic uptake and M1 to M3 survival.",
    "rham_outlet_ga_fwa_mtd": "MTD outlet FWA gross adds with first-7-day usage, M1 to M3 survival and outlet mapping status.",
    "rham_outlet_ga_fwa_mth": "Closed-month outlet FWA gross adds with first-7-day usage, M1 to M3 survival and outlet mapping status.",
    "rham_outlet_ga_fwa_5g_mtd": "MTD outlet FWA 5G gross adds with first-7-day usage and survival.",
    "rham_outlet_ga_fwa_5g_mth": "Closed-month outlet FWA 5G gross adds with first-7-day usage and survival.",
    "rham_outlet_ga_ex_dtu": "MTD outlet gross adds EXCLUDING DTU-sourced acquisitions.",
    "rham_outlet_ga_mth_ex_dtu": "Closed-month outlet gross adds EXCLUDING DTU-sourced acquisitions.",
    "rham_ftth_install_orders": "FTTH install order pipeline, one row per order: SO/SA/PA dates, plan and schedule dates, aging, status and vendor.",
    "rham_fb_ms_5g_device": "Weekly Facebook-derived 5G DEVICE owner base, gross adds and churn per operator (IOH, TSEL, XLS) by kabkota, absolute counts.",
    "rham_fb_ms_5g_network": "Weekly Facebook-derived 5G NETWORK user base, gross adds and churn per operator (IOH, TSEL, XLS) by kabkota, absolute counts.",
}

ALIASES = {
    "rham_5g_nr2600": ["nr2600", "5g rollout", "5g deployment", "5g site rollout"],
    "rham_fb_network_5g": ["facebook 5g", "5g competitor", "5g experience"],
    "rham_network_comp": ["competitive network", "competitor speed", "ioh vs tsel vs xlsmart"],
    "rham_network_internal": ["internal performance", "internal network", "network driver tree"],
    "rham_demand_inner_outer_mtd": ["inner outer", "asal tujuan", "origin destination", "demand flow"],
    "rham_demand_inner_outer_mth": ["inner outer monthly", "asal tujuan bulanan", "origin destination"],
    "rham_subs_traffic_agg_migration_matrix_monthly": ["migration matrix", "pack movement", "channel switch"],
    "rham_subs_traffic_agg_segment_mtd_lmtd": ["traffic segment", "subscriber segment", "growth contribution"],
    "rham_cohort_voucher_mobotrade": ["voucher cohort", "rebuy cohort", "mobotrade cohort"],
    "rham_ssd_details_mtd": ["ssd", "ssd product demand"],
    "rham_ssd_details_mth": ["ssd monthly", "ssd product demand"],
}


# Semantic fields a human reviewed. A metadata refresh must never overwrite these
# with the name-based heuristics in `_contract`.
PRESERVED_CONTRACT_FIELDS = (
    "source_kind",
    "grain",
    "period_semantics",
    "aggregation_rule",
    "territory_vocabulary",
    "priority",
    "metric_families",
    "use_constraints",
    "warning_columns",
    "sensitive_dimensions",
    "aliases",
)

# Reviewed contracts for tables whose semantics the heuristics get wrong. Every
# entry here is backed by a profiling run recorded in
# governance/review_2026_09_17.json. See vault/30-data/bigquery-tables.md.
CONTRACT_OVERRIDES: dict[str, dict[str, Any]] = {
    # Name-based guess said grain=kabkota; unik_kec is the kecamatan key.
    "rham_mkt_kpi_highlevel_dly": {
        "grain": "day_x_kecamatan_x_brand",
        "period_semantics": "daily",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["acquisition", "churn", "revenue", "traffic"],
        "aliases": ["kpi harian", "revenue harian", "gross add harian", "tren harian kecamatan"],
        "use_constraints": [
            "Filter dt_id to a bounded literal date range. Kecamatan key is unik_kec.",
            "Stock columns (RGU, VLR, PAU) are daily snapshots: never SUM them across days.",
        ],
    },
    "rham_hvc_highlevel_mth_serving": {
        "grain": "kecamatan",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["revenue", "hvc", "subscriber"],
        "aliases": ["hvc", "high value customer", "pelanggan hvc", "revenue hvc", "subs hvc"],
        "use_constraints": [
            "View without partition: ALWAYS filter mth_dt = DATE literal (and month_id INT64 = YYYYMM) so the base partition is pruned.",
            "Use this view, not rham_mkt_highlevel_mth, for hvc_rev_total and subs_hvc.",
            "From 202609 the split columns hvc_rev_organic, hvc_rev_mobo_trade, hvc_rev_digital "
            "and the flow columns subs_hvc_stay, subs_hvc_in, subs_hvc_out are NOT reliable (frozen or NULL). "
            "Report them as N/A for 202609 onward; only hvc_rev_total and subs_hvc are valid.",
        ],
    },
    "rham_hvc_highlevel_mtd_serving": {
        "grain": "kecamatan",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["revenue", "hvc", "subscriber"],
        "aliases": ["hvc mtd", "revenue hvc mtd", "subs hvc mtd"],
        "use_constraints": [
            "View without partition: ALWAYS filter mth_dt = DATE literal (and month_id INT64 = YYYYMM).",
            "Use this view, not rham_mkt_highlevel_mtd, for hvc_rev_total and subs_hvc.",
            "From 202609 the split columns hvc_rev_organic, hvc_rev_mobo_trade, hvc_rev_digital "
            "and the flow columns subs_hvc_stay, subs_hvc_in, subs_hvc_out are NOT reliable (frozen or NULL). "
            "Report them as N/A for 202609 onward; only hvc_rev_total and subs_hvc are valid.",
        ],
    },
    "rham_outlet_ga_5g_mtd": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "5g device"],
        "aliases": ["ga 5g outlet", "outlet ga 5g", "akuisisi 5g outlet"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "Every row is a 5G-capable GA (has_5g). Do not add it to rham_outlet_ga_mtd; it is a subset."
        ],
    },
    "rham_outlet_ga_5g_mth": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "5g device"],
        "aliases": ["ga 5g outlet bulanan", "outlet ga 5g monthly"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "Every row is a 5G-capable GA (has_5g). Subset of rham_outlet_ga_mth, never additive."
        ],
    },
    "rham_outlet_ga_fwa_mtd": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "fwa"],
        "aliases": ["ga fwa outlet", "outlet fwa", "akuisisi fwa outlet"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "FWA population only. Exclude outlet_mapping_status = 'UNKNOWN' when ranking outlets; keep it for totals."
        ],
    },
    "rham_outlet_ga_fwa_mth": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "fwa"],
        "aliases": ["ga fwa outlet bulanan", "outlet fwa monthly"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "FWA population only. Exclude outlet_mapping_status = 'UNKNOWN' when ranking outlets; keep it for totals."
        ],
    },
    "rham_outlet_ga_fwa_5g_mtd": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "fwa"],
        "aliases": ["ga fwa 5g outlet", "outlet fwa 5g"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "FWA 5G subset of the outlet FWA GA tables, never additive to them."
        ],
    },
    "rham_outlet_ga_fwa_5g_mth": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "fwa"],
        "aliases": ["ga fwa 5g outlet bulanan"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "FWA 5G subset of the outlet FWA GA tables, never additive to them."
        ],
    },
    "rham_outlet_ga_ex_dtu": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "device mix", "revenue"],
        "aliases": ["ga non dtu", "outlet ga ex dtu", "tanpa dtu"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "DTU-sourced acquisitions are excluded. For the full population use rham_outlet_ga_mtd/_mth."
        ],
    },
    "rham_outlet_ga_mth_ex_dtu": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention", "device mix", "revenue"],
        "aliases": ["ga non dtu bulanan", "outlet ga mth ex dtu"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "month_id is STRING ('YYYYMM'); filter mth_dt with a literal date for pruning.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "Validate outlet_latitude/outlet_longitude (Java bounds) before mapping; some rows are corrupt.",
            "DTU-sourced acquisitions are excluded. For the full population use rham_outlet_ga_mtd/_mth."
        ],
    },
    "rham_ftth_install_orders": {
        "grain": "order",
        "period_semantics": "latest_snapshot",
        "aggregation_rule": "count_rows",
        "territory_vocabulary": "ftth_native",
        "metric_families": ["ftth", "install pipeline"],
        "aliases": ["install order ftth", "order instalasi ftth", "backlog instalasi", "aging instalasi",
                    "so sa pa", "pipeline instalasi"],
        "sensitive_dimensions": ["bill_acc", "customer_id", "customer_name", "sales_code",
                                 "sales_name", "manager", "rm"],
        "use_constraints": [
            "One row per order (latest snapshot). Count orders with COUNT(*), group by region, circle, city, vendor, status or duration_bucket.",
            "Customer and sales identity columns (bill_acc, customer_id, customer_name, sales_code, sales_name, manager, rm) are blocked; the query is rejected if it references them or uses SELECT *.",
            "No partition; the table is small. Filter date_so/date_pa for a period.",
        ],
    },
    "rham_fb_ms_5g_device": {
        "grain": "week_x_kabkota",
        "period_semantics": "weekly_snapshot",
        "aggregation_rule": "latest_snapshot_then_recompute_share",
        "metric_families": ["competitive", "market share", "5g device"],
        "aliases": ["ms 5g device kabkota", "market share device 5g mingguan", "fb 5g device kabkota"],
        "use_constraints": [
            "dt_id is a WEEKLY snapshot. Filter ONE dt_id (latest = MAX(dt_id)); never sum across dt_id.",
            "Values are absolute counts. Share = device_5g_total_customers_ioh / device_5g_total_customers_total_abs, recomputed after SUM over kabkota.",
            "Different population from rham_report_fb_device_5g; do not mix the two in one ratio.",
        ],
    },
    "rham_fb_ms_5g_network": {
        "grain": "week_x_kabkota",
        "period_semantics": "weekly_snapshot",
        "aggregation_rule": "latest_snapshot_then_recompute_share",
        "metric_families": ["competitive", "market share", "5g network"],
        "aliases": ["ms 5g network kabkota", "market share jaringan 5g mingguan", "fb 5g network kabkota"],
        "use_constraints": [
            "dt_id is a WEEKLY snapshot. Filter ONE dt_id (latest = MAX(dt_id)); never sum across dt_id.",
            "Values are absolute counts. Share = network_5g_total_customers_ioh / network_5g_total_customers_total_abs, recomputed after SUM over kabkota.",
            "Different population from rham_report_fb_network_5g; do not mix the two in one ratio.",
        ],
    },
    "rham_ga_new_imei_mtd": {
        "grain": "monthly_cutoff_x_brand_x_site",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["acquisition", "device mix", "5g device"],
        "aliases": ["imei baru", "device baru", "new device ga", "ga imei",
                    "gross add device baru"],
        "use_constraints": [
            "dt_id holds ONE cutoff date per month, not a daily series. Filter it "
            "to a single literal date (or join MAX(dt_id) for the wanted month); "
            "summing across dt_id values double counts the same month.",
            "ga_all = ga_old_imei + ga_new_imei + remainder. The _5g columns are a "
            "SUBSET of their old/new counterparts, never add them on top.",
        ],
    },
    "rham_ga_new_imei_mth": {
        "grain": "monthly_cutoff_x_brand_x_site",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["acquisition", "device mix", "5g device"],
        "aliases": ["imei baru bulanan", "device baru bulanan", "new device ga monthly"],
        "use_constraints": [
            "dt_id holds ONE snapshot date per month. Filter to a single literal "
            "date per month; never sum across dt_id.",
        ],
    },
    "rham_outlet_ga_quality_mtd": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention",
                            "device mix", "revenue"],
        "aliases": ["kualitas ga outlet", "outlet ga quality", "survival outlet",
                    "kualitas akuisisi outlet"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "cutoff_dd is a constant 14, so this month and last month are already "
            "day-aligned. Use this table for any MTD or month-on-month comparison.",
            "m1s/m2s/m3s are SURVIVING subscriber counts, not rates. Compute a "
            "survival rate as SUM(m1s)/SUM(rgu_ga), never as AVG of a ratio.",
            "outlet_latitude and outlet_longitude contain corrupt values (observed "
            "-620 and 946). Do not use them for distance or mapping.",
        ],
    },
    "rham_outlet_ga_quality_mth": {
        "grain": "month_x_brand_x_outlet",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention",
                            "device mix", "revenue"],
        "aliases": ["kualitas ga outlet bulanan", "outlet ga quality monthly"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "outlet_latitude and outlet_longitude contain corrupt values. Do not "
            "use them for distance or mapping.",
        ],
    },
    "rham_outlet_ga_quality": {
        "grain": "ga_date_x_brand_x_outlet_x_channel",
        "period_semantics": "daily_within_month_partition",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention",
                            "device mix", "revenue"],
        "aliases": ["kualitas ga outlet harian", "outlet ga quality detail",
                    "ga outlet per channel"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "Use this only when the question needs the channel or acquisition-date "
            "detail. For a period total prefer the _mtd or _mth table.",
            "m1s/m2s/m3s are surviving counts. Rate = SUM(m1s)/SUM(rgu_ga).",
            "outlet_latitude and outlet_longitude contain corrupt values. Do not "
            "use them for distance or mapping.",
        ],
    },
    "rham_outlet_ga_quality_dtu": {
        "grain": "ga_date_x_brand_x_outlet_x_channel_x_sp_source",
        "period_semantics": "daily_within_month_partition",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "outlet distribution", "retention"],
        "aliases": ["dtu", "non dtu", "outlet dtu", "sp source"],
        "warning_columns": ["outlet_latitude", "outlet_longitude"],
        "use_constraints": [
            "sp_source splits DTU from NON-DTU. Filter it for one population, or "
            "GROUP BY it to compare. For a plain NON-DTU total the reviewed "
            "rham_outlet_ga_ex_dtu / rham_outlet_ga_mth_ex_dtu tables are cheaper.",
        ],
    },
    "rham_outlet_low_stock": {
        "grain": "date_x_brand_x_outlet_x_kpi",
        "period_semantics": "daily",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["outlet distribution", "stock availability"],
        # "stoknya" is how the question is actually asked; the tokenizer does not
        # strip Indonesian suffixes, so the bare stem has to be an alias too.
        "aliases": ["low stock", "stok rendah", "stoknya", "stok", "kehabisan stok",
                    "stock outlet", "ketersediaan stok", "stock availability"],
        "use_constraints": [
            "One row per KPI: ALWAYS filter `kpi` to the metric you mean, otherwise "
            "unrelated KPIs are summed together.",
            "mtd/lmtd/llmtd and W-0..W-6 are period columns, not stock levels. A "
            "NULL means that period is unavailable, it does not mean zero.",
            "35 GB table: a literal dt_id filter is mandatory, never a MAX() "
            "subquery or an open range.",
        ],
    },
    "rham_outlet_secondary_mtd": {
        "grain": "month_x_brand_x_outlet_x_price_point",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["secondary sales", "outlet distribution", "revenue"],
        "aliases": ["secondary sales", "penjualan sekunder", "sellin saldo",
                    "transaksi outlet"],
        "use_constraints": [
            "NOT unique on month_id+brand+outlet_id+main_price (measured 1163942 "
            "rows against 1150707 distinct keys). Always SUM with a GROUP BY; never "
            "assume one row per outlet.",
            "amount and hit are separate units. ARPT = SUM(amount)/SUM(hit).",
        ],
    },
    "rham_outlet_secondary_mth": {
        "grain": "month_x_brand_x_outlet_x_price_point",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["secondary sales", "outlet distribution", "revenue"],
        "aliases": ["secondary sales bulanan", "penjualan sekunder bulanan"],
        "use_constraints": [
            "Always SUM with a GROUP BY. amount and hit are separate units.",
        ],
    },
    "rham_outlet_secondary_daily": {
        "grain": "date_x_brand_x_outlet_x_price_point",
        "period_semantics": "daily",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["secondary sales", "outlet distribution", "revenue"],
        "aliases": ["secondary sales harian", "transaksi outlet harian"],
        "use_constraints": [
            "14.7 GB: a literal dt_id range is mandatory. Prefer the _mtd or _mth "
            "table for any period total.",
        ],
    },
    "rham_postpaid_ga_daily": {
        "grain": "activation_date_x_store_x_channel_x_order_x_package",
        "period_semantics": "daily",
        "aggregation_rule": "sum_additive_metrics",
        "metric_families": ["acquisition", "postpaid", "revenue"],
        "aliases": ["postpaid", "pascabayar", "ga postpaid", "gross add postpaid"],
        "use_constraints": [
            "Partition column is activation_date, not dt_id.",
            "acq_revenue_mio and guaranteed_revenue_mio are already in MILLIONS of "
            "rupiah. Do not divide by 1e6 again.",
        ],
    },
    "rham_report_fb_device_5g": {
        "source_kind": "proxy",
        "grain": "date_x_location_type_x_location",
        "period_semantics": "weekly_snapshot",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["market share", "5g device", "churn", "acquisition"],
        "aliases": ["market share 5g device", "pangsa pasar device 5g",
                    "5g device share", "ms device 5g"],
        "use_constraints": [
            "Population is subscribers OWNING a 5G-capable device. Never mix it "
            "with rham_report_fb_network_5g, which counts 5G network USERS.",
            "ms_* and soga_* are FRACTIONS between 0 and 1 (observed max 0.745). "
            "Multiply by 100 for a percentage; never sum them across rows.",
            "location_type holds several territory levels in one column. ALWAYS "
            "filter to exactly one location_type or levels are double counted.",
            "ga_amount_* is populated on only about 79 percent of rows.",
        ],
    },
    "rham_report_fb_network_5g": {
        "source_kind": "proxy",
        "grain": "date_x_location_type_x_location",
        "period_semantics": "weekly_snapshot",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["market share", "5g network", "churn", "acquisition"],
        "aliases": ["market share pengguna 5g", "5g network share",
                    "pangsa pengguna jaringan 5g"],
        "use_constraints": [
            "Population is subscribers USING the 5G network. Never mix it with "
            "rham_report_fb_device_5g, which counts 5G device owners.",
            "ms_* and soga_* are FRACTIONS between 0 and 1, not percentages.",
            "ALWAYS filter to exactly one location_type.",
            "ga_amount_* is populated on only about 26 percent of rows, so a "
            "gross-add answer from this table must state that coverage.",
        ],
    },
    "rham_site_ga_quality_mtd": {
        "grain": "month_x_site_x_brand",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "retention", "device mix", "revenue"],
        "aliases": ["kualitas ga site", "site ga quality", "qsc", "survival site"],
        "use_constraints": [
            "dt_id is a within-month cutoff. Filter to one literal dt_id per month; "
            "summing across dt_id double counts.",
            "ga_qsc_* and m1s/m2s/m3s are COUNTS. A rate is SUM(part)/SUM(rgu_ga).",
        ],
    },
    "rham_site_ga_quality_mth": {
        "grain": "month_x_site_x_brand",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "retention", "device mix", "revenue"],
        "aliases": ["kualitas ga site bulanan", "site ga quality monthly"],
        "use_constraints": [
            "dt_id is a within-month cutoff. Filter to one literal dt_id per month.",
            "ga_qsc_* and m1s/m2s/m3s are COUNTS, not rates.",
        ],
    },
    "rham_site_ga_quality_daily": {
        "grain": "date_x_site_x_brand",
        "period_semantics": "daily",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["acquisition", "retention", "device mix"],
        "aliases": ["kualitas ga site harian"],
        "use_constraints": [
            "12 GB: literal dt_id range mandatory. Prefer _mtd or _mth for period "
            "totals.",
        ],
    },
    "rham_site_traffic_usage_mtd": {
        "grain": "as_of_date_x_site_x_pack_channel_segment",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["traffic", "revenue", "product demand"],
        "aliases": ["traffic usage", "pemakaian traffic", "run rate traffic",
                    "proyeksi traffic"],
        "use_constraints": [
            "Partition column is as_of_date. LMTD columns are already day-aligned, "
            "so never build a second MTD comparison by hand.",
            "g_*_pct, vs_lm_full_pct, growth_index and pp_contribution_to_growth "
            "are ratios. Recompute them from the MTD and LMTD components when "
            "aggregating; never average them.",
        ],
    },
    "rham_site_traffic_usage_mth": {
        "grain": "month_x_site_x_pack_channel_segment",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["traffic", "revenue", "product demand"],
        "aliases": ["traffic usage bulanan", "quota utilization", "fully burning"],
        "use_constraints": [
            "57 GB and 334M rows. month_id is a DATE (for example DATE '2026-07-01'), "
            "NOT a 'YYYYMM' string. Filter it to a LITERAL date; a MAX() subquery or "
            "a join to a MAX() CTE scans every partition.",
            "avg_quota_utilization, pct_fully_burning and btl_rev_share are ratios. "
            "Weight them by subs_cnt or recompute from components.",
        ],
    },
    "rham_kec_wise_tnr_mtd": {
        "grain": "month_x_kecamatan_x_brand_x_tenure_group",
        "period_semantics": "mtd_cutoff_aligned",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["revenue", "traffic", "churn", "acquisition",
                            "subscriber segment"],
        "aliases": ["tenure", "tnr", "kecamatan tenure", "tenure group",
                    "kpi kecamatan tenure"],
        "warning_columns": [
            "acq_ga_inject", "acq_ga_inject_hv", "acq_ga_inject_lv",
            "acq_ga_inject_mv", "acq_qsc_m0", "acq_sc_m0", "data_uu_istimewa_30d",
            "hits_rebuy_lrs_site", "hits_sp_lrs_site", "rev_acq_qsc_m0",
            "rev_data_atl_mtd", "rev_data_btl_mtd", "rev_ewallet",
            "rev_ewallet_site", "rev_fdv", "rev_fdv_data_site", "rev_fdv_site",
            "rev_fdv_sms_site", "rev_fdv_voice_site", "rev_mobo_data_site",
            "rev_mobo_sms_site", "rev_mobo_voice_site", "rev_mobosp",
            "rev_mobosp_site", "rev_nondata_others",
        ],
        "use_constraints": [
            "dt_id is a within-month CUTOFF, not a daily series: the latest dt_id "
            "carries the whole month. Filter month_id to one literal value and take "
            "the MAX(dt_id) inside it; summing across dt_id double counts.",
            "68 of the 184 numeric columns are entirely EMPTY (see warning_columns). "
            "Ranking on one of them returns nothing and looks like missing data.",
            "Columns mix daily, rolling-30-day and MTD semantics. Match the suffix "
            "to the question: _daily, _30d and _mtd are not interchangeable.",
        ],
    },
    "rham_kec_wise_tnr_mth": {
        "grain": "month_x_kecamatan_x_brand_x_tenure_group",
        "period_semantics": "monthly_closed",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "metric_families": ["revenue", "traffic", "churn", "acquisition",
                            "subscriber segment"],
        "aliases": ["tenure bulanan", "tnr monthly", "kecamatan tenure bulanan"],
        "warning_columns": [
            "hits_rebuy_lrs_site", "hits_sp_lrs_site", "rev_fdv_sms_site",
            "rev_fdv_voice_site", "rev_mobo_sms_site", "rev_mobo_voice_site",
            "rev_org_sms_alloc_site", "rev_org_voice_alloc_site",
            "rev_rebuy_lrs_site", "rev_sms_voucher_site", "rev_sp_lrs_site",
            "rev_vas_net_dcb", "rev_vas_net_dcb_mtd", "rev_vchori_sms_site",
            "rev_vchori_voice_site", "rev_voucher_games_site",
            "rgu90_gross_add_lrs_non_ol_site", "rgu90_gross_add_lrs_ol_site",
        ],
        "use_constraints": [
            "Filter month_id to one literal value and take MAX(dt_id) inside it.",
            "18 numeric columns are entirely EMPTY (see warning_columns).",
            "Columns mix daily, rolling-30-day and MTD semantics.",
        ],
    },
    "rham_ftth_tt_mttr": {
        "grain": "period_x_mttr_bucket",
        "period_semantics": "mixed_weekly_and_monthly",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "territory_vocabulary": "not_territorial",
        "metric_families": ["ftth", "trouble ticket", "restoration time"],
        "aliases": ["mttr", "trouble ticket", "gangguan ftth", "waktu perbaikan",
                    "restorasi ftth"],
        "use_constraints": [
            "ALWAYS filter period_type to either 'MONTHLY' or 'WEEKLY'. The table "
            "holds both, and mixing them double counts every ticket.",
            "The bucket column contains a 'Grand Total' row alongside the real "
            "buckets. Exclude it when summing, or use it directly as the total.",
            "mttr_hours is an AVERAGE per bucket. Weight it by tt_count; never "
            "average it across buckets.",
            "source_scope is VENDOR only, so this covers vendor-handled tickets.",
        ],
    },
}


def _atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


# Upstream SND contract reviewed on 2026-10-08. These aliases identify actual
# unified metrics, not the retired brand-specific raw parameters.
for _snd_period in ("dly", "mtd", "mth"):
    CONTRACT_OVERRIDES[f"rham_snd_kpi_highlevel_{_snd_period}"] = {
        "grain": "kecamatan_x_brand",
        "priority": "primary",
        "aliases": ["total outlet", "outlet total", "ono", "osa", "sso", "uro",
                    "quro", "qsso", "trade supply", "trade demand", "tertiary b",
                    "outlet per region", "outlet bulan lalu"],
        "metric_families": ["outlet distribution", "acquisition", "retention",
                            "trade supply", "trade demand", "gaming", "fwa"],
        "use_constraints": [
            "Use only the unified metric columns in the live schema; raw "
            "IM3/3ID parameters without a mapped metric are not loaded.",
            "kec_unik joins to rham_ref_territory.kec_id. Use outlet_total for "
            "total outlet, quro for QURO and qsso_m0 for QSSO. Quote `primary`.",
            "RGU/VLR/prepaid revenue belong to the approved Marketing highlevel "
            "sources, not these reduced SND tables.",
        ],
    }


def _schema_hash(item: dict[str, Any]) -> str:
    fields = [
        {"name": col.get("name"), "type": col.get("type"), "mode": col.get("mode")}
        for col in item.get("columns", [])
    ]
    return hashlib.sha256(
        json.dumps(fields, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _physical_hash(item: dict[str, Any]) -> str:
    """Hash the physical contract the SQL writer depends on.

    Kept SEPARATE from `_schema_hash` on purpose: folding partitioning into the
    column hash would mark all 238 reviewed records drifted at once, which would
    force a blind mass re-review and destroy the signal. A partition or
    clustering change is still a review trigger, because a query written against
    the old partition column silently scans the whole table.
    """
    return hashlib.sha256(
        json.dumps(
            {
                "object_type": item.get("type", "TABLE"),
                "partition_field": item.get("partition_field"),
                "partition_type": item.get("partition_type"),
                "clustering_fields": item.get("clustering_fields") or [],
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


def _object_class(name: str, item: dict[str, Any]) -> str:
    lower = name.lower()
    if item.get("type") == "VIEW":
        return "view"
    if "__bak" in lower or lower.endswith("_backup") or "_bak_" in lower:
        return "backup"
    if lower.endswith("_raw") or "_raw_" in lower:
        return "raw"
    if lower.endswith("_stg") or lower.endswith("_upd"):
        return "staging"
    if lower.startswith("zz_") or "rejected_records" in lower or lower.endswith("_params"):
        return "helper"
    return "aggregate"


def _decision_for(
    name: str, item: dict[str, Any], existing_tables: dict[str, str]
) -> dict[str, Any]:
    object_class = _object_class(name, item)
    if name in PREVIOUSLY_REJECTED:
        return {
            "lifecycle": "rejected",
            "policy": "hard_block",
            "domain": None,
            "reason": PREVIOUSLY_REJECTED[name],
        }
    if name in QUARANTINE_EXACT:
        return {
            "lifecycle": "quarantined",
            "policy": "hard_block",
            "domain": None,
            "reason": QUARANTINE_EXACT[name],
        }
    if name in APPROVED_NEW:
        return {
            "lifecycle": "approved",
            "policy": "runtime_allowed",
            "domain": APPROVED_NEW[name],
            "reason": "Reviewed aggregate or observed source approved by the design panel.",
        }
    if name in existing_tables:
        return {
            "lifecycle": "approved",
            "policy": "runtime_allowed",
            "domain": existing_tables[name],
            "reason": "Existing runtime KB table retained after governance audit.",
        }
    if object_class in {"backup", "raw", "staging", "helper"}:
        return {
            "lifecycle": "quarantined",
            "policy": "hard_block",
            "domain": None,
            "reason": f"Object class {object_class} is unavailable to general chat.",
        }
    if name.startswith("rham_ftth_ins_") or name.startswith("rham_pag_") or name.startswith("v_dashboard_"):
        return {
            "lifecycle": "candidate",
            "policy": "not_runtime_allowed",
            "domain": "ftth" if name.startswith("rham_ftth") else "kpi_summary",
            "reason": "Derived or recommendation output requires formula ownership and backtest review.",
        }
    if name in {"rham_fwa_area_score", "rham_fwa_outlet_score"}:
        return {
            "lifecycle": "candidate",
            "policy": "not_runtime_allowed",
            "domain": "fwa",
            "reason": "Scoring output requires formula ownership and validation before promotion.",
        }
    return {
        "lifecycle": "candidate",
        "policy": "not_runtime_allowed",
        "domain": None,
        "reason": "New object discovered. Semantic and business-value review is pending.",
    }


def _inventory_columns(client: Any, table: Any) -> list[dict[str, Any]]:
    schema = table.schema
    if table.table_id in {
        "rham_hvc_highlevel_mtd_serving", "rham_hvc_highlevel_mth_serving",
    }:
        # SELECT * views can retain obsolete names in their stored metadata.
        # Resolve their output without executing or scanning the backing tables.
        from google.cloud import bigquery

        probe = client.query(
            f"SELECT * FROM `{table.full_table_id.replace(':', '.')}` WHERE FALSE",
            job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False),
            location=config.BQ_LOCATION,
        )
        schema = probe.schema
        if not schema:
            raise ValueError(f"Could not resolve live view schema: {table.table_id}")
    return [
        {"name": field.name, "type": field.field_type, "mode": field.mode,
         "description": field.description}
        for field in schema
    ]


def _live_inventory() -> dict[str, Any]:
    from app.bigquery_tool import get_client

    client = get_client()
    dataset_ref = f"{config.BQ_PROJECT}.{config.BQ_DATASET}"
    tables = []
    for summary in client.list_tables(dataset_ref):
        table = client.get_table(summary.reference)
        tables.append({
            "name": table.table_id,
            "type": summary.table_type,
            "rows": int(table.num_rows or 0),
            "bytes": int(table.num_bytes or 0),
            "modified": table.modified.isoformat() if table.modified else None,
            "partition_field": getattr(table.time_partitioning, "field", None),
            "partition_type": str(getattr(table.time_partitioning, "type_", "")) or None,
            "clustering_fields": table.clustering_fields or [],
            "description": table.description,
            "columns": _inventory_columns(client, table),
        })
    return {"project": config.BQ_PROJECT, "dataset": config.BQ_DATASET, "tables": tables}


def load_inventory(path: Path | None) -> dict[str, Any]:
    return json.loads(path.read_text()) if path else _live_inventory()


def _existing_table_domains(kb: dict[str, Any]) -> dict[str, str]:
    return {
        name: domain_key
        for domain_key, domain in kb.get("domains", {}).items()
        for name in domain.get("tables", {})
    }


def build_governance(inventory: dict[str, Any], kb: dict[str, Any]) -> dict[str, Any]:
    existing = _existing_table_domains(kb)
    records = {}
    for item in sorted(inventory.get("tables", []), key=lambda row: row["name"]):
        name = item["name"]
        decision = _decision_for(name, item, existing)
        records[name] = {
            "lifecycle": decision["lifecycle"],
            "object_class": _object_class(name, item),
            "policy": decision["policy"],
            "domain": decision["domain"],
            "reason": decision["reason"],
            "review_id": REVIEW_ID,
            "schema_hash": _schema_hash(item),
            "decision_history": [{
                "review_id": REVIEW_ID,
                "decision": decision["lifecycle"],
                "reason": decision["reason"],
                "reviewed_at": "2026-08-19",
            }],
            "replacement_table": (
                "rham_report_fb_ms_kabkota" if name == "rham_fb_ms_kabkota_v2"
                else "rham_report_fb_ms_kecamatan" if name == "rham_fb_ms_kecamatan_v2"
                else None
            ),
        }
    return {
        "schema_version": 1,
        "tool_version": TOOL_VERSION,
        "project": inventory.get("project"),
        "dataset": inventory.get("dataset"),
        "review_id": REVIEW_ID,
        "reversal_policy": (
            "A rejected or quarantined decision can change only through a new reviewed "
            "history entry with reviewer, evidence, and explicit override=true."
        ),
        "objects": records,
    }


def merge_catalog(
    inventory: dict[str, Any], governance: dict[str, Any]
) -> dict[str, Any]:
    governed = governance.get("objects", {})
    tables = []
    new_objects: list[str] = []
    schema_drift: list[dict[str, Any]] = []
    partition_drift: list[dict[str, Any]] = []
    for item in sorted(inventory.get("tables", []), key=lambda row: row["name"]):
        decision = governed.get(item["name"])
        if decision is None:
            new_objects.append(item["name"])
            decision = {
                "lifecycle": "candidate",
                "object_class": _object_class(item["name"], item),
                "policy": "not_runtime_allowed",
                "domain": None,
                "reason": "Discovered after the last review. Promotion is pending.",
                "review_id": None,
                "schema_hash": _schema_hash(item),
            }
        else:
            live_schema = _schema_hash(item)
            if decision.get("schema_hash") != live_schema:
                schema_drift.append({
                    "name": item["name"],
                    "lifecycle": decision.get("lifecycle"),
                    "reviewed": decision.get("schema_hash"),
                    "live": live_schema,
                })
            # Absent on records written before physical hashing existed. Treat the
            # missing value as "not yet reviewed" rather than as drift, so the
            # first run does not flag every pre-existing record.
            reviewed_physical = decision.get("physical_hash")
            live_physical = _physical_hash(item)
            if reviewed_physical is not None and reviewed_physical != live_physical:
                partition_drift.append({
                    "name": item["name"],
                    "lifecycle": decision.get("lifecycle"),
                    "reviewed": reviewed_physical,
                    "live": live_physical,
                    "partition_field": item.get("partition_field"),
                })
        tables.append({**item, "governance": decision})
    live_names = {item["name"] for item in inventory.get("tables", [])}
    missing = sorted(set(governed) - live_names)
    missing_approved = sorted(
        name for name in missing
        if governed.get(name, {}).get("lifecycle") == "approved"
    )
    return {
        "schema_version": 1,
        "tool_version": TOOL_VERSION,
        "project": inventory.get("project"),
        "dataset": inventory.get("dataset"),
        "audited_at": datetime.now(timezone.utc).isoformat(),
        "tables": tables,
        "missing_governed_objects": missing,
        "delta": {
            "new_objects": new_objects,
            "missing_governed_objects": missing,
            "missing_approved_objects": missing_approved,
            "schema_drift": schema_drift,
            "partition_drift": partition_drift,
        },
        "summary": {
            "live_objects": len(tables),
            "approved": sum(t["governance"]["lifecycle"] == "approved" for t in tables),
            "candidate": sum(t["governance"]["lifecycle"] == "candidate" for t in tables),
            "quarantined": sum(t["governance"]["lifecycle"] == "quarantined" for t in tables),
            "rejected": sum(t["governance"]["lifecycle"] == "rejected" for t in tables),
            "superseded": sum(t["governance"]["lifecycle"] == "superseded" for t in tables),
            "new_objects": len(new_objects),
            "missing_governed": len(missing),
            "missing_approved": len(missing_approved),
            "schema_drift": len(schema_drift),
            "partition_drift": len(partition_drift),
        },
    }


def validate_catalog(catalog: dict[str, Any]) -> list[str]:
    """Discovery-level gate. An unreviewed change must fail `--check` loudly.

    Without this, a new table, a dropped approved table, or a changed schema all
    exited zero, so a daily audit reported success while the runtime KB silently
    described a warehouse that no longer existed.
    """
    delta = catalog.get("delta") or {}
    errors: list[str] = []
    for name in delta.get("new_objects", []):
        errors.append(f"ungoverned new object: {name}")
    for name in delta.get("missing_approved_objects", []):
        errors.append(f"approved object is missing from the live dataset: {name}")
    for entry in delta.get("schema_drift", []):
        if entry.get("lifecycle") == "approved":
            errors.append(f"approved object has unreviewed schema drift: {entry['name']}")
    for entry in delta.get("partition_drift", []):
        if entry.get("lifecycle") == "approved":
            errors.append(
                f"approved object has unreviewed partition drift: {entry['name']}")
    return errors


def _normalize_type(value: str) -> str:
    return {
        "INTEGER": "INT64",
        "FLOAT": "FLOAT64",
        "BOOLEAN": "BOOL",
    }.get(value, value)


def _column_description(name: str, ctype: str = "") -> str:
    lower = name.lower()
    exact = {
        "dt_id": "Tanggal data.",
        "month_id": "Periode bulan.",
        "mth_dt": "Tanggal awal bulan dan kolom partisi bila ditandai.",
        "site_id": "ID site.",
        "kec_id": "ID unik kecamatan.",
        "kabkot": "Nama kabupaten atau kota.",
        "kabkot_nm": "Nama kabupaten atau kota.",
        "brand": "Brand atau operator pada baris.",
        "revenue": "Revenue dalam rupiah.",
        "hit": "Jumlah transaksi.",
        "bill_acc": "Nomor billing account pelanggan (data pribadi, diblokir).",
        "customer_id": "ID pelanggan (data pribadi, diblokir).",
        "customer_name": "Nama pelanggan (data pribadi, diblokir).",
        "sales_code": "Kode sales (identitas sales, diblokir).",
        "sales_name": "Nama sales (identitas sales, diblokir).",
        "manager": "Nama manager sales (identitas, diblokir).",
        "rm": "Nama regional manager (identitas, diblokir).",
        "remark": "Catatan bebas status order.",
        "age": "Umur atau kelompok umur pelanggan.",
        "location": "Nama lokasi.",
        "dati_ii": "Daerah tingkat II (kabupaten/kota).",
        "twr_owner": "Pemilik tower (TowerCo).",
        "scope_of_work": "Lingkup pekerjaan proyek site.",
        "update_time": "Waktu update data.",
        "morphology": "Morfologi area (urban, suburban, rural).",
    }
    if lower in exact:
        return exact[lower]
    if re.fullmatch(r"addfield\d+", lower):
        return "Field tambahan generik dari sumber; isi tidak terdokumentasi, jangan dipakai sebagai metrik."
    if "revenue" in lower or lower.startswith("rev_"):
        return "Metrik revenue. Jaga unit rupiah dan grain table."
    if "traffic" in lower:
        return "Metrik traffic. Gunakan unit yang dinyatakan oleh nama kolom."
    if "ratio" in lower or "rate" in lower or "pct" in lower or "share" in lower:
        return "Rasio atau persentase. Jangan dijumlahkan antar baris."
    if "sample" in lower:
        return "Jumlah sampel untuk pembobotan atau validasi coverage."
    if lower.startswith("sum_") or lower.startswith("total_"):
        return "Metrik agregat pada grain table."
    def term(token: str) -> str | None:
        unit = re.fullmatch(r"(\d+)(mb|gb|k|mn|m|d|mbps)", token)
        if unit:
            return f"{unit.group(1)} {COLUMN_UNITS[unit.group(2)]}"
        if re.fullmatch(r"w-?\d", token):
            return f"minggu ke-{token[-1]} sebelumnya"
        return COLUMN_TERMS.get(token)
    tokens = [lower] if re.fullmatch(r"w-\d", lower) else re.split(r"[_\-]+", lower)
    terms = list(dict.fromkeys(filter(None, map(term, tokens))))
    # ponytail: token glossary, not per-column curation. Curated desc in the KB
    # always wins (promote keeps it); refine a column there when wording matters.
    if not terms:
        return ("Atribut " if ctype == "STRING" else "Kolom ") + f"{name} pada grain table."
    kind = "Atribut" if ctype in ("STRING", "BOOL", "BOOLEAN") else (
        "Tanggal" if ctype in ("DATE", "DATETIME", "TIMESTAMP") else "Metrik")
    return f"{kind}: {', '.join(terms)}."


COLUMN_UNITS = {"mb": "MB", "gb": "GB", "k": "ribu", "mn": "juta", "m": "meter", "d": "hari", "mbps": "Mbps"}

# Telco vocabulary used to describe columns nobody curated. Keys are lowercase
# name tokens split on "_" or "-".
COLUMN_TERMS = {
    "fwa": "FWA", "ftth": "FTTH", "5g": "5G", "4g": "4G", "2g": "2G", "lte": "LTE", "volte": "VoLTE",
    "ga": "gross add", "grossadd": "gross add", "gaq": "kualitas gross add", "qga": "kualitas gross add",
    "rev": "revenue (Rp)", "revenue": "revenue (Rp)", "arpu": "ARPU", "amt": "nilai (Rp)", "amount": "nilai (Rp)",
    "rgu": "RGU", "rgu90": "RGU 90 hari", "rgu30": "RGU 30 hari", "rgu90d": "RGU 90 hari", "rgu30d": "RGU 30 hari",
    "rguga": "RGU gross add", "subs": "pelanggan", "subscriber": "pelanggan", "customers": "pelanggan",
    "customer": "pelanggan", "msisdn": "MSISDN", "vlr": "VLR", "pau": "pelanggan aktif unik",
    "uu": "unique user", "datauu": "data unique user", "datauu30d": "data unique user 30 hari",
    "churn": "churn", "churn90": "churn 90 hari", "churn90d": "churn 90 hari", "churn30": "churn 30 hari",
    "grosschurn90": "gross churn 90 hari", "churnback90": "churn back 90 hari",
    "churnback90d": "churn back 90 hari", "churnback30": "churn back 30 hari", "back": "kembali",
    "cb90": "churn back 90 hari", "gc90": "gross churn 90 hari", "gross": "gross", "net": "net",
    "nett": "net", "add": "add", "adds": "add", "netadd": "net add", "closing": "closing", "opening": "opening",
    "qsc": "quality subscriber (QSC)", "sso": "SSO", "qsso": "quality SSO", "uro": "URO", "quro": "quality URO",
    "m0": "bulan akuisisi M0", "m1": "bulan M1", "m2": "bulan M2", "m3": "bulan M3",
    "m1s": "survivor M1", "m2s": "survivor M2", "m3s": "survivor M3", "surv": "survival",
    "p1m": "pack 1 bulan", "p2m": "pack 2 bulan",
    "data": "data", "voice": "voice", "sms": "SMS", "usg": "usage", "usage": "usage", "trfc": "traffic",
    "datavol": "volume data", "vol": "volume", "gb": "GB", "mb": "MB", "min": "menit", "hit": "transaksi",
    "hits": "transaksi", "trx": "transaksi", "cnt": "jumlah", "count": "jumlah", "num": "jumlah",
    "numerator": "numerator", "den": "denominator", "denum": "denominator", "eutnum": "numerator EUT",
    "eutdenum": "denominator EUT", "prbnum": "numerator PRB", "prbdenum": "denominator PRB",
    "pack": "pack", "packs": "pack", "packsubs": "pelanggan pack", "sp": "starter pack", "vou": "voucher",
    "voucher": "voucher", "mobo": "MOBO", "trade": "trade", "trad": "traditional", "traditional": "traditional",
    "nontrade": "non-trade", "organic": "organic", "digital": "digital", "online": "online",
    "hvc": "high value customer", "mvc": "medium value customer", "lvc": "low value customer",
    "hv": "high value", "mv": "medium value", "lv": "low value", "postpaid": "postpaid", "prepaid": "prepaid",
    "acq": "akuisisi", "inject": "inject", "inj": "inject", "noinj": "tanpa inject", "rebuy": "rebuy",
    "recharge": "isi ulang", "reload": "isi ulang", "sellin": "sell-in", "secondary": "secondary sales",
    "tertiary": "tertiary sales", "primary": "primary", "saldo": "saldo", "cashback": "cashback",
    "koin": "koin", "redeem": "redeem", "rdm": "redeem",
    "site": "site", "cell": "cell", "outlet": "outlet", "outlets": "outlet", "outletcnt": "jumlah outlet",
    "gerai": "gerai", "store": "store", "retailer": "retailer", "pjp": "PJP", "atl": "ATL", "sachet": "sachet",
    "addr": "addressable site", "addressable": "addressable", "base": "base", "new": "baru", "old": "lama",
    "imei": "IMEI", "device": "device", "dev": "device", "esim": "eSIM", "sim": "SIM", "os": "OS",
    "circle": "circle", "region": "region", "area": "area", "branch": "branch", "cluster": "cluster",
    "micro": "micro", "mc": "micro cluster", "kecamatan": "kecamatan", "kec": "kecamatan",
    "kabkota": "kabupaten/kota", "kabkot": "kabupaten/kota", "province": "provinsi", "city": "kota",
    "territory": "territory", "partner": "partner", "java": "Jawa", "nonjava": "luar Jawa",
    "urban": "urban", "rural": "rural", "latitude": "latitude", "longitude": "longitude",
    "lat": "latitude", "lon": "longitude", "coord": "koordinat", "geog": "geografi",
    "dt": "tanggal", "date": "tanggal", "month": "bulan", "mth": "bulan", "week": "minggu",
    "weekly": "mingguan", "daily": "harian", "dly": "harian", "daiy": "harian", "monthly": "bulanan",
    "day": "hari", "days": "hari", "year": "tahun", "period": "periode", "snapshot": "snapshot",
    "mtd": "MTD", "lmtd": "LMTD", "llmtd": "LLMTD", "llm": "LLM", "ytd": "YTD", "lytd": "LYTD", "yoy": "YoY",
    "30d": "30 hari", "90d": "90 hari", "180d": "180 hari", "7d": "7 hari", "91d": "91 hari",
    "4week": "4 minggu", "avg4week": "rata-rata 4 minggu", "cons4wk": "4 minggu berturut",
    "avg": "rata-rata", "mean": "rata-rata", "median": "median", "p10": "persentil 10",
    "p90": "persentil 90", "p995": "persentil 99.5", "p999": "persentil 99.9", "total": "total",
    "tot": "total", "abs": "absolut", "pct": "persen", "percentage": "persen", "percent": "persen",
    "perc": "persen", "ratio": "rasio", "share": "share", "ms": "market share", "soga": "share of gross add",
    "score": "skor", "flag": "flag", "is": "flag", "has": "flag", "status": "status", "type": "tipe",
    "category": "kategori", "class": "kelas", "classification": "klasifikasi", "segment": "segmen",
    "seg": "segmen", "group": "grup", "tier": "tier", "grade": "grade", "bucket": "bucket",
    "name": "nama", "nm": "nama", "id": "ID", "code": "kode", "desc": "deskripsi",
    "ioh": "IOH", "im3": "IM3", "3id": "3ID", "tsel": "Telkomsel", "xl": "XL", "xls": "XLSmart",
    "sf": "Smartfren", "industry": "industri", "fb": "Facebook benchmark", "ookla": "Ookla benchmark",
    "speed": "kecepatan", "download": "download", "downloadspeed": "kecepatan download",
    "upload": "upload", "uploadspeed": "kecepatan upload", "dl": "downlink", "ul": "uplink",
    "tput": "throughput", "thp": "throughput", "throughput": "throughput", "mbps": "Mbps",
    "latency": "latency", "jitter": "jitter", "rtt": "round-trip time", "delay": "delay",
    "video": "video", "vid": "video", "streaming": "streaming", "strm": "streaming", "stall": "stall",
    "youtube": "YouTube", "tiktok": "TikTok", "facebook": "Facebook", "instagram": "Instagram",
    "whatsapp": "WhatsApp", "web": "web", "browsing": "browsing", "game": "game",
    "gamesexperience": "game experience", "videoexperience": "video experience",
    "livevideoexperience": "live video experience", "voiceappexperience": "voice app experience",
    "coverageexperience": "coverage experience", "experience": "experience", "qoe": "QoE",
    "avail": "availability", "availability": "availability", "avail2g": "availability 2G",
    "avail4g": "availability 4G", "avail5g": "availability 5G", "2gavail": "availability 2G",
    "4gavail": "availability 4G", "losshour": "jam hilang", "lowsite": "site availability rendah",
    "lowsite99": "site availability <99%", "lowsite80": "site availability <80%",
    "lowsite70": "site availability <70%", "rsrp": "RSRP", "rsrq": "RSRQ", "cqi": "CQI", "cssr": "CSSR",
    "dcr": "drop call rate", "ho": "handover", "hosr": "handover success rate", "cdr": "call drop rate",
    "prb": "PRB", "eutprb": "utilisasi PRB", "eut": "utilisasi E-UTRAN", "utilization": "utilisasi",
    "util": "utilisasi", "load": "load", "bh": "busy hour", "congest": "kongesti", "rb": "resource block",
    "mw": "microwave", "rf": "RF", "signal": "sinyal", "strength": "kekuatan", "peak": "puncak",
    "capacity": "kapasitas", "band": "band", "nr": "NR", "nr2600": "NR2600", "2600": "band 2600",
    "700": "band 700", "900": "band 900", "1800": "band 1800", "2100": "band 2100",
    "rollout": "rollout", "rfs": "ready for service", "rfi": "ready for installation", "caf": "CAF",
    "permit": "izin", "po": "purchase order", "vendor": "vendor", "program": "program", "project": "proyek",
    "projects": "proyek", "homepass": "homepass", "install": "instalasi", "order": "order", "so": "service order",
    "sa": "service activation", "pa": "permanent active", "aging": "aging", "mttr": "MTTR", "tt": "trouble ticket",
    "ticket": "tiket", "complaint": "komplain", "leads": "lead", "lead": "lead", "demand": "demand",
    "inner": "inner (dalam kecamatan)", "outer": "outer (luar kecamatan)", "source": "asal", "dest": "tujuan",
    "pop": "populasi", "population": "populasi", "density": "kepadatan", "road": "jalan",
    "junction": "persimpangan", "junctions": "persimpangan", "distance": "jarak", "dist": "jarak",
    "nearest": "terdekat", "spacing": "jarak antar", "tenure": "tenure", "aon90d": "AON 90 hari",
    "cohort": "kohort", "retention": "retensi", "productivity": "produktivitas", "quality": "kualitas",
    "forecast": "forecast", "target": "target", "actual": "aktual", "growth": "pertumbuhan",
    "degrowth": "penurunan", "gap": "gap", "upgrade": "upgrade", "downgrade": "downgrade",
    "migration": "migrasi", "channel": "channel", "chan": "channel", "product": "produk",
    "package": "paket", "price": "harga", "denom": "denominasi", "kpi": "KPI", "metric": "metrik",
    "value": "nilai", "sales": "sales", "selling": "penjualan", "sold": "terjual", "stock": "stok",
    "refreshed": "waktu refresh", "loaded": "waktu load", "built": "waktu build", "at": "waktu",
    "asof": "per tanggal", "cutoff": "cutoff", "w": "minggu", "wd": "hari kerja",
    "non": "non", "no": "tanpa", "plus": "ke atas", "above": "di atas", "upto": "sampai",
    "less": "kurang dari", "below": "di bawah", "low": "rendah", "high": "tinggi", "first": "pertama",
    "last": "terakhir", "overall": "keseluruhan", "connectivity": "konektivitas", "ori": "original",
    "rete": "rasio", "rate": "rasio", "stream": "streaming", "user": "user", "users": "user",
    "active": "aktif", "unik": "unik", "unknown": "tidak diketahui", "others": "lainnya",
    "all": "semua", "mapping": "pemetaan", "lrs": "LRS", "dse": "DSE", "kam": "KAM",
}


def _infer_grain(name: str, columns: list[dict[str, Any]]) -> str:
    names = {col.get("name", "").lower() for col in columns}
    if {"source_kec_id", "dest_kec_id"}.issubset(names):
        return "origin_destination_kecamatan"
    for column, grain in (
        ("outlet_id", "outlet"),
        ("site_id", "site"),
        ("kec_id", "kecamatan"),
        ("kecamatan", "kecamatan"),
        ("kabkot_nm", "kabkota"),
        ("kabkot", "kabkota"),
        ("branch", "branch"),
        ("area_id", "area"),
    ):
        if column in names:
            return grain
    if "segment" in name:
        return "subscriber_segment"
    if "migration_matrix" in name:
        return "pack_channel_migration"
    return "declared_dimensions"


def _infer_period(name: str, columns: list[dict[str, Any]]) -> str:
    if "_mtd" in name:
        return "mtd_cutoff_aligned"
    if name.endswith("_mth") or "monthly" in name:
        return "monthly"
    if "daily" in name or any(col.get("name") == "dt_id" for col in columns):
        return "daily"
    if "snapshot" in name:
        return "snapshot"
    return "latest_available"


def _infer_metrics(name: str, columns: list[dict[str, Any]]) -> list[str]:
    text = name + " " + " ".join(col.get("name", "") for col in columns)
    mapping = {
        "5g rollout": ["nr2600", "wbs_status", "rollout"],
        "5g experience": ["5g", "dl_speed", "latency"],
        "availability": ["avail", "downtime"],
        "acquisition": ["gross_add", "total_ga", "acquisition", "sellin"],
        "churn": ["churn"],
        "competitive network": ["network_comp", "fb_network"],
        "demand flow": ["source_kec_id", "dest_kec_id", "inner_outer"],
        "ftth": ["ftth", "homepass", "tur"],
        "fwa": ["fwa"],
        "gaming": ["game", "cp_name"],
        "outlet distribution": ["outlet", "uro", "sso", "snd"],
        "product demand": ["product", "ssd", "voucher"],
        "retention": ["retention", "surv_"],
        "revenue": ["revenue", "rev_"],
        "subscriber segment": ["subs_traffic", "segment_"],
        "traffic": ["traffic", "gb"],
    }
    lower = text.lower()
    metrics = [label for label, needles in mapping.items() if any(n in lower for n in needles)]
    return metrics or ["domain metrics"]


def _cost_tier(item: dict[str, Any]) -> str:
    size = int(item.get("bytes") or 0)
    if size >= 50 * 1024**3:
        return "very_high"
    if size >= 5 * 1024**3:
        return "high"
    if size >= 500 * 1024**2:
        return "medium"
    return "low"


def _contract(name: str, item: dict[str, Any]) -> dict[str, Any]:
    columns = item.get("columns", [])
    source_kind = "observed"
    if "forecast" in name:
        source_kind = "modelled"
    elif any(token in name for token in ("opensignal", "fb_ms", "fb_network", "network_comp")):
        source_kind = "proxy"
    ratios = [
        col.get("name") for col in columns
        if any(token in col.get("name", "").lower() for token in ("ratio", "rate", "pct", "share", "tur"))
    ]
    partition = item.get("partition_field")
    constraints = []
    if partition:
        constraints.append(f"Always filter partition column {partition} to a bounded period.")
    if source_kind == "proxy":
        constraints.append("Label this source as proxy and use sample columns for weighting when available.")
    if ratios:
        constraints.append("Do not sum ratio columns. Recompute from components when available.")
    priority = "high" if any(token in name for token in (
        "_mtd", "_mth", "monthly", "internal", "network_comp", "fb_network_5g"
    )) else "standard"
    contract = {
        "status": "approved",
        "source_kind": source_kind,
        "grain": _infer_grain(name, columns),
        "period_semantics": _infer_period(name, columns),
        "aggregation_rule": "sum_components_then_recompute_ratio" if ratios else "sum_additive_metrics",
        "territory_vocabulary": "ftth_native" if "ftth" in name else "ioh_java",
        "priority": priority,
        "cost_tier": _cost_tier(item),
        "metric_families": _infer_metrics(name, columns),
        "use_constraints": constraints,
        "warning_columns": [
            col.get("name") for col in columns
            if "warning" in col.get("name", "").lower()
        ],
        "sensitive_dimensions": [],
        "aliases": ALIASES.get(name, []),
        "schema_hash": _schema_hash(item),
        "physical_hash": _physical_hash(item),
        "object_type": item.get("type", "TABLE"),
    }
    # A reviewed override beats every heuristic above. `_infer_grain` picks the
    # first recognised column and `_infer_period` reads the table-name suffix, so
    # on a table like rham_kec_wise_tnr_mth (which carries daily, rolling-30 and
    # MTD columns at once) the guess is simply wrong.
    override = CONTRACT_OVERRIDES.get(name)
    if override:
        merged_constraints = list(dict.fromkeys(
            constraints + list(override.get("use_constraints", []))))
        contract.update(override)
        contract["use_constraints"] = merged_constraints
    return contract


def _kb_table(item: dict[str, Any]) -> dict[str, Any]:
    partition = item.get("partition_field")
    table = {
        "rows": int(item.get("rows") or 0),
        "bytes": int(item.get("bytes") or 0),
        # A reviewed description wins over the BigQuery one: the warehouse
        # description is frequently empty or an internal build note.
        "description": DESCRIPTIONS.get(item["name"])
                       or item.get("description")
                       or "",
        "columns": [],
    }
    for column in item.get("columns", []):
        description = column.get("description") or _column_description(column["name"], _normalize_type(column["type"]))
        output = {
            "name": column["name"],
            "type": _normalize_type(column["type"]),
            "nullable": column.get("mode", "NULLABLE") != "REQUIRED",
            "partition": column["name"] == partition,
        }
        if description:
            output["desc"] = description
        table["columns"].append(output)
    table.update(_contract(item["name"], item))
    return table


def _catalog_items(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {item["name"]: item for item in catalog.get("tables", [])}


def _clean_rejected_references(value: Any) -> Any:
    """Remove contradictory positive guidance for hard-blocked sources."""
    if isinstance(value, dict):
        return {
            key: _clean_rejected_references(item)
            for key, item in value.items()
            if key not in PREVIOUSLY_REJECTED
        }
    if isinstance(value, list):
        return [_clean_rejected_references(item) for item in value]
    if not isinstance(value, str):
        return value
    text = re.sub(
        r"or use rham_fb_ms_kecamatan_v2 \([^)]*\)\.",
        "Use the approved branch-level rham_report_fb_ms_branch_im3 or rham_report_fb_ms_branch_3id source for branch analysis.",
        value,
    )
    text = text.replace(
        "rham_fb_ms_kecamatan_v2, rham_fb_ms_kabkota_v2, ",
        "",
    )
    text = text.replace(
        "(e.g. rham_report_fb_ms_circle, rham_fb_ms_kecamatan_v2, rham_site_data_rev_product_mth)",
        "(e.g. rham_report_fb_ms_circle, rham_site_data_rev_product_mth)",
    )
    text = text.replace("competitive/reporting domain", "competitive domain")
    text = text.replace("rham_5g_territory_dly", "rham_5g_territory_daily")
    return text


def _refresh_distribution_guidance(kb: dict[str, Any]) -> None:
    """Apply the reviewed SND metric contract, without editing generated JSON."""
    snd = kb.get("domains", {}).get("sales_distribution", {}).get("agent", {})
    persona = snd.get("persona", "")
    snd["persona"] = persona.replace(
        "SND KPIs: rham_snd_kpi_highlevel_dly (165 cols daily) + rham_snd_kecwise_mtd/mth.",
        "SND KPIs: rham_snd_kpi_highlevel_dly/_mtd/_mth expose 54 unified metrics "
        "at kecamatan x brand grain. Raw brand parameters without a metric are no longer loaded.",
    )
    facts = snd.get("key_facts", [])
    for index, fact in enumerate(facts):
        if not isinstance(fact, str):
            continue
        if fact.startswith("M1S/M2S/M3 (=surv_m1/m2/m3)"):
            facts[index] = (
                "SND highlevel survival: ga_m1/ga_m2 are the acquisition cohorts; "
                "ga_m1s/ga_m2s are survivors after month 1/2. No month-3 survival "
                "metric exists in this SND highlevel contract."
            )
        elif fact.startswith("QSSO / QURO GRAIN:"):
            facts[index] = (
                "QSSO / QURO GRAIN: SND highlevel uses qsso_m0 and quro at kecamatan "
                "x brand grain. rham_snd_kecwise_mtd/_mth retain their own live schema. "
                "rham_outlet_wise_mtd has neither metric. Never substitute an outlet "
                "transaction proxy and present it as QSSO/QURO."
            )
    gtm_fact = (
        "Approved GTM categories in zz_territory_kecamatan.super_gtm are "
        "'MUST WIN 50', 'SUPER-88', 'REST'. Live audit on 2026-10-08 also finds "
        "residual 'HIGH POTENTIAL' and '0' values. Treat those as legacy/unclassified "
        "values, not aliases of REST; do not silently relabel or discard them. "
        "The separate high-potential report source was dropped and is not queryable."
    )
    guidance = {
        "sales_distribution": (
            "SND highlevel metric contract (2026-10-08): use outlet_total, ono, osa, "
            "sso, uro, quro, qsso_m0, site_3qsso, site_5quro, site_addr, rgu_ga_fwa, "
            "rev_game, rgu_ga_trade, rgu_ga_trad_no_inj, tertiary_b and ga_m1/ga_m1s/ga_m2/ga_m2s. "
            "Use SUM(`primary`) for the primary metric. Monthly uses _mth, MTD uses "
            "_mtd, daily uses _dly, with literal bounded partition filters. Join "
            "kec_unik to rham_ref_territory.kec_id for Circle/Region/Area/District. "
            "Mapping authority is rham_ref_snd_metric (brand, parameter, metric), "
            "currently candidate, not an approved runtime SQL source. RGU/VLR/prepaid "
            "revenue must come from approved Marketing sources, not SND highlevel. "
            "For other removed raw parameters, use another approved source only "
            "if its live KB schema actually contains the requested metric; "
            "otherwise state that it is unavailable. Preserve NULL when a brand has "
            "no mapped/populated metric; do not turn missing primary into an "
            "observed zero with COALESCE."
        ),
        "kpi_summary": (
            "Marketing highlevel SND columns (2026-10-08): use ono, osa, `primary`, "
            "secondary, sso, uro, quro, qsso_m0, site_3qsso, site_5quro, rguga_digital, "
            "rguga_digital_modern, rguga_digital_ola, rguga_digital_online and "
            "rgu_ga_trad_no_inj. sso/uro now contain real SND data. Since 2026-10-08 "
            "all 54 SND metrics are also loaded here under their metric names "
            "(outlet_total, tertiary_b*, trade_supply, trade_demand, rgu_ga, sellin_fwa, "
            "acq_rev, rev_game ...); SND survival is snd_ga_m1s/snd_ga_m2s because "
            "ga_m1s/ga_m2s here are the Marketing metrics. The always-zero placeholders "
            "q_uro, q_sso, qsc, vlr_postpaid, site_3/5_uro, site_3/5_quro, site_3/5_sso, "
            "site_3/5_qsso and site_20/40_qsc were dropped and do not exist. "
            "Revenue/RGU/VLR columns remain valid in Marketing highlevel."
        ),
        "territory_reference": gtm_fact,
        "competitive": gtm_fact,
    }
    for domain, fact in guidance.items():
        agent = kb.get("domains", {}).get(domain, {}).get("agent")
        if agent is None:
            continue
        facts = agent.setdefault("key_facts", [])
        # Replace earlier versions of the same managed fact instead of stacking them.
        prefixes = {
            "sales_distribution": ("SND highlevel metric contract (2026-10-08):",),
            "kpi_summary": ("Marketing highlevel SND columns (2026-10-08):",),
        }.get(domain, ("Current zz_territory_kecamatan.super_gtm labels are exactly ",
                       "Approved GTM categories in zz_territory_kecamatan.super_gtm"))
        facts[:] = [f for f in facts if f == fact or not (
            isinstance(f, str) and f.startswith(prefixes))]
        if fact not in facts:
            facts.append(fact)


def promote(kb: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    items = _catalog_items(catalog)
    decisions = {
        name: item.get("governance", {}) for name, item in items.items()
    }

    kb["domains"] = _clean_rejected_references(kb.get("domains", {}))

    for domain_key, metadata in DOMAIN_METADATA.items():
        kb["domains"].setdefault(domain_key, {**metadata, "tables": {}, "table_count": 0})

    # Remove sources that are now explicitly rejected or quarantined, AND sources
    # that have disappeared from BigQuery. The second case used to slip through:
    # a dropped table is absent from the catalog, so `decisions.get(name)` was
    # None and the table stayed in the KB, leaving the agent with the schema of a
    # table that no longer exists and a query that always fails at execution.
    for domain in kb.get("domains", {}).values():
        for name in list(domain.get("tables", {})):
            decision = decisions.get(name)
            if decision is None or decision.get("lifecycle") != "approved":
                del domain["tables"][name]

    for name, decision in decisions.items():
        if decision.get("lifecycle") != "approved":
            continue
        domain_key = decision.get("domain")
        item = items[name]
        if not domain_key or domain_key not in kb["domains"]:
            raise ValueError(f"Approved table {name} has no valid domain")
        # Refreshing physical metadata from a schema nobody reviewed would put new
        # or renamed columns in front of the SQL writer with no reviewed contract.
        if decision.get("schema_hash") != _schema_hash(item):
            raise ValueError(
                f"Approved table {name} has unreviewed schema drift. Review the "
                f"columns, update the contract, then update schema_hash.")
        reviewed_physical = decision.get("physical_hash")
        if reviewed_physical is not None and reviewed_physical != _physical_hash(item):
            raise ValueError(
                f"Approved table {name} has unreviewed partition or clustering "
                f"drift. A stale partition rule silently scans the whole table.")
        # Ensure one owner if a reviewed decision moves a table.
        for other_key, other_domain in kb["domains"].items():
            if other_key != domain_key:
                other_domain.get("tables", {}).pop(name, None)
        current = kb["domains"][domain_key].setdefault("tables", {}).get(name)
        refreshed = _kb_table(item)
        if current:
            # Preserve curated descriptions, while refreshing physical metadata and contracts.
            for column in refreshed["columns"]:
                existing_column = next(
                    (old for old in current.get("columns", []) if old.get("name") == column["name"]),
                    None,
                )
                if existing_column and existing_column.get("desc"):
                    column["desc"] = existing_column["desc"]
            if current.get("description"):
                refreshed["description"] = current["description"]
            # Physical metadata is refreshed from BigQuery; reviewed SEMANTICS are
            # not. Without this, every promotion overwrote hand-reviewed grain,
            # period, aggregation and alias values with name-based guesses, so a
            # routine metadata refresh quietly undid the review.
            if name not in CONTRACT_OVERRIDES:
                for field in PRESERVED_CONTRACT_FIELDS:
                    if current.get(field) not in (None, "", [], {}):
                        refreshed[field] = current[field]
        kb["domains"][domain_key]["tables"][name] = refreshed

    for domain in kb["domains"].values():
        domain["table_count"] = len(domain.get("tables", {}))

    _refresh_distribution_guidance(kb)

    facts = _clean_rejected_references(kb.get("data_facts", {}))
    facts["banned_tables"] = {
        "competitive_fb_ms": {
            "tables": ["rham_fb_ms_kabkota_v2", "rham_fb_ms_kecamatan_v2"],
            "reason": "Deprecated and hard-blocked. Use rham_report_fb_ms_* matched to territory grain.",
            "alternative_domain": "competitive",
            "replacement_table": "rham_report_fb_ms_kabkota or rham_report_fb_ms_kecamatan",
        },
        "governance_rejections": {
            "tables": sorted(PREVIOUSLY_REJECTED),
            "reason": "Rejected decisions persist until an explicit reviewed governance version reverses them.",
        },
    }
    facts["knowledge_governance"] = {
        "authority": "knowledge_base.json plus table_governance.json",
        "discovery": "Offline report-only metadata audit. New objects enter candidate state.",
        "promotion": "Only reviewed approved objects may become SQL candidates.",
        "rejection_precedence": "Rejected and quarantined objects are blocked before BigQuery dry run.",
    }
    facts["runtime_graph"] = {
        "authority": "Compiled only from approved runtime KB content.",
        "developer_graph_boundary": "FastAPI never reads graphify-out.",
        "retrieval": "Normally 4 tables, bounded expansion to 6 for complex domains.",
        "learning": "Successful approved queries create candidate term-to-table evidence. Three unique successes activate only an existing edge.",
        "prohibited_learning": "User text cannot create facts, tables, columns, joins, or formulas.",
    }
    facts["hvc_source_status"] = {
        "authority": "rham_hvc_highlevel_mtd_serving / rham_hvc_highlevel_mth_serving (review additional-sources-2026-10-04).",
        "reliable": "subs_hvc and hvc_rev_total, all months, kecamatan grain.",
        "not_reliable_from_202609": "hvc_rev_organic, hvc_rev_mobo_trade, hvc_rev_digital, subs_hvc_stay, subs_hvc_in, subs_hvc_out. Report N/A, never a number.",
        "stale_tables": "rham_hvc_kec_* and rham_hvc_site_* stop at month 202609; rham_mkt_highlevel_* HVC columns are NULL/stale from 202609.",
        "site_grain": "rham_site_wise_monthly subs_hvc* is 0 for unpopulated months (only 202608 filled). Treat 0 as N/A.",
        "mtd_mixed_months": "Some MTD months (202504, 202510-202602, 202608) hold FULL-MONTH hvc_rev_total, 7-8x prepaid MTD. HVC revenue above rev_prepaid for the same rows is N/A. For closed months use rham_hvc_highlevel_mth_serving.",
    }
    facts["customer_demand_tables"] = {
        "flow": [
            "rham_demand_inner_outer",
            "rham_demand_inner_outer_mtd",
            "rham_demand_inner_outer_mth",
        ],
        "digital": ["rham_data_rev_digicommerce_daily", "rham_game_mtd", "rham_game_mth"],
        "product": ["rham_ssd_details_mtd", "rham_ssd_details_mth", "rham_cohort_voucher_mobotrade"],
        "subscriber_aggregates": [
            "rham_subs_traffic_agg_geo_mtd_lmtd",
            "rham_subs_traffic_agg_migration_matrix_monthly",
            "rham_subs_traffic_agg_segment_mtd_lmtd",
        ],
        "privacy": "Only aggregate sources are approved. Subscriber-grain and raw transaction sources are blocked.",
    }
    kb["data_facts"] = facts
    kb["knowledge_version"] = "2026-08-19.1"
    kb["updated_at"] = datetime.now(timezone.utc).isoformat()
    kb["governance_review_id"] = REVIEW_ID
    return kb


def validate_state(kb: dict[str, Any], governance: dict[str, Any]) -> list[str]:
    errors = []
    objects = governance.get("objects", {})
    valid_states = {"approved", "candidate", "quarantined", "rejected", "superseded"}
    for name, decision in objects.items():
        if decision.get("lifecycle") not in valid_states:
            errors.append(f"{name}: invalid lifecycle {decision.get('lifecycle')}")
        if decision.get("lifecycle") in {"rejected", "quarantined"} and decision.get("policy") != "hard_block":
            errors.append(f"{name}: blocked lifecycle must use hard_block policy")
        history = decision.get("decision_history") or []
        if not history or history[-1].get("decision") != decision.get("lifecycle"):
            errors.append(f"{name}: decision history does not match current lifecycle")
        previously_blocked = any(
            entry.get("decision") in {"rejected", "quarantined"}
            for entry in history[:-1]
        )
        if previously_blocked and decision.get("lifecycle") == "approved":
            last = history[-1]
            if not (last.get("override") is True and last.get("reviewer") and last.get("evidence")):
                errors.append(f"{name}: blocked lifecycle reversal lacks reviewed override evidence")
        lifecycle = decision.get("lifecycle")
        if lifecycle == "approved":
            if decision.get("policy") != "runtime_allowed":
                errors.append(f"{name}: approved lifecycle must use runtime_allowed policy")
            if not decision.get("domain"):
                errors.append(f"{name}: approved lifecycle requires a domain owner")
            if not decision.get("reason"):
                errors.append(f"{name}: approved lifecycle requires a reason")
            if not decision.get("review_id"):
                errors.append(f"{name}: approved lifecycle requires a review_id")
        if lifecycle == "candidate" and decision.get("policy") != "not_runtime_allowed":
            errors.append(f"{name}: candidate lifecycle must use not_runtime_allowed policy")
        if lifecycle == "superseded":
            if decision.get("policy") != "hard_block":
                errors.append(f"{name}: superseded lifecycle must use hard_block policy")
            if not decision.get("replacement_table"):
                errors.append(f"{name}: superseded lifecycle requires a replacement_table")
    kb_tables = _existing_table_domains(kb)
    for name in kb_tables:
        if name not in objects:
            errors.append(f"KB table has no governance decision: {name}")
    for name in PREVIOUSLY_REJECTED:
        if name in kb_tables:
            errors.append(f"Rejected table remains in KB: {name}")
    for name, domain in kb_tables.items():
        decision = objects.get(name)
        if decision and decision.get("lifecycle") != "approved":
            errors.append(f"KB table is not approved: {name}")
        if decision and decision.get("domain") != domain:
            errors.append(f"Domain mismatch for {name}: {domain} vs {decision.get('domain')}")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, help="Read a saved inventory instead of BigQuery")
    parser.add_argument("--bootstrap-governance", action="store_true")
    parser.add_argument("--rebuild-governance", action="store_true")
    parser.add_argument("--write-catalog", action="store_true")
    parser.add_argument("--promote-reviewed", action="store_true")
    parser.add_argument("--compile-graph", action="store_true")
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    kb = json.loads(config.KB_PATH.read_text())
    inventory = load_inventory(args.inventory)

    if args.bootstrap_governance or args.rebuild_governance:
        if config.TABLE_GOVERNANCE_PATH.exists() and not args.rebuild_governance:
            raise SystemExit("Governance exists. Use --rebuild-governance for an explicit reviewed replacement.")
        governance = build_governance(inventory, kb)
        _atomic_json(config.TABLE_GOVERNANCE_PATH, governance)
    else:
        governance = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())

    catalog = merge_catalog(inventory, governance)
    if args.write_catalog or args.promote_reviewed:
        _atomic_json(config.TABLE_CATALOG_PATH, catalog)

    catalog_errors = validate_catalog(catalog)
    if args.promote_reviewed and catalog_errors:
        raise SystemExit(
            "Discovery validation failed. Review these objects before promoting:\n- "
            + "\n- ".join(catalog_errors))

    if args.promote_reviewed:
        backup = config.KB_PATH.with_name(
            config.KB_PATH.name + ".bak" + datetime.now().strftime("%Y%m%d%H%M%S")
        )
        shutil.copy2(config.KB_PATH, backup)
        promoted = promote(kb, catalog)
        errors = validate_state(promoted, governance)
        if errors:
            raise SystemExit("Promotion validation failed:\n- " + "\n- ".join(errors))
        _atomic_json(config.KB_PATH, promoted)
        kb = promoted

    if args.compile_graph or args.promote_reviewed:
        write_graph_atomic(kb)

    errors = validate_state(kb, governance) + validate_catalog(catalog)
    summary = catalog["summary"]
    print(json.dumps({
        "summary": summary,
        "delta": catalog["delta"],
        "kb_tables": len(_existing_table_domains(kb)),
        "governance_objects": len(governance.get("objects", {})),
        "errors": errors,
        "catalog_written": bool(args.write_catalog or args.promote_reviewed),
        "promoted": bool(args.promote_reviewed),
    }, indent=2))
    if args.check and errors:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
