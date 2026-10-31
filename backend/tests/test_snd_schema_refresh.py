"""Regression gates for the unified SND metrics and resolved serving views."""
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from google.cloud import bigquery

import tools_knowledge_refresh as refresh
from app import knowledge, profile_engine, reports_comprehensive


def test_serving_view_uses_resolved_schema_without_executing():
    table = SimpleNamespace(
        table_id="rham_hvc_highlevel_mtd_serving",
        full_table_id="data-java-prd-97b9:java_precalc.rham_hvc_highlevel_mtd_serving",
        schema=[bigquery.SchemaField("primary_all", "FLOAT")],
    )
    client = Mock()
    client.query.return_value.schema = [bigquery.SchemaField("primary", "FLOAT")]
    assert refresh._inventory_columns(client, table)[0]["name"] == "primary"
    sql = client.query.call_args.args[0]
    assert "WHERE FALSE" in sql
    options = client.query.call_args.kwargs["job_config"]
    assert options.dry_run is True
    assert options.use_query_cache is False


def test_missing_resolved_view_schema_fails_closed():
    table = SimpleNamespace(
        table_id="rham_hvc_highlevel_mth_serving",
        full_table_id="project:dataset.rham_hvc_highlevel_mth_serving",
        schema=[],
    )
    client = Mock()
    client.query.return_value.schema = None
    with pytest.raises(ValueError, match="Could not resolve"):
        refresh._inventory_columns(client, table)


def test_regular_tables_keep_physical_metadata_without_querying():
    client = Mock()
    table = SimpleNamespace(
        table_id="rham_snd_kpi_highlevel_mth",
        schema=[bigquery.SchemaField("outlet_total", "FLOAT")],
    )
    assert refresh._inventory_columns(client, table)[0]["name"] == "outlet_total"
    client.query.assert_not_called()


def test_reviewed_distribution_guidance_is_idempotent_and_scoped():
    kb = {"domains": {
        "sales_distribution": {"agent": {
            "persona": "SND KPIs: rham_snd_kpi_highlevel_dly (165 cols daily) + rham_snd_kecwise_mtd/mth.",
            "key_facts": ["M1S/M2S/M3 (=surv_m1/m2/m3)=old.", "QSSO / QURO GRAIN: old."],
        }},
        "kpi_summary": {"agent": {"key_facts": []}},
        "territory_reference": {"agent": {"key_facts": [
            "Current zz_territory_kecamatan.super_gtm labels are exactly old.",
        ]}},
        "competitive": {"agent": {"key_facts": []}},
        "customer_hvc": {"agent": {"key_facts": ["Preserve HVC reliability."]}},
    }}
    refresh._refresh_distribution_guidance(kb)
    first = deepcopy(kb)
    refresh._refresh_distribution_guidance(kb)
    assert kb == first
    snd = kb["domains"]["sales_distribution"]["agent"]
    assert "54 unified metrics" in snd["persona"]
    assert "ga_m1s/ga_m2s" in snd["key_facts"][0]
    assert "qsso_m0 and quro" in snd["key_facts"][1]
    assert "Preserve NULL" in snd["key_facts"][-1]
    territory = kb["domains"]["territory_reference"]["agent"]["key_facts"]
    assert len(territory) == 1
    assert "legacy/unclassified" in territory[0]
    assert kb["domains"]["customer_hvc"]["agent"]["key_facts"] == ["Preserve HVC reliability."]


def test_kpi_summary_guidance_replaces_its_older_version():
    stale = "Marketing highlevel SND columns (2026-10-08): q_uro remain zero placeholders."
    kb = {"domains": {"kpi_summary": {"agent": {"key_facts": ["Keep me.", stale]}}}}
    refresh._refresh_distribution_guidance(kb)
    facts = kb["domains"]["kpi_summary"]["agent"]["key_facts"]
    assert facts[0] == "Keep me." and stale not in facts and len(facts) == 2
    assert "were dropped" in facts[1]


def test_report_codes_stay_compatible_while_source_columns_are_current():
    trade = next(s for s in reports_comprehensive.SECTIONS if s["title"] == "Trade")
    metrics = {m["code"]: m for m in trade["metrics"]}
    assert metrics["primary_all"]["expr"] == "m.`primary`"
    assert metrics["secondary_nat"]["expr"] == "m.secondary"
    assert "tertiary_a_nat" not in metrics


def test_profile_question_uses_unified_snd_metric_names():
    section = next(s for s in profile_engine.PROFILE_SECTIONS_FULL
                   if s["section_title"] == "Sales & Distribution KPI")
    assert "outlet_total" in section["question_template"]
    assert "qsso_m0" in section["question_template"]
    assert "total_outlet" not in section["question_template"]


def test_snd_contract_retains_metric_aliases_and_partition_constraints():
    item = {
        "name": "rham_snd_kpi_highlevel_mth", "type": "TABLE",
        "partition_field": "mth_dt", "partition_type": "MONTH",
        "columns": [], "bytes": 0,
    }
    contract = refresh._contract(item["name"], item)
    assert contract["grain"] == "kecamatan_x_brand"
    assert {"ono", "osa", "total outlet"}.issubset(contract["aliases"])
    assert any("mth_dt" in rule for rule in contract["use_constraints"])


@pytest.mark.parametrize("second_columns,needs_reference", [
    (["kec_unik", "tertiary_b"], True),
    (["kabkota", "tertiary_b"], False),
])
def test_secondary_source_gets_required_approved_territory_reference(
    monkeypatch, second_columns, needs_reference
):
    monkeypatch.setattr(knowledge, "load_kb", lambda: {
        "domains": {"sales_distribution": {"label": "SND", "description": "SND"}},
    })
    monkeypatch.setattr(knowledge, "selection_for_question", lambda *a, **kw: {
        "tables": ["outlet_native", "snd"], "confidence": 1,
    })
    monkeypatch.setattr(knowledge, "table_index", lambda: {
        "outlet_native": {"columns": [{"name": "kabkota"}]},
        "snd": {"columns": [{"name": name} for name in second_columns]},
    })
    monkeypatch.setattr(knowledge, "approved_table_names", lambda: {
        "outlet_native", "snd", "zz_territory_kecamatan",
    })
    monkeypatch.setattr(knowledge, "_schema_for_named_tables", lambda *a: "schema")
    _, selection = knowledge.schema_for_question("sales_distribution", "Trade kabkota Surabaya")
    assert ("zz_territory_kecamatan" in selection["tables"]) is needs_reference
