---
title: ADR - run project on opus with fable-level quality process
type: decision
updated: 2026-07-29
---

# ADR: opus + process instead of fable

## Decision

Project model pinned to `opus` in `.claude/settings.json` (effort high). Fable reserved for
explicit per-task escalation via `/model fable`.

## Why

Token cost. Opus is cheaper per token; most tasks here are bounded (vault + graphify give
tight context). Quality gap closed by process, not model size.

## Quality compensation (mandatory, see CLAUDE.md "Model & cost policy")

1. Plan (2-3 lines) before non-trivial edits.
2. Self-review `git diff` after multi-file/logic changes; `/code-review` for risky backend work.
3. Verify against running system (curl API, run script) rather than reasoning from memory.
4. Delegate locate work to `cavecrew-investigator`, small edits to `cavecrew-builder`.
5. Escalate to fable explicitly when architecture-level quality falls short. Never silently degrade.

## Token cost measures (same commit)

- Project-disabled plugins: playwright, ralph-loop, skill-creator, claude-code-setup,
  code-simplifier, feature-dev, superpowers (removes tool schemas + session-start injection).
- `skillOverrides`: dataviz, deep-research hidden from model listing (user-invocable only).
- Existing stack unchanged: vault-first recall, graphify hook-guard, caveman output, RTK proxy.

Re-enable any plugin per-machine via `.claude/settings.local.json` if needed.
