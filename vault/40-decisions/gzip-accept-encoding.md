---
title: "ADR: gzip only on Accept-Encoding"
type: decision
updated: 2026-07-26
---

# ADR: geo shapes gzip only when client asks

**Decision**: `/api/geo/shapes/*` serves gzipped payloads ONLY when the client sends
`Accept-Encoding: gzip`. Do NOT change it to always-gzip.

## Why

The geojson files are pre-gzipped on disk (`data/geo/*.geojson.gz`). Serving them always-gzip
regardless of the request header caused a **proxy double-gzip bug** (nginx/proxy re-compressing
or a client that can't decode a body it didn't negotiate). Gating on the client's
`Accept-Encoding` avoids sending gzip to something that won't decode it.

## Rule

Keep the header check. A future "cleanup" to always-gzip will reintroduce the bug.

## Where

`main.py` geo shapes endpoints; files built by `build_geojson.py`. See [[geo]].

## Related

- [[geo]] · [[session-log]]
