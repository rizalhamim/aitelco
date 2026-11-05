"""Latency levers of the 2026-11 agent rework: each one skips a model call only when a
deterministic check already establishes what the call would have said."""
from app import orchestrator as o


def test_requested_grain_reads_explicit_groupings_only():
    assert o.requested_grain("revenue per kabupaten bulan ini") == "kabkota"
    assert o.requested_grain("payload tiap kecamatan di Garut") == "kecamatan"
    assert o.requested_grain("trend revenue per bulan") == "month"
    assert o.requested_grain("GA by micro cluster") == "district"
    assert o.requested_grain("revenue Kabupaten Bandung") is None


def test_result_has_grain_matches_column_families():
    assert o.result_has_grain(["kabupaten", "revenue"], "kabkota")
    assert o.result_has_grain(["kec_id", "kecamatan", "rev"], "kecamatan")
    assert o.result_has_grain(["month_id", "revenue"], "month")
    assert o.result_has_grain(["branch_im3", "ga"], "area")
    assert not o.result_has_grain(["region", "revenue"], "kabkota")


def test_reroute_only_when_the_analyst_changed_the_question():
    q = "revenue per kabupaten di jawa barat bulan ini"
    assert not o.needs_reroute_after_analyst(
        q, "revenue by kabupaten in West Java for the latest month",
        "revenue per kabupaten Jawa Barat untuk month_id terbaru")
    assert o.needs_reroute_after_analyst(
        "gimana performanya?", "performance overview",
        "market share IOH vs Telkomsel per kecamatan Bandung bulan September")
    assert not o.needs_reroute_after_analyst(q, q, "")
