#!/usr/bin/env python3
"""Report how many rows actually carry a value for each numeric column of a table.

A column existing in the schema does not mean it holds data. The SQL writer only sees
the schema, so it will happily rank on a column that is empty in practice and return a
permanently empty result that looks like missing data (this is exactly what happened
with the FWA 90d columns). Run this when a metric mysteriously returns nothing, then
record the finding as a KB key fact.

    venv/bin/python tools_column_population.py rham_site_fwa_daily
    venv/bin/python tools_column_population.py rham_site_fwa_daily --date-col dt_id
"""
from __future__ import annotations

import argparse

from app import bigquery_tool as bq, knowledge


def numeric_columns(table: str) -> list[str]:
    kb = knowledge.load_kb()
    for domain in kb.get("domains", {}).values():
        spec = (domain.get("tables") or {}).get(table)
        if not spec:
            continue
        cols = spec.get("columns") or {}
        entries = cols.values() if isinstance(cols, dict) else cols
        out = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            if str(entry.get("type", "")).upper() in {"INT64", "FLOAT64", "NUMERIC",
                                                      "BIGNUMERIC", "INTEGER", "FLOAT"}:
                out.append(entry["name"])
        return out
    raise SystemExit(f"table '{table}' not found in the runtime KB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("table")
    parser.add_argument("--date-col", default="",
                        help="restrict to the latest value of this column (e.g. dt_id)")
    parser.add_argument("--like", default="",
                        help="only columns whose name contains this substring")
    parser.add_argument("--limit-cols", type=int, default=40)
    args = parser.parse_args()

    kb = knowledge.load_kb()
    fq = f"`{kb['project']}.{kb['dataset']}.{args.table}`"
    cols = [c for c in numeric_columns(args.table) if args.like.lower() in c.lower()]
    if not cols:
        raise SystemExit("no matching numeric columns")
    cols = cols[: args.limit_cols]

    where = ""
    if args.date_col:
        where = (f"WHERE t.{args.date_col} = "
                 f"(SELECT MAX({args.date_col}) FROM {fq})")

    parts = ", ".join(
        f"COUNTIF(t.{c} IS NOT NULL) AS {c}__nn, COUNTIF(t.{c} > 0) AS {c}__pos, "
        f"MIN(t.{c}) AS {c}__min, MAX(t.{c}) AS {c}__max"
        for c in cols)
    sql = f"SELECT COUNT(*) AS total, {parts} FROM {fq} t {where}"

    row = bq.run_query(sql)["rows"][0]
    total = row["total"]
    print(f"{args.table}: {total:,} rows"
          + (f" at latest {args.date_col}" if args.date_col else ""))
    print(f"{'column':34s} {'non-null':>10s} {'positive':>10s}  range")
    for c in cols:
        nn, pos = row[f"{c}__nn"], row[f"{c}__pos"]
        share = (nn / total * 100) if total else 0.0
        flag = "  <- EMPTY IN PRACTICE" if total and share < 1 else ""
        print(f"{c:34s} {nn:>10,} {pos:>10,}  "
              f"[{row[f'{c}__min']}, {row[f'{c}__max']}] {share:5.1f}%{flag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
