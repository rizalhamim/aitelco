"""Daily Performance dump: BigQuery aggregates saved as Parquet once a day.

Dashboard and Performance read these files instead of querying BigQuery on every
page open (Redesign v2 brief: "dump performance data to Parquet"). The dump runs
at 05.00 WIB from the backend loop (main.py) or by hand:

    PYTHONPATH=. venv/bin/python -m app.perf_dump            # run now
    PYTHONPATH=. venv/bin/python -m app.perf_dump --check    # dry-run every query, write nothing

Layout under backend/data/dump/ (gitignored with the rest of data/):
    <YYYYMMDD-HHMM>/<table>.parquet
    <YYYYMMDD-HHMM>/manifest.json   {"created_at", "latest_month", "tables": {name: rows}}
    current                          name of the newest complete dump (written last)

Tables (all Circle Java):
    kec_month     kecamatan x month, 25 months (YoY needs 13): revenue, subs, payload_gb,
                  gross_add plus region / kabupaten / provinsi / kecamatan names
    avail_month   4G availability per territory (circle, region, kabkot) and month
    region_daily  region x day, last 70 days (10 weeks), when the daily KPI table has the same
                  measures (probed from the table schema, skipped otherwise)
    site_month    site x month for this month, last month and the same month last year:
                  payload, revenue when present, 4G availability

Columns are probed from table metadata before each run, so an upstream rename drops
one optional measure instead of failing the whole dump. Readers get None when the dump
is missing or older than STALE_HOURS and fall back to BigQuery.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import logging
import shutil
import sys
import threading
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Callable, Optional

from . import config

log = logging.getLogger("perf_dump")

DUMP_ROOT = config.DATA_DIR / "dump"
STALE_HOURS = 30
KEEP = 3
RUN_HOUR_WIB = 5
WIB = timezone(timedelta(hours=7))

_P, _D = config.BQ_PROJECT, config.BQ_DATASET
T_MTD = "rham_mkt_highlevel_mtd"
T_TERR = "rham_ref_territory"
T_ZZ = "zz_territory_kecamatan"
T_AVAIL = "rham_avail_stat_territory_monthly"
T_DLY = "rham_mkt_kpi_highlevel_dly"
T_SITE = "rham_site_wise_monthly"
T_SITE_AV = "rham_avail_stat_site_monthly"
T_ADDR = "rham_site_wise_addr_java"

# measure -> physical column on the highlevel tables (same names as dashboard.KPIS)
MEASURES = {"revenue": "rev_prepaid", "subs": "rgu_90d", "payload_gb": "usg_data_gb", "gross_add": "gross_add"}


def _fq(table: str) -> str:
    return f"`{_P}.{_D}.{table}`"


def month_add(mid: int, n: int) -> int:
    y, m = divmod(int(mid), 100)
    k = y * 12 + (m - 1) + n
    return (k // 12) * 100 + (k % 12) + 1


def _pick(cols: set[str], *names: str) -> Optional[str]:
    return next((n for n in names if n in cols), None)


# ── Queries ──────────────────────────────────────────────────────────────────

def _columns(table: str) -> set[str]:
    """Column names from table metadata (no bytes scanned)."""
    from .bigquery_tool import get_client
    try:
        return {f.name.lower() for f in get_client().get_table(f"{_P}.{_D}.{table}").schema}
    except Exception as e:  # missing table or no access: the query using it is skipped
        log.warning(f"schema {table}: {e}")
        return set()


def build_queries(latest: int, latest_day: Optional[date], cols: Callable[[str], set[str]]) -> dict[str, str]:
    """SQL per dump table. Partition filters are literals (hard rule)."""
    q: dict[str, str] = {}
    first = month_add(latest, -24)
    zz = cols(T_ZZ)
    kec_name = _pick(zz, "kecamatan", "kec_name", "nama_kecamatan")
    kab = _pick(zz, "kabkota", "kabupaten", "kabkot")
    prov = _pick(zz, "province", "provinsi")
    names = ",\n  ".join(
        f"ANY_VALUE(z.{c}) AS {alias}" for c, alias in ((kab, "kabupaten"), (prov, "provinsi"), (kec_name, "kecamatan")) if c)
    mtd = cols(T_MTD)
    sums = ",\n  ".join(f"SUM(x.{c}) AS {m}" for m, c in MEASURES.items() if c in mtd)
    if sums:
        q["kec_month"] = f"""
SELECT x.month_id AS month_id, x.kec_id AS kec_id, ANY_VALUE(t.region) AS region{(',' + chr(10) + '  ' + names) if names else ''},
  {sums}
FROM {_fq(T_MTD)} x
JOIN {_fq(T_TERR)} t ON x.kec_id = t.kec_id
{f'LEFT JOIN {_fq(T_ZZ)} z ON x.kec_id = z.kec_id' if names else ''}
WHERE t.circle = 'JAVA' AND t.region IS NOT NULL
  AND x.month_id BETWEEN {first} AND {latest}
