"""Discovery and promotion gates for the java_precalc governance tooling.

The failure these guard against is silent: before the delta gate existed, a new
table, a dropped approved table, or a changed schema all exited zero, so the
daily audit reported success while the runtime KB described a warehouse that no
longer matched BigQuery.
"""
from __future__ import annotations

import pytest

import tools_knowledge_refresh as tkr


def _item(name: str, columns=None, **overrides):
    item = {
        "name": name,
        "type": "TABLE",
        "rows": 10,
        "bytes": 1024,
        "modified": "2026-09-17T00:00:00+00:00",
        "partition_field": "dt_id",
        "partition_type": "DAY",
        "clustering_fields": [],
        "description": None,
        "columns": columns or [
            {"name": "dt_id", "type": "DATE", "mode": "NULLABLE", "description": None},
            {"name": "revenue", "type": "FLOAT", "mode": "NULLABLE", "description": None},
        ],
    }
    item.update(overrides)
    return item


def _governance(records: dict) -> dict:
    return {"schema_version": 1, "objects": records}


def _approved(item, domain="revenue", **overrides):
    record = {
        "lifecycle": "approved",
        "object_class": "aggregate",
        "policy": "runtime_allowed",
        "domain": domain,
        "reason": "Reviewed.",
        "review_id": "test-review",
        "schema_hash": tkr._schema_hash(item),
        "physical_hash": tkr._physical_hash(item),
        "decision_history": [{
            "review_id": "test-review",
            "decision": "approved",
            "reason": "Reviewed.",
            "reviewed_at": "2026-09-17",
        }],
        "replacement_table": None,
    }
    record.update(overrides)
    return record


def test_an_ungoverned_live_table_is_reported_and_fails_the_gate():
    item = _item("rham_brand_new")
    catalog = tkr.merge_catalog({"tables": [item]}, _governance({}))
    assert catalog["delta"]["new_objects"] == ["rham_brand_new"]
    assert "ungoverned new object: rham_brand_new" in tkr.validate_catalog(catalog)


def test_an_ungoverned_table_defaults_to_candidate_and_never_to_approved():
    catalog = tkr.merge_catalog({"tables": [_item("rham_brand_new")]}, _governance({}))
    decision = catalog["tables"][0]["governance"]
    assert decision["lifecycle"] == "candidate"
    assert decision["policy"] == "not_runtime_allowed"
    assert decision["domain"] is None


def test_a_dropped_approved_table_fails_the_gate():
    live = _item("rham_still_here")
    gone = _item("rham_deleted")
    governance = _governance({
        "rham_still_here": _approved(live),
        "rham_deleted": _approved(gone),
    })
    catalog = tkr.merge_catalog({"tables": [live]}, governance)
    assert catalog["delta"]["missing_approved_objects"] == ["rham_deleted"]
    assert any("missing from the live dataset" in e for e in tkr.validate_catalog(catalog))


def test_schema_drift_on_an_approved_table_fails_the_gate():
    item = _item("rham_drifting")
    governance = _governance({
        "rham_drifting": _approved(item, schema_hash="stale-hash")})
    catalog = tkr.merge_catalog({"tables": [item]}, governance)
    assert catalog["delta"]["schema_drift"][0]["name"] == "rham_drifting"
    assert any("schema drift" in e for e in tkr.validate_catalog(catalog))


def test_partition_drift_on_an_approved_table_fails_the_gate():
    item = _item("rham_repartitioned")
    governance = _governance({
        "rham_repartitioned": _approved(item, physical_hash="stale-physical")})
    catalog = tkr.merge_catalog({"tables": [item]}, governance)
    assert catalog["delta"]["partition_drift"][0]["name"] == "rham_repartitioned"
    assert any("partition drift" in e for e in tkr.validate_catalog(catalog))


def test_a_record_without_a_physical_hash_is_not_reported_as_drift():
    # Pre-existing records predate physical hashing. Flagging them all would force
    # a blind mass re-review and destroy the signal.
    item = _item("rham_legacy")
    record = _approved(item)
    del record["physical_hash"]
    catalog = tkr.merge_catalog({"tables": [item]}, _governance({"rham_legacy": record}))
    assert catalog["delta"]["partition_drift"] == []
    assert tkr.validate_catalog(catalog) == []


def test_a_clean_dataset_passes_the_gate():
    item = _item("rham_clean")
    catalog = tkr.merge_catalog({"tables": [item]}, _governance({"rham_clean": _approved(item)}))
    assert tkr.validate_catalog(catalog) == []


def test_drift_on_a_candidate_does_not_block_the_gate():
    # A candidate is not in the runtime KB, so its schema changing harms nothing.
    item = _item("rham_candidate")
    governance = _governance({"rham_candidate": {
        "lifecycle": "candidate",
        "object_class": "aggregate",
        "policy": "not_runtime_allowed",
        "domain": None,
        "reason": "Pending review.",
        "review_id": "test-review",
        "schema_hash": "stale-hash",
        "decision_history": [{"decision": "candidate"}],
    }})
    catalog = tkr.merge_catalog({"tables": [item]}, governance)
    assert catalog["delta"]["schema_drift"]
    assert tkr.validate_catalog(catalog) == []


