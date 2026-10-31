"""The live benchmark must score a wrong route as a failure.

The corpus always carried an expected domain per line, but `classify()` never
compared it, so a question answered from the WRONG domain scored OK as long as
rows came back. A routing regression was therefore invisible to the benchmark
whose job is to catch it.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

RUNNER = (Path(__file__).resolve().parent.parent
          / "data" / "training" / "run_hard_questions.py")
_spec = importlib.util.spec_from_file_location("run_hard_questions", RUNNER)
runner = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(runner)


def _good(route="product", rows=5):
    return {"route": route, "rows": rows, "err": None, "ntok": 40,
            "sql": "SELECT 1", "clarify": "", "done": True}


def test_a_correct_route_passes():
    assert runner.classify(_good(), "product") == ("OK", "")


def test_a_wrong_route_fails_even_with_rows():
    status, cls = runner.classify(_good(route="revenue"), "product")
    assert (status, cls) == ("FAIL", "wrong_route")


def test_multi_accepts_any_route():
    assert runner.classify(_good(route="PROFILE"), "multi") == ("OK", "")


def test_no_expectation_keeps_the_old_behaviour():
    assert runner.classify(_good(route="anything"), "") == ("OK", "")


def test_a_more_specific_failure_wins_over_the_route_check():
    # An error tells the operator what to fix; "wrong_route" would bury it.
    bad = _good(route="revenue")
    bad["err"] = "Syntax error: Unexpected keyword LIMIT"
    assert runner.classify(bad, "product") == ("FAIL", "sql_syntax")


def test_an_empty_result_still_fails_before_the_route_check():
    empty = _good(route="revenue", rows=0)
    assert runner.classify(empty, "product") == ("FAIL", "empty_result")


def test_the_onboarding_corpus_is_loadable_and_uses_known_domains():
    from app import knowledge

    corpus = RUNNER.parent / "precalc_onboarding_questions.txt"
    cases = runner.load_cases(corpus)
    assert len(cases) >= 15
    domains = set(knowledge.load_kb()["domains"])
    for expected, question in cases:
        assert expected in domains, f"unknown domain {expected}"
        assert question.strip()
