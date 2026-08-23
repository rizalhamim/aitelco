---
title: Vault conventions — how to write notes
type: meta
updated: 2026-07-26
---

# Vault conventions

## Note shape

- Frontmatter: `title`, `type`, `updated` (absolute date `YYYY-MM-DD`).
- One fact / concept per note. Target < ~100 lines. If it grows, split and link.
- Start with a one-line "what this is", then the substance.

## Naming

- Files: `kebab-case.md`. The filename stem IS the wikilink target (`[[ytd-lytd-apple-to-apple]]`).
- Keep names stable — renames break wikilinks. If you must rename, grep-fix `[[old-name]]`.

## Folders

- `00-meta` how to use/write · `10-architecture` system · `20-domains` analytics ·
  `30-data` tables · `40-decisions` ADRs · `50-conventions` style/ops ·
  `90-references` pointers · `99-log` change log.
- MOC files (`*-moc.md` or hub notes) are just link lists + one line each. No deep content.

## Linking

- Link liberally with `[[wikilinks]]`. A link to a not-yet-written note is fine — it marks
  a TODO. Prefer linking over repeating.
- Decisions live once in `40-decisions/`. Other notes link to them, never restate the why.

## Dates & facts

- Convert relative dates to absolute ("last month" → `2026-06`).
- Never store live metrics (revenue, counts) — those come from BigQuery at query time.
- Record durable knowledge only: rules, rationale, conventions, structure. Not git-derivable.

## When to update

- Changed a decision → edit its ADR + append [[session-log]].
- Learned a durable gotcha → new node in the right folder + link from the relevant MOC/INDEX.
- Keep [[INDEX]] route table in sync when you add a top-level node.
