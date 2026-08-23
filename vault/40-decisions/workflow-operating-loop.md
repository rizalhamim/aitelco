---
title: ADR - model-agnostic operating loop (opus/codex, fable parity)
type: decision
updated: 2026-08-21
---

# ADR: operating loop for any coding model

## Decision

Replaced the opus-specific "Model & cost policy" with a model-agnostic 6-step operating loop
in `CLAUDE.md` (mirrored in `AGENTS.md` for codex, which reads AGENTS.md not CLAUDE.md):
orient (vault+graphify), plan (2-3 lines), execute (smallest diff), verify (named gates),
self-review (git diff), record (vault + graphify update).

## Verification gates (the fable-parity mechanism)

- Backend: `venv/bin/python -m pytest tests/ -q` (pytest now installed, `requirements-dev.txt`).
- Knowledge/routing: `tools_agent_knowledge_benchmark.py` must stay full-pass.
- Chat pipeline: spot-run hard-30 questions against restarted server.
- Frontend `npm run lint && npm run build`; mobile `flutter analyze`.
- Live claims verified by curl, never memory.

## Design panel scoped down

The 5-agent design panel is now ONLY for new pages/screens or major visual redesigns, one
condensed round (top 2-3 proposals per agent). It no longer runs "on every prompt". Its hard
constraints (never hide data, no em-dashes) apply always, panel or not.

## Agent-quality work

Routing/SQL/knowledge/synthesis changes follow `docs/agent-improvement-plan.md`: measure
before/after with training runners, one lever per experiment, knowledge fixes only in
`knowledge_base.json`.

## Why

The project will be driven by opus or codex going forward. Fable-level quality must come from
enforced process (gates + measurement) rather than model size, and token spend must stay low
(vault/graphify-first orientation unchanged). Supersedes the process part of
[[opus-cost-policy]]; the cost/plugin part of that ADR still stands.

## Related

- [[opus-cost-policy]] · [[agent-protocol]] · [[knowledge-base-json]] · [[session-log]]