GROUP BY month_id, kec_id
"""
    q["avail_month"] = f"""
SELECT LOWER(territory_level) AS level, UPPER(territory_name) AS name, CAST(month_id AS INT64) AS month_id,
  AVG(mean_avg_avail_pct_4g) AS avail, SUM(sites_below_sla99_4g) AS below_sla
FROM {_fq(T_AVAIL)}
WHERE territory_level IN ('circle', 'region', 'kabkot')
  AND CAST(month_id AS INT64) BETWEEN {first} AND {latest}
GROUP BY level, name, month_id
"""
    dly = cols(T_DLY)
    day_col = _pick(dly, "dt_id")
    dsums = ",\n  ".join(f"SUM(x.{c}) AS {m}" for m, c in MEASURES.items() if c in dly)
    if latest_day and day_col and "kec_id" in dly and dsums:
        start = latest_day - timedelta(days=69)
        q["region_daily"] = f"""
SELECT x.dt_id AS dt_id, t.region AS region,
  {dsums}
FROM {_fq(T_DLY)} x
JOIN {_fq(T_TERR)} t ON x.kec_id = t.kec_id
WHERE t.circle = 'JAVA' AND t.region IS NOT NULL
  AND x.dt_id BETWEEN DATE '{start.isoformat()}' AND DATE '{latest_day.isoformat()}'
GROUP BY dt_id, region
"""
    site = cols(T_SITE)
    addr = cols(T_ADDR)
    if "site_id" in site and "usg_data_gb" in site and "site_id" in addr:
        rev = _pick(site, "rev_total", "rev_prepaid", "revenue")
        sm = f"{latest}, {month_add(latest, -1)}, {month_add(latest, -12)}"
        av = cols(T_SITE_AV)
        has_av = "site_id" in av and "avg_avail_pct_4g" in av
        q["site_month"] = f"""
WITH addr AS (
  SELECT site_id, ANY_VALUE(site_name) AS site_name, ANY_VALUE(kecamatan) AS kecamatan, ANY_VALUE(kabupaten) AS kabupaten,
    ANY_VALUE(provinsi) AS provinsi, ANY_VALUE(SAFE_CAST(latitude AS FLOAT64)) AS lat, ANY_VALUE(SAFE_CAST(longitude AS FLOAT64)) AS lon
  FROM {_fq(T_ADDR)}
  WHERE month_id = (SELECT MAX(month_id) FROM {_fq(T_ADDR)})
  GROUP BY site_id
), perf AS (
  SELECT site_id, month_id, SUM(usg_data_gb) AS payload_gb{f', SUM({rev}) AS revenue' if rev else ''}
  FROM {_fq(T_SITE)}
  WHERE month_id IN ({sm})
  GROUP BY site_id, month_id
){f''', av AS (
  SELECT site_id, CAST(month_id AS INT64) AS month_id, AVG(avg_avail_pct_4g) AS avail
  FROM {_fq(T_SITE_AV)}
  WHERE CAST(month_id AS INT64) IN ({sm})
  GROUP BY site_id, month_id
)''' if has_av else ''}
SELECT p.site_id, p.month_id, a.site_name, a.kecamatan, a.kabupaten, a.provinsi, a.lat, a.lon,
  p.payload_gb{', p.revenue' if rev else ''}{', v.avail' if has_av else ''}
