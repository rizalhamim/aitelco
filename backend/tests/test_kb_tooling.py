"""Guards for the KB edit tool and the runtime graph artifact.

A KB edit that skips the graph rebuild leaves the backend on a silent in-memory
fallback with a degraded health status, so the invariant is worth a test.
"""
from __future__ import annotations

import json

import pytest

import tools_kb_edit as kbe
from app import knowledge
from app.knowledge_graph import graph_health


def test_runtime_graph_artifact_matches_the_current_kb():
    health = graph_health(knowledge.load_kb())
    assert health["status"] == "ok", (
        "runtime_knowledge_graph.json is stale for the current knowledge_base.json. "
        "Run: venv/bin/python tools_runtime_graph.py")
    assert health["source"] == "artifact"


def test_facts_list_returns_a_mutable_list_for_a_known_domain():
    kb = kbe.load()
    facts = kbe.facts_list(kb, "ftth")
    assert isinstance(facts, list) and facts


def test_facts_list_rejects_a_non_list_key_facts():
    kb = {"domains": {"x": {"agent": {"key_facts": {"a": 1}}}}}
    with pytest.raises(SystemExit):
        kbe.facts_list(kb, "x")


def test_facts_list_creates_the_container_when_absent():
    kb = {"domains": {"x": {}}}
    assert kbe.facts_list(kb, "x") == []
    assert kb["domains"]["x"]["agent"]["key_facts"] == []


def test_ftth_sales_region_fact_is_present():
    facts = kbe.facts_list(kbe.load(), "ftth")
    joined = " ".join(f if isinstance(f, str) else json.dumps(f) for f in facts)
    assert "province" in joined and "sales_region" in joined, (
        "the FTTH sales-region-is-not-geography fact is missing")


def test_revenue_scan_cap_fact_is_present():
    facts = kbe.facts_list(kbe.load(), "revenue")
    joined = " ".join(f if isinstance(f, str) else json.dumps(f) for f in facts)
    assert "SCAN-CAP" in joined, "the revenue daily-table scan-cap fact is missing"
