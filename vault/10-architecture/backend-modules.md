---
title: Backend modules
type: architecture
updated: 2026-07-26
---

# Backend modules

Non-obvious module roles in `backend/app/`. `graphify query "<module>.py"` for detail.

| Module | Role |
|--------|------|
| `main.py` | one large file; `/api/chat/stream` core generator ([[chat-pipeline]]) |
| `bigquery_tool.py` | read-only, byte-capped BQ access; `run_query()`, `dry_run()`, `validate_sql()`, `_ensure_limit()`. God node (57 edges). See [[bigquery-tables]] |
| `knowledge.py` | loads `data/knowledge_base.json` via `@lru_cache`d `load_kb()`. See [[knowledge-base-json]] |
| `memory.py` | short-term context + analytics + learnings. `store_context` feeds advisor follow-ups |
| `geo_locate.py` | GPS → kecamatan via SHP, then nearest sites/outlets. See [[geo]] |
| `export_agent.py` | XLSX/PDF export (non-LLM) |
| `orchestrator.py` | route / write_sql / critique |
| `profile_engine.py` / `correlate_agent.py` / `advisor_agent.py` / `map_synth_agent.py` | pipeline branch modes ([[agent-swarm]]) |
| `reports_*.py` | Performance Outlook builders. See [[reports]] |
| `database.py` / `auth.py` / `routes_auth.py` | JWT auth, users, chat history, usage logs. See [[auth-optional-chat]] |

## Config & env

`config.py` parses `backend/.env` itself (no python-dotenv) with defaults for everything —
missing vars fail silently with possibly-wrong defaults. Keys: LLM (`LLM_BASE`, `LLM_KEY`,
per-role models → [[llm-model-roles]]), BigQuery (`BQ_PROJECT`/`BQ_DATASET`/`BQ_LOCATION`/`BQ_ADC`),
DB (`TELCO_AI_DB`), Geo (`KEC_SHP_PATH`).

## Dependency gotcha

Many deps imported LAZILY inside functions (`jose`/`passlib` auth, `openpyxl`/`reportlab`
export, `pyshp`/`shapely` geo). Server starts even if one is missing; fails only when you hit
that endpoint. Add a feature → install dep AND add to `requirements.txt`.

## Related

- [[system-overview]] · [[deploy-restart]]
