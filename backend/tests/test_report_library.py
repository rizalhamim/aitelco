"""Laporan documents: section shapes and numbers from a synthetic dump and overview (no BigQuery)."""
from app import performance as pf, report_library as rl
from tests.test_performance import _rows

OV = {
    "month_id": 202610, "month_label": "Oktober 2026", "prev_label": "Sep 2026", "has_targets": True,
    "source": {"kind": "dump", "created_at": "2026-10-31T22:30:00Z"},
    "kpis": [
        {"key": "revenue", "value": 1.84e12, "pct_change": 1.2},
        {"key": "subs", "value": 41.3e6, "pct_change": 0.6},
        {"key": "payload", "value": 84.2e6, "pct_change": -0.4},
        {"key": "availability", "value": 99.62, "target": 99.5, "below_sla": 12},
    ],
    "regions": [
        {"region": "WEST JAVA", "revenue": 412.6e9, "mom_pct": -2.4, "subs": 1, "payload_gb": 1, "availability": 99.4, "achievement_pct": 93.2},
        {"region": "EAST JAVA", "revenue": 788e9, "mom_pct": 2.1, "subs": 1, "payload_gb": 1, "availability": 99.7, "achievement_pct": 101.4},
    ],
    "revenue_by_region": {"labels": ["Sep 2026", "Okt 2026"], "series": [{"name": "WEST JAVA", "values": [4.2e11, 4.126e11]},
                                                                         {"name": "EAST JAVA", "values": [7.7e11, 7.88e11]}]},
}


def _patch(monkeypatch):
    kec, site, avail = _rows()
    monkeypatch.setattr(pf, "_data", lambda: (kec, site, avail, {"kind": "dump", "created_at": "2026-10-31T22:30:00Z"}))
    monkeypatch.setattr(rl, "_overview", lambda region: OV)


def test_format():
    assert rl.rp(1.84e12) == "Rp 1,84 T" and rl.rp(412.6e9) == "Rp 412,6 M" and rl.rp(312e6) == "Rp 312 jt"
    assert rl.num(41.3e6) == "41,3 jt" and rl.num(1.32e6) == "1,32 jt" and rl.num(812e3) == "812 rb" and rl.num(2900) == "2,9 rb"
    assert rl.gb(84.2e6) == "84,2 PB" and rl.delta(-0.4) == {"v": "▼ 0,4%", "tone": "down"}
    assert rl.kab_name("KOTA SEMARANG") == "Kota Semarang" and rl.kab_name("KAB. GARUT") == "Kab. Garut"


def test_outlook(monkeypatch):
    _patch(monkeypatch)
    d = rl.outlook_doc("")
    assert d["title"] == "Performance Outlook Circle Java" and d["heading"] == "Circle Java, Oktober 2026"
    assert len(d["pages"]) == 6 and [s["n"] for s in d["pages"][0]] == [1, 2, 5, 7] and len(d["toc"]) == 9
    assert d["byline"] == "Disusun Agent Java · 1 Nov 2026 05.30 WIB · sumber dump Parquet"
    assert d["meta"] == "Analis · 6 hlm · Agent Java, 1 Nov 05.30 WIB"
    summ, reg, prod, prof = d["pages"][0]
    assert summ["text"].startswith("Revenue **naik 1,2% MoM** ke Rp 1,84 T, ditopang East Java.")
    assert "Perhatian: payload Garut turun" in summ["text"] and "West Java di bawah target (93,2%)" in summ["text"]
    assert [k["label"] for k in summ["kpis"]] == ["Revenue", "Pelanggan aktif", "Payload", "Availability"]
    assert summ["kpis"][3]["delta"] == "target 99,5%" and summ["kpis"][0]["delta"] == "▲ 1,2% MoM"
    assert [r[0] for r in reg["rows"]] == ["East Java", "West Java"] and reg["rows"][0][5]["bar"]["c"] == "#0E8579"
    assert prod["rows"][0][2] is None and prod["rows"][0][4] is None and prod["rows"][0][1]["bar"]["w"] == 44
    assert prof["rows"][0][0] == "Kab. Garut" and prof["rows"][0][1] is None and prof["rows"][0][4] == "2"


def test_bulanan_and_profile(monkeypatch):
    _patch(monkeypatch)
    b = rl.bulanan_doc("WEST JAVA")
    assert b["title"] == "Performa Bulanan West Java" and len(b["pages"]) == 2
    assert [r[0] for r in b["pages"][0][1]["rows"]] == ["Kab. Garut", "Kab. Cianjur"]
    p = rl.profile_doc("KAB. GARUT")
    assert p["title"] == "Profile Kab. Garut" and p["sites"] == 2
    kec = p["pages"][0][1]["rows"]
    assert {r[0] for r in kec} == {"Tarogong Kidul", "Cibatu"}
    worst = p["pages"][1][0]["rows"][0]
    assert worst[0].startswith("GRT-1") and worst[3]["tone"] == "down"


def test_library(monkeypatch):
    _patch(monkeypatch)
    lib = rl.library()
    assert [i["title"] for i in lib["lead"]] == ["Performance Outlook Circle Java", "Performa Bulanan West Java",
                                                 "Profile Kab. Garut", "Site Performance Kab. Garut"]
    assert lib["lead"][3]["href"] == "/performance?kabupaten=GARUT" and lib["month_short"] == "Okt 2026"
