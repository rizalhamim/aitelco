---
title: Runtime knowledge projection for Graphify
type: generated-knowledge-index
source_sha256: "54e09a90974c30bf5ab15374bd53de39ec06b0e02e1c010667cd923fc8963107"
---

# Runtime knowledge projection for Graphify

This directory is a deterministic, development-only projection of
`backend/data/knowledge_base.json`. The JSON remains the runtime source of truth.

> [!warning] Generated corpus
> Do not edit these files. Run `backend/venv/bin/python tools_graphify_kb.py`.

## Coverage

- Source SHA-256: `54e09a90974c30bf5ab15374bd53de39ec06b0e02e1c010667cd923fc8963107`
- Project: `data-java-prd-97b9`
- Dataset: `java_precalc`
- Region: `asia-southeast2`
- Domains: 17
- Tables: 157
- Columns: 7125
- Approved domain key facts: 99
- Approved global data fact groups: 26

## Security and ownership boundary

Included: domain labels, descriptions, domain-to-table relationships, column names and
types, partition flags, approved domain key facts, and allowlisted global data facts.

Excluded: agent personas, prompt templates, credentials, environment values, row samples,
customer data, SQLite content, and live KPI values. Graphify must not be used as a source
for production business metrics or chat answers.

## Domains

- [`5g`](domains/5g.md): 9 tables, 5G Performance
- [`acquisition`](domains/acquisition.md): 4 tables, Acquisition (Gross Add)
- [`competitive`](domains/competitive.md): 28 tables, Competitive Market Share
- [`customer_demand`](domains/customer-demand.md): 13 tables, Customer Demand & Digital Behavior
- [`customer_hvc`](domains/customer-hvc.md): 6 tables, High Value Customer
- [`forecast`](domains/forecast.md): 14 tables, Forecast (Revenue Prediction)
- [`ftth`](domains/ftth.md): 10 tables, FTTH / HBB Home Broadband
- [`fwa`](domains/fwa.md): 10 tables, FWA Business
- [`kpi_summary`](domains/kpi-summary.md): 9 tables, KPI Summary (Marketing High-Level)
- [`network`](domains/network.md): 8 tables, Network Quality & Availability
- [`network_benchmark`](domains/network-benchmark.md): 13 tables, Network Benchmark (Competitor)
- [`performance_outlook_extended`](domains/performance-outlook-extended.md): 0 tables, Performance Outlook Extended
- [`product`](domains/product.md): 3 tables, Product Revenue Intelligence
- [`revenue`](domains/revenue.md): 6 tables, Revenue Deep-Dive
- [`sales_distribution`](domains/sales-distribution.md): 14 tables, Sales & Distribution
- [`site_performance`](domains/site-performance.md): 6 tables, Site Performance
- [`territory_reference`](domains/territory-reference.md): 4 tables, Territory Reference

## Global data facts

- [`banned_tables`](data-facts/banned-tables.md)
- [`brands`](data-facts/brands.md)
- [`causal_analysis_flow`](data-facts/causal-analysis-flow.md)
- [`circle_region_mapping`](data-facts/circle-region-mapping.md)
- [`competitive_tables`](data-facts/competitive-tables.md)
- [`customer_demand_tables`](data-facts/customer-demand-tables.md)
- [`date_columns`](data-facts/date-columns.md)
- [`date_ranges`](data-facts/date-ranges.md)
- [`follow_up_handling`](data-facts/follow-up-handling.md)
- [`forecast_tables`](data-facts/forecast-tables.md)
- [`ftth_tables`](data-facts/ftth-tables.md)
- [`geography`](data-facts/geography.md)
- [`knowledge_governance`](data-facts/knowledge-governance.md)
- [`metric_prefixes`](data-facts/metric-prefixes.md)
- [`month_id_arithmetic`](data-facts/month-id-arithmetic.md)
- [`month_id_casting`](data-facts/month-id-casting.md)
- [`operators_for_competitive`](data-facts/operators-for-competitive.md)
- [`partial_period_warning`](data-facts/partial-period-warning.md)
- [`query_guidance`](data-facts/query-guidance.md)
- [`read_only`](data-facts/read-only.md)
- [`revenue_defaults`](data-facts/revenue-defaults.md)
- [`runtime_graph`](data-facts/runtime-graph.md)
- [`site_kec_id_mapping`](data-facts/site-kec-id-mapping.md)
- [`table_grains`](data-facts/table-grains.md)
- [`table_routing_constraints`](data-facts/table-routing-constraints.md)
- [`window_filter_examples`](data-facts/window-filter-examples.md)

## Governance

- [Full java_precalc lifecycle registry](table-governance.md)

## Refresh workflow

1. Edit the authoritative runtime KB.
2. Run `backend/venv/bin/python tools_graphify_kb.py`.
3. Run the semantic Graphify update workflow because Markdown changed.
4. Verify with `backend/venv/bin/python tools_graphify_kb.py --check` and smoke queries.

See `vault/40-decisions/graphify-development-index.md` for the architecture boundary.
