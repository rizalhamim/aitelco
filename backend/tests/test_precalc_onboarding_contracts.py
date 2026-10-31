"""The reviewed contracts for the 2026-09-17 onboarding must reach the prompt.

These are the facts that cost real money or produce a silently wrong answer if
the SQL writer never sees them: a 57 GB table filtered with a MAX() subquery
instead of a literal, a KPI cube with 68 empty columns, an MTTR table holding a
'Grand Total' row, and two 5G tables measuring different populations.

Offline only: asserts what the KB carries, not what BigQuery returns.
"""
from __future__ import annotations

import json

import pytest

from app import config, knowledge


@pytest.fixture(scope="module")
def kb():
    return knowledge.load_kb()


@pytest.fixture(scope="module")
def governance():
    return json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]


def contract(kb, name):
    for domain in kb["domains"].values():
        table = (domain.get("tables") or {}).get(name)
        if table:
            return table
    raise AssertionError(f"{name} is not in the runtime KB")


def constraints_text(kb, name):
    return " ".join(contract(kb, name).get("use_constraints", [])).lower()


ONBOARDED = {
    "rham_mkt_highlevel_mtd": "kpi_summary",
    "rham_mkt_highlevel_mth": "kpi_summary",
    "rham_postpaid_ga_daily": "acquisition",
    "rham_outlet_ga": "sales_distribution",
    "rham_outlet_ga_dtu": "sales_distribution",
    "rham_outlet_ga_mtd": "sales_distribution",
    "rham_outlet_ga_mth": "sales_distribution",
    "rham_outlet_low_stock": "sales_distribution",
    "rham_outlet_secondary_daily": "sales_distribution",
    "rham_outlet_secondary_mtd": "sales_distribution",
    "rham_outlet_secondary_mth": "sales_distribution",
    "rham_report_fb_device_5g": "competitive",
    "rham_report_fb_network_5g": "competitive",
    "rham_site_ga_quality_daily": "site_performance",
    "rham_site_ga_quality_mtd": "site_performance",
    "rham_site_ga_quality_mth": "site_performance",
    "rham_site_wise_mtd": "site_performance",
    "rham_site_wise_monthly": "site_performance",
    "rham_kec_wise_tnr_mtd": "kpi_summary",
    "rham_kec_wise_tnr_mth": "kpi_summary",
    "rham_ftth_tt_mttr": "ftth",
    # review additional-sources-2026-10-04
    "rham_hvc_highlevel_mtd_serving": "customer_hvc",
    "rham_hvc_highlevel_mth_serving": "customer_hvc",
    "rham_outlet_ga_ex_dtu": "sales_distribution",
    "rham_outlet_ga_mth_ex_dtu": "sales_distribution",
    "rham_outlet_ga_5g_mtd": "sales_distribution",
    "rham_outlet_ga_fwa_mth": "sales_distribution",
    "rham_ftth_install_orders": "ftth",
    "rham_fb_ms_5g_device": "competitive",
    "rham_fb_ms_5g_network": "competitive",
}

BLOCKED = [
    # Subscriber or employee identifiers.
    "rham_ga_quality_tracker",
    "rham_ref_msisdn_dtu",
    "rham_ref_msisdn_dtu_check",
    "rham_ref_msisdn_dtu_bak20260912",
    "_stg_ref_msisdn_dtu",
    "rham_postpaid_ga_daily_direct_sales",
    "rham_postpaid_ga_daily_gerai",
    "rham_ftth_tt_mo_detail",
    "rham_ftth_tt_mo_impacted",
    "rham_ftth_tt_single_detail",
    # Staging, empty, snapshot, or duplicated sources.
    "rham_network_ncp_stg",
    "rham_site_competitor_stg",
    "rham_site_wise_daily_snap_20260828",
    "rham_outlet_ga_quality_ex_dtu",
    "rham_kec_wise_tnr",
]


@pytest.mark.parametrize("name,domain", sorted(ONBOARDED.items()))
def test_each_onboarded_table_is_queryable_from_its_domain(kb, name, domain):
    assert name in (kb["domains"][domain].get("tables") or {})
    assert name in knowledge.approved_table_names()


@pytest.mark.parametrize("name", BLOCKED)
def test_blocked_sources_never_become_queryable(name):
    assert name not in knowledge.approved_table_names()


