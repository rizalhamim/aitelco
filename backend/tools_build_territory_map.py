"""Regenerate canonical territory metadata for web and bundled mobile maps."""
import gzip
import json
from pathlib import Path

from app import config
from app.bigquery_tool import run_query
from app.territory import HIERARCHY_VERSION, public_territory


def main():
    result = run_query(f"SELECT kec_id, kecamatan, kabkot, province, circle, region, branch_im3, micro_cluster_im3, island FROM `{config.BQ_PROJECT}.{config.BQ_DATASET}.rham_ref_territory`", row_limit=15000)
    mapping = {str(r["kec_id"]).strip().upper(): {**public_territory(r),
               "branch": r.get("branch_im3"), "microcluster": r.get("micro_cluster_im3"),
               "hierarchy_version": HIERARCHY_VERSION} for r in result["rows"] if r.get("kec_id")}
    raw = json.dumps(mapping, ensure_ascii=False, separators=(",", ":")).encode()
    root = Path(__file__).resolve().parent
    for target in [root / "data/geo/territory_map.json.gz", root.parent / "mobile/assets/geo/territory_map.json.gz"]:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(gzip.compress(raw, mtime=0))
        print(target, len(mapping), "territories", HIERARCHY_VERSION)
    plain = root / "data/geo/territory_map.json"
    if plain.exists():
        plain.write_bytes(raw)


if __name__ == "__main__":
    main()
