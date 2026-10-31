"""A validated table hint must SURVIVE retrieval, not merely score higher.

The caller only sends a hint after the policy gate rejected that exact table, or a
scope gate named it as the one it was missing. If retrieval then drops it, the next
attempt fails for the same reason and the turn burns all three tries. This happened
live: the territory-reference swap evicted the hinted table from the last slot.
"""
from __future__ import annotations

from app import knowledge
from app.knowledge_graph import select_tables


KB = knowledge.load_kb()
QUESTION = ("Tampilkan 10 kabkota dengan market share IM3 terendah tapi SOGA tinggi "
            "di region East Java")
HINT = "rham_report_fb_ms_kabkota"


def test_the_hinted_table_is_selected_even_at_a_tight_budget():
    for budget in (1, 2, 4, 6):
        sel = select_tables(KB, "competitive", QUESTION, max_tables=budget,
                            table_hints=[HINT])
        assert HINT in sel["tables"], f"hint dropped at budget={budget}"


def test_a_territory_question_does_not_evict_the_hint():
    # The question mentions region and kabkota, which triggers the territory-reference
    # injection. That injection used to overwrite the last slot unconditionally.
    sel = select_tables(KB, "competitive", QUESTION, max_tables=4, table_hints=[HINT])
    assert HINT in sel["tables"]


def test_an_unapproved_hint_is_ignored():
    sel = select_tables(KB, "competitive", QUESTION, max_tables=4,
                        table_hints=["definitely_not_a_table"])
    assert "definitely_not_a_table" not in sel["tables"]


def test_a_hint_from_another_domain_is_ignored():
    # Hints must never widen the policy gate across domains.
    sel = select_tables(KB, "competitive", QUESTION, max_tables=4,
                        table_hints=["rham_site_fwa_daily"])
    assert "rham_site_fwa_daily" not in sel["tables"]


def test_no_hint_leaves_selection_unchanged():
    plain = select_tables(KB, "competitive", QUESTION, max_tables=4)
    assert plain["tables"], "baseline retrieval should still return tables"


def test_multiple_hints_all_survive():
    hints = [HINT, "rham_report_fb_ms_region"]
    sel = select_tables(KB, "competitive", QUESTION, max_tables=2, table_hints=hints)
    for hint in hints:
        assert hint in sel["tables"]
