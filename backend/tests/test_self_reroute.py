"""A domain that reroutes to ITSELF is reporting a retrieval miss, not out-of-scope.

Observed live: the `competitive` scope gate rerouted to `competitive` because the
kabkota market-share table was not in the subset it was shown. The suggestion was
discarded, the turn bounced through a second domain, and the user got
"di luar cakupan data" for a question the warehouse can answer.
"""
from __future__ import annotations

from app import orchestrator


REASON = ("Butuh grain kabkota, tapi tabel yang tersedia di retrieval saya hanya "
          "mp3_3kiosk_region dan region, tidak ada rham_report_fb_ms_kabkota di domain "
          "saya saat ini.")


def test_table_named_in_the_gate_reason_is_extracted():
    assert orchestrator.tables_named_in(REASON, "competitive") == [
        "rham_report_fb_ms_kabkota"]


def test_a_table_from_another_domain_is_not_returned():
    # Only tables belonging to the named domain may become hints, so this can never
    # widen the policy gate.
    text = "should use rham_site_fwa_daily instead"
    assert orchestrator.tables_named_in(text, "competitive") == []


def test_empty_or_missing_reason_is_safe():
    assert orchestrator.tables_named_in("", "competitive") == []
    assert orchestrator.tables_named_in(None, "competitive") == []
    assert orchestrator.tables_named_in("no table here", "competitive") == []


def test_unknown_domain_is_safe():
    assert orchestrator.tables_named_in(REASON, "not_a_domain") == []


def test_only_approved_tables_are_returned():
    approved = orchestrator.knowledge.approved_table_names()
    for name in orchestrator.tables_named_in(REASON, "competitive"):
        assert name in approved


def test_write_sql_accepts_scope_table_hints():
    import inspect

    params = inspect.signature(orchestrator.write_sql).parameters
    assert "table_hints" in params, (
        "the scope gate needs to pass the table it named into SQL generation")


def test_scope_table_hints_is_initialised_outside_the_gate():
    """The fast path and map mode SKIP the scope gate but still reach SQL generation.

    Initialising the variable inside the gate raised
    "cannot access local variable 'scope_table_hints'" on every fast-path turn, which
    broke 17 of 30 benchmark questions at once. Static check because the streaming
    generator cannot be exercised without a live server.
    """
    from pathlib import Path

    source = (Path(__file__).resolve().parents[1] / "app" / "main.py").read_text()
    init = source.find("scope_table_hints = None")
    gate = source.find('if not req.map_context and not fast_flow.get("safe")')
    use = source.find("table_hints=scope_table_hints")
    assert init != -1 and gate != -1 and use != -1
    assert init < gate, "initialise before the gate, which the fast path skips"
    assert init < use


def test_every_write_sql_call_site_can_reach_its_arguments():
    """No name used in a write_sql call may be defined only inside a branch."""
    import ast
    from pathlib import Path

    path = Path(__file__).resolve().parents[1] / "app" / "main.py"
    tree = ast.parse(path.read_text())
    kwargs_seen = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr == "write_sql"):
            kwargs_seen.extend(
                kw.value.id for kw in node.keywords
                if kw.arg and isinstance(kw.value, ast.Name))
    assert "scope_table_hints" in kwargs_seen, (
        "the scope-gate hint is no longer passed into write_sql")


def test_retrieval_miss_is_handled_before_the_tried_domains_bounce():
    """Guards the ordering in main.py: the retrieval-miss check must run BEFORE the
    domain is appended to _tried_domains, otherwise it can never be retried."""
    from pathlib import Path

    source = (Path(__file__).resolve().parents[1] / "app" / "main.py").read_text()
    check = source.find("_hint_tables = orchestrator.tables_named_in")
    append = source.find("_tried_domains.append(domain)", check)
    assert check != -1 and append != -1
    assert check < append


def test_the_gate_keys_off_the_named_table_not_the_suggested_domain():
    """A gate that blames another domain while naming a table from its OWN domain is
    still reporting a retrieval miss, so the check must not require suggested == domain.
    """
    from pathlib import Path

    source = (Path(__file__).resolve().parents[1] / "app" / "main.py").read_text()
    assert "if suggested == domain and domain not in _tried_domains" not in source, (
        "keying off suggested_domain misses the common case where the gate blames "
        "another domain but names a table it owns itself")
    assert "if _hint_tables and domain not in _tried_domains" in source


# ---------------- owner lookup ----------------

OWNER_REASON = ("Butuh region filter (East Java) dan FB market share/SOGA di grain "
                "kabkota yang tersedia di rham_report_fb_ms_kabkota (domain competitive), "
                "bukan di domain saya")


def test_owner_of_a_named_table_is_found():
    owner, tables = orchestrator.domain_owning_named_table(OWNER_REASON)
    assert owner == "competitive"
    assert tables == ["rham_report_fb_ms_kabkota"]


def test_reason_without_a_table_name_yields_no_owner():
    assert orchestrator.domain_owning_named_table("tidak ada tabel disebut") == ("", [])
    assert orchestrator.domain_owning_named_table("") == ("", [])
    assert orchestrator.domain_owning_named_table(None) == ("", [])


def test_owner_lookup_only_returns_approved_tables():
    approved = orchestrator.knowledge.approved_table_names()
    _owner, tables = orchestrator.domain_owning_named_table(OWNER_REASON)
    for name in tables:
        assert name in approved


def test_retrieval_miss_is_checked_before_declaring_out_of_scope():
    """Guards ordering in main.py: the owner lookup must run before the reroute that
    can end the turn with 'di luar cakupan data'."""
    from pathlib import Path

    source = (Path(__file__).resolve().parents[1] / "app" / "main.py").read_text()
    owner = source.find("domain_owning_named_table")
    out_of_scope = source.find("di luar cakupan data")
    assert owner != -1 and out_of_scope != -1
    assert owner < out_of_scope
