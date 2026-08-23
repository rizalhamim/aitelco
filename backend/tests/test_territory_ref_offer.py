"""Province-scoped questions must be able to join the canonical territory reference.

Most fact tables carry kabkota/kecamatan but no province column, so without this the
policy gate rejects a legitimate join and the turn fails all three attempts.
"""
from __future__ import annotations

import pytest

from app import knowledge, orchestrator


def test_province_question_needs_the_reference():
    assert knowledge.question_needs_territory_ref(
        "Kecamatan mana di Jawa Timur yang share revenue non-data paling tinggi")


def test_region_and_branch_questions_need_the_reference():
    assert knowledge.question_needs_territory_ref("revenue per region bulan ini")
    assert knowledge.question_needs_territory_ref("top branch di circle Java")


def test_plain_kabkota_question_does_not_need_the_reference():
    assert not knowledge.question_needs_territory_ref(
        "Top 10 kecamatan dengan revenue tertinggi di Kota Surabaya")


def test_reference_tables_are_governance_approved():
    approved = knowledge.approved_table_names()
    for name in knowledge.TERRITORY_REF_TABLES:
        assert name in approved, f"{name} is not approved; do not offer it to the SQL writer"


def _patch_write_sql(monkeypatch, captured, domain_tables):
    def fake_schema_for_question(domain_key, question, max_cols_per_table=48,
                                 max_tables=None, table_hints=None):
        return "FACT SCHEMA", {"tables": list(domain_tables), "confidence": 0.9}

    monkeypatch.setattr(knowledge, "schema_for_question", fake_schema_for_question)
    monkeypatch.setattr(knowledge, "load_kb",
                        lambda: {"domains": {"product": {"label": "Product"},
                                             "territory_reference": {"label": "Ref"}},
                                 "project": "p", "dataset": "d"})
    monkeypatch.setattr(knowledge, "agent_persona", lambda d: "")
    monkeypatch.setattr(knowledge, "data_facts_text", lambda d, q: "")
    monkeypatch.setattr(knowledge, "territory_ref_schema", lambda q="": "REF SCHEMA")
    monkeypatch.setattr(knowledge, "approved_territory_ref_tables",
                        lambda: list(knowledge.TERRITORY_REF_TABLES))

    def fake_chat_json(msgs, **kw):
        captured["system"] = msgs[0]["content"]
        return {"sql": "SELECT 1", "explanation": ""}

    monkeypatch.setattr(orchestrator.llm, "chat_json", fake_chat_json)


def test_province_question_gets_the_reference_in_allowed_tables(monkeypatch):
    captured = {}
    _patch_write_sql(monkeypatch, captured, ["rham_site_data_rev_product_mtd"])
    out = orchestrator.write_sql(
        "product", "Kecamatan mana di Jawa Timur yang share revenue non-data tertinggi")
    assert "zz_territory_kecamatan" in out["_allowed_tables"]
    assert "TERRITORY REFERENCE" in captured["system"]


def test_kabkota_only_question_does_not_widen_allowed_tables(monkeypatch):
    captured = {}
    _patch_write_sql(monkeypatch, captured, ["rham_site_data_rev_product_mtd"])
    out = orchestrator.write_sql(
        "product", "revenue produk di Kota Surabaya bulan ini")
    assert "zz_territory_kecamatan" not in out["_allowed_tables"]
    assert "TERRITORY REFERENCE" not in captured["system"]


def test_ungoverned_reference_is_never_added_to_allowed_tables(monkeypatch):
    # If governance quarantines the reference, it must drop out of the allowed set,
    # not just out of the schema text.
    captured = {}
    _patch_write_sql(monkeypatch, captured, ["rham_site_data_rev_product_mtd"])
    monkeypatch.setattr(knowledge, "approved_territory_ref_tables", list)
    out = orchestrator.write_sql("product", "revenue per region bulan ini")
    assert out["_allowed_tables"] == ["rham_site_data_rev_product_mtd"]
    assert "TERRITORY REFERENCE" not in captured["system"]


def test_approved_filter_uses_the_governance_list(monkeypatch):
    monkeypatch.setattr(knowledge, "approved_table_names",
                        lambda: {"zz_territory_kecamatan"})
    assert knowledge.approved_territory_ref_tables() == ["zz_territory_kecamatan"]


def test_territory_domain_itself_is_not_double_offered(monkeypatch):
    captured = {}
    _patch_write_sql(monkeypatch, captured, ["zz_territory_kecamatan"])
    out = orchestrator.write_sql("territory_reference", "region mapping per province")
    assert out["_allowed_tables"].count("zz_territory_kecamatan") == 1
    assert "TERRITORY REFERENCE" not in captured["system"]
