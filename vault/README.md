---
title: About this vault
type: readme
updated: 2026-08-18
---

# telco-ai Knowledge Vault

A distilled, wikilinked knowledge layer for the telco-ai project. Built to **save tokens**:
an agent reads [[INDEX]] (~2KB) and drills to one small atomic node, instead of slurping
`FTTH_KNOWLEDGE_BASE.txt` (48KB) or `session-ses_16ca.md` (5.2MB) whole.

## Why it exists

Project knowledge was scattered across many large `.txt/.md` files. Every fact lookup cost
a full-document read. This vault holds the **20% that gets used 80% of the time**, distilled
and cross-linked. The remaining detail stays in the source files, referenced (not copied) via
[[big-docs]].

## Three-layer knowledge model

- **Runtime KB** (`backend/data/knowledge_base.json`) = prompt facts and BigQuery schemas used by
  the production chat agent.
- **Vault** = why / what / decisions / conventions (human knowledge, rationale not in code).
- **Graphify** (`graphify-out/`) = where / how in code plus curated developer knowledge. Run
  `graphify query "..."`.

`graphify-knowledge/` is a generated bridge from approved runtime KB metadata into Graphify. It
does not replace the runtime JSON. See [[graphify-development-index]].

## Structure

```
INDEX.md          entry point (read first)
00-meta/          how to use + write the vault
10-architecture/  system, pipeline, agents, modules, frontend, mobile
20-domains/       analytics domains, ftth, reports, geo
30-data/          bigquery tables, knowledge_base.json
40-decisions/     ADRs — expensive "why" facts
50-conventions/   style/brand, deploy/restart
90-references/    pointers to big source docs
99-log/           append-only change log
```

## Rules of thumb

- One fact per node, < ~100 lines. Link liberally with `[[wikilinks]]`.
- Decisions live once in `40-decisions/`; everything else links to them.
- Update [[session-log]] when a decision changes.
- See [[vault-conventions]] for the full writing guide.

## Obsidian skills

`.claude/skills/` symlinks the kepano obsidian-skills (markdown, bases, canvas, cli, defuddle).
These symlinks are local-only (absolute paths) and are gitignored; they break on a fresh clone.
