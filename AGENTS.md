# AGENTS.md

Canonical operating guide for every coding agent on this repo: GPT 6.1 Sol (Codex), Opus 5.5
and Fable 5.1 (Claude Code), Astra 6.1, or any harness that reads `AGENTS.md`. Claude Code
loads this file through `CLAUDE.md`. Keep it the single source; put facts in the vault, not here.

## Project

Telco AI analytics platform for Indosat (IOH) Java region. Read-only BigQuery
(`data-java-prd-97b9.java_precalc`) behind an LLM agent swarm.

```
backend/    FastAPI: chat agent swarm, reports, BigQuery, SQLite auth/history (port 8000)
frontend/   Next.js 16 + React 19 web app (port 3000). Read frontend/AGENTS.md first.
mobile/     Flutter Android client (bizplan_java_agent), same backend
vault/      Obsidian knowledge vault: decisions, domain rules, conventions (why/what)
graphify-out/  code knowledge graph (where/how), dev-only
```

Prod: `agent-02.bizplan-java.com` via nginx. Services: `telco-backend`, `telco-frontend` (systemd).

## Where knowledge lives (one owner per kind)

| Kind | Owner | How to reach it |
|------|-------|-----------------|
| Why / what / which (decisions, domain rules, conventions) | `vault/` | `vault/INDEX.md` route table, then ONE node |
| Where / how in code | `graphify-out/` | `graphify query "..."`, `graphify explain`, `graphify affected` |
| Runtime agent knowledge (prompt-injected) | `backend/data/knowledge_base.json` | edit via tools below, never hand-patch prompts |
| Table lifecycle (approved/candidate/rejected) | `backend/governance/table_governance.json` | dated review files + `tools_apply_review.py` |
| Live numbers | BigQuery / running API | query or curl; never cache metrics in docs |
| Agent-quality roadmap + measured history | `docs/agent-improvement-plan.md` | read the ground rules before routing/SQL/KB work |

When two sources disagree, `vault/40-decisions/` wins over prose, and live systems win over both.

## Operating loop (every non-trivial task)

1. **Orient**: vault INDEX, one node, then a graphify query. Open raw files only to edit or debug
   specific lines. A PreToolUse hook nudges Read/Grep toward graphify; follow it.
2. **Plan**: 2-3 lines: target files, the change, the gate you will run. Write the plan down
   first when it touches more than ~3 files or changes agent/pipeline logic.
3. **Execute**: smallest diff, match surrounding style. Independent reads/queries in parallel.
4. **Verify**: run every gate that applies (table below). A skipped gate means not done; say so.
5. **Self-review**: read `git diff` once. Risky backend change: second review pass
   (Claude: `/code-review` or reviewer subagent; other harnesses: fresh-context review).
6. **Record**: durable fact or decision: update the ONE relevant vault node and append
   `vault/99-log/session-log.md` (absolute date). Code changed: `graphify update .`.

Definition of done: gates green, diff reviewed, vault/graph updated, touched services restarted.

## Verification gates

Run from `backend/` with the venv unless noted. Counts drift; the rule is "all pass".

| Touched | Gate |
|---------|------|
| Backend logic | `venv/bin/python -m pytest tests/ -q` (no network, about 2 s) |
| KB, routing, governance | `venv/bin/python tools_agent_knowledge_benchmark.py` must be full pass; add a case per new domain/table |
| Chat pipeline (`main.py` `/api/chat/stream`) | restart backend, then `venv/bin/python data/training/run_hard_questions.py --only 2,11,20 --run-tag smoke` BEFORE any full run |
| Agent quality claims | hard-30 + `data/training/run_correlation_questions.py`, before and after numbers |
| Frontend | `cd frontend && npm run lint && npm run build` |
| Mobile | `cd mobile && /home/ubuntu/flutter/bin/flutter analyze && /home/ubuntu/flutter/bin/flutter test` |
| Any live-behavior claim | curl the running API |

The chat stream is one long generator no unit test executes: scoping or import errors there
pass pytest and fail only live. That is why the smoke run exists.

## Knowledge and governance workflow

Upstream schema changes land without notice. `tools_knowledge_refresh.py --check` is the drift
detector; run it when a report or query suddenly fails with "Name X not found".

