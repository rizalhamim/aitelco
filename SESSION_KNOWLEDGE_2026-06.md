# Session Knowledge - FTTH report expansion, YTD/LYTD fix, agent training (2026-06)

Consolidated, recallable record of the work done in this session. Pairs with
`AGENTS.md` (root) and `TELCO_REPORTS_REPLICATION_KNOWLEDGE.txt`.

Current state at end of session:
- Mobile release: **1.43.1+49** (`mobile/pubspec.yaml` + `backend/data/app_release.json`).
- Services active: `telco-backend` (127.0.0.1:8000), `telco-frontend` (127.0.0.1:3000),
  `system-monitor` (port 8080, serves `server-02.bizplan-java.com`).
- Prod host: `agent-02.bizplan-java.com` (nginx `/etc/nginx/sites-available/sysmonitor`).

---

## 1. Indosat HiFi (FTTH) report - built then expanded

Files: `backend/app/reports_ftth.py`, `backend/app/routes_reports.py`,
`frontend/src/app/reports/page.tsx`, `mobile/lib/src/screens/reports_screen.dart`,
`mobile/lib/src/api/api_client.dart`.

### Data model (verified from BigQuery `data-java-prd-97b9.java_precalc`)
- Detail (per-customer funnel): `rham_ftth_{so,sa,pa}_detail`. Columns incl
  province, city, ward, sales_region, sales_code/name/tl/manager, product, price,
  site_project_awal, shp_kabkota, shp_kecamatan (**both NULL in live data**),
  date_so/date_sa/date_pa. Funnel SO->SA->PA counted on each event date.
  PA detail only has data from ~Nov 2025 onward (so FTTH PA LYTD is legitimately 0).
- Sitewise (monthly per-site subscriber snapshot): `rham_ftth_sitewise_monthly`,
  ~166K rows, month_id STRING 202312..202606, brand = 'Orbit'/'Non Orbit'.
  Key cols: pa (cumulative active subs), homepass, available_hp, ga, pa_net_latest,
  region_25, provinsi, city, kecamatan, project_awal, site_id.
  TUR % = SUM(pa)/SUM(homepass)*100. Total subs = SUM(pa) at MAX(month_id).

### Territory filtering (the big fix)
- FTTH does NOT use `rham_ref_territory`. The detail shp_* join columns are NULL,
  and `rham_ref_territory.region` = "CENTRAL JAVA"/"EAST JAVA"/"BALI NUSRA" which is
  a DIFFERENT vocabulary from FTTH `sales_region`/`region_25` = "04. Central Java",
  "05. East Java".
- Filter on native columns via `_detail_scope_clause` / `_sitewise_scope_clause`:
  - detail: ftth_region->sales_region, ftth_province->province, ftth_kabkota->city
    (detail has NO kecamatan col).
  - sitewise: ftth_region->region_25, ftth_province->provinsi, ftth_kabkota->city,
    ftth_kecamatan->kecamatan.
- `_norm_kec()` strips the `|kabkota` suffix from My Coordinate kec_id
  ("ADIWERNA|KAB. TEGAL" -> "ADIWERNA"), fixing My Coordinate kecamatan returning 0.
- Old IM3 levels (region/area/branch/microcluster) from My Coordinate have no FTTH
  equivalent and degrade to circle scope rather than empty.
- Options endpoint: `GET /api/reports/ftth/scope-options?circle=&level=` (sitewise).

### Sections (payload order; first = "FTTH Infrastructure & Utilization")
grid: Infrastructure & Utilization (Homepass/Available/Subs/NetAdd/GA/TUR/Extraction).
ftth_counts: Infrastructure Coverage (#kec w/HP, #kabkota w/HP, #low-TUR sites where
  pa/homepass<0.2 AND homepass>0); Footprint by Project (ORBIT=mplay, NON-ORBIT=
  seahawk|spartan, IFORTE=iforte; cols Homepass+Subs); Product Mix (Advance Payment
  regex `^(AP|Super ?)[0-9]+` vs Regular); Man Power (AE generated SO/SA/PA + AE hit
  >=5 PA). grid: Sales Funnel (SO/SA/PA/PA Revenue/Avg Rev per PA/conversions).
hierarchy: SM->TL->AE nested, expandable, [SO,SA,PA] MTD, sorted SO MTD desc, caps
  20 SM / 20 TL / 50 AE (`_build_hierarchy`).

### Frontend
- Brand IOH/IM3/3ID bar HIDDEN on FTTH tab (web `tab!=="ftth"`, mobile `_tab!='ftth'`).
- New renderers: web FtthCountTable / FtthHierarchyTable; mobile _ftthCountTable /
  _FtthHierTree.
