#!/usr/bin/env python3
"""Profile a java_precalc table that is NOT yet in the runtime KB.

`tools_column_population.py` reads the runtime KB, so it cannot look at a table
under review: the table is only in the KB after it is approved, and it can only
be approved after someone looks at it. This closes that loop.

Every query is dry-run first and refused above a byte ceiling, because the
review list includes a 37 GB and a 61 GB table where one unbounded profiling
query costs more than the feature is worth.

    venv/bin/python tools_profile_candidate.py rham_ga_new_imei_mtd
    venv/bin/python tools_profile_candidate.py rham_outlet_low_stock --grain dt_id,outlet_id,kpi
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app import config  # noqa: E402

MAX_SCAN_BYTES = 8 * 1024 ** 3
DATE_TYPES = {"DATE", "DATETIME", "TIMESTAMP"}
NUMERIC_TYPES = {"INTEGER", "INT64", "FLOAT", "FLOAT64", "NUMERIC", "BIGNUMERIC"}


def live_table(name: str) -> dict[str, Any]:
    from app.bigquery_tool import get_client

    table = get_client().get_table(f"{config.BQ_PROJECT}.{config.BQ_DATASET}.{name}")
    return {
        "name": table.table_id,
        "type": table.table_type,
        "rows": int(table.num_rows or 0),
        "bytes": int(table.num_bytes or 0),
        "partition_field": getattr(table.time_partitioning, "field", None),
        "clustering_fields": table.clustering_fields or [],
        "columns": [
            {"name": f.name, "type": f.field_type, "mode": f.mode} for f in table.schema
        ],
    }


def run(sql: str) -> list[dict[str, Any]]:
    """Dry run, refuse an expensive scan, then execute."""
    from google.cloud import bigquery

    from app.bigquery_tool import dry_run, get_client

    scanned = dry_run(sql)
    if scanned > MAX_SCAN_BYTES:
        raise SystemExit(
            f"refusing to scan {scanned / 1024 ** 3:.1f} GB. Narrow the filter first.")
    job = get_client().query(
        sql, job_config=bigquery.QueryJobConfig(maximum_bytes_billed=MAX_SCAN_BYTES))
    result = job.result(timeout=config.QUERY_TIMEOUT_S)
    columns = [f.name for f in result.schema]
    rows = [{c: r[c] for c in columns} for r in result]
    return json.loads(json.dumps(rows, default=str))


def coverage(meta: dict[str, Any], date_col: str) -> list[dict[str, Any]]:
    fq = f"`{config.BQ_PROJECT}.{config.BQ_DATASET}.{meta['name']}`"
    return run(
        f"SELECT MIN({date_col}) AS min_period, MAX({date_col}) AS max_period, "
        f"COUNT(DISTINCT {date_col}) AS periods, COUNT(*) AS row_count FROM {fq}")


def grain_uniqueness(meta: dict[str, Any], grain: list[str],
                     where: str) -> list[dict[str, Any]]:
    fq = f"`{config.BQ_PROJECT}.{config.BQ_DATASET}.{meta['name']}`"
    keys = ", ".join(grain)
    return run(
        f"WITH scoped AS (SELECT {keys} FROM {fq} {where}) "
        f"SELECT COUNT(*) AS row_count, COUNT(DISTINCT TO_JSON_STRING(t)) AS distinct_keys "
        f"FROM scoped t")


def population(meta: dict[str, Any], where: str, limit: int) -> list[dict[str, Any]]:
    fq = f"`{config.BQ_PROJECT}.{config.BQ_DATASET}.{meta['name']}`"
    numeric = [c["name"] for c in meta["columns"]
               if c["type"].upper() in NUMERIC_TYPES][:limit]
    if not numeric:
        return []
    parts = []
    for col in numeric:
        parts.append(
            f"STRUCT('{col}' AS col, COUNTIF(`{col}` IS NOT NULL) AS non_null, "
            f"COUNTIF(`{col}` < 0) AS negative, MIN(`{col}`) AS min_v, "
            f"MAX(`{col}`) AS max_v)")
    sql = (f"SELECT stat.* FROM (SELECT [{', '.join(parts)}] AS stats FROM {fq} {where}), "
           f"UNNEST(stats) AS stat")
    return run(sql)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("table")
    parser.add_argument("--date-col", default="", help="override the period column")
    parser.add_argument("--grain", default="", help="comma-separated grain columns")
    parser.add_argument("--where", default="", help="extra predicate, without WHERE")
    parser.add_argument("--limit-cols", type=int, default=25)
    parser.add_argument("--skip-population", action="store_true")
    args = parser.parse_args()

    meta = live_table(args.table)
    date_col = args.date_col or meta["partition_field"] or next(
        (c["name"] for c in meta["columns"]
         if c["type"].upper() in DATE_TYPES or c["name"] in {"month_id", "period_id"}),
        "")

    report: dict[str, Any] = {
        "table": meta["name"],
        "object_type": meta["type"],
        "rows": meta["rows"],
        "gb": round(meta["bytes"] / 1024 ** 3, 3),
        "partition_field": meta["partition_field"],
        "clustering_fields": meta["clustering_fields"],
        "column_count": len(meta["columns"]),
        "period_column": date_col,
    }

    if date_col:
        try:
            report["coverage"] = coverage(meta, date_col)
        except SystemExit as exc:
            report["coverage_error"] = str(exc)

    where = f"WHERE {args.where}" if args.where else ""
    if args.grain:
        grain = [c.strip() for c in args.grain.split(",") if c.strip()]
        try:
            report["grain"] = {"columns": grain,
                               "result": grain_uniqueness(meta, grain, where)}
        except SystemExit as exc:
            report["grain_error"] = str(exc)

    if not args.skip_population:
        try:
            report["population"] = population(meta, where, args.limit_cols)
        except SystemExit as exc:
            report["population_error"] = str(exc)

    print(json.dumps(report, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
