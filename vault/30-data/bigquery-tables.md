---
title: BigQuery tables + scan cap + gotchas
type: data
updated: 2026-10-04
---

# BigQuery tables, scan cap, column gotchas

Shared warehouse. Project `data-java-prd-97b9`, dataset `java_precalc`, location
`asia-southeast2`. ADC auth (host-bound OAuth, never service-account keys). Access is
read-only + byte-capped via `bigquery_tool.py` (`run_query`, `dry_run`, `_ensure_limit`).

## Hard rules

- Application execution budget is now 5 GiB per query by default, capped again by
  the existing 50 GiB hard maximum. Latest-period probes have a separate 256 MiB
  budget and a five-minute cache. Overrides are environment configuration, not LLM decisions.
- Product `_mth` table needs an EXACT `month_id` filter (never `LIKE '%05'`) to stay under cap.
- `run_query()` is a god node (57 edges) — the single choke point every report/agent uses.

## Partition pruning needs a LITERAL value (measured 2026-09-17)

A `MAX()` subquery or a join to a MAX() CTE does NOT prune. Same aggregate, same table:

| Table | Literal filter | `MAX()` subquery |
|-------|---------------:|-----------------:|
| `rham_site_traffic_usage_mth` (57 GB) | 0.28 GB | 4.98 GB |
| `rham_outlet_low_stock` (35 GB) | 0.01 GB | 0.71 GB |

`rham_site_traffic_usage_mth.month_id` is a **DATE** (`DATE '2026-07-01'`), not a
`'YYYYMM'` string like the other monthly tables.

## Column gotchas

- `rham_report_fb_ms_*` (market share, monthly) use column **`kabkot`** (NOT `kabkota`) and
  have no branch/circle column.
- `rham_kec_wise_tnr_mtd` has **68 of 184 numeric columns entirely empty**, `_mth` has 18.
  Ranking on one returns zero rows and reads as missing data. The lists ship as
  `warning_columns` in the KB.
- `rham_ftth_tt_mttr` holds both `period_type='WEEKLY'` and `'MONTHLY'` rows AND a
  `bucket='Grand Total'` row. Filter both or every ticket is counted twice.
- `rham_outlet_secondary_mtd` is **not unique** on month + brand + outlet + price.
  Always `SUM` with a `GROUP BY`.
- `rham_report_fb_device_5g` (device owners) and `rham_report_fb_network_5g` (network
  users) measure DIFFERENT populations. `ms_*` are fractions 0-1, not percentages, and
  `location_type` mixes territory levels in one column.
- `rham_postpaid_ga_daily.acq_revenue_mio` is already in millions; partition column is
  `activation_date`.
- Outlet coordinate columns in the GA-quality tables contain corrupt values (latitude
  -620, longitude 946). Not usable for distance or mapping.
- Snapshot-style GA tables (`rham_ga_new_imei_*`, `rham_kec_wise_tnr_*`,
  `rham_site_ga_quality_*`) carry ONE cutoff `dt_id` per month. Summing across `dt_id`
  double counts the month.

## Governance and drift

`backend/governance/table_governance.json` is the lifecycle authority; decisions live in
dated review files next to it. `tools_knowledge_refresh.py --check` fails on an
ungoverned new object, a dropped approved object, or unreviewed schema/partition drift.
Profile a table BEFORE approving it with `tools_profile_candidate.py`, then apply the
review with `tools_apply_review.py` (never `--rebuild-governance`, which erases history).
- FTTH detail tables' `shp_kabkota` / `shp_kecamatan` are NULL → filter on native FTTH columns
  ([[ftth]]).
- FWA = `family_group='09. FWA'`; unlimited = `product_group='HIFI AIR UNLIMITED'`.

## Circle → region mapping (`data_facts.circle_region_mapping`)

- JAVA = Central Java / East Java / Bali Nusra
- JAKARTA RAYA = Inner/Outer Jakarta + West Java
- SUMATERA = North / Central / South
- KALISUMAPA = Kalimantan / Sulawesi / MAPA

## Key tables (by domain)

- Market KPI highlevel: `rham_mkt_kpi_highlevel_dly` for daily, plus
  `rham_mkt_highlevel_mtd` / `_mth` for MTD and monthly.
  The legacy `rham_kpi_highlevel_{dly,mtd,mth}` sources were superseded on
  2026-09-21 and are blocked from runtime routing before their planned deletion.
