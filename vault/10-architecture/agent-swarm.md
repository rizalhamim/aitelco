---
title: Agent swarm (MOC)
type: architecture
updated: 2026-07-26
---

# Agent swarm — MOC

The LLM agents that make up the backend brain. Dispatched inside [[chat-pipeline]].
`graphify query "<agent>_agent.py"` for code.

## Runtime agents (chat pipeline)

| Agent / module | Role |
|----------------|------|
| `orchestrator.py` | route / write_sql / critique — the pipeline spine |
| `analyst_agent.py` | frames the analytic question |
| `advisor_agent.py` | advisory follow-ups; reasons over already-fetched data, no re-query |
| `correlate_agent.py` | joins two domains on a territory key (`CORRELATE` mode) |
| `profile_engine.py` | `PROFILE` mode: parallel multi-domain fan-out into a deck |
| `map_synth_agent.py` | `map_context` mode: map render spec + narration |

Supporting: `analyst_agent` + `orchestrator` lean on `bigquery_tool.py` (read-only, capped),
`knowledge.py` (KB facts), `memory.py` (short-term + analytics + learnings). See [[backend-modules]].

## Design panel (dev-time, NOT runtime)

Separate from the runtime swarm: a **5-agent design panel** defined in `.kilo/agent/` that
runs at development time before writing/changing UI code (see project `AGENTS.md`):
`ui-ux-designer`, `business-planner-analyst`, `dataviz-expert`, `dataviz-engineer`,
`frontend-architect`. Flow: 5 parallel proposals each → debate round → finalize → execute.
This is a workflow rule for the coding agent, not part of `/api/chat`.

## LLM models

Per-role model config → [[llm-model-roles]].

## Related

- [[chat-pipeline]] · [[system-overview]] · [[knowledge-base-json]]
