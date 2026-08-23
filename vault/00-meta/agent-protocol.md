---
title: Agent protocol — token-saving recall
type: meta
updated: 2026-08-18
---

# Agent protocol (read this to save tokens)

How an agent should use this vault so it spends ~2KB instead of ~50KB per lookup.

## Recall order

1. Read [[INDEX]] — pick the ONE node matching your intent from the route table.
2. Read that node (small, atomic). Follow at most 1–2 `[[wikilinks]]` if needed.
3. Only if the node says "for full detail see X" do you open a big source doc ([[big-docs]]).
4. For code location / call graph, use `graphify query "<question>"` — NOT a raw file read.

## Do

- Trust the node. It is the distilled truth; the big docs are backup, not the default.
- When two facts conflict, the node in `40-decisions/` wins (it records the final call).
- Add a new node when you learn something durable that is not derivable from code or git.

## Don't

- Don't read `AGENTS.md`, `FTTH_KNOWLEDGE_BASE.txt`, or `session-ses_16ca.md` to answer a
  question a node already covers. That defeats the vault's purpose.
- Don't duplicate a decision's rationale into other nodes — link to the ADR instead.

## Division of labor (four workflows)

- **vault** answers **why / what / which** (decisions, domain rules, conventions). This node.
- **graphify** answers **where / how** (which file, which function, what calls what).
  Use `graphify query "..."` to locate code — never a directory sweep or bulk read.
- **graphify-knowledge** is a generated bridge from approved runtime KB metadata into Graphify.
  Regenerate it with `backend/venv/bin/python tools_graphify_kb.py`; never edit it by hand.
- **obsidian-skills** are for WRITING here: creating/editing notes, `.base`, `.canvas`, and
  pulling a web page in cleanly via `defuddle` (not a raw full-page fetch). Keeps edits small.
- **caveman** keeps the agent's OUTPUT terse. Compression of the answer, not the knowledge.
- Live BigQuery / running server answers **current numbers** (never cache real metrics here).

Graphify is development-only. It must not be imported by the production backend or exposed in
the web/mobile clients. The full boundary and refresh lanes are in [[graphify-development-index]].

The whole point: one node or one query, never "load the codebase". Looking around is the
expensive path. See also [[vault-conventions]] and the "Token budget" block in `../../CLAUDE.md`.