- Commercial detail: `rham_kec_data_rev_{channel,price_slab,product}_{daily,mtd,mth}`.
  The former site-grain family is retired. Never attribute these aggregates to a site.
- FTTH: `rham_ftth_{so,sa,pa}_detail`, `rham_ftth_sitewise_monthly` ([[ftth]])
- Territory ref: `rham_ref_territory` (IM3 hierarchy; FTTH does NOT use it)
- HVC (2026-10-04): source of truth is `rham_hvc_highlevel_mtd_serving` / `_mth_serving`
  (views, same grain as `rham_mkt_highlevel_*`; `mth_dt` literal prunes the base table).
  Only `subs_hvc` and `hvc_rev_total` are reliable. Split (organic/trade/digital) and
  flow (stay/in/out) are N/A from 202609 (`report_metric_catalog.hvc_unreliable`).
  MTD `hvc_rev_total` holds full-month values in 202504, 202510-202602, 202608: gate
  "HVC rev > rev_prepaid" means N/A. `rham_hvc_kec_*` / `rham_hvc_site_*` stop at 202609;
  `rham_site_wise_monthly.subs_hvc` is 0 except 202608 (treat 0 as N/A).
- Added 2026-10: `rham_ftth_install_orders` (PII columns blocked in `bigquery_tool`),
  FB 5G market share, outlet GA 5G/FWA tables (see governance review additional-sources-2026-10-04).

MTD tables are cutoff-capped (partial current month); `_mth` are full closed months. This split
is the basis of the YTD/LYTD rule → [[ytd-lytd-apple-to-apple]].

For a fuller table→domain map, see [[big-docs]] (`agent-table-mapping.txt`, `precalc-table-audit.txt`).

## October territory and source migration

Live schema was inspected on 2026-10-04. Operational hierarchy is
Circle > Region > Area > District. Former Area is abolished. Public Area maps to
`rham_ref_territory.branch_im3` / `zz_territory_kecamatan.branch`; District maps to
`micro_cluster_im3` / `im3_mc`. Physical old Area columns are NULL. Legacy API
branch/MC aliases remain compatible, but web and mobile show Area/District.
FTTH keeps its independent territory vocabulary.

The reviewed inventory has 330 live objects, 150 runtime-approved sources,
zero missing approved sources, and zero unreviewed schema/partition drifts.
Unknown tables remain candidates or quarantined. No BigQuery tables were altered
or deleted. Existing governance history and KB backups were retained.

- Outlet GA quality sources become `rham_outlet_ga{,_dtu,_mtd,_mth}`. Validate
  coordinates separately; corrupt outlet coordinates must not enter proximity queries.
- Kecamatan device acquisition uses `gaq_*` in market highlevel. Site acquisition
  still has `ga_new_imei` in `rham_site_ga_quality_mtd`; these are different grains.
- Old traffic quota/utilization detail and forecast sources have no verified equivalent.
  Observed traffic is available in site-wise `usg_data_gb`, not an invented forecast.
- Current monthly FWA does not have eight former acquisition split columns. Reports
  keep these readings N/A while rendering supported totals. Snapshot stocks are never
  summed across daily dates to manufacture monthly RGU or VLR.
- Main site performance and Kecamatan commercial detail can have different cutoffs.
  Detail payload includes its own grain, scope, and month; clients label both scopes.
- Occupancy MAX(month_id)=202512 versus site availability=202609, rechecked live.
  Comparisons must use common covered periods, never independent latest-month joins.

### PART-001 diagnostic and remediation checklist

1. Historical processed and billed bytes were requested with the following diagnostic.
   The account lacks `bigquery.jobs.listAll`, so project-wide billing savings cannot
   be measured here. This is not permission to change IAM.

```sql
SELECT job_id, total_bytes_processed, total_bytes_billed, query
FROM `data-java-prd-97b9.region-asia-southeast2`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY total_bytes_billed DESC
LIMIT 50;
```

2. Physical partition types and populated partitions were checked using live catalog
   metadata and INFORMATION_SCHEMA. Kecamatan detail monthly tables partition on
   `mth_dt` DATE, not their STRING YYYYMM `month_id`.

```sql
SELECT table_name, column_name, data_type, is_partitioning_column,
       clustering_ordinal_position
FROM `data-java-prd-97b9.java_precalc.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name LIKE 'rham_kec_data_rev_%'
  AND (is_partitioning_column='YES' OR clustering_ordinal_position IS NOT NULL);

