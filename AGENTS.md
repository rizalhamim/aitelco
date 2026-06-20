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

### requirements.txt is INCOMPLETE

`requirements.txt` lists only fastapi/uvicorn/bigquery/pydantic. The app also imports, at runtime, packages that are NOT declared: `python-jose` (`jose`), `passlib`, `sqlalchemy`, `openpyxl`, `reportlab`, `pyshp` (`shapefile`), `shapely`, `requests`. Many are imported lazily inside functions, so the server starts fine and only fails when you hit the relevant endpoint (auth, export, geo). If you add a feature, install the dep and add it here.

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
