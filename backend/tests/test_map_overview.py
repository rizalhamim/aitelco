from app import map_overview as mo


def test_explain_mentions_sites_and_actions():
    kpis = [{"pct_change": -7.9}, {"pct_change": -9.1}, {"pct_change": -0.6}, {"pct_change": 1.3}]
    worst = [
        {"kecamatan": "Cikajang", "availability": 96.1, "payload_pct": -14.2},
        {"kecamatan": "Pameungpeuk", "availability": 97.5, "payload_pct": -11.7},
    ]
    out = mo._explain("KABUPATEN GARUT", kpis, worst, 98.9, "Sep")
    assert "turun 7,9%" in out["text"] and "2 site" in out["text"] and "Cikajang" in out["text"]
    assert any("Pulihkan 2 site" in a for a in out["actions"])


def test_explain_without_sites():
    out = mo._explain("KOTA BANDUNG", [{"pct_change": 2.0}, {"pct_change": None}, {}, {}], [], 99.6, "Sep")
    assert out["text"].startswith("Revenue Kota Bandung naik 2,0%") and out["actions"] == []
