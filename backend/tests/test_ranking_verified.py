"""Only an OUTER ORDER BY may mark a result as a verified ranking.

The synthesizer is allowed to make top-N claims when ranking_verified is true, so a
false positive here turns into a wrong ranking in the user-facing answer.
"""
from __future__ import annotations

from app.result_profiler import profile_result, _order_by_column, _has_outer_order_by


def _result(sql, n=6):
    rows = [{"kabkota": f"K{i}", "rev": 100 - i} for i in range(n)]
    return {"rows": rows, "columns": ["kabkota", "rev"], "row_count": n, "sql": sql}


def test_outer_order_by_verifies_ranking():
    prof = profile_result(_result("SELECT kabkota, rev FROM t ORDER BY rev DESC LIMIT 10"))
    assert prof["profile"]["ranking_verified"] is True
    assert prof["profile"]["ordered_top"]


def test_order_by_only_inside_a_cte_does_not_verify_ranking():
    sql = ("WITH x AS (SELECT kabkota, rev FROM t ORDER BY rev DESC LIMIT 100) "
           "SELECT kabkota, rev FROM x")
    prof = profile_result(_result(sql))
    assert prof["profile"]["ranking_verified"] is False
    assert prof["profile"]["ordered_top"] == []


def test_order_by_in_a_subquery_does_not_verify_ranking():
    sql = "SELECT * FROM (SELECT kabkota, rev FROM t ORDER BY rev DESC)"
    assert _has_outer_order_by(sql) is False


def test_order_by_in_a_comment_does_not_verify_ranking():
    assert _has_outer_order_by("SELECT a FROM t -- order by rev desc\n") is False


def test_order_by_in_a_string_literal_does_not_verify_ranking():
    assert _has_outer_order_by("SELECT 'order by rev' AS note FROM t") is False


def test_cte_order_by_plus_outer_order_by_verifies():
    sql = ("WITH x AS (SELECT k, v FROM t ORDER BY v) "
           "SELECT k, v FROM x ORDER BY v DESC")
    assert _has_outer_order_by(sql) is True


def test_order_by_column_reads_the_outer_clause():
    sql = ("WITH x AS (SELECT k, a FROM t ORDER BY a) "
           "SELECT k, b FROM x ORDER BY b ASC")
    assert _order_by_column(sql) == "b"


def test_positional_order_by_has_no_column_name():
    assert _order_by_column("SELECT k, v FROM t ORDER BY 2 DESC") is None


def test_window_function_order_by_does_not_count_as_outer():
    sql = "SELECT k, ROW_NUMBER() OVER (ORDER BY v DESC) rn FROM t"
    assert _has_outer_order_by(sql) is False


def test_degenerate_check_still_uses_the_outer_ranking_column():
    rows = [{"k": f"K{i}", "conv": None} for i in range(5)]
    result = {"rows": rows, "columns": ["k", "conv"], "row_count": 5,
              "sql": "WITH x AS (SELECT k FROM t ORDER BY k) "
                     "SELECT k, conv FROM x ORDER BY conv ASC"}
    prof = profile_result(result)
    assert any("ranking column 'conv'" in d for d in prof["qa"]["degenerate"])
