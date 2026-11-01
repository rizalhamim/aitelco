"""Peta Agent: map payload, chat answers, upload parsing and export (synthetic geo, no BigQuery)."""
import io
import json
import zipfile

import shapefile

from app import map_agent as ma, performance as pf
from tests.test_performance import _rows


def _sq(x0, y0, x1, y1):
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]


GEO = {
    "kec": [
        {"kab": "GARUT", "prov": "JAWA BARAT", "kec": "TAROGONG KIDUL", "rings": [_sq(107.85, -7.25, 107.95, -7.15)]},
        {"kab": "GARUT", "prov": "JAWA BARAT", "kec": "CIBATU", "rings": [_sq(107.95, -7.15, 108.05, -7.05)]},
    ],
    "kab": [
        {"kab": "GARUT", "prov": "JAWA BARAT", "kec": None, "rings": [_sq(107.85, -7.25, 108.05, -7.05)]},
        {"kab": "TASIKMALAYA", "prov": "JAWA BARAT", "kec": None, "rings": [_sq(108.05, -7.4, 108.3, -7.1)]},
        {"kab": "MALANG", "prov": "JAWA TIMUR", "kec": None, "rings": [_sq(112.5, -8.0, 112.9, -7.7)]},
    ],
}


def _patch(monkeypatch):
    kec, site, avail = _rows()
    monkeypatch.setattr(pf, "_data", lambda: (kec, site, avail, {"kind": "dump", "label": "Dump", "queries": 0}))
    monkeypatch.setattr(ma, "geo", lambda: GEO)
    ma._cached.cache_clear()


def test_map_payload(monkeypatch):
    _patch(monkeypatch)
    d = ma.map_payload("", "GARUT")
    assert d["scope"]["name"] == "Kab. Garut" and d["scope"]["province"] == "West Java"
    assert d["unit_level"] == "kecamatan" and [u["n"] for u in d["units"]] == ["Cibatu", "Tarogong Kidul"]
    tk = next(u for u in d["units"] if u["n"] == "Tarogong Kidul")
    assert tk["m"]["payload_mom"] < -19 and tk["status"] == "kritis" and tk["sites"] == 1 and tk["crit"] == 1
    assert tk["m"]["rev_site"] is not None and tk["m"]["vlr_site"] is None
    assert {s["id"] for s in d["sites"]} == {"GRT-1", "GRT-2"}
    g1 = next(s for s in d["sites"] if s["id"] == "GRT-1")
    assert g1["crit"] and 0 < g1["x"] < ma.FRAME_W and 0 < g1["y"] < ma.FRAME_H and g1["lat"] == -7.2
    assert [n["n"] for n in d["neighbors"]] == ["Kab. Tasikmalaya"]
    assert d["outline"].startswith("M") and d["month_label"] == "Okt 2026"
    avail = {m["key"]: m["available"] for m in d["metrics"]}
    assert avail["payload_mom"] and not avail["market_share"]


def test_frame_roundtrip():
    fr = ma.Frame([107.4, -7.7, 108.1, -6.9])
    x, y = fr.p(107.9, -7.2)
    lon, lat = fr.inv(x, y)
    assert abs(lon - 107.9) < 1e-9 and abs(lat + 7.2) < 1e-9


def test_ask_metric_and_threshold(monkeypatch):
    _patch(monkeypatch)
    a = ma.ask("Tampilkan payload MoM per kecamatan di Garut, tandai site yang turun lebih dari 10%", "", "GARUT")
    assert a["text"].startswith("Payload Kab. Garut turun **")
    assert "**Tarogong Kidul (−19,9%)**" in a["text"] and a["text"].endswith("Dua layer saya tambahkan ke peta:")
    assert [l["kind"] for l in a["layers"]] == ["chor", "sites"]
    assert a["layers"][1]["label"] == "1 site turun > 10%" and a["site_ids"] == ["GRT-1"]
    assert a["focus"] and a["focus"][2] > a["focus"][0]


def test_ask_area_and_coords(monkeypatch):
    _patch(monkeypatch)
    shape = {"rings": [_sq(107.86, -7.24, 107.94, -7.16)]}
    a = ma.ask("Berapa site dan revenue di dalam area ini?", "", "GARUT", [shape])
    assert a["text"].startswith("Area seluas **") and "Tarogong Kidul" in a["text"]
    assert a["stats"][0]["value"] == "1" and a["stats"][0]["sub"] == "1 kritis"
    assert a["stats"][1]["label"] == "Revenue Okt" and a["actions"] == ["sites", "geojson", "png"]
    c = ma.ask("site terdekat dari -7.2, 107.9", "", "GARUT")
    assert c["layers"][0]["kind"] == "point" and c["select"] == "Tarogong Kidul" and c["site_ids"][0] == "GRT-1"


def _shp_zip():
    shp, shx, dbf = io.BytesIO(), io.BytesIO(), io.BytesIO()
    w = shapefile.Writer(shp=shp, shx=shx, dbf=dbf, shapeType=shapefile.POLYGON)
    w.field("nama", "C")
    w.poly([_sq(107.86, -7.24, 107.94, -7.16)])
    w.record("area")
    w.close()
    z = io.BytesIO()
    with zipfile.ZipFile(z, "w") as zf:
        for ext, b in (("shp", shp), ("shx", shx), ("dbf", dbf)):
            zf.writestr(f"area_ekspansi.{ext}", b.getvalue())
    return z.getvalue()


def test_upload_formats(monkeypatch):
    _patch(monkeypatch)
    u = ma.upload_payload("area_ekspansi.zip", _shp_zip(), "", "GARUT")
    assert u["kind"] == "SHP" and u["polygons"] == 1 and u["label"] == "area_ekspansi.shp"
    assert 70 < u["area_km2"] < 90 and u["d"].startswith("M") and u["sub"].startswith("Shapefile · 1 poligon")
    gj = json.dumps({"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [_sq(107.9, -7.2, 107.95, -7.15)]}}]})
    assert ma.parse_upload("a.geojson", gj.encode())["kind"] == "GeoJSON"
    kml = b"<kml><Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>107.9,-7.2 107.95,-7.2 107.95,-7.15 107.9,-7.2</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark></kml>"
    assert len(ma.parse_upload("a.kml", kml)["polygons"]) == 1
    c = ma.parse_upload("t.csv", b"site,lat,long\nA,-7.2,107.9\nB,-7.1,107.95\n")
    assert c["kind"] == "CSV" and c["points"][0] == [107.9, -7.2]


def test_export_shp_roundtrip():
    feats = [{"type": "Feature", "properties": {"site_id": "GRT-1", "kecamatan": "Tarogong Kidul"}, "geometry": {"type": "Point", "coordinates": [107.9, -7.2]}},
             {"type": "Feature", "properties": {"nama": "area"}, "geometry": {"type": "Polygon", "coordinates": [_sq(107.86, -7.24, 107.94, -7.16)]}}]
    body, mime, name = ma.export_file("shp", "area ekspansi", feats)
    assert mime == "application/zip" and name == "area_ekspansi_shp.zip"
    z = zipfile.ZipFile(io.BytesIO(body))
    assert {"area_ekspansi_titik.shp", "area_ekspansi_area.shp", "area_ekspansi_area.prj"} <= set(z.namelist())
    back = ma.parse_upload("x.zip", body)
    assert back["polygons"] or back["points"]
    csv_body, _, _ = ma.export_file("csv", "x", feats)
    assert b"GRT-1" in csv_body and b"-7.2" in csv_body
