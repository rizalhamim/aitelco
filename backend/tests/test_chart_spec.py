from app.chart_spec import suggest


def test_empty_and_no_measures():
    assert suggest([], [])["type"] == "none"
    assert suggest(["kabupaten"], [{"kabupaten": "Garut"}])["type"] == "none"


def test_single_row_is_kpi():
    s = suggest(["revenue", "gross_add"], [{"revenue": 1.2e9, "gross_add": 300}])
    assert s["type"] == "kpi" and s["y"] == ["revenue", "gross_add"]
    assert s["formats"]["revenue"] == "currency"


def test_time_series_single_measure_is_area():
    rows = [{"month": 202601 + i, "revenue": 100 + i} for i in range(6)]
    s = suggest(["month", "revenue"], rows)
    assert s["type"] == "area" and s["x"] == "month" and s["y"] == ["revenue"]


def test_date_strings_are_time():
    rows = [{"tanggal": f"2026-10-{d:02d}", "payload_tb": d * 10.5} for d in range(1, 10)]
    assert suggest(["tanggal", "payload_tb"], rows)["x"] == "tanggal"


def test_time_series_split_by_category():
    rows = [{"bulan": m, "region": r, "revenue": 1.0} for m in ("2026-08", "2026-09") for r in ("Jabar", "Jatim")]
    s = suggest(["bulan", "region", "revenue"], rows)
    assert s["type"] == "line" and s["series_by"] == "region"


def test_time_series_abs_and_pct_is_combo():
    rows = [{"month": 202601 + i, "revenue": 1e9, "growth_pct": 1.5} for i in range(4)]
    s = suggest(["month", "revenue", "growth_pct"], rows)
    assert s["type"] == "combo" and s["y"] == ["revenue"] and s["y2"] == ["growth_pct"]


def test_category_bar_and_hbar():
    few = [{"region": r, "revenue": i} for i, r in enumerate(["Jabar", "Jateng", "Jatim"])]
    assert suggest(["region", "revenue"], few)["type"] == "bar"
    many = [{"kabupaten": f"Kabupaten Nomor {i}", "revenue": i} for i in range(20)]
    s = suggest(["kabupaten", "revenue"], many)
    assert s["type"] == "hbar" and s["top_n"] == 15 and s["map_key"] == "kabupaten"


def test_share_is_donut():
    rows = [{"operator": o, "market_share": v} for o, v in [("IOH", 40), ("A", 35), ("B", 25)]]
    s = suggest(["operator", "market_share"], rows)
    assert s["type"] == "donut"


def test_long_format_stacked():
    rows = [{"kabupaten": k, "tech": t, "sites": 3} for k in ("Garut", "Bogor") for t in ("4G", "5G")]
    s = suggest(["kabupaten", "tech", "sites"], rows)
    assert s["type"] == "stacked_bar" and s["series_by"] == "tech"


def test_correlation_question_is_scatter():
    rows = [{"kabupaten": f"K{i}", "arpu": i * 1.0, "payload": i * 2.0} for i in range(10)]
    s = suggest(["kabupaten", "arpu", "payload"], rows, "korelasi arpu vs payload per kabupaten")
    assert s["type"] == "scatter" and s["label"] == "kabupaten"


def test_mixed_magnitudes_split_axis():
    rows = [{"month": 202601 + i, "revenue": 1e10 + i, "sites": 300 + i} for i in range(5)]
    s = suggest(["month", "revenue", "sites"], rows)
    assert s["type"] == "combo" and s["y"] == ["revenue"] and s["y2"] == ["sites"]
