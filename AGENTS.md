# AGENTS.md

Telco AI analytics platform for Indosat (IOH) Java region. Three components:

```
backend/    Python FastAPI server (LLM agent swarm, BigQuery, SQLite auth/history)
frontend/   Next.js 16 + React 19 web app (TypeScript, Tailwind)
mobile/     Flutter Android client (bizplan_java_agent), talks to the same backend
```

The three are separate git repos / loosely coupled; there is no root workspace manifest. Work in one component at a time.

## Operating protocol (all coding agents: Claude, codex, others)

Quality comes from process, not model tier. For every non-trivial task:

1. **Orient**: `vault/INDEX.md` route table (why/what/which), then `graphify query "..."`
   (where/how in code). Never bulk-read source or big docs to orient. One node or one query,
   not a directory sweep.
2. **Plan**: 2-3 lines naming target files, the change, and the verification gate you will run.
   No exploratory edits.
3. **Execute**: smallest diff. Match surrounding style. Never use em-dashes.
4. **Verify** (mandatory, every gate that applies):
   - Backend logic: `cd backend && venv/bin/python -m pytest tests/ -q` (34+ tests, ~2s)
   - Knowledge/routing/KB: `cd backend && venv/bin/python tools_agent_knowledge_benchmark.py`
     (must stay at full pass; add a case when adding a domain/table)
   - Chat pipeline: spot-run 3-5 questions from `backend/data/training/hard_questions_30.txt`
     against the restarted local server
   - Frontend: `npm run lint && npm run build`. Mobile: `flutter analyze`.
   - Any claim about live behavior: curl the running API, never assert from memory.
5. **Self-review**: read `git diff` once before declaring done.
6. **Record**: durable fact/decision goes to the ONE relevant vault node + a line in
   `vault/99-log/session-log.md` (absolute date). Code changed: `graphify update .`.
   Runtime KB changed: `tools_graphify_kb.py` + backend restart (KB is lru_cached).

Agent-quality work (routing, SQL generation, knowledge, synthesis) additionally follows
`docs/agent-improvement-plan.md`: measure before/after with the training runners, change one
lever per experiment, fix knowledge in `knowledge_base.json` not in per-case prompt patches.

## 5-agent design panel (SIGNIFICANT UI work only)

Run the design panel ONLY when creating a new page/screen/report section or doing a major
visual redesign of one (web or mobile). Do NOT run it for: backend work, bug fixes, copy or
styling tweaks, refactors, small component edits, agent/knowledge work, or anything the user
asked to be quick. For those, apply the panel's hard constraints yourself and proceed.

The panel (defined in `.kilo/agent/`, dispatched via subagent/Task calls):
1. `ui-ux-designer` - layout, hierarchy, readability, interaction, a11y.
2. `business-planner-analyst` - business question, KPIs, decision value, data correctness.
3. `dataviz-expert` - chart/encoding strategy, perceptual accuracy.
4. `dataviz-engineer` - buildable React/Tailwind/SVG implementation plan.
5. `frontend-architect` - architecture, state, data flow, reuse, maintainability.

### Flow (one condensed round)
1. Dispatch the 5 agents in parallel with the same brief. Each returns its TOP 2-3 proposals
   with a confidence score (not 5+; depth over volume).
2. One debate/reconcile pass: you (the primary agent) merge the proposals, resolve conflicts,
   note rejected alternatives in one line each.
3. Execute the merged plan, then run the normal validation gates (lint/build/deploy).

### Hard constraints (apply even without the panel)
- NEVER remove or hide data to make a page look cleaner. If density is a problem, use grouping, progressive disclosure (expand/collapse, tabs, tooltips), small multiples, or better encoding. Every field the backend returns must remain reachable in the UI.
- Never use em-dashes anywhere (matches the repo-wide style rule).
- After execution, do the normal repo validation (lint/typecheck/build) and deploy/restart steps for the component you touched.

## Backend

### Setup & run

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

`python`/`pip` are only available inside the venv — activate it before running anything.

### requirements.txt