```bash
venv/bin/python tools_knowledge_refresh.py --check            # drift + ungoverned objects
# write governance/review_<date>_<topic>.json, then:
venv/bin/python tools_apply_review.py governance/review_<file>.json --dry-run   # then --write
venv/bin/python tools_knowledge_refresh.py --write-catalog --promote-reviewed --compile-graph
venv/bin/python tools_kb_edit.py add-fact --domain <d> --text "..."   # single facts, atomic + .bak
venv/bin/python tools_runtime_graph.py                         # rebuild SHA-keyed runtime graph
cd .. && backend/venv/bin/python tools_graphify_kb.py           # dev projection (allowlisted keys)
sudo systemctl restart telco-backend                           # load_kb() is lru_cached
```

Never `--rebuild-governance` (erases decision history). Profile before approving
(`tools_profile_candidate.py`, `tools_column_population.py`). Details: vault
`30-data/bigquery-tables.md` and `30-data/knowledge-base-json.md`.

## Hard rules

- BigQuery is read-only; scans are byte-capped. Partition filters must be literals.
- PII columns stay blocked in `bigquery_tool._reject_sensitive_columns`; never weaken it.
- Fix wrong answers in `knowledge_base.json` or governance, not per-case prompt patches.
  One lever per experiment (router vs SQL prompt vs KB).
- YTD/LYTD are apple-to-apple (current month always from MTD tables). See vault ADR.
- Never use em-dashes anywhere (code, comments, copy, docs).
- Never restart the backend during a benchmark run; never let `--only`/`--limit` runs
  overwrite a stored baseline.
- Never remove or hide data in UI to look cleaner; use disclosure, grouping, better encoding.
- Mobile release: bump `mobile/pubspec.yaml` AND `backend/data/app_release.json` (authoritative
  current version). Steps: vault `50-conventions/deploy-restart.md`. Current release: 1.49.0+67.
- Restarts need `sudo`; some agent harnesses block them. If blocked, finish everything else
  and hand the exact command to the user.
- Never put real secrets as code defaults; `backend/.env.example` lists every key.

## Dependencies and environment

- `requirements.txt` declares everything the app imports (FastAPI, BigQuery, SQLAlchemy, jose,
  passlib, openpyxl, reportlab, pyshp, shapely, requests). Many are imported lazily inside
  endpoints, so a missing package only fails when that endpoint is hit (auth, export, geo).
  Add new deps to `requirements.txt`.
- `backend/data/` (knowledge_base.json, geo files, SQLite DB) is gitignored, so a fresh clone
  cannot answer questions until that folder is copied from the server.
- Security keys in `backend/.env`: `JWT_SECRET_KEY` (server refuses to start without it when
  `APP_ENV=production`), `CORS_ORIGINS` (comma-separated, default `*`), `SMTP_PASS` (no
  default; email fails without it).

## Design system

`design/tokens.json` is the single source for colors, spacing, radius, type and motion on web
and Android. Run `python3 design/build_tokens.py` after editing it; it regenerates
`frontend/src/app/design-tokens.css` and `mobile/lib/src/design_tokens.dart`. See
`design/README.md`.

## Design panel (significant UI work only)

New page/screen/report section or major visual redesign: dispatch the 5 agents in
`.kilo/agent/` (ui-ux-designer, business-planner-analyst, dataviz-expert, dataviz-engineer,
frontend-architect) in parallel, each returns top 2-3 proposals; merge once; execute; run
gates. Skip it for bug fixes, backend, tweaks, or anything asked to be quick.

## Gotchas that cost real time

- Venv BigQuery probes: a `RequestsDependencyWarning` swallows stdout. Redirect to a `/tmp`
  file and read it back. Run scripts with `PYTHONPATH=.` from `backend/`.
- `config.py` parses `backend/.env` itself with silent defaults; a missing key gives a wrong
  default, not an error.
- Views (`*_serving`) can report stale column names in INFORMATION_SCHEMA after an upstream
  rename; dry-run the real column before trusting the catalog.
- Many backend deps import lazily inside endpoints; add new deps to `requirements.txt`.
