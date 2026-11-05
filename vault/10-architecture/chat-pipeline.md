---
title: Chat pipeline (/api/chat/stream)
type: architecture
updated: 2026-11-05
---

# Chat pipeline: `/api/chat/stream`

The core of the product. SSE streaming endpoint in `backend/app/main.py`, implemented as one
large inline generator. `graphify query "chat stream pipeline"` for exact code.

## Flow

```text
Router
  -> low-risk graph match: SQL write -> policy guard -> deterministic profile -> Synthesizer
  -> complex or ambiguous: Analyst -> scope gate -> SQL write -> policy guard
     -> conditional critique/refine -> deterministic profile -> Synthesizer
```

- **Router** picks the domain / mode.
- **Runtime graph retrieval** selects about four relevant tables and only relevant columns.
- **Analyst** frames complex analytic questions. Low-risk graph matches skip this model call.
- **Scope gate** can reroute, ask a clarifying question, or mark out-of-scope. It is skipped only
  when bounded graph retrieval has high confidence and no risk terms.
- **SQL write** generates SQL, runs with an error-retry loop + a self-critique refine loop.
- **Policy guard** rejects cross-dataset, banned, unapproved, and unselected tables before dry run.
- **Result profiler** examines the complete returned row set, source provenance, nulls, periods,
  truncation, and verified ordering before synthesis.
- **Synthesizer** turns rows into the narrated answer without inferring rankings from a 50-row preview.

## Branch modes (by `domain` / flags)

| Condition | Handler | Note |
|-----------|---------|------|
| `PROFILE` | `profile_engine.py` | fans out parallel multi-domain queries into a deck |
| `CORRELATE` | `correlate_agent.py` | joins two domains on a territory key |
| advisory follow-up | `advisor_agent.py` | reasons over already-fetched data (from `memory.store_context`), no re-query |
| `map_context=True` | `map_synth_agent.py` | map render spec + narration; skips scope gate AND critique loop |

## SSE events

`step_start` · `route` · `sql` · `result` · `token` · `done`. Needs `X-Accel-Buffering: no`
for nginx. Non-streaming variant: `POST /api/chat`.

## Speed paths and visible thinking (2026-11)

- The Analyst runs in parallel with the Router (`_SPEC_POOL`), used only off the fast path.
- After the Analyst, the router runs again only when the rewrite changed the question
  (`orchestrator.needs_reroute_after_analyst`, word overlap below 0.5).
- SQL is generated speculatively while the scope gate runs (round 0); used only when the
  gate confirms the SAME domain with no table hints, otherwise discarded.
- `needs_llm_critique` no longer sends every "per X" question to the critique model: an
  explicit grouping the result visibly carries (`requested_grain` + `result_has_grain`)
  is verified deterministically. A territory used as a filter still gets the critique.
- `step_start` labels are one plain-language vocabulary (`main.STEP_LABELS`); the original
  agent name moves to `agent`. `done` carries `elapsed_ms` and `timeline` (label + ms per step).
- The writer gets `key_facts` (`app/answer_facts.py`): numbers computed once in Indonesian
  format, quoted verbatim, and a fixed report template in `SYNTH_SYS`. The same facts make
  `fallback_report()` when the model returns nothing.
- `tests/test_chat_stream_flow.py` runs the whole generator with stubs; it does not replace
  the live smoke run.

## Related

- [[agent-swarm]] (who the agents are) · [[knowledge-base-json]] (where prompts get facts)
- [[auth-optional-chat]] (anonymous vs 401) · [[backend-modules]]