- FTTH-native View dropdown (FTTH_SCOPE_LEVELS web / FTTH option map mobile).
- Searchable scope value: web `<input list>`+`<datalist>` (data fetch gated so partial
  typing doesn't fire invalid queries); mobile `_ScopeSearchSheet` bottom sheet with a
  search field. Mobile filter UI made compact (smaller fonts/padding, 30px controls).

---

## 2. YTD / LYTD apple-to-apple fix (ALL reports)

Bug: YTD mixed full closed months + partial current month (MTD), but LYTD summed FULL
months for all of Jan..current-month last year (a FULL prior-year current month). So a
partial June 2026 was compared against a full June 2025. For rev_prepaid LYTD was
overstated ~1.72 trillion (21.24T -> correct 19.52T).

Fix (both sides symmetric, current month from the cutoff-capped MTD table):
- `YTD  = SUM(_mth, Jan..mid-1 this year) + MTD(_mtd, mid)`
- `LYTD = SUM(_mth, Jan..mid-1 last year) + MTD(_mtd, mid-100)`
Prior-year MTD snapshot is symmetric: `_mtd[202506].dt_id_snapshot = 2025-06-16` matches
`202606 = 2026-06-16`.

Implemented in:
- `reports_comprehensive.py`: added `r_lytd_cur_mtd` from `_MTD[mid-100]`; flow LYTD =
  prior-LY `_mth` + current-LY `_mtd`.
- `reports_data.py`: same in all 4 cumulative blocks (channel chunks, price slabs,
  product-demand slabs, top products) using `_channel`/`_slab`/`_product` MTD tables for
  the current-LY month (`mid_ly = mid-100`, `prior_ly` excludes mid_ly).
- `reports_ftth.py`: LYTD by date range, `LYTD = [(year-1)-01-01 .. cur_dt minus 1 year]`
  via DATE_SUB (fixes a January edge case).
- `reports_city_profile.py`: consumes comprehensive, inherits the fix.
- Snapshot metrics unchanged: point-in-time MTD-this-year vs MTD-last-year (NOT a sum).

Verified live: comprehensive rev_prepaid LYTD = 19,517,981,810,937 (= Jan-May 2025 `_mth`
+ Jun 2025 `_mtd`); data-revenue YTD 20.77T vs LYTD 18.11T (+14.7%).

---

## 3. Chat agent training (knowledge_base.json)

The agent's ONLY prompt-injected knowledge is `backend/data/knowledge_base.json`
(`data_facts` + per-domain `agent.key_facts`). `learning_notes` (SQLite) is write-only
telemetry exposed at `/api/learnings`, NEVER fed back into prompts. Past questions:
`backend/data/sessions.db` table `analytics` (question, domain, sql, success, error_msg,
response_summary, ts=unix epoch). `knowledge.py:load_kb()` is `@lru_cache`d -> restart
`telco-backend` to reload.

Added this session (from reviewing 7-day questions + the new FTTH table):
- `domains.ftth.tables.rham_ftth_sitewise_monthly` (33 cols documented), table_count
  3->4, enriched persona/key_facts (two grains: funnel detail vs sitewise subscriber
  snapshot; pa=cumulative subs; TUR; footprint; SUM(pa) at MAX(month_id)).
- `data_facts.circle_region_mapping`: JAVA = CENTRAL JAVA, EAST JAVA, BALI NUSRA;
  JAKARTA RAYA = INNER JAKARTA, OUTER JAKARTA, WEST JAVA; SUMATERA = NORTH/CENTRAL/SOUTH
  SUMATERA; KALISUMAPA = KALIMANTAN, SULAWESI, MAPA.
- competitive key_facts: `rham_report_fb_ms_kecamatan` uses `kabkot` (NOT `kabkota`),
  has region but NO branch/circle col; for circle scope filter region IN (...). Never
  write `kabkota` for the rham_report_fb_ms_* tables.
- product key_facts: FWA = `family_group='09. FWA'`, unlimited = `product_group='HIFI
  AIR UNLIMITED'`; for `rham_site_data_rev_product_mth` always pin an EXACT month_id
  (never `LIKE '%05'`) to stay under the 50 GB scan cap; that table uses `kabkota`.

Verified: previously-failing questions now succeed (kecamatan MS for Circle Java; FWA
unlimited Jember no longer hits the scan cap).

---

## 4. Ops gotchas (reconfirmed this session)
- systemctl needs `sudo` here.
- Restart after backend edits: `sudo systemctl restart telco-backend`.
  Web: `cd frontend && npm run build && sudo systemctl restart telco-frontend`.
- Flutter at `/home/ubuntu/flutter/bin`; build apk then copy to
  `/home/ubuntu/telco-ai/Bizplan-Java-Agent.apk`; bump pubspec + app_release.json.
- BigQuery probes from the venv get their stdout swallowed by a
  `RequestsDependencyWarning` in the bash tool, so redirect to a `/tmp` file and Read it.
- KB edits leave timestamped `.bak*` files next to knowledge_base.json.
- HARD STYLE RULE: no em-dashes anywhere (code, comments, labels, copy).
- Free memory by stopping the leftover Gradle java daemon
  (`cd mobile/android && ./gradlew --stop`) and restarting the app services.
