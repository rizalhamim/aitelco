---
title: Reports — Performance Outlook
type: domain
updated: 2026-10-06
---

# Reports — "Performance Outlook"

Web `src/app/reports/page.tsx`, mobile `lib/src/screens/reports_screen.dart`.
Routes: `routes_reports.py` (`/api/reports/*`), cached via `reports_cache.py`.

## Caching

Family markers `highlevel` / `data` / `benchmark`. Payloads keyed by `report|marker|params`.
`graphify query "reports_cache"` for the cache flow.

## Builders

`reports_comprehensive.py` · `reports_data.py` · `reports_network.py` ·
`reports_market_insight.py` · `reports_ftth.py` ([[ftth]]) · `reports_city_profile.py`.

## UI structure

- **3 modes**: My Coordinate / Territory Wise / Daily Snapshot.
- **Sub-tabs**: Comprehensive, Data Revenue, Product Demand, Network Benchmark,
  Market Insight, Indosat HiFi (FTTH).
- **Brand model**: IOH = IM3 + 3ID. Bottom IOH/IM3/3ID brand bar is GLOBAL except hidden on
  the FTTH tab.

## Critical rule

YTD / LYTD must be apple-to-apple (full closed months + partial current month capped to the
same cutoff day, both years from the MTD table). This is the single most important report rule
→ [[ytd-lytd-apple-to-apple]].

## Trade: Tertiary B Trad

The Comprehensive Trade row `tertiary_b` is labeled **Tertiary B Trad** and uses
IDR, as do its Inner and Outer components. Its value is the sum of
`tertiary_b_inner` and `tertiary_b_outer` for each brand, period, and territory;
the source `tertiary_b` column is not used. A populated single component is
retained; two missing components remain NULL. The S/T ratio uses this total.

## Related

- [[ftth]] · [[bigquery-tables]] · [[ytd-lytd-apple-to-apple]] · [[frontend]] · [[mobile]]
