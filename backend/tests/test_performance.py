"""Performance drill-down built from synthetic dump rows (no BigQuery, no disk)."""
from app import perf_dump, performance as pf


def _rows():
    kec, site = [], []
    months = [perf_dump.month_add(202610, -i) for i in range(24, -1, -1)]
    areas = [("WEST JAVA", "GARUT", "JAWA BARAT", "TAROGONG KIDUL", 1), ("WEST JAVA", "GARUT", "JAWA BARAT", "CIBATU", 2),
             ("WEST JAVA", "CIANJUR", "JAWA BARAT", "CIBEBER", 3), ("EAST JAVA", "MALANG", "JAWA TIMUR", "LAWANG", 4)]
    for i, m in enumerate(months):
        for reg, kab, prov, kc, kid in areas:
            drop = 0.8 if (m == 202610 and kc == "TAROGONG KIDUL") else 1.0
            kec.append({"month_id": m, "kec_id": kid, "region": reg, "kabupaten": kab, "provinsi": prov, "kecamatan": kc,
                        "revenue": (100 + i + kid) * 1e6 * drop, "payload_gb": (500 + i) * drop, "subs": 1000 + i})
    for m, f in ((202610, 1.0), (202609, 1.2), (202510, 0.9)):
        site += [
            {"site_id": "GRT-1", "month_id": m, "site_name": "Tarogong 1", "kecamatan": "TAROGONG KIDUL", "kabupaten": "KAB. GARUT",
             "provinsi": "JAWA BARAT", "lat": -7.2, "lon": 107.9, "payload_gb": 80 / f if m == 202610 else 100, "revenue": 4e8, "avail": 99.1},
            {"site_id": "GRT-2", "month_id": m, "site_name": "Cibatu 1", "kecamatan": "CIBATU", "kabupaten": "KAB. GARUT",
             "provinsi": "JAWA BARAT", "lat": -7.1, "lon": 107.98, "payload_gb": 50, "revenue": 2e8, "avail": 99.9},
            {"site_id": "MLG-1", "month_id": m, "site_name": "Lawang", "kecamatan": "LAWANG", "kabupaten": "KAB. MALANG",
             "provinsi": "JAWA TIMUR", "lat": -7.8, "lon": 112.7, "payload_gb": 70, "revenue": 3e8, "avail": 99.8},
        ]
    avail = [{"level": "circle", "name": "JAVA", "month_id": m, "avail": 99.6} for m in months]
    return kec, site, avail


def _patch(monkeypatch):
    kec, site, avail = _rows()
    monkeypatch.setattr(pf, "_data", lambda: (kec, site, avail, {"kind": "dump", "label": "Dump Performance 1 Nov 05.00", "queries": 0}))


def test_circle_level(monkeypatch):
    _patch(monkeypatch)
    d = pf.build()
    assert d["level"] == "circle" and d["child_level"] == "region"
    assert d["month_label"] == "Okt 2026" and d["prev_label"] == "Sep 2026" and d["yoy_label"] == "Okt 2025"
    k = {x["key"]: x for x in d["kpis"]}
    assert k["availability"]["value"] == 99.6 and k["sites"]["value"] == 3
    assert len(d["trend"]["labels"]) == 12 and d["trend"]["labels"][-1] == "Okt"
    assert [c["name"] for c in d["contrib"]][0] == "West Java"  # Tarogong drop makes West the biggest fall
    assert d["source"]["kind"] == "dump" and d["source"]["queries"] == 0


def test_kabupaten_drill_and_sites(monkeypatch):
    _patch(monkeypatch)
    d = pf.build(region="WEST JAVA", kabupaten="GARUT")
    assert d["name"] == "Kab. Garut" and d["child_level"] == "kecamatan"
    assert [p["name"] for p in d["path"]] == ["Circle Java", "West Java", "Garut"]
    assert {c["name"] for c in d["contrib"]} == {"Tarogong Kidul", "Cibatu"}
    assert d["contrib"][0]["name"] == "Tarogong Kidul" and d["contrib"][0]["delta"] < 0
    rows = d["sites"]["rows"]
    assert [r["site_id"] for r in rows] == ["GRT-1", "GRT-2"]  # KAB. GARUT matches GARUT; payload MoM ascending
    assert rows[0]["status"] == "kritis" and rows[0]["payload_mom"] == -20.0
    assert "Payload turun 20,0% MoM" in rows[0]["note"]
    assert d["sites"]["counts"] == {"kritis": 1, "waspada": 0, "normal": 1}


def test_region_sites_follow_provinces_and_status_filter(monkeypatch):
    _patch(monkeypatch)
    d = pf.build(region="EAST JAVA")
    assert [r["site_id"] for r in d["sites"]["rows"]] == ["MLG-1"]
    d = pf.build(region="WEST JAVA", status="normal")
    assert [r["site_id"] for r in d["sites"]["rows"]] == ["GRT-2"] and d["sites"]["total"] == 1


def test_status_rules():
    assert pf._status(-14.7, 99.1) == "kritis"
    assert pf._status(-1.0, 98.42) == "kritis"
    assert pf._status(-9.6, 99.71) == "waspada"
    assert pf._status(-5.2, 99.92) == "normal"


def test_search_and_site(monkeypatch):
    _patch(monkeypatch)
    res = pf.search("garut")
    assert res[0] == {**res[0], "type": "kabupaten", "name": "Garut"}
    assert any(r["type"] == "site" and r["name"] == "GRT-1" for r in pf.search("grt"))
    s = pf.site_detail("GRT-1")
    assert s["kecamatan"] == "Tarogong Kidul" and s["status"] == "kritis"
    assert pf.site_detail("NOPE")["kind"] == "not_found"


def test_site_detail_cards(monkeypatch):
    _patch(monkeypatch)
    row = pf.build(kabupaten="GARUT")["sites"]["rows"][0]
    labels = [d["label"] for d in row["detail"]]
    assert labels == ["Payload Okt 2025", "Revenue Okt 2025", "Availability Sep", "Koordinat"]
    assert row["detail"][1]["value"] == "Rp 400 jt"
    assert pf.fmt_gb(96200) == "96,2 TB" and pf.fmt_rp(38.2e9) == "Rp 38,2 M"
