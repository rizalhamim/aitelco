---
title: Geo / choropleth / kecamatan
type: domain
updated: 2026-07-26
---

# Geo / choropleth / kecamatan

Geography domain. Module `geo_locate.py`. `graphify query "geo_locate"` for code.

## GPS → territory flow

`geo_locate.py`: GPS coordinate → kecamatan (via SHP polygon lookup) → nearest sites / outlets.
SHP path from `KEC_SHP_PATH` (default `/home/ubuntu/telco-ai/shp/Data Kecamatan Indonesia`).
Endpoint: `POST /api/geo/locate`.

## Choropleth build (pre-built, not on the fly)

`python build_geojson.py` reads the kecamatan SHP → writes gzipped
`data/geo/{kecamatan,kabupaten}.geojson.gz` + `territory_map.json`.

Endpoints: `GET /api/geo/shapes/{kecamatan|kabupaten}`, `GET /api/geo/territory-map`.

## gzip quirk (do not "fix")

`/api/geo/shapes/*` serves gzip ONLY when the client sends `Accept-Encoding: gzip`. This is
deliberate to avoid a proxy double-gzip bug — do NOT simplify to always-gzip.
Full rationale → [[gzip-accept-encoding]].

## Circle ↔ region ↔ province mapping

FTTH and IM3 use different territory vocabularies. Circle→region and province→circle maps live
in [[bigquery-tables]] and [[ftth]].

## Related

- [[ftth]] · [[bigquery-tables]] · [[gzip-accept-encoding]]
