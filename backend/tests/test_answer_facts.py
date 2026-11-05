"""Pre-computed answer facts: one number format, honest totals, a time series delta."""
from app import answer_facts as af
from app.chart_spec import suggest


def test_indonesian_number_format():
    assert af.fmt_number(1234567.85, 1) == "1.234.567,9"
    assert af.fmt_number(-12.5, 1, "en") == "-12.5"


def test_currency_keeps_one_magnitude_per_column():
    f = af.formatter("revenue", [3.2e6, 1.5e9])
    assert f(1.5e9) == "Rp 1,5 M"
    assert f(1.2e9) == "Rp 1,2 M"
    assert f(3.2e6) == "Rp 3,2 Jt"  # never "Rp 0,0 M" for a real value
    small = af.formatter("revenue", [3.2e6, 4.1e6])
    assert small(3.2e6) == "Rp 3,2 Jt"


def test_percent_has_one_decimal_and_sign():
    assert af.formatter("market_share", [40.0])(40) == "40,0%"


def test_period_label():
    assert af.period_label(202609) == "September 2026 (202609)"
    assert af.period_label("2026-10-05") == "5 Oktober 2026"


def test_time_series_latest_previous_and_change():
    rows = [{"month_id": 202609 - i, "revenue": 100e9 - i * 10e9} for i in range(4)]
    chart = suggest(["month_id", "revenue"], rows, sql="ORDER BY month_id DESC")
    facts = af.build(["month_id", "revenue"], rows, chart)
    m = facts["measures"][0]
    assert m["latest"].startswith("Rp 100,0 M (September 2026")
    assert m["previous"].startswith("Rp 90,0 M (Agustus 2026")
    assert m["change"] == "11,1%"
    assert "sum_of_rows" not in m  # summing a trend over months is not a total
    assert facts["period"].startswith("Juni 2026")


def test_category_ranking_facts_and_sum_of_rows():
    rows = [{"kabupaten": k, "revenue": v} for k, v in [("Bandung", 50e9), ("Bogor", 30e9), ("Garut", 20e9)]]
    chart = suggest(["kabupaten", "revenue"], rows)
    facts = af.build(["kabupaten", "revenue"], rows, chart)
    m = facts["measures"][0]
    assert m["highest"] == "Bandung: Rp 50,0 M"
    assert m["lowest"] == "Garut: Rp 20,0 M"
    assert m["sum_of_rows"] == "Rp 100,0 M" and m["top_share_of_rows"] == "50,0%"


def test_growth_and_rates_are_never_summed():
    rows = [{"region": r, "growth_pct": g} for r, g in [("A", 1.0), ("B", -2.0), ("C", 3.0)]]
    m = af.build(["region", "growth_pct"], rows, suggest(["region", "growth_pct"], rows))["measures"][0]
    assert "sum_of_rows" not in m and m["negative_rows"] == 1


def test_fallback_report_uses_the_template():
    rows = [{"kabupaten": k, "revenue": v} for k, v in [("Bandung", 50e9), ("Bogor", 30e9), ("Garut", 20e9)]]
    facts = af.build(["kabupaten", "revenue"], rows, suggest(["kabupaten", "revenue"], rows))
    text = af.fallback_report("revenue per kabupaten", facts)
    assert text.startswith("**revenue tertinggi di Bandung: Rp 50,0 M**")
    assert "### Temuan utama" in text and "\u2014" not in text


def test_build_never_raises():
    assert af.build(["a"], [{"a": object()}]) == {}
    assert af.build([], []) == {}
