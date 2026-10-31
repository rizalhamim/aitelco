---
title: "ADR: per-role LLM models"
type: decision
updated: 2026-07-26
---

# ADR: per-role LLM model config

**Decision**: Different pipeline roles use different LLM models, configured via env, not a
single model for everything.

## Config (env, parsed by `config.py`)

- `LLM_BASE`, `LLM_KEY` — endpoint + key (the "9Router" LLM endpoint).
- Per-role: `LLM_MODEL`, `LLM_MODEL_FAST`, `LLM_MODEL_SQL`, `LLM_MODEL_CODER`, `LLM_MODEL_ANALYST`.
- `LLM_OMIT_TEMPERATURE` defaults true.

## Why

Route each task to a fit model: fast/cheap for routing, a stronger model for SQL writing and
analysis. Keeps latency and cost down without dropping quality where it matters.

## Known gotcha

There is a documented 9Router / Haiku long-context bug and a "general reply missing model
param" bug — see `docs/9router-haiku-long-context-bug.md` via [[big-docs]] before touching
model routing.

## Where

`config.py`, `llm.py` (`chat`, `chat_stream`, `_accumulate_usage`). `graphify query "llm.py"`.

## Related

- [[backend-modules]] · [[chat-pipeline]] · [[big-docs]]
