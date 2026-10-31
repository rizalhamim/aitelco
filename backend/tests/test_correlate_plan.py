"""Correlation planner validity: A and B must be two DIFFERENT domains."""
from __future__ import annotations

import pytest

from app import correlate_agent


def _plan(da, db, qa="q a", qb="q b"):
    return {"sub_a": {"domain": da, "question": qa},
            "sub_b": {"domain": db, "question": qb}}


def test_two_different_domains_is_valid():
    assert correlate_agent.plan_is_valid(_plan("customer_hvc", "network"))


def test_same_domain_is_invalid():
    assert not correlate_agent.plan_is_valid(_plan("competitive", "competitive"))


def test_missing_domain_is_invalid():
    assert not correlate_agent.plan_is_valid(_plan("", "network"))
    assert not correlate_agent.plan_is_valid(_plan("network", ""))


def test_missing_subquestion_is_invalid():
    assert not correlate_agent.plan_is_valid(_plan("network", "product", qa=""))
    assert not correlate_agent.plan_is_valid(_plan("network", "product", qb="   "))


def test_non_dict_is_invalid():
    assert not correlate_agent.plan_is_valid(None)
    assert not correlate_agent.plan_is_valid([])


def test_retry_recovers_a_valid_two_domain_plan(monkeypatch):
    calls = []

    def fake_chat_json(msgs, **kw):
        calls.append(msgs)
        if len(calls) == 1:
            return {"domain_a": "competitive", "question_a": "share",
                    "domain_b": "competitive", "question_b": "soga"}
        return {"domain_a": "competitive", "question_a": "share",
                "domain_b": "kpi_summary", "question_b": "soga"}

    monkeypatch.setattr(correlate_agent.llm, "chat_json", fake_chat_json)
    monkeypatch.setattr(correlate_agent.knowledge, "domain_overview_text", lambda q: "")

    plan = correlate_agent.plan_correlation("soga tinggi tapi share rendah")
    assert correlate_agent.plan_is_valid(plan)
    assert plan["sub_a"]["domain"] != plan["sub_b"]["domain"]
    assert len(calls) == 2, "planner should retry exactly once on a same-domain plan"
    assert "REJECTED" in calls[1][-1]["content"]


def test_persistent_same_domain_falls_back_instead_of_shipping_invalid(monkeypatch):
    def fake_chat_json(msgs, **kw):
        return {"domain_a": "customer_hvc", "question_a": "ratio",
                "domain_b": "customer_hvc", "question_b": "churn"}

    monkeypatch.setattr(correlate_agent.llm, "chat_json", fake_chat_json)
    monkeypatch.setattr(correlate_agent.knowledge, "domain_overview_text", lambda q: "")

    plan = correlate_agent.plan_correlation("hvc ratio tinggi tapi churn hvc tinggi")
    assert plan.get("invalid") == "same_domain"
    assert plan.get("single_domain") == "customer_hvc"
    assert not correlate_agent.plan_is_valid(plan)


def test_planner_may_declare_single_domain_explicitly(monkeypatch):
    calls = []

    def fake_chat_json(msgs, **kw):
        calls.append(msgs)
        if len(calls) == 1:
            return {"domain_a": "competitive", "question_a": "a",
                    "domain_b": "competitive", "question_b": "b"}
        return {"single_domain": "competitive"}

    monkeypatch.setattr(correlate_agent.llm, "chat_json", fake_chat_json)
    monkeypatch.setattr(correlate_agent.knowledge, "domain_overview_text", lambda q: "")

    plan = correlate_agent.plan_correlation("soga vs market share")
    assert plan.get("invalid") == "single_domain"
    assert plan.get("single_domain") == "competitive"


def test_planner_failure_returns_invalid_not_exception(monkeypatch):
    monkeypatch.setattr(correlate_agent.llm, "chat_json", lambda msgs, **kw: "not-a-dict")
    monkeypatch.setattr(correlate_agent.knowledge, "domain_overview_text", lambda q: "")
    plan = correlate_agent.plan_correlation("x")
    assert plan.get("invalid")
