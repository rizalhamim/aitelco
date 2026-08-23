"""Chart specs must be built from column MEANING, not column type.

Every case below is a result shape observed in production. The old client-side
heuristic plotted the first numeric column, which drew `rank` as bars and squashed
percentages against rupiah on a shared axis.
"""
from __future__ import annotations

from app.chart_spec import (
    build_chart_spec,
    classify_column,
    ROLE_CURRENCY,
    ROLE_COUNT,
    ROLE_DELTA,
    ROLE_IDENTIFIER,
    ROLE_PERCENT,
    ROLE_TEMPORAL,
    ROLE_TERRITORY,
)


def plotted(spec):
    return [s["column"] for s in spec.get("series", [])]


# ---------------- column roles ----------------

def test_rank_is_an_identifier_not_a_metric():
    assert classify_column("rank", [1, 2, 3]) == ROLE_IDENTIFIER


def test_month_id_is_temporal_not_a_metric():
    assert classify_column("month_id", [202608, 202607]) == ROLE_TEMPORAL


def test_site_id_is_an_identifier():
    assert classify_column("site_id", [101, 102]) == ROLE_IDENTIFIER


def test_revenue_columns_are_currency():
    for name in ("revenue", "total_revenue", "rev_prepaid", "arpt", "osa_mtd"):
        assert classify_column(name, [1.0, 2.0]) == ROLE_CURRENCY, name


def test_percent_columns_are_percent():
    for name in ("share_pct", "avg_avail_pct_4g", "hvc_ratio", "penetration_5g"):
        assert classify_column(name, [10.0, 20.0]) == ROLE_PERCENT, name


def test_growth_columns_are_delta():
    for name in ("revenue_growth_pct", "mom_growth", "net_add_90", "delta_hit"):
        assert classify_column(name, [-1.0, 2.0]) == ROLE_DELTA, name


def test_count_columns_are_counts():
    for name in ("so_count", "congest_sites", "pack_subs", "total_hit"):
        assert classify_column(name, [10, 20]) == ROLE_COUNT, name


def test_territory_columns_are_territory():
    for name in ("kabkota", "kecamatan", "region", "branch", "site_nm"):
        assert classify_column(name, ["A", "B"]) == ROLE_TERRITORY, name


def test_a_text_column_is_a_label():
    assert classify_column("product_group", ["FREEDOM", "HAPPY"]) == "label"


# ---------------- case A: ranked revenue, rank column first ----------------

A_COLUMNS = ["rank", "kecamatan", "revenue_mn", "share_pct"]
A_ROWS = [
    {"rank": 1, "kecamatan": "WONOKROMO", "revenue_mn": 2379.0, "share_pct": 12.6},
    {"rank": 2, "kecamatan": "SUKOLILO", "revenue_mn": 2040.0, "share_pct": 10.8},
    {"rank": 3, "kecamatan": "GUBENG", "revenue_mn": 2037.0, "share_pct": 10.7},
]


def test_rank_is_never_plotted():
    spec = build_chart_spec(A_COLUMNS, A_ROWS)
    assert "rank" not in plotted(spec)


def test_the_category_axis_is_the_territory_not_the_rank():
    assert build_chart_spec(A_COLUMNS, A_ROWS)["category"] == "kecamatan"


def test_the_revenue_column_is_actually_plotted():
    assert "revenue_mn" in plotted(build_chart_spec(A_COLUMNS, A_ROWS))


# ---------------- case B: currency and percent together ----------------

B_COLUMNS = ["kabkota", "total_revenue", "growth_pct"]
B_ROWS = [
    {"kabkota": "SURABAYA", "total_revenue": 2.3e9, "growth_pct": 4.2},
    {"kabkota": "SIDOARJO", "total_revenue": 1.1e9, "growth_pct": -2.1},
]


def test_currency_and_percent_get_separate_axes():
    spec = build_chart_spec(B_COLUMNS, B_ROWS)
    assert spec["dual_axis"] is True
    assert len(spec["axes"]) == 2
    units = {a["unit"] for a in spec["axes"]}
    assert units == {"Rp", ""} or units == {"Rp", "%"}


def test_each_series_knows_its_axis_side():
    spec = build_chart_spec(B_COLUMNS, B_ROWS)
    sides = {s["column"]: s["axis_side"] for s in spec["series"]}
    assert sides["total_revenue"] != sides["growth_pct"]


def test_a_negative_capable_series_requests_a_zero_line():
    spec = build_chart_spec(B_COLUMNS, B_ROWS)
    assert any(a["zero_line"] for a in spec["axes"])


def test_currency_series_carries_the_rupiah_unit():
    spec = build_chart_spec(B_COLUMNS, B_ROWS)
    rev = next(s for s in spec["series"] if s["column"] == "total_revenue")
    assert rev["unit"] == "Rp"