Many of these deps are imported LAZILY inside functions (auth via `jose`/`passlib`, export via `openpyxl`/`reportlab`, geo via `shapefile` (pyshp)/`shapely`), so the server starts fine even if one is missing and only fails when you hit the relevant endpoint. If you add a feature, install the dep AND add it to `requirements.txt`.

### Environment

`config.py` parses `backend/.env` itself (no python-dotenv) and provides defaults for everything, so missing vars fail silently with possibly-wrong defaults rather than erroring. Keys:
- LLM: `LLM_BASE`, `LLM_KEY`, plus per-role models `LLM_MODEL`, `LLM_MODEL_FAST`, `LLM_MODEL_SQL`, `LLM_MODEL_CODER`, `LLM_MODEL_ANALYST`. `LLM_OMIT_TEMPERATURE` defaults true.
- BigQuery: `BQ_PROJECT`, `BQ_DATASET`, `BQ_LOCATION`, and `BQ_ADC` (path to ADC json; default is a hardcoded `~/.config/gcloud/...` path — override it).
- DB: `TELCO_AI_DB` (SQLite file, default `backend/data/telco_ai.db`).
- Geo: `KEC_SHP_PATH` (default `/home/ubuntu/telco-ai/shp/Data Kecamatan Indonesia`).

### Architecture (not obvious from filenames)

`main.py` is one large file; `/api/chat/stream` (SSE) is the core and contains the full pipeline inline as a generator. Flow: Router → Analyst → Domain scope gate (can reroute/clarify/out-of-scope) → SQL write with error-retry + self-critique refine loop → Synthesizer. It branches into special modes by `domain`:
- `PROFILE` → `profile_engine.py` fans out parallel multi-domain queries into a deck.
- `CORRELATE` → `correlate_agent.py` joins two domains on a territory key.
- advisory follow-ups → `advisor_agent.py` reasons over already-fetched data (stored via `memory.store_context`) instead of re-querying.
- `map_context=True` → `map_synth_agent.py` (map render spec + narration); skips the scope gate and critique loop.

Other agents/modules: `orchestrator.py` (route/write_sql/critique), `analyst_agent.py`, `geo_locate.py` (GPS→kecamatan via SHP, then nearest sites/outlets), `knowledge.py` (loads `data/knowledge_base.json`), `bigquery_tool.py` (read-only, byte-capped), `export_agent.py` (XLSX/PDF), `memory.py` (short-term + analytics + learnings), `database.py`/`auth.py`/`routes_auth.py` (JWT auth, users, chat history persistence, usage logs).

Auth is optional on chat: a request with no token stays anonymous; an EXPIRED token returns 401 (so mobile refreshes) rather than saving as anonymous. JWT `sub` is the username — resolve to user PK via the `User` table, never `int(sub)`.

### Geo / choropleth build step

Map polygons are pre-built, not generated on the fly. `python build_geojson.py` reads the kecamatan SHP and writes gzipped `data/geo/{kecamatan,kabupaten}.geojson.gz` + `territory_map.json`. The `/api/geo/shapes/*` endpoints only serve gzip when the client sends `Accept-Encoding: gzip` — this is deliberate to avoid a proxy double-gzip bug; don't "simplify" it to always-gzip.

### Knowledge base

`backend/data/knowledge_base.json` defines domains (site performance, network, market share, forecast, HVC, marketing, sales, fixed broadband, geography, KPI, reports), BigQuery table schemas, and SQL-generation prompts. Edit this to add domains/tables rather than hardcoding in agents.

No Python linter, formatter, or unit test suite. Root-level `test_batch.py` / `rerun_failures.py` / `test_pipeline.py` are integration scripts that POST real questions to a running `localhost:8000`; they need the server + BigQuery live.

## Frontend

```bash
cd frontend
npm install
npm run dev      # http://localhost:3000
npm run build
npm run lint     # eslint (flat config: eslint.config.mjs)
```

