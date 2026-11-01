from app import chart_spec
from app.headline_kpis import headline

MONTHS = [{"bulan": f"2026-{m:02d}", "revenue": r, "availability_pct": a}
          for m, r, a in [(5, 412e9, .991), (6, 418e9, .993), (7, 425e9, .994),
                          (8, 431e9, .995), (9, 422.7e9, .996), (10, 412.6e9, .992)]]


def _spec(cols, rows):
    return chart_spec.suggest(cols, rows, "revenue per bulan")


def test_time_series_gives_latest_vs_previous_with_spark():
    cols = ["bulan", "revenue", "availability_pct"]
    cards = headline(cols, MONTHS, _spec(cols, MONTHS))
    rev = next(c for c in cards if c["column"] == "revenue")
    assert rev["value"] == 412.6e9
    assert rev["delta"] == round((412.6 - 422.7) / 422.7 * 100, 2)
    assert rev["delta_unit"] == "%" and rev["vs"] == "2026-09"
    assert rev["spark"] == [r["revenue"] for r in MONTHS]


def test_percent_metric_delta_is_in_points():
    cols = ["bulan", "revenue", "availability_pct"]
    cards = headline(cols, MONTHS, _spec(cols, MONTHS))
    av = next((c for c in cards if c["column"] == "availability_pct"), None)
    if av is not None:
        assert av["delta_unit"] == "pp"
        assert av["delta"] == -0.4


def test_ranking_by_region_has_no_cards():
    rows = [{"kabupaten": k, "revenue": v} for k, v in [("Garut", 21.6e9), ("Bogor", 58.4e9), ("Cianjur", 19.2e9)]]
    cols = ["kabupaten", "revenue"]
    assert headline(cols, rows, _spec(cols, rows)) == []


def test_single_row_gives_plain_cards():
    rows = [{"revenue": 412.6e9, "site_count": 37}]
    cols = ["revenue", "site_count"]
    spec = _spec(cols, rows)
    cards = headline(cols, rows, spec)
    assert all(c["delta"] is None and c["spark"] == [] for c in cards)
    assert {c["column"] for c in cards} <= set(cols)


def test_no_spec_or_empty_rows():
    assert headline(["a"], [], {"type": "line"}) == []
    assert headline(["a"], [{"a": 1}], None) == []