SELECT table_name, partition_id, total_rows, total_logical_bytes
FROM `data-java-prd-97b9.java_precalc.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name='rham_kec_data_rev_product_mtd'
ORDER BY partition_id DESC;
```

3. Application enforcement is live: equivalent literal bounds derived from existing
   month predicates; independent MAX probes resolved and cached; large unbounded
   facts rejected before execution; dry-run and actual maximum_bytes_billed both
   use the same budget. INNER JOIN constant filters may be pushed into WHERE;
   outer-join predicates are never pushed because that would change results.
  The requested window and YTD/LYTD cutoff symmetry are preserved. LIMIT is not
  a scan-cost control. Warehouse `require_partition_filter=TRUE` remains a proposed
  DBA change, not executed by this application migration.
   Unclustered product YTD detail can still exceed a single-job budget even with
   correct pruning. Its additive SUM reports use literal two-month batches,
   recombine all months before ranking or ratios, and cache the complete report.
   Batching bounds each job, not the total bytes needed for a full YTD report;
   it does not silently discard months or override the cost guard.
4. Recommend reviewing clustering on `kec_id`, `brand`, `circle`, and the frequently
   filtered product/channel dimension, within the four-column BigQuery limit.
   Check current clustering and workload first. No repartitioning, clustering DDL,
   or table replacement was executed.

Dry-run measurements, same aggregate and requested latest period:

| Source | Dynamic latest period | Optimized literal partitions |
|--------|----------------------:|-----------------------------:|
| Market KPI MTD | 14,843,184 bytes | 535,130 bytes |
| Kecamatan product MTD, IM3 JAVA revenue data | 2,542,643,162 bytes | 186,676,031 bytes |

The product example reduces estimated scanned bytes by 92.66%. These are scan
estimates, not billed-money savings; minimum billing units, cold metadata lookups,
and cache hits matter. An already-literal query is not assumed to become cheaper.

### Client and map contract

The shared territory asset contains 7,175 mappings with hierarchy_version=2026-10.
Mobile polygon parsing preserves holes and multipart geometry; hit tests include
boundaries and exclude hole interiors. Server location uses polygon covers, with
no approximate centroid substitution for points outside polygons. Invalid
coordinates are excluded from maps without deleting their source table rows.
GPS refresh reacquires a fix, displays accuracy and capture time, and shows an
uncertainty radius. Sequential magnitude and zero-centered/favorable change scales
have matching legends. Result bounds exclude unrelated remote GPS locations.
Detail sheets scroll all fields rather than truncating them. Shared mobile theme
keeps 48-pixel touch targets while reducing visual spacing.

Web verification at 390x844 confirmed Area/District filters, a working Surabaya
Comprehensive report, and no page-wide horizontal overflow. A live AI question
that previously changed per-District into per-Kecamatan now returns six District
rows with 881,833 processed bytes. Routing rephrases and Analyst validation preserve
explicit grouping; runtime hierarchy knowledge is now injected into the router.

Mobile release was 1.48.0+63 at that time (current: `backend/data/app_release.json`). Signing certificate matches the installed release;
the prior 1.47.0+62 APK is retained for rollback. Device GPS accuracy still depends
on permission, sensor quality, and field conditions; automated geometry tests do
not replace physical-device field validation.

Product Demand now forwards Area/District filters through both client APIs,
uses territory-specific server/client cache keys, and returns its applied scope.
Web/mobile reports fetch on selection rather than warming every unopened tab.
Previously visited scoped payloads remain cached; all report tabs are reachable.
The bounded YTD Product Demand report passed live at circle scope and the final
District check uses the same full-period aggregation, not a circle-only fallback.
The deployed nginx host verified on 2026-10-04 is `agent.bizplan-java.com`,
not the older `agent-02.bizplan-java.com` documented in setup instructions.

Validation: 357 backend tests, 28/28 knowledge benchmark cases, 53 mobile tests,
clean Flutter analysis and frontend lint/build, and 3/3 live chat smoke cases.
Runtime graph and generated KB projection are current. Developer Graphify AST
refresh succeeds; semantic refresh is partial when the provider rejects a
region or times out. This developer index is not production chat retrieval.

## Related

- [[knowledge-base-json]] · [[ytd-lytd-apple-to-apple]] · [[ftth]] · [[domains-moc]]
