"""Pre-flight SQL structure checks and empty/degenerate result handling."""
from __future__ import annotations

import pytest

from app.bigquery_tool import check_sql_balance
from app import orchestrator
from app.result_profiler import profile_result, empty_result_hint


# ---------------- check_sql_balance ----------------

def test_well_formed_query_passes():
    sql = "SELECT a, COUNT(*) AS n FROM `p.d.t` WHERE x = 'a(b' GROUP BY a ORDER BY n DESC LIMIT 10"
    assert check_sql_balance(sql) is None


def test_multi_cte_query_passes():
    sql = ("WITH a AS (SELECT k, SUM(v) v FROM `p.d.t1` GROUP BY k), "
           "b AS (SELECT k, SUM(v) v FROM `p.d.t2` GROUP BY k) "
           "SELECT a.k, SAFE_DIVIDE(b.v, a.v) r FROM a JOIN b USING (k)")
    assert check_sql_balance(sql) is None


def test_unclosed_paren_is_detected():
    sql = "WITH a AS (SELECT k, SUM(v) FROM `p.d.t` GROUP BY k SELECT * FROM a"
    reason = check_sql_balance(sql)
    assert reason and "unbalanced" in reason


def test_extra_closing_paren_is_detected():
    assert "too many" in (check_sql_balance("SELECT (1)) FROM t") or "")


def test_unterminated_string_is_detected():
    sql = "SELECT * FROM `p.d.t` WHERE region = 'East Java"
    reason = check_sql_balance(sql)
    assert reason and "unterminated" in reason


def test_paren_inside_string_is_not_counted():
    assert check_sql_balance("SELECT * FROM t WHERE s = '((('") is None


def test_paren_inside_line_comment_is_not_counted():
    assert check_sql_balance("SELECT 1 -- ((( note\nFROM t") is None


def test_paren_inside_block_comment_is_not_counted():
    assert check_sql_balance("SELECT 1 /* ((( */ FROM t") is None


def test_dangling_keyword_is_detected():
    reason = check_sql_balance("SELECT a FROM t GROUP BY")
    assert reason and "dangling keyword" in reason


def test_trailing_semicolon_is_fine():
    assert check_sql_balance("SELECT 1 FROM t;") is None


# ---------------- truncation hint routing ----------------

def test_truncation_error_asks_for_a_simpler_query():
    hint = orchestrator._error_hint(
        "Generated SQL is structurally invalid: unbalanced parentheses (2 unclosed), "
        "the query looks cut off.")
    assert "SIMPLER" in hint
    assert "FEWEST possible CTEs" in hint


def test_plain_syntax_error_keeps_the_in_place_fix():
    hint = orchestrator._error_hint("Syntax error: Unexpected keyword LIMIT at [4:12]")
    assert "Fix the SQL syntax" in hint
    assert "SIMPLER" not in hint


def test_scan_cap_hint_is_unchanged():
    hint = orchestrator._error_hint("Query would scan 96.6 GB, exceeding the 50 GB safety cap.")
    assert "SHRINK" in hint


# ---------------- degenerate result detection ----------------

def _result(rows, sql="SELECT kabkota, conv FROM t ORDER BY conv ASC"):
    columns = list(rows[0].keys()) if rows else ["kabkota", "conv"]
    return {"rows": rows, "columns": columns, "row_count": len(rows), "sql": sql}


def test_all_null_metric_is_flagged_degenerate():
    rows = [{"kabkota": "KOTA A", "conv": None}, {"kabkota": "KOTA B", "conv": None}]
    prof = profile_result(_result(rows))
    assert prof["qa"]["degenerate"]
    assert prof["qa"]["status"] == "warning"


def test_null_ranking_column_kills_ranking_verified():
    rows = [{"kabkota": f"KOTA {i}", "conv": None, "so": 10 + i} for i in range(6)]
    prof = profile_result(_result(rows))
    assert prof["profile"]["ranking_verified"] is False
    assert any("ranking column" in d for d in prof["qa"]["degenerate"])


def test_healthy_result_is_not_degenerate():
    rows = [{"kabkota": "KOTA A", "conv": 12.5}, {"kabkota": "KOTA B", "conv": 30.0}]
    prof = profile_result(_result(rows))
    assert prof["qa"]["degenerate"] == []
    assert prof["qa"]["status"] == "verified"


def test_partial_nulls_are_tolerated():
    rows = [{"kabkota": "A", "conv": 10.0}, {"kabkota": "B", "conv": None}]
    prof = profile_result(_result(rows))
    assert prof["qa"]["degenerate"] == []


# ---------------- empty_result_hint ----------------

def test_zero_rows_produces_a_territory_and_period_hint():
    hint = empty_result_hint(profile_result(_result([])))
    assert hint and "ZERO rows" in hint
    assert "territory column" in hint


def test_degenerate_rows_produce_a_rewrite_hint():
    rows = [{"kabkota": "A", "conv": None}, {"kabkota": "B", "conv": None}]
    hint = empty_result_hint(profile_result(_result(rows)))
    assert hint and "do not answer the question" in hint


def test_healthy_result_produces_no_hint():
    rows = [{"kabkota": "A", "conv": 1.0}]
    assert empty_result_hint(profile_result(_result(rows))) is None


# ---------------- truncation retry budget ----------------

def test_truncation_is_recognised_for_budget_escalation():
    assert orchestrator._is_truncation_error(
        "Generated SQL is structurally invalid: unterminated ' literal, the query looks cut off.")
    assert orchestrator._is_truncation_error(
        "Syntax error: Expected \")\" but got end of script")
    assert orchestrator._is_truncation_error(
        "Generated SQL is structurally invalid: unbalanced parentheses (2 unclosed)")


def test_ordinary_errors_do_not_escalate_the_budget():
    assert not orchestrator._is_truncation_error("Syntax error: Unexpected keyword LIMIT")
    assert not orchestrator._is_truncation_error(
        "Query would scan 96.6 GB, exceeding the 50 GB safety cap.")
    assert not orchestrator._is_truncation_error("Unrecognized name: foo")
    assert not orchestrator._is_truncation_error(None)


def test_truncation_retry_gets_a_larger_budget_than_the_first_attempt():
    from app import config
    assert config.SQL_MAX_TOKENS_TRUNCATED > config.SQL_MAX_TOKENS, (
        "a retry after truncation must not reuse the budget that just overflowed")
