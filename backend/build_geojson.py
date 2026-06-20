"""Convert the master kecamatan SHP into simplified, compressed GeoJSON for
web/app choropleth rendering. Produces TWO files (gzipped):
  - geo/kecamatan.geojson.gz   (key: kec_id  = "KEC|KAB_KOT")
  - geo/kabupaten.geojson.gz   (key: kabkot_id = "KAB_KOT|PROV", dissolved)

Original SHP is kept untouched for backend point queries.
Smooth simplification (Douglas-Peucker tolerance ~0.0001 deg ~ 11m) so the
kecamatan boundaries render with smooth curves at city zoom
(~11.9MB gz kecamatan / ~6.0MB gz kabupaten, ~38% of original points).
"""
import os, json, gzip, sys
from collections import defaultdict
import shapefile
from shapely.geometry import shape, mapping
from shapely.ops import unary_union

SHP = os.environ.get("KEC_SHP_PATH", "/home/ubuntu/telco-ai/shp/Data Kecamatan Indonesia")
OUT_DIR = os.path.join(os.path.dirname(__file__), "data", "geo")
TOL = float(os.environ.get("GEO_SIMPLIFY_TOL", "0.0001"))   # smooth (~11m)
COORD_ND = int(os.environ.get("GEO_COORD_ND", "5"))          # ~1.1m precision
os.makedirs(OUT_DIR, exist_ok=True)


def _round_geom(geom, nd=COORD_ND):
    """Round coordinates to nd decimals (~1m at nd=5) to shrink JSON further."""
    gj = mapping(geom)

    def rd(c):
        if isinstance(c, (list, tuple)):
            if c and isinstance(c[0], (int, float)):
                return [round(c[0], nd), round(c[1], nd)]
            return [rd(x) for x in c]
        return c

    gj["coordinates"] = rd(gj["coordinates"])
    return gj


def main():
    print(f"Reading {SHP} ...")
    sf = shapefile.Reader(SHP)
    flds = [f[0] for f in sf.fields[1:]]
    idx = {name: i for i, name in enumerate(flds)}
    n = len(sf)
    print(f"{n} shapes, fields: {flds}")

    kec_features = []
    kab_groups = defaultdict(list)   # kabkot_id -> list[shapely geom]
    kab_meta = {}

    ok = 0
    for i in range(n):
        try:
            sr = sf.shapeRecord(i)
            rec = sr.record
            kec_id = rec[idx["KEC_ID"]]
            kabkot_id = rec[idx["KABKOT_ID"]]
            prov = rec[idx["PROV"]]
            kab = rec[idx["KAB_KOT"]]
            kec = rec[idx["KEC"]]
            geom = shape(sr.shape.__geo_interface__)
            if not geom.is_valid:
                geom = geom.buffer(0)
            simp = geom.simplify(TOL, preserve_topology=True)
            if simp.is_empty:
                simp = geom
            kec_features.append({
                "type": "Feature",
                "properties": {"kec_id": kec_id, "kabkot_id": kabkot_id,
                               "kecamatan": kec, "kabupaten": kab, "provinsi": prov},
                "geometry": _round_geom(simp),
            })
            kab_groups[kabkot_id].append(geom)
            kab_meta[kabkot_id] = {"kabupaten": kab, "provinsi": prov}
            ok += 1
            if ok % 1000 == 0:
                print(f"  ...{ok}/{n}")
        except Exception as e:
            print(f"  skip shape {i}: {e}", file=sys.stderr)

    kec_fc = {"type": "FeatureCollection", "features": kec_features}
    _write(os.path.join(OUT_DIR, "kecamatan.geojson"), kec_fc)

    # dissolve to kabupaten
    print(f"Dissolving {len(kab_groups)} kabupaten ...")
    kab_features = []
    for kid, geoms in kab_groups.items():
        try:
            merged = unary_union(geoms)
            merged = merged.simplify(TOL, preserve_topology=True)
            meta = kab_meta[kid]
            kab_features.append({
                "type": "Feature",
                "properties": {"kabkot_id": kid, "kabupaten": meta["kabupaten"], "provinsi": meta["provinsi"]},
                "geometry": _round_geom(merged),
            })
        except Exception as e:
            print(f"  skip kab {kid}: {e}", file=sys.stderr)
    kab_fc = {"type": "FeatureCollection", "features": kab_features}
    _write(os.path.join(OUT_DIR, "kabupaten.geojson"), kab_fc)
    print("Done.")


def _write(path, fc):
    raw = json.dumps(fc, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with open(path, "wb") as f:
        f.write(raw)
    gz = path + ".gz"
    with gzip.open(gz, "wb", compresslevel=9) as f:
        f.write(raw)
    print(f"  wrote {path}  ({len(raw)/1e6:.2f} MB raw, {os.path.getsize(gz)/1e6:.2f} MB gz, {len(fc['features'])} features)")


if __name__ == "__main__":
    main()
