---
title: Reports — Performance Outlook
type: domain
updated: 2026-07-26
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

## Related

- [[ftth]] · [[bigquery-tables]] · [[ytd-lytd-apple-to-apple]] · [[frontend]] · [[mobile]]
