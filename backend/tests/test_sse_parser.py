"""The benchmark runner's SSE parser must not silently drop events.

A naive split on the blank-line separator loses any event whose JSON payload contains
a blank line, which made real successes look like pipeline failures.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "data" / "training"))

from run_hard_questions import parse_sse, classify  # noqa: E402


def test_basic_event_sequence():
    stream = ('event: route\ndata: {"domain":"competitive"}\n\n'
              'event: token\ndata: {"t":"a"}\n\n')
    assert list(parse_sse(stream)) == [
        ("route", {"domain": "competitive"}),
        ("token", {"t": "a"}),
    ]


def test_multiline_data_lines_are_joined():
    stream = 'event: result\ndata: {"row_count":10,\ndata: "sql":"SELECT 1"}\n\n'
    assert list(parse_sse(stream)) == [("result", {"row_count": 10, "sql": "SELECT 1"})]


def test_payload_containing_a_blank_line_is_not_dropped():
    stream = 'event: result\ndata: {"row_count": 5, "note": "a\\n\\nb"}\n\n'
    events = list(parse_sse(stream))
    assert events[0][0] == "result"
    assert events[0][1]["row_count"] == 5


def test_comment_lines_are_ignored():
    stream = ': keepalive\nevent: token\ndata: {"t":"x"}\n\n'
    assert list(parse_sse(stream)) == [("token", {"t": "x"})]


def test_final_event_without_trailing_blank_line_is_emitted():
    assert list(parse_sse('event: done\ndata: {"domain":"x"}')) == [
        ("done", {"domain": "x"})]


def test_malformed_json_is_skipped_not_fatal():
    stream = 'event: bad\ndata: {oops\n\nevent: token\ndata: {"t":"y"}\n\n'
    assert list(parse_sse(stream)) == [("token", {"t": "y"})]


def test_crlf_line_endings_are_handled():
    assert list(parse_sse('event: token\r\ndata: {"t":"z"}\r\n\r\n')) == [
        ("token", {"t": "z"})]


# ---------------- classify ----------------

def _r(**kw):
    base = {"route": "product", "rows": 5, "err": None, "ntok": 10, "sql": "",
            "clarify": "", "done": True}
    base.update(kw)
    return base


def test_healthy_turn_is_ok():
    assert classify(_r()) == ("OK", "")


def test_empty_result_is_a_failure():
    assert classify(_r(rows=0)) == ("FAIL", "empty_result")


def test_missing_route_is_its_own_class():
    assert classify(_r(route=None)) == ("FAIL", "no_route")


def test_scan_cap_is_its_own_class():
    err = "Query would scan 57.5 GB, exceeding the 50 GB safety cap."
    assert classify(_r(err=err)) == ("FAIL", "scan_cap")


def test_sql_syntax_is_its_own_class():
    assert classify(_r(err='Syntax error: Expected ")"'))[1] == "sql_syntax"


def test_truncated_generation_is_distinct_from_a_syntax_error():
    """Different fix: a cut-off generation needs a SIMPLER query, not a patched one."""
    err = ("Generated SQL is structurally invalid: unterminated ' literal, the query "
           "looks cut off.")
    assert classify(_r(err=err))[1] == "truncated_sql"


def test_clarify_is_scored_as_a_miss_with_its_own_class():
    assert classify(_r(rows=None, clarify="Metrik mana?")) == ("FAIL", "clarify")


def test_timeout_is_reported():
    assert classify(_r(route="TIMEOUT")) == ("FAIL", "timeout")


def test_a_cut_off_capture_is_named_as_such():
    """A stream with no terminal `done` says nothing about the agent.

    This is what a client-timeout or a mid-run backend restart looks like, and it must
    never be reported as the agent failing to answer.
    """
    assert classify(_r(done=False, ntok=0, rows=None)) == ("FAIL", "truncated_capture")


def test_a_complete_turn_is_not_flagged_as_truncated():
    assert classify(_r(done=True)) == ("OK", "")


def test_client_timeout_is_generous_enough_for_a_hard_turn():
    source = (Path(__file__).resolve().parents[1] / "data" / "training"
              / "run_hard_questions.py").read_text()
    assert "DEFAULT_TIMEOUT = 300" in source, (
        "hard analytic turns legitimately take 60-120 s; a tight timeout produces "
        "fake no-answer failures")


# ---------------- runner guards ----------------

def test_partial_runs_do_not_overwrite_the_baseline():
    """--only / --limit must not replace hard_results_latest.json.

    Guards the source directly: a partial run writing the baseline silently destroys
    the numbers the next comparison depends on.
    """
    source = (Path(__file__).resolve().parents[1] / "data" / "training"
              / "run_hard_questions.py").read_text()
    assert "partial = bool(wanted or args.limit)" in source
    assert "if not partial:\n        out_json.write_text" in source


def test_default_run_tag_is_time_based_not_corpus_derived():
    """A constant default tag reuses server-side session ids between runs, which lets
    stored context divert the turn to the advisory path."""
    source = (Path(__file__).resolve().parents[1] / "data" / "training"
              / "run_hard_questions.py").read_text()
    assert 'tag = args.run_tag or time.strftime' in source


def test_fanout_questions_get_a_longer_timeout():
    """PROFILE and CORRELATE run several sub-queries plus a compiled deck."""
    from run_hard_questions import timeout_for, DEFAULT_TIMEOUT, FANOUT_TIMEOUT

    assert timeout_for("Top 10 kecamatan revenue di Surabaya") == DEFAULT_TIMEOUT
    assert timeout_for("Profile lengkap Kota Surabaya") == FANOUT_TIMEOUT
    assert timeout_for("Korelasikan HVC ratio dengan congestion") == FANOUT_TIMEOUT
    assert FANOUT_TIMEOUT > DEFAULT_TIMEOUT


def test_implicit_correlate_questions_also_get_the_long_timeout():
    """The router sends contrast questions to CORRELATE even without the word
    'korelasi', and those fan out just as wide."""
    from run_hard_questions import timeout_for, FANOUT_TIMEOUT, DEFAULT_TIMEOUT

    assert timeout_for(
        "Channel gross add mana yang paling efektif (M1S survival tinggi) per branch"
    ) == FANOUT_TIMEOUT
    assert timeout_for(
        "Kabkota dengan site congest tinggi tapi availability 4G rendah") == FANOUT_TIMEOUT
    assert timeout_for("Berapa revenue prepaid di Kota Malang") == DEFAULT_TIMEOUT
