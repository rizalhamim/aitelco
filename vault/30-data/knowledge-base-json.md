---
title: knowledge_base.json as the agent knowledge authority
type: data
updated: 2026-08-19
---

# knowledge_base.json

`backend/data/knowledge_base.json` is the **only** knowledge injected into the chat agent's
prompts. Loaded by `knowledge.py:load_kb()` (`@lru_cache`d). Edit this to change what the agent
knows — do NOT hardcode facts in agents.

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
