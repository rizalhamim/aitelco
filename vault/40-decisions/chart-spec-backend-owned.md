---
title: ADR - the backend decides the chart, the clients only render it
type: decision
updated: 2026-08-23
---

# ADR: chart_spec is built in the backend

## Decision

`backend/app/chart_spec.py` classifies a query result into a render spec and streams it
as an SSE `chart_spec` event. Web (`ChartPanel.tsx`) and mobile (`chart_panel.dart`)
render that spec instead of deciding for themselves. Same contract as the existing
`map_synth_agent.detect_map_spec`.

## Why

The clients used to split columns into "numeric" and "not numeric" and plot the FIRST
numeric column. A column's TYPE says nothing about its MEANING, so on real results that
drew the wrong thing:

- `rank, kecamatan, revenue_mn, share_pct` plotted `rank` (1, 2, 3) as the bars.
- `kabkota, total_revenue, growth_pct` put billions of rupiah and a percentage on ONE
  axis, flattening the percentage into the baseline. Measured across the last 400
  successful production queries: **21 percent of results carry a currency column and a
  percent column together**, so this was not an edge case.
- `month_id` 202608 could be treated as a numeric value rather than a time axis.
- More categories than fit as bars produced NO chart at all.

Duplicating the fix in TypeScript and Dart would have meant two implementations drifting
apart with no test runner on the JS side. In Python it is covered by
`tests/test_chart_spec.py` and one fix reaches both clients.

## The unit of work is the column ROLE

`identifier` (never plotted) · `temporal` (x-axis, never a value) · `territory` ·
`currency` (Rp) · `percent` (%) · `count` · `delta` (can be negative, needs a zero line).
The vocabulary was derived from the output aliases of real production queries, not
invented. `delta` is tested BEFORE `percent` because `revenue_growth_pct` is a change
that happens to be expressed in percent, and what matters for rendering is that it can
go negative; it still carries the percent unit.

## Rules the spec enforces

- **One axis per unit, max two.** Rupiah left, percent right, each with its own scale.
- **A pie must be honest.** Only a single non-negative metric, at most 12 slices, not
  truncated, and no period column present. A truncated top-N is a comparison, not a
  composition: drawing it as a pie claims the slices sum to the whole.
- **Too many categories still get a chart.** Beyond 24 rows the backend sends the ranked
  top-24 in `spec.rows` and the caption says "24 teratas dari 38 kabkota". The clients
  plot `spec.rows` so the chart cannot contradict its own caption.
- **Captions disclose coverage and period.** A time axis is described by its span
  ("3 periode (202606 sampai 202608)"), not by a row count. Differing period columns are
  named explicitly, which is what surfaces the occupancy-versus-availability mismatch.
- **Funnels are detected** (`so/sa/pa`, `primary/secondary/tertiary`) and drawn with the
  drop-off between stages, instead of plotting only the first stage.

## Narration must agree with the chart

The synthesizer payload carries a trimmed `chart_spec`, and `SYNTH_SYS` requires the
text to match it: same metric, same units, same coverage. Without this the answer said
"seluruh kabkota" while the chart showed a top-10.

## Fallback

Both clients keep a local heuristic for chat history rendered before this existed. The
fallback was also fixed to never plot an identifier or a period column.

## Related

- [[agent-quality-gates]] · [[chat-pipeline]] · [[frontend]] · [[mobile]]