- **Next.js 16 / React 19** — APIs differ from older docs. Read `node_modules/next/dist/docs/` before writing code (see `frontend/AGENTS.md`). `frontend/CLAUDE.md` just re-exports `@AGENTS.md`.
- `next.config.ts` rewrites `/api/*` → `BACKEND_URL` (default `http://localhost:8000`). The browser calls same-origin `/api/*`, so CORS is usually a non-issue in this setup; set `BACKEND_URL` to point at a remote backend.
- `@/*` → `./src/*`. App Router pages live in `src/app/` (`map/`, `profile/`, `admin/`, `login/`).

## Mobile (Flutter)

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:8000   # default targets the deployed server
flutter build apk
```

Backend base URL is compile-time via `--dart-define=API_BASE=...` (`lib/src/config.dart`), defaulting to the production host — override it for local dev. Uses JWT auth + refresh against the backend.

## API endpoints (backend)

- `POST /api/chat/stream` — SSE streaming chat (main; emits `step_start`/`route`/`sql`/`result`/`token`/`done` events). Requires `X-Accel-Buffering: no` for nginx.
- `POST /api/chat` — non-streaming.
- `GET /api/domains`, `POST /api/run_sql` (raw read-only SQL), `POST /api/export`, `GET /api/export/last/{session_id}`.
- `POST /api/geo/locate`, `GET /api/geo/shapes/{kecamatan|kabupaten}`, `GET /api/geo/territory-map`.
- `/api/auth/*`, `/api/admin/*`, history routes (in `routes_auth.py`), `/api/health`, `/api/memory/*`, `/api/analytics/*`, `/api/learnings`.

## Reports - "Performance Outlook" (web `src/app/reports/page.tsx`, mobile `lib/src/screens/reports_screen.dart`)

Routes under `routes_reports.py` (`/api/reports/*`), cached via `reports_cache.py` (family markers `highlevel`/`data`/`benchmark`; payloads keyed by `report|marker|params`). Builders: `reports_comprehensive.py`, `reports_data.py`, `reports_network.py`, `reports_market_insight.py`, `reports_ftth.py`. UI has 3 modes (My Coordinate / Territory Wise / Daily Snapshot) and sub-tabs (Comprehensive, Data Revenue, Product Demand, Network Benchmark, Market Insight, Indosat HiFi (FTTH)). Brand model: IOH = IM3 + 3ID; bottom IOH/IM3/3ID brand bar is GLOBAL except hidden on the FTTH tab.

### YTD / LYTD must be apple-to-apple (critical, fixed 2026-06)
Both YTD and LYTD mix full closed months + a PARTIAL current month capped at the same data cutoff day. The current month (this year AND last year) ALWAYS comes from the MTD table (`rham_mkt_highlevel_mtd`, `rham_site_data_rev_*_mtd`, etc., which are cutoff-capped), never the full-month `_mth` table:
- `YTD  = SUM(_mth, Jan..mid-1 this year) + MTD(this year, mid)`
- `LYTD = SUM(_mth, Jan..mid-1 last year) + MTD(last year, mid-100)`
The prior-year month snapshot is symmetric (e.g. `_mtd[202506].dt_id_snapshot = 2025-06-16` matches `202606 = 2026-06-16`). Implemented in `reports_comprehensive.py` (flow metrics) and `reports_data.py` (all 4 cumulative blocks: channel chunks, price slabs, product-demand slabs, top products). FTTH (`reports_ftth.py`) computes YTD/LYTD by date range on the event-dated detail tables: `LYTD = [(year-1)-01-01 .. cur_dt minus 1 year]`. Snapshot metrics (site/RGU/VLR/outlets) use point-in-time MTD-this-year vs MTD-last-year, NOT a YTD sum. `reports_city_profile.py` consumes these, so it inherits the fix.

### FTTH / Indosat HiFi report (`reports_ftth.py`)
- FTTH has its OWN territory vocabulary: `sales_region` (detail) / `region_25` (sitewise) coded like `04. Central Java`, `05. East Java`, plus `province`/`city`/`kecamatan`. It does NOT align with the IM3 `rham_ref_territory` hierarchy, and the detail tables' `shp_kabkota`/`shp_kecamatan` are NULL. So FTTH filters on native columns, never via `rham_ref_territory`. Filter levels: `ftth_region`/`ftth_province`/`ftth_kabkota`/`ftth_kecamatan` (helpers `_detail_scope_clause`/`_sitewise_scope_clause`). Options endpoint: `GET /api/reports/ftth/scope-options?circle=&level=` (from sitewise).
- My Coordinate sends IM3 `kecamatan` filter as a `kec_id` like `ADIWERNA|KAB. TEGAL`; FTTH stores bare `ADIWERNA`. `_norm_kec()` strips the `|kabkota` suffix. IM3 region/area/branch/microcluster levels have no FTTH equivalent and degrade to circle scope.
- Two grains: detail tables (`rham_ftth_{so,sa,pa}_detail`, per-customer funnel SO→SA→PA on each event date) and `rham_ftth_sitewise_monthly` (monthly per-site SUBSCRIBER snapshot: `pa`=cumulative active subs, `homepass`, `available_hp`, `ga`, `pa_net_latest`; TUR = SUM(pa)/SUM(homepass)*100; total subs = SUM(pa) at MAX(month_id), never summed across months). Footprint from `project_awal`: mplay=ORBIT, seahawk/spartan=NON-ORBIT, iforte=IFORTE. Product mix AP regex `^(AP|Super ?)[0-9]+`. Low TUR site = `pa/homepass < 0.2 AND homepass > 0`.
- Section layouts the frontends render: `grid` (CompTable), `ftth_counts` (label+number table), `hierarchy` (expandable SM→TL→AE, sorted SO MTD desc). "FTTH Infrastructure & Utilization" is the first section.

### Build / deploy / services
- Services (systemd, need `sudo`): `telco-backend` (127.0.0.1:8000), `telco-frontend` (127.0.0.1:3000). After backend edits run `sudo systemctl restart telco-backend` (the KB loader `knowledge.py:load_kb()` is `@lru_cache`d, so a restart is required to reload `knowledge_base.json`).
- Web: `cd frontend && npm run build` then `sudo systemctl restart telco-frontend`.
- Mobile: flutter is at `/home/ubuntu/flutter/bin`. `flutter build apk --release`, then copy `build/app/outputs/flutter-apk/app-release.apk` to `/home/ubuntu/telco-ai/Bizplan-Java-Agent.apk`. Bump `mobile/pubspec.yaml` version AND `backend/data/app_release.json` (`version_name`/`version_code`/`notes`). Current release: 1.47.0+62 (authoritative source: `backend/data/app_release.json`, do not trust this line if they disagree).
- Prod host: `agent-02.bizplan-java.com` (nginx `/etc/nginx/sites-available/sysmonitor`: `/api/`→8000 with `proxy_buffering off`, `/`→3000). A separate `system-monitor.service` serves `server-02.bizplan-java.com` on port 8080.
- HARD STYLE RULE: never use em-dashes anywhere (code, comments, labels, copy).

### Training / answer-quality knowledge (chat agent)
The agent's only prompt-injected knowledge is `backend/data/knowledge_base.json` (`data_facts` + per-domain `agent.key_facts`). The `learning_notes` SQLite table is write-only telemetry (exposed at `/api/learnings`, NEVER fed back into prompts), so to improve answers, edit `knowledge_base.json`. Past questions for review live in `backend/data/sessions.db` table `analytics` (cols: question, domain, sql, success, error_msg, response_summary, ts=unix epoch). Key facts added 2026-06: circle->region mapping (`data_facts.circle_region_mapping`: JAVA=Central Java/East Java/Bali Nusra; JAKARTA RAYA=Inner/Outer Jakarta+West Java; SUMATERA=North/Central/South; KALISUMAPA=Kalimantan/Sulawesi/MAPA); the `rham_report_fb_ms_*` monthly tables use column `kabkot` (NOT `kabkota`) and have no branch/circle col; product `_mth` table needs an EXACT `month_id` filter (never `LIKE '%05'`) to stay under the 50 GB scan cap; FWA = `family_group='09. FWA'`, unlimited = `product_group='HIFI AIR UNLIMITED'`. FTTH `rham_ftth_sitewise_monthly` was added to the `ftth` domain (subscriber/homepass/TUR snapshot).

### Agent-quality tooling and gates (run from `backend/` with the venv)

Durable rules behind these: `vault/40-decisions/agent-quality-gates.md`. Phased work and
measured numbers: `docs/agent-improvement-plan.md`.

```bash
venv/bin/python -m pytest tests/ -q                    # unit gate (fast, no network)
venv/bin/python tools_agent_knowledge_benchmark.py     # routing/governance/prompt-size gate
venv/bin/python data/training/run_correlation_questions.py   # router + correlation planner
venv/bin/python data/training/run_hard_questions.py --run-tag <tag>   # live, needs the server
venv/bin/python tools_weekly_review.py --days 7        # report-only failure buckets
venv/bin/python tools_column_population.py <table> --date-col dt_id --like 90
```

`tools_column_population.py` answers "is this column actually populated, and what sign
are its values?" Run it FIRST whenever a metric returns an empty result: a column can
exist in the schema and still be empty in practice, which makes the SQL writer rank on
nothing. It also surfaces sign conventions (FWA churn is stored negative).

KB edit order (all four steps, in order, or the runtime graph goes stale):

```bash
venv/bin/python tools_kb_edit.py add-fact --domain <d> --text "..."   # atomic + .bak
venv/bin/python tools_runtime_graph.py                 # rebuild the SHA-keyed artifact
venv/bin/python ../tools_graphify_kb.py                # regenerate the dev projection
sudo systemctl restart telco-backend                   # load_kb() is lru_cached
```

Non-negotiables when changing agent behaviour: measure before and after (never claim an
improvement without numbers), verify a benchmark expectation against the KB schema before
treating a miss as a model failure, and change one lever per experiment.

Two BigQuery facts that cost real debugging time (details in the ADR):
- Partition pruning needs a LITERAL filter value. `month_id = (SELECT MAX(month_id) ...)`
  or a JOIN to a MAX() CTE scans every partition: measured 45.0 GB versus 1.6 GB for the
  same aggregate on `rham_site_data_rev_product_mth`.
- Tables inside one domain can have different coverage. `rham_site_wise_occupancy` stops
  at 202512 while `rham_avail_stat_site_monthly` runs to the current month, so joining
  them on a shared MAX(month_id) always returns zero rows.

Never restart the backend while a benchmark run is in flight, and never let a partial run
(`--only`/`--limit`) overwrite the stored baseline.

**Smoke-run before benchmarking.** `/api/chat/stream` is one long generator that no unit
test executes, so a scoping or import error on the hot path passes every unit test and
only shows up live. After ANY chat-pipeline edit, restart the backend and run
`venv/bin/python data/training/run_hard_questions.py --only 2,11,20 --run-tag smoke`
(about 90 seconds) BEFORE starting a full run.

### Backups
KB edits leave timestamped `.bak*` copies next to `backend/data/knowledge_base.json`. When probing BigQuery from the venv, output is often swallowed by a `RequestsDependencyWarning`; redirect script output to a `/tmp` file and read it back.

## Graphify project workflow

Knowledge ownership:
- `backend/data/knowledge_base.json` is the only runtime knowledge injected into chat prompts.
- `vault/` holds durable rationale, decisions, domain rules, and operating conventions.
- `graphify-knowledge/` is a generated safe projection of runtime KB metadata for developer discovery.
- `graphify-out/` is derived developer tooling for code topology and cross-file relationships.

Use `vault/INDEX.md` for domain rationale and project decisions. Use Graphify for code location,
relationships, and impact analysis. `graphify affected "<concept>"` is the preferred impact command.

After a runtime KB change, run:

```bash
backend/venv/bin/python tools_graphify_kb.py
backend/venv/bin/python tools_graphify_kb.py --check
```

Then perform a semantic Graphify refresh because the generated projection is Markdown. Code-only
changes use `graphify update .` for the deterministic AST refresh. Never add Graphify to the
FastAPI request path, frontend bundle, mobile app, or production chat retrieval without a separate
product requirement. Full ownership and recovery rules are in
`vault/40-decisions/graphify-development-index.md`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
