"""Deterministic contrast-pair assist for implicit cross-domain routing."""
from __future__ import annotations

from app import orchestrator


def test_no_contrast_marker_yields_no_hint():
    assert orchestrator.contrast_domain_hint(
        "Berapa revenue prepaid di Kota Malang bulan ini") == ""


def test_korelasi_wording_without_contrast_marker_is_left_to_the_router():
    # Explicit "korelasikan" is already handled by the router prompt.
    assert orchestrator.contrast_domain_hint("Korelasikan availability 5G dengan revenue") == ""


def test_contrast_pair_across_two_domains_produces_a_hint(monkeypatch):
    scores = {"acquisition": 0.9, "sales_distribution": 0.8, "network": 0.2}

    monkeypatch.setattr(orchestrator.knowledge, "load_kb",
                        lambda: {"domains": {k: {} for k in scores}})
    monkeypatch.setattr(
        orchestrator.knowledge, "selection_for_question",
        lambda d, q, max_tables=None: {"confidence": scores[d], "tables": ["t"]})

    hint = orchestrator.contrast_domain_hint(
        "Kabkota dengan gross add tinggi tapi M1S survival rendah")
    assert "acquisition" in hint and "sales_distribution" in hint
    assert "CORRELATE" in hint
    assert "ignore this hint" in hint


def test_single_strong_domain_yields_no_hint(monkeypatch):
    scores = {"competitive": 0.95, "network": 0.10}
    monkeypatch.setattr(orchestrator.knowledge, "load_kb",
                        lambda: {"domains": {k: {} for k in scores}})
    monkeypatch.setattr(
        orchestrator.knowledge, "selection_for_question",
        lambda d, q, max_tables=None: {"confidence": scores[d], "tables": ["t"]})

    assert orchestrator.contrast_domain_hint(
        "Kabkota dengan SOGA IM3 tinggi tapi market share masih rendah") == ""


def test_hint_is_advisory_and_never_forces_correlate(monkeypatch):
    scores = {"product": 0.88, "5g": 0.71}
    monkeypatch.setattr(orchestrator.knowledge, "load_kb",
                        lambda: {"domains": {k: {} for k in scores}})
    monkeypatch.setattr(
        orchestrator.knowledge, "selection_for_question",
        lambda d, q, max_tables=None: {"confidence": scores[d], "tables": ["t"]})

    hint = orchestrator.contrast_domain_hint(
        "revenue paket data turun MoM tapi 5G penetration justru naik")
    assert "advisory" in hint
    assert "route to that single domain" in hint


def test_retrieval_failure_is_swallowed(monkeypatch):
    def boom(domain, question, max_tables=None):
        raise RuntimeError("retrieval down")

    monkeypatch.setattr(orchestrator.knowledge, "load_kb",
                        lambda: {"domains": {"a": {}, "b": {}}})
    monkeypatch.setattr(orchestrator.knowledge, "selection_for_question", boom)
    assert orchestrator.contrast_domain_hint("x tinggi tapi y rendah") == ""
