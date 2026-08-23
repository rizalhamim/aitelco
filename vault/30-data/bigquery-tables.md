---
title: BigQuery tables + scan cap + gotchas
type: data
updated: 2026-07-26
---

# BigQuery tables, scan cap, column gotchas

Shared warehouse. Project `data-java-prd-97b9`, dataset `java_precalc`, location
`asia-southeast2`. ADC auth (host-bound OAuth, never service-account keys). Access is
read-only + byte-capped via `bigquery_tool.py` (`run_query`, `dry_run`, `_ensure_limit`).

## Hard rules

- **50 GB scan cap** on some tables. Keep queries partition-pruned and bounded.
- Product `_mth` table needs an EXACT `month_id` filter (never `LIKE '%05'`) to stay under cap.
- `run_query()` is a god node (57 edges) — the single choke point every report/agent uses.

## Column gotchas

- `rham_report_fb_ms_*` (market share, monthly) use column **`kabkot`** (NOT `kabkota`) and
  have no branch/circle column.
- FTTH detail tables' `shp_kabkota` / `shp_kecamatan` are NULL → filter on native FTTH columns
  ([[ftth]]).
- FWA = `family_group='09. FWA'`; unlimited = `product_group='HIFI AIR UNLIMITED'`.

## Circle → region mapping (`data_facts.circle_region_mapping`)

- JAVA = Central Java / East Java / Bali Nusra
- JAKARTA RAYA = Inner/Outer Jakarta + West Java
- SUMATERA = North / Central / South
- KALISUMAPA = Kalimantan / Sulawesi / MAPA

## Key tables (by domain)

- Market highlevel: `rham_mkt_highlevel_mtd` / `_mth`
- Site data revenue: `rham_site_data_rev_*_mtd` / `_mth`
- FTTH: `rham_ftth_{so,sa,pa}_detail`, `rham_ftth_sitewise_monthly` ([[ftth]])
- Territory ref: `rham_ref_territory` (IM3 hierarchy; FTTH does NOT use it)

MTD tables are cutoff-capped (partial current month); `_mth` are full closed months. This split
is the basis of the YTD/LYTD rule → [[ytd-lytd-apple-to-apple]].

For a fuller table→domain map, see [[big-docs]] (`agent-table-mapping.txt`, `precalc-table-audit.txt`).

## Related

- [[knowledge-base-json]] · [[ytd-lytd-apple-to-apple]] · [[ftth]] · [[domains-moc]]
