# AGENTS.md

Telco AI analytics platform for Indosat (IOH) Java region. Three components:

```
backend/    Python FastAPI server (LLM agent swarm, BigQuery, SQLite auth/history)
frontend/   Next.js 16 + React 19 web app (TypeScript, Tailwind)
mobile/     Flutter Android client (bizplan_java_agent), talks to the same backend
```

The three are separate git repos / loosely coupled; there is no root workspace manifest. Work in one component at a time.

## Backend

### Setup & run

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

`python`/`pip` are only available inside the venv — activate it before running anything.

### Dependencies

`requirements.txt` declares everything the app imports (FastAPI, BigQuery, SQLAlchemy, jose, passlib, openpyxl, reportlab, pyshp, shapely, requests). Many are imported lazily inside functions, so a missing package only fails when you hit the relevant endpoint (auth, export, geo). If you add a feature, add its dep here.

`backend/data/` (knowledge_base.json, geo files, SQLite DB) is gitignored, so a fresh clone cannot answer questions until that folder is copied from the server.

### Environment

`config.py` parses `backend/.env` itself (no python-dotenv) and provides defaults for everything, so missing vars fail silently with possibly-wrong defaults rather than erroring. `backend/.env.example` lists every key. Never put real secrets as code defaults. Keys:
- LLM: `LLM_BASE`, `LLM_KEY`, plus per-role models `LLM_MODEL`, `LLM_MODEL_FAST`, `LLM_MODEL_SQL`, `LLM_MODEL_CODER`, `LLM_MODEL_ANALYST`. `LLM_OMIT_TEMPERATURE` defaults true.
- BigQuery: `BQ_PROJECT`, `BQ_DATASET`, `BQ_LOCATION`, and `BQ_ADC` (path to ADC json; default is a hardcoded `~/.config/gcloud/...` path — override it).
- DB: `TELCO_AI_DB` (SQLite file, default `backend/data/telco_ai.db`).
- Security: `JWT_SECRET_KEY` (server refuses to start without it when `APP_ENV=production`), `CORS_ORIGINS` (comma-separated, default `*`), `SMTP_PASS` (no default; email fails without it).
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

## Design system

`design/tokens.json` is the single source for colors, spacing, radius, type and motion on web and Android. Run `python3 design/build_tokens.py` after editing it; it regenerates `frontend/src/app/design-tokens.css` and `mobile/lib/src/design_tokens.dart`. See `design/README.md`.

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
- Mobile: flutter is at `/home/ubuntu/flutter/bin`. `flutter build apk --release`, then copy `build/app/outputs/flutter-apk/app-release.apk` to `/home/ubuntu/telco-ai/Bizplan-Java-Agent.apk`. Bump `mobile/pubspec.yaml` version AND `backend/data/app_release.json` (`version_name`/`version_code`/`notes`). Current release: 1.44.0+50.
- Prod host: `agent-02.bizplan-java.com` (nginx `/etc/nginx/sites-available/sysmonitor`: `/api/`→8000 with `proxy_buffering off`, `/`→3000). A separate `system-monitor.service` serves `server-02.bizplan-java.com` on port 8080.
- HARD STYLE RULE: never use em-dashes anywhere (code, comments, labels, copy).

### Training / answer-quality knowledge (chat agent)
The agent's only prompt-injected knowledge is `backend/data/knowledge_base.json` (`data_facts` + per-domain `agent.key_facts`). The `learning_notes` SQLite table is write-only telemetry (exposed at `/api/learnings`, NEVER fed back into prompts), so to improve answers, edit `knowledge_base.json`. Past questions for review live in `backend/data/sessions.db` table `analytics` (cols: question, domain, sql, success, error_msg, response_summary, ts=unix epoch). Key facts added 2026-06: circle->region mapping (`data_facts.circle_region_mapping`: JAVA=Central Java/East Java/Bali Nusra; JAKARTA RAYA=Inner/Outer Jakarta+West Java; SUMATERA=North/Central/South; KALISUMAPA=Kalimantan/Sulawesi/MAPA); the `rham_report_fb_ms_*` monthly tables use column `kabkot` (NOT `kabkota`) and have no branch/circle col; product `_mth` table needs an EXACT `month_id` filter (never `LIKE '%05'`) to stay under the 50 GB scan cap; FWA = `family_group='09. FWA'`, unlimited = `product_group='HIFI AIR UNLIMITED'`. FTTH `rham_ftth_sitewise_monthly` was added to the `ftth` domain (subscriber/homepass/TUR snapshot).

### Backups
KB edits leave timestamped `.bak*` copies next to `backend/data/knowledge_base.json`. When probing BigQuery from the venv, output is often swallowed by a `RequestsDependencyWarning`; redirect script output to a `/tmp` file and read it back.
