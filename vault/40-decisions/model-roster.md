---
title: "ADR: coding-model roster and model-agnostic process"
type: decision
updated: 2026-10-08
supersedes: opus-cost-policy, workflow-operating-loop
---

# ADR: coding-model roster (2026-10)

## Decision

The repo is maintained by several frontier models. Instructions are written once, for all of
them, in `AGENTS.md`; `CLAUDE.md` imports it (`@AGENTS.md`) and adds only Claude Code
specifics. Quality comes from the operating loop and gates, not from the model tier.

| Model | Harness | Role here |
|-------|---------|-----------|
| Opus 5.5 | Claude Code (`opus`, pinned in `.claude/settings.json`) | default implementer |
| Fable 5.1 | Claude Code (`/model fable`) | per-task escalation: architecture, cross-component contracts, repeated quality misses |
| GPT 6.1 Sol | Codex (reads `AGENTS.md`) | implementer or independent reviewer |
| Astra 6.1 | any harness reading `AGENTS.md` | implementer or independent reviewer |

Not to confuse with the runtime chat models (`Agent-Java-v02.3*` via 9Router), which are
configured in `backend/.env`; see [[llm-model-roles]].

## Why this shape

- One instruction file avoids drift: the 2026-08 setup duplicated the loop in `CLAUDE.md` and
  `AGENTS.md`, and both went stale (gate counts, release version, a "no test suite" line).
- Gate numbers are not written as fixed counts ("must be full pass", not "13/13"): counts
  change every time a test or benchmark case is added and stale numbers mislead.
- Current models follow instructions literally and over-react to shouting. Rules are stated
  once, calmly, with the reason, instead of repeated in capitals.
- Current models handle long context and parallel tool calls well, but token cost and
  attention still favour vault-node + graphify orientation over bulk reads, so that stays.
- Cross-model review catches blind spots a same-model self-review misses.

## Cost measures (kept from opus-cost-policy)

Project-disabled plugins in `.claude/settings.json` (playwright, ralph-loop, skill-creator,
claude-code-setup, code-simplifier, feature-dev, superpowers); `dataviz` and `deep-research`
are user-invocable only. Re-enable per machine via `.claude/settings.local.json`.

## Known environment issue

The user-level `~/.claude/settings.json` maps the `haiku` alias to a model the router does not
serve, so the haiku-pinned cavecrew subagents fail with `model_not_found`. Workaround: pass
`model: "opus"` on the Agent call. Fix belongs to the user's config.

## Related

- [[agent-protocol]] · [[agent-quality-gates]] · [[llm-model-roles]] · [[session-log]]
