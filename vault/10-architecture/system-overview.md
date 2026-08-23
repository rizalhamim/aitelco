---
title: System overview
type: architecture
updated: 2026-07-26
---

# System overview

Telco AI analytics platform for Indosat (IOH) Java region. LLM agent swarm over BigQuery.
Three loosely-coupled components (separate git repos, no root manifest — work in one at a time):

```
backend/    Python FastAPI — LLM agent swarm, BigQuery, SQLite auth/history
frontend/   Next.js 16 + React 19 — TypeScript, Tailwind web app
mobile/     Flutter Android — bizplan_java_agent, same backend
```

## Data flow (high level)

1. Client (web/mobile) → `POST /api/chat/stream` (SSE) on backend.
2. Backend runs the agent pipeline ([[chat-pipeline]]) → writes SQL → hits BigQuery.
3. Streams events back (`route`/`sql`/`result`/`token`/`done`).
4. Frontends render; reports have their own cached path ([[reports]]).

## Key facts

- Backend is the brain; frontends are thin. Same backend for web + mobile.
- Prompt knowledge comes from `backend/data/knowledge_base.json` → [[knowledge-base-json]].
- Read-only, byte-capped BigQuery access → [[bigquery-tables]].
- Auth is optional on chat → [[auth-optional-chat]].

## Drill down

- [[chat-pipeline]] · [[agent-swarm]] · [[backend-modules]] · [[frontend]] · [[mobile]]
- Domains: [[domains-moc]] · Data: [[bigquery-tables]] · Ops: [[deploy-restart]]

For code location, use `graphify query "..."` (e.g. entry is `backend/app/main.py`).
