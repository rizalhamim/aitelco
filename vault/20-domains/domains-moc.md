---
title: Analytics domains (MOC)
type: domain
updated: 2026-07-26
---

# Analytics domains — MOC

Domains defined in `backend/data/knowledge_base.json` ([[knowledge-base-json]]). Each has BQ
table schemas + SQL-generation prompts. Add domains by editing the KB, not by hardcoding.

## Domains

- **site performance** — per-site metrics, RGU/VLR/outlets
- **network** — network benchmark vs competitors
- **market share** — Indosat vs competitors per territory (`rham_report_fb_ms_*`, col `kabkot`)
- **forecast** — projections
- **HVC** — high-value customer
- **marketing / sales** — acquisition, campaigns
- **fixed broadband / FTTH** — Indosat HiFi → [[ftth]] (its own territory vocabulary)
- **geography** — kecamatan/choropleth → [[geo]]
- **KPI / kpi_summary** — headline KPIs
- **reports** — Performance Outlook composite → [[reports]]
- **revenue** — prepaid data revenue
- **5g / fwa / acquisition / competitive / customer_hvc** — sub-domains seen in routing

## Cross-domain

- `CORRELATE` mode joins two domains on a territory key (`correlate_agent.py`).
- Circle → region mapping and table→domain map: [[bigquery-tables]].

## Related

- [[knowledge-base-json]] · [[bigquery-tables]] · [[agent-swarm]]
