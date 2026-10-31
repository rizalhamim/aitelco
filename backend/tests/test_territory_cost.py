from unittest.mock import Mock

import pytest
import sqlglot

from app import config, knowledge
from app.bigquery_tool import QueryError
from app.query_cost import prepare_query
from app.territory import normalize_level, public_territory, scope_column


TABLE = f"`{config.BQ_PROJECT}.{config.BQ_DATASET}.rham_kec_data_rev_product_mtd`"


def test_operational_area_and_district_ignore_abolished_area():
    assert scope_column("area") == "t.branch_im3"
    assert scope_column("district") == "t.micro_cluster_im3"
    assert normalize_level("branch") == "area"
    assert normalize_level("microcluster") == "district"
    assert public_territory({"area": "OLD", "branch": "SURABAYA", "im3_mc": "MC-GUBENG"})["area"] == "SURABAYA"


@pytest.mark.parametrize("predicate,low,high", [
    ("month_id='202610'", "2026-10-01", "2026-11-01"),
    ("month_id IN ('202512','202601')", "2025-12-01", "2026-02-01"),
    ("month_id='202509' OR month_id='202609'", "2025-09-01", "2026-10-01"),
    ("CAST(month_id AS INT64) BETWEEN 202601 AND 202609", "2026-01-01", "2026-10-01"),
])
def test_existing_period_gets_equivalent_literal_partition_bounds(predicate, low, high):
    sql, notes = prepare_query(f"SELECT SUM(revenue) FROM {TABLE} WHERE {predicate}", Mock())
    assert low in sql and high in sql
    assert "month_id" in sql and "mth_dt" in sql
    assert notes
    sqlglot.parse_one(sql, read="bigquery")


@pytest.mark.parametrize("predicate", ["circle='JAVA'", "month_id='202610' OR circle='JAVA'", "month_id LIKE '%10'",
                                       "mth_dt IS NOT NULL", "mth_dt=mth_dt", "mth_dt=DATE '2026-10-01' OR circle='JAVA'"])
def test_unbounded_facts_are_rejected_before_bigquery(predicate):
    client = Mock()
    with pytest.raises(QueryError, match="partition column"):
        prepare_query(f"SELECT SUM(revenue) FROM {TABLE} WHERE {predicate} LIMIT 10", client)
    client.query.assert_not_called()


def test_each_physical_scan_needs_its_own_partition_filter():
    with pytest.raises(QueryError):
        prepare_query(f"SELECT SUM(a.revenue) FROM {TABLE} a JOIN {TABLE} b ON a.kec_id=b.kec_id WHERE a.month_id='202610'", Mock())


def test_static_territory_reference_can_be_read_without_date_filter():
    sql, notes = prepare_query(f"SELECT kec_id, branch_im3 FROM `{config.BQ_PROJECT}.{config.BQ_DATASET}.rham_ref_territory`", Mock())
    assert not notes
    assert "branch_im3" in sql


def test_current_product_schema_cannot_be_queried_as_site_data():
    table = knowledge.table_index()["rham_kec_data_rev_product_mtd"]
    names = {c["name"] for c in table["columns"]}
    assert "kec_id" in names
    assert "site_id" not in names
    assert "service_type" not in names
    assert "rham_site_data_rev_product_mtd" not in knowledge.approved_table_names()


def test_profile_resolves_new_hierarchy_and_filters_physical_reference():
    from app.profile_engine import _direct_sql_templates, _resolve_territory
    assert _resolve_territory("profil area SURABAYA") == ("area", "Surabaya")
    assert _resolve_territory("profil district MC-GUBENG") == ("district", "Mc-Gubeng")
    area = _direct_sql_templates("area", "SURABAYA")["Revenue Overview (Trend 360)"]
    district = _direct_sql_templates("district", "MC-GUBENG")["Revenue Overview (Trend 360)"]
    assert "UPPER(branch)" in area and "UPPER(area)" not in area
    assert "UPPER(im3_mc)" in district


def test_missing_fwa_splits_stay_null_without_breaking_other_metrics():
    from app.site_fwa import _select
    sql = _select()
    assert "SUM(ga_fwa) AS ga_fwa" in sql
    assert "CAST(NULL AS FLOAT64) AS ga_fwa_4g" in sql
    assert "SUM(ga_fwa_4g)" not in sql


def test_question_rephrasing_cannot_change_requested_grain():
    from app.territory import preserve_requested_grain
    original = "revenue per district di Area Surabaya"
    assert preserve_requested_grain(original, "revenue per kecamatan Surabaya") == original
    assert preserve_requested_grain("revenue per branch", "revenue per area") == "revenue per area"
    assert preserve_requested_grain("revenue per MC", "revenue per district") == "revenue per district"


def test_literal_inner_join_filter_is_pushed_without_changing_left_join_semantics():
    sql, notes = prepare_query(f"SELECT SUM(a.revenue) FROM {TABLE} a JOIN (SELECT '202610' AS month_id) b ON a.month_id=b.month_id", Mock())
    assert "2026-10-01" in sql and notes
    with pytest.raises(QueryError):
        prepare_query(f"SELECT SUM(a.revenue) FROM {TABLE} a LEFT JOIN (SELECT '202610' AS month_id) b ON a.month_id=b.month_id", Mock())


def test_existing_upper_month_bound_does_not_invent_a_lower_cutoff():
    sql, _ = prepare_query(f"SELECT MAX(month_id) FROM {TABLE} m JOIN `{config.BQ_PROJECT}.{config.BQ_DATASET}.rham_ref_territory` t USING(kec_id) WHERE m.month_id <= '202609'", Mock())
    assert "2026-10-01" in sql
    assert "mth_dt >=" not in sql


def test_product_year_batches_preserve_all_months_null_and_negative_corrections():
    from app.reports_data import _sum_product_months
    called = []
    def query(table, where):
        called.append(where)
        return {('product',): {"product": "product", "ioh": -2, "im3": None, "id3": 0, "hit": 1}}
    rows = _sum_product_months(query, "source", [202512, 202601, 202602])
    assert len(called) == 2
    assert all(str(month) in " ".join(called) for month in (202512, 202601, 202602))
    assert rows[('product',)] == {"product": "product", "ioh": -4, "im3": None, "id3": 0, "hit": 2}


def test_product_report_forwards_territory_and_separates_cached_scopes(monkeypatch):
    from app import routes_reports
    cache_keys = []
    builder = Mock(return_value={"ok": True})
    def cached(report, key, build, force):
        cache_keys.append(key)
        return build()
    monkeypatch.setattr(routes_reports.reports_cache, "get_or_build", cached)
    monkeypatch.setattr(routes_reports.reports_data, "build_product_demand", builder)
    for level, value in (("area", "SURABAYA"), ("district", "MC-GUBENG")):
        assert routes_reports.product_demand(circle="JAVA", month_id=202610, scope="total",
                                             brand="ioh", filter_type=level,
                                             filter_value=value, refresh=False) == {"ok": True}
        builder.assert_called_with("JAVA", 202610, "total", "ioh", level, value)
    assert cache_keys[0] != cache_keys[1]