FROM perf p JOIN addr a USING (site_id){' LEFT JOIN av v USING (site_id, month_id)' if has_av else ''}
"""
    return q


def _latest_month() -> int:
    from .bigquery_tool import run_query
    return int(run_query(f"SELECT MAX(month_id) AS m FROM {_fq(T_MTD)}")["rows"][0]["m"])


def _latest_day() -> Optional[date]:
    from .bigquery_tool import run_query
    if "dt_id" not in _columns(T_DLY):
        return None
    since = (datetime.now(WIB).date() - timedelta(days=40)).isoformat()
    try:
        v = run_query(f"SELECT MAX(dt_id) AS d FROM {_fq(T_DLY)} WHERE dt_id >= DATE '{since}'")["rows"][0]["d"]
    except Exception as e:
        log.warning(f"latest day: {e}")
        return None
    return date.fromisoformat(str(v)[:10]) if v else None


# ── Run ──────────────────────────────────────────────────────────────────────

_ROW_CAP = 2_000_000


def run_dump(check: bool = False) -> dict:
    """Run every query and write a new dump (or only dry-run them with check=True)."""
    from .bigquery_tool import dry_run, run_query
    import pyarrow as pa
    import pyarrow.parquet as pq

    latest = _latest_month()
    queries = build_queries(latest, _latest_day(), _columns)
    if check:
        out = {}
        for name, sql in queries.items():
            try:
                out[name] = {"ok": True, "gb": round(dry_run(sql) / 1024**3, 3)}
            except Exception as e:
                out[name] = {"ok": False, "error": str(e)[:300]}
        return {"latest_month": latest, "queries": out}

    DUMP_ROOT.mkdir(parents=True, exist_ok=True)
    lock = open(DUMP_ROOT / ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return {"skipped": "another dump is running"}
    try:
        stamp = datetime.now(WIB).strftime("%Y%m%d-%H%M")
        tmp = DUMP_ROOT / f".{stamp}.tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        tmp.mkdir()
        tables, errors = {}, {}
        for name, sql in queries.items():
            t0 = time.time()
            try:
                res = run_query(sql, row_limit=_ROW_CAP)
            except Exception as e:
                errors[name] = str(e)[:300]
                log.warning(f"dump {name}: {e}")
                continue
            cols = res["columns"]
            table = pa.table({c: [r.get(c) for r in res["rows"]] for c in cols}) if res["rows"] else pa.table({c: [] for c in cols})
            pq.write_table(table, tmp / f"{name}.parquet", compression="zstd")
            tables[name] = {"rows": res["row_count"], "gb": round(res["bytes_processed"] / 1024**3, 3), "s": round(time.time() - t0, 1)}
        if "kec_month" not in tables:
            shutil.rmtree(tmp, ignore_errors=True)
            return {"error": "kec_month failed", "errors": errors}
        manifest = {"created_at": datetime.now(timezone.utc).isoformat(), "latest_month": latest, "tables": tables, "errors": errors}
        (tmp / "manifest.json").write_text(json.dumps(manifest, indent=1))
        final = DUMP_ROOT / stamp
        shutil.rmtree(final, ignore_errors=True)
        tmp.rename(final)
        (DUMP_ROOT / "current.tmp").write_text(stamp)
        (DUMP_ROOT / "current.tmp").replace(DUMP_ROOT / "current")
        for old in sorted(p for p in DUMP_ROOT.iterdir() if p.is_dir() and not p.name.startswith("."))[:-KEEP]:
            shutil.rmtree(old, ignore_errors=True)
        _cache.clear()
        return {"dump": stamp, **manifest}
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


# ── Read ─────────────────────────────────────────────────────────────────────

_cache: dict[tuple[str, str], list[dict]] = {}
_cache_lock = threading.Lock()


def _current() -> Optional[Path]:
    try:
        name = (DUMP_ROOT / "current").read_text().strip()
    except OSError:
        return None
    d = DUMP_ROOT / name
    return d if (d / "manifest.json").exists() else None


def manifest() -> Optional[dict]:
    d = _current()
    if not d:
        return None
    try:
        m = json.loads((d / "manifest.json").read_text())
    except (OSError, ValueError):
        return None
    m["dump"] = d.name
    return m


def status() -> dict:
    """{"available", "fresh", "created_at", "age_hours", "label"} for UI source labels."""
    m = manifest()
    if not m:
        return {"available": False, "fresh": False}
    created = datetime.fromisoformat(m["created_at"])
    age = (datetime.now(timezone.utc) - created).total_seconds() / 3600
    return {
        "available": True, "fresh": age <= STALE_HOURS, "created_at": m["created_at"], "age_hours": round(age, 1),
        "latest_month": m.get("latest_month"), "label": source_label(created),
    }


MONTHS_ID = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]


def source_label(created: datetime) -> str:
    """"Dump Performance 1 Nov 05.00" (WIB), the label shown next to numbers."""
    w = created.astimezone(WIB)
    return f"Dump Performance {w.day} {MONTHS_ID[w.month - 1]} {w:%H.%M}"


def load(name: str, allow_stale: bool = False) -> Optional[list[dict]]:
    """Rows of one dump table, or None when the dump is missing, stale or lacks it."""
    d = _current()
    if not d:
        return None
    if not allow_stale and not status().get("fresh"):
        return None
    f = d / f"{name}.parquet"
    if not f.exists():
        return None
    key = (d.name, name)
    with _cache_lock:
        if key in _cache:
            return _cache[key]
    import pyarrow.parquet as pq
    rows = pq.read_table(f).to_pylist()
    with _cache_lock:
        for k in [k for k in _cache if k[0] != d.name]:
            _cache.pop(k, None)
        _cache[key] = rows
    return rows


def due(now: Optional[datetime] = None) -> bool:
    """True when today's 05.00 WIB dump has not run yet."""
    now = (now or datetime.now(timezone.utc)).astimezone(WIB)
    if now.hour < RUN_HOUR_WIB:
        return False
    m = manifest()
    if not m:
        return True
    created = datetime.fromisoformat(m["created_at"]).astimezone(WIB)
    return created.date() < now.date() or created.hour < RUN_HOUR_WIB


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="dry-run every query and print the scan size")
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    res = run_dump(check=args.check)
    print(json.dumps(res, indent=1, default=str))
    bad = res.get("error") or (args.check and any(not v["ok"] for v in res.get("queries", {}).values()))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
