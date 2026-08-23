"""A table rejected by the policy gate becomes a retrieval hint on the retry.

Without this, the SQL writer can burn all three attempts being rejected for the same
table, and a previously-working question class turns into a hard failure.
"""
from __future__ import annotations

from app import orchestrator


REJECTION = (
    "Table `rham_ref_territory` was not selected for this question. "
    "Regenerate SQL using only the retrieved schema."
)


def test_rejection_message_yields_the_table_name():
    assert orchestrator._policy_rejected_tables(REJECTION) == ["rham_ref_territory"]


def test_multiple_rejected_tables_are_all_returned():
    err = REJECTION + " " + REJECTION.replace("rham_ref_territory", "rham_site_wise_addr_java")
    assert orchestrator._policy_rejected_tables(err) == [
        "rham_ref_territory", "rham_site_wise_addr_java"]


def test_unrelated_errors_yield_no_hint():
    assert orchestrator._policy_rejected_tables("Syntax error: Expected )") == []
    assert orchestrator._policy_rejected_tables(
        "Query would scan 96.6 GB, exceeding the 50 GB safety cap.") == []
    assert orchestrator._policy_rejected_tables(None) == []
    assert orchestrator._policy_rejected_tables("") == []


def test_blocked_table_message_is_not_treated_as_a_hint():
    # A banned/blocked table uses different wording and must never become a hint.
    assert orchestrator._policy_rejected_tables(
        "Table `zz_secret` is blocked by governance.") == []


def test_write_sql_passes_the_hint_into_retrieval(monkeypatch):
    seen = {}

    def fake_schema_for_question(domain_key, question, max_cols_per_table=48,
                                 max_tables=None, table_hints=None):
        seen["hints"] = table_hints
        return "SCHEMA", {"tables": ["rham_ftth_so_detail"], "confidence": 0.9}

    monkeypatch.setattr(orchestrator.knowledge, "schema_for_question",
                        fake_schema_for_question)
    monkeypatch.setattr(orchestrator.knowledge, "load_kb",
                        lambda: {"domains": {"ftth": {"label": "FTTH"}},
                                 "project": "p", "dataset": "d"})
    monkeypatch.setattr(orchestrator.knowledge, "agent_persona", lambda d: "")
    monkeypatch.setattr(orchestrator.knowledge, "data_facts_text", lambda d, q: "")
    monkeypatch.setattr(orchestrator.llm, "chat_json",
                        lambda *a, **k: {"sql": "SELECT 1", "explanation": ""})

    orchestrator.write_sql("ftth", "funnel per kabkota", prior_error=REJECTION,
                           prior_sql="SELECT 1")
    assert seen["hints"] == ["rham_ref_territory"]


def test_first_attempt_sends_no_hint(monkeypatch):
    seen = {}

    def fake_schema_for_question(domain_key, question, max_cols_per_table=48,
                                 max_tables=None, table_hints=None):
        seen["hints"] = table_hints
        return "SCHEMA", {"tables": ["rham_ftth_so_detail"], "confidence": 0.9}

    monkeypatch.setattr(orchestrator.knowledge, "schema_for_question",
                        fake_schema_for_question)
    monkeypatch.setattr(orchestrator.knowledge, "load_kb",
                        lambda: {"domains": {"ftth": {"label": "FTTH"}},
                                 "project": "p", "dataset": "d"})
    monkeypatch.setattr(orchestrator.knowledge, "agent_persona", lambda d: "")
    monkeypatch.setattr(orchestrator.knowledge, "data_facts_text", lambda d, q: "")
    monkeypatch.setattr(orchestrator.llm, "chat_json",
                        lambda *a, **k: {"sql": "SELECT 1", "explanation": ""})

    orchestrator.write_sql("ftth", "funnel per kabkota")
    assert seen["hints"] is None
