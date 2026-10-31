"""Guards for review additional-sources-2026-10-04: PII columns, view pruning, HVC N/A."""
from unittest.mock import Mock, patch

import pytest

from app import config, reports_comprehensive, routes_reports
from app.bigquery_tool import QueryError, _reject_sensitive_columns
from app.query_cost import prepare_query

T = f"`{config.BQ_PROJECT}.{config.BQ_DATASET}"
FTTH = f"{T}.rham_ftth_install_orders`"


@pytest.mark.parametrize("sql", [
    f"SELECT customer_name, COUNT(*) FROM {FTTH} GROUP BY customer_name",
    f"SELECT o.sales_code FROM {FTTH} o",
    f"SELECT * FROM {FTTH}",
    f"SELECT o.* FROM {FTTH} o",
    f"SELECT TO_JSON_STRING(o) FROM {FTTH} o",
    f"SELECT o FROM {FTTH} o",
])
def test_identity_columns_are_blocked(sql):
    with pytest.raises(QueryError):
        _reject_sensitive_columns(sql, {"rham_ftth_install_orders"})


def test_aggregate_without_identity_is_allowed():
    _reject_sensitive_columns(f"SELECT status, COUNT(*) AS n FROM {FTTH} GROUP BY status",
                              {"rham_ftth_install_orders"})


def test_serving_view_gets_mth_dt_bounds_from_month_id():
    sql, _ = prepare_query(
        f"SELECT SUM(subs_hvc) FROM {T}.rham_hvc_highlevel_mth_serving` WHERE month_id=202608", Mock())
    assert "mth_dt" in sql and "2026-08-01" in sql and "2026-09-01" in sql


@patch.object(reports_comprehensive, "_data_as_of", return_value="2026-10-03")
@patch.object(reports_comprehensive, "_m2m_query", return_value=({}, None))
def test_hvc_split_is_na_from_202609_but_total_stays(_m2m, _as_of):
    row = {f"{c}_{b}": 10.0 for c in ("hvc_rev_total", "hvc_rev_organic", "subs_hvc", "subs_hvc_in")
           for b in ("ioh", "im3", "3id")}
    with patch.object(reports_comprehensive, "_wide_one_month", return_value={"rows": [row]}), \
         patch.object(reports_comprehensive, "_wide_cumulative", return_value={"rows": [row]}):
        out = reports_comprehensive.build_comprehensive("ALL", 202610)
    metrics = {m["code"]: m for s in out["sections"] for m in s.get("metrics", [])}
    assert metrics["hvc_rev_total"]["ioh"]["mtd"] == 10.0
    assert metrics["subs_hvc"]["ioh"]["mtd"] == 10.0
    organic = metrics["hvc_rev_organic"]["ioh"]
    # 202610 and 202609 (lmtd) are broken; 202608 (llmtd) and LYTD (2025) are valid.
    assert organic["mtd"] is None and organic["lmtd"] is None and organic["ytd"] is None
    assert organic["llmtd"] == 10.0 and organic["lytd"] == 20.0  # Jan..Sep 2025 closed + Oct 2025 MTD
    assert metrics["hvc_organic_pct"]["ioh"]["mtd"] is None
    assert metrics["subs_hvc_in"]["ioh"]["mtd"] is None
    assert out["notes"]


@patch.object(routes_reports, "_level_summary")
def test_map_explore_returns_na_for_broken_hvc_metric(summary):
    out = routes_reports.map_explore(metric="hvc_rev_organic", circle="JAVA", level="kecamatan",
                                     brand="ioh", value_mode="growth", filter_type="all",
                                     filter_value="", month_id=202609)
    assert out["kind"] == "not_available"
    summary.assert_not_called()


@patch.object(reports_comprehensive, "_data_as_of", return_value="2026-08-03")
@patch.object(reports_comprehensive, "_m2m_query", return_value=({}, None))
def test_full_month_hvc_revenue_in_mtd_row_is_na(_m2m, _as_of):
    def month(table, metrics, circle, month_id, fc, extra_select=""):
        hvc = 2224.0 if month_id == 202608 else 170.0  # 202608 MTD holds the full month
        return {"rows": [{f"{c}_{b}": v for c, v in (("hvc_rev_total", hvc), ("hvc_rev_total_pt", hvc),
                                                      ("rev_prepaid_h", 280.0)) for b in ("ioh", "im3", "3id")}]}
    with patch.object(reports_comprehensive, "_wide_one_month", side_effect=month), \
         patch.object(reports_comprehensive, "_wide_cumulative", return_value={"rows": [{}]}):
        out = reports_comprehensive.build_comprehensive("ALL", 202608)
    metrics = {m["code"]: m for s in out["sections"] for m in s.get("metrics", [])}
    assert metrics["hvc_rev_total"]["ioh"]["mtd"] is None
    assert metrics["hvc_rev_total"]["ioh"]["lmtd"] == 170.0
    assert any("full-month" in n for n in out["notes"])


@pytest.mark.parametrize("sql,expected", [
    (f"SELECT x.a FROM {T}.rham_mkt_highlevel_mth` x, (SELECT 202609 AS m) mx WHERE x.month_id=mx.m",
     "CROSS JOIN (SELECT 202609 AS m) AS mx"),
    (f"SELECT a FROM {T}.rham_mkt_highlevel_mth` WHERE month_id IN (SELECT 202609)", "month_id IN (202609)"),
])
def test_constant_derived_table_stays_valid_sql(sql, expected):
    with patch("app.query_cost._resolve_max", return_value=None):
        out, _ = prepare_query(sql, Mock())
    assert expected in out and "mth_dt" in out
