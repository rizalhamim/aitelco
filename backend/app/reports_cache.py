"""Server-side cache for Daily Reports.

Reports are expensive (multiple BigQuery scans) but the underlying data only
changes when the precalc tables are re-cut. Each source family exposes a
freshness marker:
  - highlevel (snapshot / comprehensive): MAX(dt_id_snapshot) on rham_mkt_highlevel_mtd
  - data-revenue / product-demand:        MAX(as_of_dt) on the site_data_rev_* tables

Strategy:
  - Cache each report payload keyed by its request params + the data marker.
  - The marker itself is cached for a short TTL (default 120s) so we don't query
    BigQuery on every request just to check freshness.
  - When the marker changes (server data updated), old cache entries become
    unreachable (new key) and are evicted; the report is rebuilt once.
"""
from __future__ import annotations

import threading
import time
from typing import Callable, Optional

from . import config
from .bigquery_tool import run_query

_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET
_MTD = f"`{_PROJECT}.{_DATASET}.rham_mkt_highlevel_mtd`"
_CHANNEL = f"`{_PROJECT}.{_DATASET}.rham_site_data_rev_channel_mtd`"

_FB_NET = f"`{_PROJECT}.{_DATASET}.rham_fb_network_territory_wly_wide`"
_FWA_MTD = f"`{_PROJECT}.{_DATASET}.rham_fwa_kec_wise_mtd`"
_FTTH_MTD = f"`{_PROJECT}.{_DATASET}.rham_ftth_kec_wise_mtd`"
_NET_COMP = f"`{_PROJECT}.{_DATASET}.rham_network_comp`"
_NET_INTERNAL = f"`{_PROJECT}.{_DATASET}.rham_network_internal`"

# marker source per family
_MARKER_SQL = {
    "highlevel": f"SELECT MAX(dt_id_snapshot) AS m FROM {_MTD}",
    "data": f"SELECT MAX(as_of_dt) AS m FROM {_CHANNEL}",
    "benchmark": f"SELECT MAX(wk_end_dt) AS m FROM {_FB_NET}",
    "fwa": f"SELECT MAX(dt_id) AS m FROM {_FWA_MTD}",
    "ftth-summary": f"SELECT MAX(dt_id) AS m FROM {_FTTH_MTD}",
    "network-catalog": (
        "SELECT MAX(m) AS m FROM ("
        f"SELECT MAX(dt_id) AS m FROM {_NET_COMP} UNION ALL "
        f"SELECT MAX(dt_id) AS m FROM {_NET_INTERNAL})"
    ),
}

# which family each report belongs to
_FAMILY = {
    "snapshot": "highlevel",
    "comprehensive": "highlevel",
    "data-revenue": "data",
    "product-demand": "data",
    "network-benchmark": "network-catalog",
    "internal-performance": "network-catalog",
    "fwa": "fwa",
    "market-insight": "highlevel",
    "profile-analysis": "highlevel",
    "ftth": "ftth-summary",
}

_MARKER_TTL = 120.0  # seconds
_MAX_ENTRIES = 256

_lock = threading.Lock()
_marker_cache: dict[str, tuple[float, str]] = {}   # family -> (fetched_at, marker)
_payload_cache: dict[str, tuple[str, float, dict]] = {}  # key -> (marker, stored_at, payload)


def _fetch_marker(family: str) -> str:
    sql = _MARKER_SQL.get(family)
    if not sql:
        return ""
    try:
        r = run_query(sql, row_limit=2)
        v = r["rows"][0].get("m") if r["rows"] else None
        return str(v) if v is not None else ""
    except Exception:
        return ""


def data_marker(family: str, force: bool = False) -> str:
    """Current freshness marker for a family, with short TTL caching."""
    now = time.time()
    with _lock:
        cached = _marker_cache.get(family)
    if not force and cached and (now - cached[0]) < _MARKER_TTL:
        return cached[1]
    m = _fetch_marker(family)
    with _lock:
        # keep prior marker if the fetch failed (empty) so we don't thrash
        if not m and cached:
            m = cached[1]
        _marker_cache[family] = (now, m)
    return m


def version() -> dict:
    """Expose current markers (used by clients to decide a refresh)."""
    return {fam: data_marker(fam) for fam in _MARKER_SQL}


def get_or_build(report: str, params_key: str, builder: Callable[[], dict],
                 force: bool = False) -> dict:
    """Return a cached report payload if the data marker is unchanged, else
    rebuild via `builder` and cache it. `force` bypasses + refreshes the marker
    and rebuilds unconditionally."""
    family = _FAMILY.get(report, "highlevel")
    marker = data_marker(family, force=force)
    key = f"{report}|{marker}|{params_key}"

    if not force:
        with _lock:
            hit = _payload_cache.get(key)
        if hit:
            payload = dict(hit[2])
            payload.setdefault("_cache", {})
            payload["_cache"] = {"hit": True, "marker": marker, "age": round(time.time() - hit[1], 1)}
            return payload

    payload = builder()
    # do not cache error payloads
    if isinstance(payload, dict) and "error" not in payload:
        with _lock:
            # drop stale-marker entries for this report + cap size
            for k in [k for k in _payload_cache if k.startswith(f"{report}|") and f"|{marker}|" not in k]:
                _payload_cache.pop(k, None)
            if len(_payload_cache) >= _MAX_ENTRIES:
                oldest = min(_payload_cache.items(), key=lambda kv: kv[1][1])[0]
                _payload_cache.pop(oldest, None)
            _payload_cache[key] = (marker, time.time(), dict(payload))
        if isinstance(payload, dict):
            payload = dict(payload)
            payload["_cache"] = {"hit": False, "marker": marker, "age": 0.0}
    return payload


def clear() -> int:
    with _lock:
        n = len(_payload_cache)
        _payload_cache.clear()
        _marker_cache.clear()
    return n