# ---------------- case C: time series ----------------

C_COLUMNS = ["month_id", "revenue"]
C_ROWS = [{"month_id": 202606 + i, "revenue": 1.0 + i} for i in range(3)]


def test_a_varying_month_column_makes_it_a_line_chart():
    spec = build_chart_spec(C_COLUMNS, C_ROWS)
    assert spec["mode"] == "line"
    assert spec["category"] == "month_id"


def test_month_id_is_not_plotted_as_a_value():
    assert "month_id" not in plotted(build_chart_spec(C_COLUMNS, C_ROWS))


def test_a_constant_month_is_context_not_a_trend():
    rows = [{"month_id": 202608, "kabkota": f"K{i}", "revenue": i} for i in range(4)]
    spec = build_chart_spec(["month_id", "kabkota", "revenue"], rows)
    assert spec["mode"] == "bar"
    assert spec["category"] == "kabkota"


# ---------------- case D: mixed periods ----------------

D_COLUMNS = ["kabkota", "congest_sites", "avg_avail_pct_4g",
             "occ_month_id", "avail_month_id"]
D_ROWS = [
    {"kabkota": "SURABAYA", "congest_sites": 2587, "avg_avail_pct_4g": 99.85,
     "occ_month_id": 202512, "avail_month_id": 202607},
    {"kabkota": "SIDOARJO", "congest_sites": 1800, "avg_avail_pct_4g": 99.85,
     "occ_month_id": 202512, "avail_month_id": 202607},
]


def test_differing_periods_are_disclosed_in_the_caption():
    spec = build_chart_spec(D_COLUMNS, D_ROWS)
    assert "Periode berbeda" in spec["caption"]
    assert "202512" in spec["caption"] and "202607" in spec["caption"]


def test_a_count_and_a_percent_do_not_share_one_axis():
    spec = build_chart_spec(D_COLUMNS, D_ROWS)
    sides = {s["column"]: s["axis_side"] for s in spec["series"]}
    assert sides["congest_sites"] != sides["avg_avail_pct_4g"]


# ---------------- case E: funnel ----------------

E_COLUMNS = ["kabkota", "so_count", "sa_count", "pa_count", "so_to_pa_pct"]
E_ROWS = [{"kabkota": "SURABAYA", "so_count": 26617, "sa_count": 9000,
           "pa_count": 8000, "so_to_pa_pct": 30.1}]


def test_funnel_columns_produce_a_funnel_chart():
    spec = build_chart_spec(E_COLUMNS, E_ROWS)
    assert spec["mode"] == "funnel"
    assert plotted(spec) == ["so_count", "sa_count", "pa_count"]


# ---------------- pie honesty ----------------

def test_pie_is_used_for_a_small_complete_composition():
    rows = [{"product": p, "revenue": v}
            for p, v in [("A", 10.0), ("B", 20.0), ("C", 30.0)]]
    assert build_chart_spec(["product", "revenue"], rows)["mode"] == "pie"


def test_a_truncated_result_is_never_a_pie():
    rows = [{"product": p, "revenue": 10.0} for p in "ABC"]
    spec = build_chart_spec(["product", "revenue"], rows,
                            result_profile={"truncated": True, "row_count": 500})
    assert spec["mode"] != "pie"
    assert "dipotong" in spec["caption"]


def test_negative_values_are_never_a_pie():
    rows = [{"product": "A", "revenue": -5.0}, {"product": "B", "revenue": 10.0}]
    assert build_chart_spec(["product", "revenue"], rows)["mode"] != "pie"


def test_a_percent_metric_alone_is_not_a_pie():
    # Percentages across territories do not sum to a whole.
    rows = [{"kabkota": f"K{i}", "share_pct": 20.0} for i in range(4)]
    assert build_chart_spec(["kabkota", "share_pct"], rows)["mode"] != "pie"


# ---------------- degenerate inputs ----------------

def test_empty_result_yields_no_chart():
    assert build_chart_spec([], [])["mode"] == "none"
    assert build_chart_spec(["a"], [])["mode"] == "none"


def test_a_result_with_no_metric_yields_no_chart():
    rows = [{"kabkota": "A", "region": "EJ"}]
    assert build_chart_spec(["kabkota", "region"], rows)["mode"] == "none"


def test_a_result_of_only_identifiers_yields_no_chart():
    rows = [{"site_id": 1, "kec_id": 2}]
    assert build_chart_spec(["site_id", "kec_id"], rows)["mode"] == "none"


def test_nulls_do_not_break_classification():
    rows = [{"kabkota": "A", "revenue": None}, {"kabkota": "B", "revenue": 5.0}]
    spec = build_chart_spec(["kabkota", "revenue"], rows)
    assert "revenue" in plotted(spec)


