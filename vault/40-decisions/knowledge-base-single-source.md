---
title: "ADR: knowledge_base.json is the single source of agent knowledge"
type: decision
updated: 2026-07-26
---

# ADR: single-source agent knowledge

**Decision**: All chat-agent domain knowledge lives in `backend/data/knowledge_base.json`.
Agents do NOT hardcode facts, table names, or SQL hints in Python.

## Why

- One place to audit and change what the agent "knows" → predictable answer quality.
- Adding a domain/table = a JSON edit, not a code change across multiple agents.
- The `learning_notes` telemetry is deliberately NOT fed back into prompts (avoids drift and
  feedback loops); improving answers is an explicit KB edit, not automatic learning.

## Consequences

- KB is `@lru_cache`d → backend restart required after edits ([[deploy-restart]]).
- Edits leave timestamped `.bak*` copies.
- To improve an answer: edit `data_facts` / per-domain `agent.key_facts`, then restart.

## Where

`knowledge.py:load_kb()`, `backend/data/knowledge_base.json`. Full detail → [[knowledge-base-json]].

## Related

- [[knowledge-base-json]] · [[agent-swarm]] · [[deploy-restart]]
