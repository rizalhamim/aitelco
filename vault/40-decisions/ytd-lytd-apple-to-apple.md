---
title: "ADR: YTD/LYTD must be apple-to-apple"
type: decision
status: fixed 2026-06
updated: 2026-07-26
---

# ADR: YTD / LYTD apple-to-apple

**Decision**: YTD and LYTD both mix full closed months + a PARTIAL current month capped at the
same data-cutoff day. The current month (this year AND last year) ALWAYS comes from the MTD
table (cutoff-capped), never the full-month `_mth` table.

## Why

Comparing a partial current month against a full prior-year month (or calendar-day vs data-day)
double-counts and misleads. "Today" for MTD = MAX DATA DAY loaded (e.g. the 14th), not the
calendar day. The same day-of-month cap applies to both years so the windows are equal.

## Formula

```
YTD  = SUM(_mth, Jan..mid-1 this year) + MTD(this year, mid)
LYTD = SUM(_mth, Jan..mid-1 last year) + MTD(last year, mid-100)
```

Prior-year month snapshot is symmetric: `_mtd[202506].dt_id_snapshot = 2025-06-16` matches
`202606 = 2026-06-16`.

## Where implemented

- `reports_comprehensive.py` (flow metrics).
- `reports_data.py` (all 4 cumulative blocks: channel chunks, price slabs, product-demand
  slabs, top products).
- `reports_ftth.py`: YTD/LYTD by date range on event-dated detail tables:
  `LYTD = [(year-1)-01-01 .. cur_dt minus 1 year]`. Snapshot metrics (site/RGU/VLR/outlets) use
  point-in-time MTD-this-year vs MTD-last-year, NOT a YTD sum.
- `reports_city_profile.py` consumes these → inherits the fix.

## Related

- [[reports]] · [[ftth]] · [[bigquery-tables]] · [[session-log]]
