---
title: knowledge_base.json as the agent knowledge authority
type: data
updated: 2026-10-08
---

# knowledge_base.json

`backend/data/knowledge_base.json` is the **only** knowledge injected into the chat agent's
prompts. Loaded by `knowledge.py:load_kb()` (`@lru_cache`d). Edit this to change what the agent
knows; do NOT hardcode facts in agents.

## What it defines

- **Domains** (site performance, network, market share, forecast, HVC, marketing, sales,
  fixed broadband, geography, KPI, reports) → [[domains-moc]].
- **BigQuery table schemas** per domain → [[bigquery-tables]].
- **SQL-generation prompts** per domain.
- `data_facts` (global) + per-domain `agent.key_facts` — the actual injected text.

Current structural inventory on 2026-08-19: 17 domain records, 16 routable data domains, 157
approved tables, 7,125 declared columns, 91 object-based domain key facts, and 26 global
`data_facts` groups. The `performance_outlook_extended` record is documentation-only and owns no
runtime tables.

## Table governance and live discovery

`backend/governance/table_governance.json` records a lifecycle and object class for all 238 live
`java_precalc` objects. Lifecycle values are `approved`, `candidate`, `quarantined`, `rejected`,
and `superseded`. Only approved objects enter the runtime KB. A rejected or quarantined object
cannot be reactivated by schema rediscovery, chat usage, or model output.

Daily metadata discovery is report-only:

```bash
cd backend
venv/bin/python tools_knowledge_refresh.py --write-catalog --check
```

The generated catalog lives at `backend/data/table_catalog.json`. New objects enter candidate
state until a reviewed governance decision promotes them.

## Graphify projection

The runtime JSON is inside ignored `backend/data/`, so the developer Graphify index does not read
it directly. A safe generated projection lives in `graphify-knowledge/` and includes domain,
table, column, semantic contract, governance, approved key facts, and allowlisted global facts.

```bash
backend/venv/bin/python tools_graphify_kb.py
backend/venv/bin/python tools_graphify_kb.py --check
```

The projection records the source SHA-256 and excludes personas, prompts, credentials, row
samples, environment data, and live KPI values. After regeneration, use a semantic Graphify
refresh because the projection is Markdown. See [[graphify-development-index]].

`backend/data/runtime_knowledge_graph.json` is a separate production artifact compiled only from
approved KB content. It uses stable domain, table, and column nodes plus typed edges. FastAPI never
reads `graphify-out/`. A KB hash mismatch causes a safe in-memory fallback and a health warning.

## SND schema reconciliation, 2026-10-08

The reviewed SND highlevel contract has 54 unified metrics at kecamatan x brand grain.
Use `outlet_total`, `quro`, `qsso_m0`, `tertiary_b`, and quoted `primary`; removed raw
parameters are not columns in these tables. RGU/VLR/prepaid revenue remain in Marketing
highlevel. Marketing `sso`/`uro` now hold real SND data. Since the second 2026-10-08 load,
Marketing highlevel also carries all 54 SND metrics (SND survival as `snd_ga_m1s`/`snd_ga_m2s`)
and the 14 always-zero placeholders (`q_uro`, `q_sso`, `qsc`, `vlr_postpaid`, `site_*_uro|quro|sso|qsso`,
`site_20/40_qsc`) are dropped. Preserve NULL for an unmapped or unpopulated brand metric.
Report identifiers `primary_all` and `secondary_nat` remain stable compatibility codes,
not source-column names.

The two approved HVC serving views remain valid without recreating them. Stored table
metadata exposed 18 obsolete column names per view. Discovery now resolves their actual
output with a zero-byte `SELECT * ... WHERE FALSE` dry run. The resolved output has 278
MTD columns and 262 monthly columns. Official review, refresh, runtime-graph, and
projection tools regenerate the artifacts; do not hand-edit the generated JSON.

Territory-schema selection must supply the approved reference when any selected source
lacks the requested geography, even if the first source already has it. This fixes the
Profile Channel Trade query's reference allowlist without weakening table governance.

The intended GTM labels are `MUST WIN 50`, `SUPER-88`, and `REST`, but the live audit also
found residual `HIGH POTENTIAL` and `0`. Keep them explicitly legacy/unclassified, not
aliases of REST. The dropped high-potential report stays rejected. `rham_ref_snd_metric`
and the newly discovered `rham_site_wise_occupancy_5g` remain candidates, not runtime sources.

Verification: zero missing KB/catalog columns against `bq show --schema` for the three
requested physical tables, plus zero missing columns for the resolved HVC views; 403
backend tests and 36/36 knowledge cases passed. Three requested questions executed
successfully on a temporary updated API with live BigQuery. Targeted Surabaya Profile
sections returned data without errors. The production Comprehensive API returned 200
with Primary/Secondary/Tertiary B populated for IOH. The last-month outlet smoke query
scanned about 23.8 MB and did not acquire a literal partition bound; do not claim complete
query-cost optimization from this schema reconciliation.

Deployment remains pending: sandbox `sudo` is blocked by no-new-privileges, and production
health still reports the old cached KB. Check that no host benchmark is running, then run
`sudo systemctl restart telco-backend` and repeat the three questions against production.
Runtime graph and Markdown projection are current on disk. Deterministic Graphify code
refresh succeeded, but semantic extraction timed out at the provider and is not current.

## Critical operational facts

- It is `@lru_cache`d → **a backend restart is required** to reload after editing
  (`sudo systemctl restart telco-backend`). See [[deploy-restart]].
- KB edits leave timestamped `.bak*` copies next to the file.
- `learning_notes` remains write-only telemetry and is never fed back into prompts.
- `knowledge_route_edges` stores only known normalized terms and approved table edges. Three
  unique successful query executions activate a bounded routing weight. It cannot create facts,
  schemas, formulas, joins, or approvals.
- Past questions for review: `backend/data/sessions.db` table `analytics`
  (question, domain, sql, success, error_msg, response_summary, ts=unix epoch).

## Why single-source

Rationale for keeping all agent knowledge here → [[knowledge-base-single-source]].

## Related

- [[bigquery-tables]] · [[domains-moc]] · [[agent-swarm]] · [[deploy-restart]] ·
  [[graphify-development-index]]
