---
title: Big source docs (pointers, not copies)
type: reference
updated: 2026-07-26
---

# Big source docs — pointers

The vault distills these. Read a full source doc ONLY when a node says to, or when you need
detail the vault does not carry. Paths relative to repo root `/home/ubuntu/telco-ai/`.

| Source doc | Size | Read it for | Distilled in |
|------------|------|-------------|--------------|
| `AGENTS.md` | 9KB | shared operating guide for all coding models (loop, gates, KB workflow) | [[model-roster]] |
| `FTTH_KNOWLEDGE_BASE.txt` | 48KB | legacy PHP FTTH reverse-engineering, full funnel/hierarchy detail | [[ftth]] |
| `SESSION_KNOWLEDGE_2026-06.md` | 8KB | the live FTTH implementation session notes | [[ftth]], [[ytd-lytd-apple-to-apple]] |
| `TELCO_REPORTS_REPLICATION_KNOWLEDGE.txt` | 9KB | report replication detail (section 6 = FTTH) | [[reports]] |
| `agent-architecture-recommendation.txt` | 26KB | agent architecture rationale / options | [[agent-swarm]] |
| `agent-table-mapping.txt` | 18KB | domain → BigQuery table mapping | [[bigquery-tables]] |
| `precalc-table-audit.txt` | 14KB | audit of `java_precalc` tables (cols, storage) | [[bigquery-tables]] |
| `design-rule.txt` | 11KB | full IOH analyst-deck design system | [[style-brand]] |
| `docs/design-system-teal.md` | 5KB | full web-app teal design system | [[style-brand]] |
| `city_profile_radar_PROMPT.md` | 17KB | city profile radar feature prompt | (profile engine) |
| `docs/9router-haiku-long-context-bug.md` | 3KB | 9Router/Haiku long-context bug writeup | [[llm-model-roles]] |
| `session-ses_16ca.md` | 5.2MB | raw session transcript — almost never read whole; grep a keyword | — |
| `training-questions-100.txt` / `training-results-summary.txt` | small | answer-quality test corpus + results | — |

## Rule

Prefer the distilled node. These are backup. `session-ses_16ca.md` especially: never read whole
(5.2MB) — search it for a specific string if you must.

## Related

- [[INDEX]] · [[agent-protocol]]