def test_promote_refuses_an_approved_table_with_schema_drift():
    item = _item("rham_drifting")
    catalog = tkr.merge_catalog(
        {"tables": [item]},
        _governance({"rham_drifting": _approved(item, schema_hash="stale-hash")}))
    kb = {"domains": {"revenue": {"tables": {}}}}
    with pytest.raises(ValueError, match="unreviewed schema drift"):
        tkr.promote(kb, catalog)


def test_promote_refuses_an_approved_table_with_partition_drift():
    item = _item("rham_repartitioned")
    catalog = tkr.merge_catalog(
        {"tables": [item]},
        _governance({"rham_repartitioned": _approved(item, physical_hash="stale")}))
    kb = {"domains": {"revenue": {"tables": {}}}}
    with pytest.raises(ValueError, match="partition or clustering"):
        tkr.promote(kb, catalog)


def test_promote_refuses_an_unknown_domain():
    item = _item("rham_orphan")
    catalog = tkr.merge_catalog(
        {"tables": [item]},
        _governance({"rham_orphan": _approved(item, domain="not_a_domain")}))
    kb = {"domains": {"revenue": {"tables": {}}}}
    with pytest.raises(ValueError, match="no valid domain"):
        tkr.promote(kb, catalog)


def test_promote_admits_only_approved_objects():
    approved_item = _item("rham_ok")
    blocked_item = _item("rham_blocked")
    catalog = tkr.merge_catalog(
        {"tables": [approved_item, blocked_item]},
        _governance({
            "rham_ok": _approved(approved_item),
            "rham_blocked": {
                "lifecycle": "quarantined",
                "object_class": "raw",
                "policy": "hard_block",
                "domain": None,
                "reason": "Raw.",
                "review_id": "test-review",
                "schema_hash": tkr._schema_hash(blocked_item),
                "decision_history": [{"decision": "quarantined"}],
            },
        }))
    kb = tkr.promote({"domains": {"revenue": {"tables": {}}}}, catalog)
    assert "rham_ok" in kb["domains"]["revenue"]["tables"]
    assert "rham_blocked" not in kb["domains"]["revenue"]["tables"]


def test_a_reviewed_contract_survives_a_physical_metadata_refresh():
    # The regression this catches: every promotion used to overwrite reviewed
    # grain/period/aliases with name-based guesses, silently undoing the review.
    item = _item("rham_reviewed")
    catalog = tkr.merge_catalog(
        {"tables": [item]}, _governance({"rham_reviewed": _approved(item)}))
    kb = {"domains": {"revenue": {"tables": {"rham_reviewed": {
        "description": "Reviewed description.",
        "grain": "kecamatan_x_brand_x_tenure",
        "period_semantics": "mtd_latest_cutoff_only",
        "aggregation_rule": "sum_components_then_recompute_ratio",
        "aliases": ["tenure", "tnr"],
        "columns": [],
    }}}}}
    promoted = tkr.promote(kb, catalog)
    table = promoted["domains"]["revenue"]["tables"]["rham_reviewed"]
    assert table["grain"] == "kecamatan_x_brand_x_tenure"
    assert table["period_semantics"] == "mtd_latest_cutoff_only"
    assert table["aliases"] == ["tenure", "tnr"]
    assert table["description"] == "Reviewed description."
    # Physical metadata IS refreshed.
    assert table["rows"] == 10
    assert table["schema_hash"] == tkr._schema_hash(item)


def test_a_contract_override_beats_the_name_heuristics(monkeypatch):
    item = _item("rham_kec_wise_tnr_mth")
    monkeypatch.setitem(
        tkr.CONTRACT_OVERRIDES, "rham_kec_wise_tnr_mth",
        {"grain": "kecamatan_x_brand_x_tenure", "period_semantics": "monthly_closed"})
    contract = tkr._contract("rham_kec_wise_tnr_mth", item)
    assert contract["grain"] == "kecamatan_x_brand_x_tenure"
    assert contract["period_semantics"] == "monthly_closed"
    # The heuristic partition constraint is kept, not replaced.
    assert any("dt_id" in c for c in contract["use_constraints"])


def test_validate_state_rejects_an_approved_record_with_a_blocking_policy():
    item = _item("rham_bad_policy")
    governance = _governance({
        "rham_bad_policy": _approved(item, policy="hard_block")})
    errors = tkr.validate_state({"domains": {}}, governance)
    assert any("must use runtime_allowed" in e for e in errors)


def test_validate_state_rejects_a_superseded_record_without_a_replacement():
    governance = _governance({"rham_old": {
        "lifecycle": "superseded",
        "object_class": "aggregate",
        "policy": "hard_block",
        "domain": None,
        "reason": "Replaced.",
        "review_id": "test-review",
        "schema_hash": "x",
        "decision_history": [{"decision": "superseded"}],
        "replacement_table": None,
    }})
    errors = tkr.validate_state({"domains": {}}, governance)
    assert any("requires a replacement_table" in e for e in errors)


def test_validate_state_rejects_a_kb_table_with_no_governance_decision():
    kb = {"domains": {"revenue": {"tables": {"rham_ghost": {}}}}}
    errors = tkr.validate_state(kb, _governance({}))
    assert any("no governance decision: rham_ghost" in e for e in errors)
