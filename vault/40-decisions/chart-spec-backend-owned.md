---
title: ADR - the backend decides the chart, the clients only render it
type: decision
updated: 2026-11-05
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

## 2026-11 validation layer (the spec the clients draw is `suggest()`)

Since Redesign v1 the clients draw `result.chart` (`suggest()`), and `build_chart_spec()`
only feeds the legacy `chart_spec` event. The synthesizer was still narrating the
`build_chart_spec()` view, so text and chart could disagree. Now:

- `suggest()` = `_suggest_raw()` (type choice) + `_finalize()` (safety): every y/y2
  column must exist and be numeric in at least half the drawn rows and not all zero
  (a KPI keeps a 0), a missing axis gives type `none` with a `reason`, it never raises.
- A time axis runs oldest to newest (`spec.rows`). SQL ending in `ORDER BY month DESC`
  drew every trend right to left. When the SQL ordered by the time column (or not at
  all), `chronological_rows()` also re-orders `result.rows`, so older APKs that ignore
  `spec.rows` draw it correctly too. A ranking order (ORDER BY revenue) stays in the table.
- `year`/`tahun` ints are an axis, never a measure. Decimal is a number.
- More than 8 groups on a time axis (month x 38 kabkota) keeps the 6 biggest groups and
  says so in the caption, instead of one line zigzagging through every kabkota.
- `caption` and `units` come with the spec; the synthesizer receives `chart_brief()` of
  this SAME spec. Guarded by the `suggest() validation layer` tests in `test_chart_spec.py`.

## Related

- [[agent-quality-gates]] · [[chat-pipeline]] · [[frontend]] · [[mobile]]