def test_caption_states_how_many_categories_are_shown():
    spec = build_chart_spec(A_COLUMNS, A_ROWS)
    assert spec["caption"].startswith("3 ")


def test_title_names_the_metric_and_the_category():
    title = build_chart_spec(A_COLUMNS, A_ROWS)["title"]
    assert "Revenue mn" in title and "kecamatan" in title.lower()


# ---------------- many categories ----------------

def _many(n):
    cols = ["kabkota", "revenue"]
    rows = [{"kabkota": f"KAB {i:02d}", "revenue": float(1000 - i * 10)} for i in range(n)]
    return cols, rows


def test_more_categories_than_fit_still_produce_a_ranked_bar():
    """Returning no chart at all for 38 kabkota was worse than a top-N bar."""
    spec = build_chart_spec(*_many(38))
    assert spec["mode"] == "bar"
    assert spec["ranked_subset"] is True
    assert len(spec["rows"]) == 24


def test_the_ranked_subset_is_sorted_by_the_primary_metric():
    spec = build_chart_spec(*_many(38))
    values = [r["revenue"] for r in spec["rows"]]
    assert values == sorted(values, reverse=True)


def test_the_caption_admits_it_is_a_subset():
    spec = build_chart_spec(*_many(38))
    assert "teratas dari 38" in spec["caption"]


def test_a_normal_sized_result_is_not_marked_as_a_subset():
    spec = build_chart_spec(*_many(10))
    assert not spec.get("ranked_subset")
    assert "teratas" not in spec["caption"]


def test_an_absurd_number_of_categories_still_yields_no_chart():
    assert build_chart_spec(*_many(400))["mode"] == "none"


def test_nulls_sort_last_in_the_ranked_subset():
    cols = ["kabkota", "revenue"]
    rows = [{"kabkota": f"K{i}", "revenue": None if i % 2 else float(i)} for i in range(30)]
    spec = build_chart_spec(cols, rows)
    plotted_values = [r["revenue"] for r in spec["rows"]]
    assert plotted_values[0] is not None


def test_a_time_axis_caption_states_the_period_span():
    """"3 month id" tells the user nothing; the actual span does."""
    spec = build_chart_spec(C_COLUMNS, C_ROWS)
    assert "202606 sampai 202608" in spec["caption"]
    assert "periode" in spec["caption"]


def test_a_single_period_is_named_not_ranged():
    rows = [{"month_id": 202608, "revenue": 1.0}, {"month_id": 202608, "revenue": 2.0}]
    spec = build_chart_spec(["month_id", "revenue"], rows)
    # One constant period is context, so this is a bar chart, not a trend.
    assert spec["mode"] != "line"


# ---------------- top-N is a comparison, not a composition ----------------

_COMPOSITION = (["family_group", "revenue"],
                [{"family_group": f, "revenue": v}
                 for f, v in [("FREEDOM", 5e8), ("HAPPY", 3e8), ("CVM", 2e8)]])


def test_an_order_by_limit_result_is_not_a_pie():
    """`ORDER BY revenue DESC LIMIT 10` returns 10 of many, so the slices sum to nothing.

    BigQuery's `truncated` flag does not catch this: the query asked for 10 rows and got
    exactly 10. Observed live: a "Top 10 kecamatan" question was drawn as a pie.
    """
    cols, rows = _COMPOSITION
    spec = build_chart_spec(cols, rows,
                            sql="SELECT family_group, revenue FROM t "
                                "ORDER BY revenue DESC LIMIT 10")
    assert spec["mode"] == "bar"


def test_a_top_n_question_is_not_a_pie_even_without_sql():
    cols, rows = _COMPOSITION
    for question in ("Top 10 kecamatan dengan revenue tertinggi",
                     "kecamatan mana yang revenue-nya paling rendah",
                     "5 besar family group terbesar"):
        spec = build_chart_spec(cols, rows, question=question)
        assert spec["mode"] == "bar", question


def test_a_genuine_composition_is_still_a_pie():
    cols, rows = _COMPOSITION
    spec = build_chart_spec(cols, rows,
                            question="Komposisi revenue per family group",
                            sql="SELECT family_group, SUM(revenue) revenue FROM t "
                                "GROUP BY family_group")
    assert spec["mode"] == "pie"


def test_ordering_without_a_limit_is_still_a_composition():
    # Sorting for readability does not make a result a top-N.
    cols, rows = _COMPOSITION
    spec = build_chart_spec(cols, rows,
                            sql="SELECT family_group, revenue FROM t ORDER BY revenue DESC")
    assert spec["mode"] == "pie"
