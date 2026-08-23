"""Load-bearing rules in the SQL generation prompt.

These are not style preferences: each one was added after a measured production failure,
and losing one silently reintroduces a class of empty or wrong answers.
"""
from __future__ import annotations

from app import orchestrator


PROMPT = orchestrator.SQL_SYS


def test_prompt_forbids_invented_thresholds():
    """Kabkota 4G availability spans 98.77 to 100.0, so `< 95` matches nothing."""
    assert "RANK, DO NOT GUESS A THRESHOLD" in PROMPT
    assert "APPROX_QUANTILES" in PROMPT


def test_prompt_warns_about_sign_conventions():
    """Some churn columns are stored negative, so a `> 0` filter never matches."""
    assert "ABS()" in PROMPT


def test_prompt_still_requires_partition_bounding():
    assert "ALWAYS bound cost" in PROMPT


def test_prompt_still_forbids_inventing_columns():
    assert "DO NOT invent column names" in PROMPT


def test_prompt_still_carries_the_month_id_arithmetic_rule():
    assert "NEVER do integer math" in PROMPT


def test_prompt_forbids_a_shared_period_cte():
    """Tables have different refresh coverage: occupancy stops at 202512 while
    availability runs to the current month, so a shared-month CTE yields nothing."""
    assert "NEVER force TWO tables onto a single shared period" in PROMPT
    assert "common_month" in PROMPT
