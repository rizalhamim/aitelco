#!/usr/bin/env python3
"""Fetch BigQuery schema for a list of tables.

Reads tables via INFORMATION_SCHEMA so we get description/nullable/etc
in one pass (no per-table API call). Writes structured JSON for downstream
KB enrichment.

Usage:
  python3 tools_fetch_table_schemas.py <output.json>

Hard-coded against the 36 unmapped tables from precalc-table-audit.txt.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, "/home/ubuntu/telco-ai/backend")
from app.bigquery_tool import get_client  # noqa: E402
from app import config  # noqa: E402

UNMAPPED = [
    "ds_snd_kecwise_is_performance",
    "rham_desa_perf_history",
    "rham_desa_perf_monthly",
    "rham_desa_perf_mtd",
    "rham_fb_ms_age",
    "rham_fb_ms_kabkota_v2",
    "rham_fb_ms_kecamatan_v2",
    "rham_forecast_daily_branch_output",
    "rham_forecast_daily_branch_output_v3",
    "rham_forecast_daily_branch_source",
    "rham_forecast_daily_kabkota_output",
    "rham_forecast_daily_kabkota_output_v3",
    "rham_forecast_daily_kabkota_source",
    "rham_forecast_daily_mc_output",
    "rham_forecast_daily_mc_output_v3",
    "rham_forecast_daily_mc_source",
    "rham_forecast_daily_rev_mc_input",
    "rham_forecast_daily_rev_mc_output",
    "rham_forecast_monthly_branch_output_v3",
    "rham_forecast_monthly_kabkota_output_v3",
    "rham_forecast_monthly_mc_output_v3",
    "rham_fwa_site_raw",
    "rham_kpi_highlevel_dly",
    "rham_kpi_highlevel_mtd",
    "rham_kpi_highlevel_mth",
    "rham_master_tracker_fwa",
    "rham_project_desa_java",
    "rham_ref_site_desa",
    "rham_ref_super88",
    "rham_ref_territory",
    "rham_ref_territory2",
    "rham_ref_territory_3id_static",
    "rham_ref_territory_zz",
    "rham_site_wise_addr_java_perf_yoy",
    "rham_site_wise_daily_raw",
    "rham_zz_ref_holiday",
]


def main():
    out_path = Path(sys.argv[1])
    client = get_client()

    # Pull all columns in one go via INFORMATION_SCHEMA.COLUMNS
    project = config.BQ_PROJECT
    dataset = config.BQ_DATASET
    table_names_sql = ", ".join(f"'{t}'" for t in UNMAPPED)
    sql = f"""
    SELECT
      table_name,
      column_name,
      data_type,
      is_nullable,
      is_partitioning_column,
      ordinal_position
    FROM `{project}.{dataset}.INFORMATION_SCHEMA.COLUMNS`
    WHERE table_name IN ({table_names_sql})
    ORDER BY table_name, ordinal_position
    """
    print(f"Querying {len(UNMAPPED)} tables...", file=sys.stderr)
    rows = list(client.query(sql))
    print(f"Got {len(rows)} column rows", file=sys.stderr)

    # Also fetch row counts and table descriptions
    # __TABLES__ uses `table_id` not `table_name`; alias to align
    sql_meta = f"""
    SELECT rc.table_name, rc.row_count, dsc.table_description
    FROM (
      SELECT table_id AS table_name, row_count FROM `{project}.{dataset}.__TABLES__`
    ) AS rc
    LEFT JOIN (
      SELECT table_name, option_value AS table_description
      FROM `{project}.{dataset}.INFORMATION_SCHEMA.TABLE_OPTIONS`
      WHERE option_name = 'description'
    ) AS dsc USING (table_name)
    WHERE rc.table_name IN ({table_names_sql})
    """
    meta_rows = list(client.query(sql_meta))
    meta = {r.table_name: {"rows": r.row_count, "description": r.table_description}
            for r in meta_rows}

    # Also fetch column descriptions
    sql_col_opts = f"""
    SELECT table_name, column_name, option_value AS col_description
    FROM `{project}.{dataset}.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
    WHERE table_name IN ({table_names_sql})
      AND field_path = column_name
    """
    try:
        col_opt_rows = list(client.query(sql_col_opts))
        col_desc = {(r.table_name, r.column_name): r.col_description for r in col_opt_rows
                    if r.col_description}
    except Exception as e:
        print(f"col_desc query failed (non-fatal): {e}", file=sys.stderr)
        col_desc = {}

    # Group by table
    by_table = {}
    for r in rows:
        t = r.table_name
        by_table.setdefault(t, {
            "table_name": t,
            "rows": meta.get(t, {}).get("rows", 0),
            "description": (meta.get(t, {}).get("description") or "").strip('"'),
            "columns": [],
        })
        by_table[t]["columns"].append({
            "name": r.column_name,
            "type": r.data_type,
            "nullable": r.is_nullable == "YES",
            "partition": r.is_partitioning_column == "YES",
            "desc": (col_desc.get((t, r.column_name)) or "").strip('"'),
        })

    # Tables with no columns returned (missing from BQ?)
    missing = [t for t in UNMAPPED if t not in by_table]
    if missing:
        print(f"WARNING: not found in BQ: {missing}", file=sys.stderr)

    out = {
        "project": project,
        "dataset": dataset,
        "tables": by_table,
        "missing": missing,
    }
    out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False))
    print(f"Wrote {out_path} ({len(by_table)} tables)", file=sys.stderr)
    # Quick summary
    print("\nSummary:")
    for t, d in by_table.items():
        ncol = len(d["columns"])
        print(f"  {t:<45} {d['rows']:>12,} rows, {ncol:>3} cols, desc={'yes' if d['description'] else 'no'}")


if __name__ == "__main__":
    main()