@pytest.mark.parametrize("name", sorted(ONBOARDED))
def test_each_onboarded_table_carries_a_reviewed_contract(kb, name):
    table = contract(kb, name)
    assert table.get("description"), f"{name} has no description"
    assert table.get("grain")
    assert table.get("period_semantics")
    assert table.get("aggregation_rule")
    assert table.get("aliases"), f"{name} has no user-language aliases"


def test_retired_traffic_detail_is_not_offered_as_current_data(kb):
    assert "rham_site_traffic_usage_mth" not in knowledge.approved_table_names()
    table = contract(kb, "rham_site_wise_monthly")
    assert "usg_data_gb" in {c["name"] for c in table["columns"]}
    assert "unavailable" in table["description"]


def test_the_35gb_low_stock_table_demands_a_kpi_filter(kb):
    text = constraints_text(kb, "rham_outlet_low_stock")
    assert "kpi" in text
    assert "literal" in text
    assert "null" in text, "NULL means unavailable, not zero, must be stated"


def test_the_tnr_cube_lists_its_empty_columns(kb):
    # 68 of 184 numeric columns are entirely empty. Ranking on one returns
    # nothing and reads to the user as missing data.
    table = contract(kb, "rham_kec_wise_tnr_mtd")
    assert len(table["warning_columns"]) >= 20
    assert "rev_ewallet" in table["warning_columns"]
    assert "empty" in constraints_text(kb, "rham_kec_wise_tnr_mtd")


def test_the_tnr_cube_explains_its_cutoff_semantics(kb):
    for name in ("rham_kec_wise_tnr_mtd", "rham_kec_wise_tnr_mth"):
        text = constraints_text(kb, name)
        assert "max(dt_id)" in text, f"{name} must state the cutoff rule"


def test_mttr_warns_about_grand_total_and_mixed_period_types(kb):
    text = constraints_text(kb, "rham_ftth_tt_mttr")
    assert "grand total" in text
    assert "period_type" in text
    assert "weight" in text, "mttr_hours is an average and must be weighted"


def test_the_two_5g_market_share_tables_declare_distinct_populations(kb):
    device = constraints_text(kb, "rham_report_fb_device_5g")
    network = constraints_text(kb, "rham_report_fb_network_5g")
    assert "rham_report_fb_network_5g" in device
    assert "rham_report_fb_device_5g" in network
    for text in (device, network):
        assert "fraction" in text, "ms_* are 0-1 fractions, not percentages"
        assert "location_type" in text


def test_snapshot_style_ga_tables_forbid_summing_across_cutoffs(kb):
    for name in ("rham_mkt_highlevel_mtd", "rham_mkt_highlevel_mth"):
        assert "dt_id" in constraints_text(kb, name)
        assert "double count" in constraints_text(kb, name) \
            or "never sum" in constraints_text(kb, name)


def test_secondary_sales_declares_that_its_grain_is_not_unique(kb):
    text = constraints_text(kb, "rham_outlet_secondary_mtd")
    assert "not unique" in text
    assert "group by" in text


def test_postpaid_revenue_units_are_stated(kb):
    text = constraints_text(kb, "rham_postpaid_ga_daily")
    assert "million" in text
    assert "activation_date" in text


def test_survival_metrics_are_declared_as_counts_not_rates(kb):
    for name in ("rham_outlet_ga_mtd", "rham_site_ga_quality_mtd"):
        text = constraints_text(kb, name)
        assert "count" in text
        assert "sum(" in text


def test_corrupt_outlet_coordinates_are_flagged(kb):
    # Observed latitude -620 and longitude 946.
    for name in ("rham_outlet_ga_mtd", "rham_outlet_ga_mth"):
        table = contract(kb, name)
        assert "outlet_latitude" in table["warning_columns"]
        assert "corrupt" in constraints_text(kb, name)


def test_superseded_sources_point_at_a_live_replacement(governance):
    approved = knowledge.approved_table_names()
    for name, record in governance.items():
        if record["lifecycle"] != "superseded":
            continue
        replacement = record.get("replacement_table")
        assert replacement, f"{name} names no replacement"
        # The replacement may itself still be a candidate (the migration matrix
        # case), so only assert it is not another blocked object.
        assert governance.get(replacement, {}).get("lifecycle") in {
            "approved", "candidate"}, f"{name} points at a blocked replacement"
        if governance.get(replacement, {}).get("lifecycle") == "approved":
            assert replacement in approved
