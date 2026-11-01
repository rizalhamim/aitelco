"""Dashboard Monitoring API — the numbers behind the web/Android Dashboard.

GET /api/dashboard/overview?region=&months=6

One grouped query over rham_mkt_highlevel_mtd (month × region) feeds the
KPI cards, their sparklines, the revenue-per-region chart and the region
table; availability comes from rham_avail_stat_territory_monthly. The agent
summary in the hero card is written from those numbers (no LLM call), so the
dashboard stays fast and deterministic.

Optional monthly targets live in data/targets.json, per KPI and region:
    {"revenue": {"<region name>": <IDR per month>, ...}, "subs": {...}, "payload": {...}, "gross_add": {...}}
Revenue targets drive "Pencapaian target" in the region table (otherwise each region's
contribution to Java revenue); every KPI with targets for all scope regions gets a
target bar on its card.

When the daily Performance dump (perf_dump.py) is fresh, the numbers come from its
Parquet files and no BigQuery query runs; the payload says which via "source".
"""
from __future__ import annotations

import json
import os
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from . import config, perf_dump, reports_cache
from .auth import get_current_user
from .bigquery_tool import QueryError, run_query
from .database import ChatMessage, UsageLog, User, get_db

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])

_P, _D = config.BQ_PROJECT, config.BQ_DATASET
_MTD = f"`{_P}.{_D}.rham_mkt_highlevel_mtd`"
_TERR = f"`{_P}.{_D}.rham_ref_territory`"
_AVAIL = f"`{_P}.{_D}.rham_avail_stat_territory_monthly`"
_TARGETS = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "targets.json")

CIRCLE = "JAVA"
MONTHS_ID = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]

KPIS = [
    {"key": "revenue", "label": "Revenue", "expr": "x.rev_prepaid", "format": "currency", "icon": "wallet"},
    {"key": "subs", "label": "Pelanggan aktif", "expr": "x.rgu_90d", "format": "number", "icon": "users"},
    {"key": "payload", "label": "Payload data", "expr": "x.usg_data_gb", "format": "gb", "icon": "database"},
    {"key": "gross_add", "label": "Gross add", "expr": "x.gross_add", "format": "number", "icon": "user-plus"},
]


def _esc(v: str) -> str:
    return (v or "").replace("'", "").replace("\\", "")


def month_add(mid: int, n: int) -> int:
    y, m = divmod(mid, 100)
    k = y * 12 + (m - 1) + n
    return (k // 12) * 100 + (k % 12) + 1


def month_label(mid: int, with_year: bool = False) -> str:
    y, m = divmod(int(mid), 100)
    return f"{MONTHS_ID[m - 1]} {y}" if with_year else MONTHS_ID[m - 1]


def _pct(cur: Optional[float], prev: Optional[float]) -> Optional[float]:
    if cur is None or not prev:
        return None
    return (cur - prev) / abs(prev) * 100


def _load_targets() -> dict:
    try:
        with open(_TARGETS, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _region_month_rows(months: list[int]) -> list[dict]:
    sums = ",\n  ".join(f"SUM({k['expr']}) AS {k['key']}" for k in KPIS)
    sql = f"""
SELECT x.month_id AS month_id, t.region AS region,
  {sums}
FROM {_MTD} x
LEFT JOIN {_TERR} t ON x.kec_id = t.kec_id
WHERE t.circle = '{CIRCLE}' AND t.region IS NOT NULL
  AND x.month_id BETWEEN {months[0]} AND {months[-1]}
GROUP BY month_id, region
"""
    return run_query(sql, row_limit=2000)["rows"]


def _availability(months: list[int]) -> dict:
    """{(level, name): {month_id: {"avail": pct, "below_sla": n}}}; empty when the table is unavailable."""
    try:
        rows = run_query(f"""
SELECT territory_level, territory_name, CAST(month_id AS INT64) AS month_id,
  mean_avg_avail_pct_4g AS avail, sites_below_sla99_4g AS below_sla
FROM {_AVAIL}
WHERE territory_level IN ('circle', 'region')
  AND CAST(month_id AS INT64) BETWEEN {months[0]} AND {months[-1]}
""", row_limit=2000)["rows"]
    except Exception:
        return {}
    out: dict = {}
    for r in rows:
        key = (str(r["territory_level"]).lower(), str(r["territory_name"]).upper())
        out.setdefault(key, {})[int(r["month_id"])] = {
            "avail": float(r["avail"]) if r.get("avail") is not None else None,
            "below_sla": int(r["below_sla"] or 0) if r.get("below_sla") is not None else None,
        }
    return out


_DUMP_KEYS = {"revenue": "revenue", "subs": "subs", "payload": "payload_gb", "gross_add": "gross_add"}


def _from_dump(spark_n: int):
    """(latest, months, region-month rows, availability, daily rows, status) from the
    Performance dump, or None when it is missing or stale."""
    st = perf_dump.status()
    kec = perf_dump.load("kec_month") if st.get("fresh") else None
    if not kec:
        return None
    latest = int(st.get("latest_month") or max(int(r["month_id"]) for r in kec))
    months = [month_add(latest, -i) for i in range(spark_n - 1, -1, -1)]
    agg: dict = {}
    for r in kec:
        m = int(r["month_id"])
        if m not in months or not r.get("region"):
            continue
        a = agg.setdefault((m, r["region"]), {"month_id": m, "region": r["region"], **{k: 0.0 for k in _DUMP_KEYS}})
        for k, col in _DUMP_KEYS.items():
            a[k] += float(r.get(col) or 0)
    avail: dict = {}
    for r in perf_dump.load("avail_month") or []:
        if r.get("level") in ("circle", "region"):
            avail.setdefault((r["level"], str(r["name"]).upper()), {})[int(r["month_id"])] = {
                "avail": r.get("avail"), "below_sla": int(r["below_sla"]) if r.get("below_sla") is not None else None}
    return latest, months, list(agg.values()), avail, perf_dump.load("region_daily") or [], st


def _daily_spark(daily: list[dict], scope: list[str], key: str, n: int = 10):
    """Last n days of one KPI for the scope regions: (values, labels) or (None, None)."""
    col = _DUMP_KEYS.get(key)
    if not daily or not col:
        return None, None
    by: dict = {}
    scope_u = {s.upper() for s in scope}
    for r in daily:
        if str(r.get("region") or "").upper() in scope_u and r.get(col) is not None:
            d = str(r["dt_id"])[:10]
            by[d] = by.get(d, 0.0) + float(r[col])
    days = sorted(by)[-n:]
    if len(days) < 2:
        return None, None
    return [by[d] for d in days], [f"{int(d[8:10])} {MONTHS_ID[int(d[5:7]) - 1]}" for d in days]


def build_overview(region: str = "", months_back: int = 6) -> dict:
    spark_n = 12
    dump = _from_dump(spark_n)
    if dump:
        latest, months, rows, avail, daily, st = dump
        source = {"kind": "dump", "label": st["label"], "created_at": st["created_at"]}
    else:
        latest = int(run_query(f"SELECT MAX(month_id) AS m FROM {_MTD}")["rows"][0]["m"])
        months = [month_add(latest, -i) for i in range(spark_n - 1, -1, -1)]
        rows = _region_month_rows(months)
        avail = _availability(months)
        daily = []
        st = perf_dump.status()
        source = {"kind": "bigquery", "label": "BigQuery langsung" + (" (dump terlambat)" if st.get("available") else ""),
                  "created_at": None}

    regions = sorted({r["region"] for r in rows})
    scope = [rg for rg in regions if not region or rg.upper() == region.upper()]

    def val(rg: str, mid: int, key: str) -> float:
        return sum(float(r.get(key) or 0) for r in rows if r["region"] == rg and int(r["month_id"]) == mid)

    def total(mid: int, key: str, regs=None) -> float:
        return sum(val(rg, mid, key) for rg in (regs if regs is not None else scope))

    prev = month_add(latest, -1)
    all_targets = _load_targets()
    kpis = []
    for k in KPIS:
        cur, last = total(latest, k["key"]), total(prev, k["key"])
        tg = all_targets.get(k["key"]) or {}
        tvals = [tg.get(rg) or tg.get(rg.upper()) for rg in scope]
        dvals, dlabels = _daily_spark(daily, scope, k["key"])
        kpis.append({
            "key": k["key"], "label": k["label"], "format": k["format"], "icon": k["icon"],
            "value": cur, "prev": last, "pct_change": _pct(cur, last),
            "spark": [total(m, k["key"]) for m in months],
            "spark_daily": dvals, "spark_daily_labels": dlabels,
            "target": sum(tvals) if tvals and all(tvals) else None,
            "note_prev_label": month_label(prev),
        })

    # Site availability (4G) as the fourth card when the table has data.
    av_key = ("region", region.upper()) if region else ("circle", CIRCLE)
    av_series = avail.get(av_key, {})
    if av_series.get(latest, {}).get("avail") is not None:
        a_cur = av_series[latest]["avail"]
        a_prev = av_series.get(prev, {}).get("avail")
        kpis[-1] = {
            "key": "availability", "label": "Site availability", "format": "percent", "icon": "radio",
            "value": a_cur, "prev": a_prev,
            "pct_change": (a_cur - a_prev) if a_prev is not None else None, "change_unit": "pp",
            "spark": [av_series.get(m, {}).get("avail") for m in months],
            "target": 99.5, "below_sla": av_series[latest].get("below_sla"),
            "note_prev_label": month_label(prev),
        }

    chart_months = months[-months_back:]
    targets = _load_targets().get("revenue", {})
    java_rev = total(latest, "revenue", regions)
    region_rows = []
    for rg in regions:
        rev, rev_prev = val(rg, latest, "revenue"), val(rg, prev, "revenue")
        tgt = targets.get(rg) or targets.get(rg.upper())
        a = avail.get(("region", rg.upper()), {}).get(latest, {})
        region_rows.append({
            "region": rg,
            "revenue": rev, "revenue_prev": rev_prev, "mom_pct": _pct(rev, rev_prev),
            "subs": val(rg, latest, "subs"), "payload_gb": val(rg, latest, "payload"),
            "gross_add": val(rg, latest, "gross_add"),
            "availability": a.get("avail"),
            "achievement_pct": (rev / tgt * 100) if tgt else None,
            "share_pct": (rev / java_rev * 100) if java_rev else None,
            "spark": [val(rg, m, "revenue") for m in chart_months],
        })
    region_rows.sort(key=lambda r: r["revenue"], reverse=True)

    return {
        "month_id": latest,
        "month_label": month_label(latest, True),
        "prev_label": month_label(prev),
        "months": months,
        "month_labels": [month_label(m) for m in months],
        "scope": {"circle": CIRCLE, "region": region or None, "regions": regions},
        "data_as_of": reports_cache.data_marker("highlevel"),
        "kpis": kpis,
        "revenue_by_region": {
            "months": chart_months,
            "labels": [month_label(m) for m in chart_months],
            "series": [{"name": r["region"], "values": r["spark"]} for r in region_rows],
        },
        "regions": region_rows,
        "has_targets": bool(targets),
        "summary": _summary(kpis, region_rows, region),
        "source": source,
        "kabupaten_count": len({(r.get("kabupaten"), r.get("provinsi")) for r in (perf_dump.load("kec_month") or [])
                                if int(r["month_id"]) == latest and r.get("kabupaten")}) or None,
    }


def _fmt_pct(p: Optional[float]) -> str:
    return "–" if p is None else f"{abs(p):.1f}".replace(".", ",") + "%"


def _summary(kpis: list[dict], regions: list[dict], region: str) -> dict:
    """Short agent-style briefing for the hero card, built from the numbers."""
    rev = next((k for k in kpis if k["key"] == "revenue"), None)
    scope = region.title() if region else "Circle Java"
    parts, highlights = [], []
    movers = [r for r in regions if r["mom_pct"] is not None]
    if rev and rev["pct_change"] is not None:
        up = rev["pct_change"] >= 0
        verb = "naik" if up else "turun"
        lead = ""
        if movers and not region:
            pick = max(movers, key=lambda r: r["mom_pct"]) if up else min(movers, key=lambda r: r["mom_pct"])
            lead = f", ditopang {pick['region'].title()}" if up else f", terutama dari {pick['region'].title()}"
        parts.append(f"Revenue {scope} **{verb} {_fmt_pct(rev['pct_change'])} MoM**{lead}.")
    weak = [k for k in kpis if k["key"] != "revenue" and k["pct_change"] is not None and k["pct_change"] < 0]
    if weak:
        names = " dan ".join(
            f"**{k['label'].lower()} turun {_fmt_pct(k['pct_change'])}**".replace("%", " pp" if k.get("change_unit") == "pp" else "%")
            for k in weak[:2])
        parts.append(f"Perlu perhatian: {names}.")
        highlights = [k["key"] for k in weak]
    if rev and rev["pct_change"] is not None and rev["pct_change"] >= 0 and not region:
        worst = min(movers, key=lambda r: r["mom_pct"], default=None)
        if worst and worst["mom_pct"] < 0:
            parts.append(f"Revenue **{worst['region'].title()}** masih turun {_fmt_pct(worst['mom_pct'])}.")
    return {"text": " ".join(parts) or "Data bulan ini belum cukup untuk ringkasan.", "attention": highlights}


@router.get("/overview")
def overview(
    region: str = Query("", description="Region name; empty = all of Java"),
    months: int = Query(6, ge=3, le=12),
    refresh: bool = Query(False),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    key = f"{_esc(region)}|{months}"
    try:
        data = reports_cache.get_or_build("dashboard", key, lambda: build_overview(_esc(region), months), force=refresh)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
    if isinstance(data, dict) and "error" not in data:
        data = {**data, "activity": _activity(db)}
    return data


def _activity(db: Session) -> dict:
    """Agent usage today (WIB) for the hero stats."""
    now = datetime.now(timezone.utc)
    wib_midnight = (now + timedelta(hours=7)).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(hours=7)
    since = wib_midnight.replace(tzinfo=None)
    q = db.query(UsageLog).filter(UsageLog.created_at >= since, UsageLog.action == "query")
    week = since - timedelta(days=6)
    answers = db.query(ChatMessage).filter(ChatMessage.role == "assistant", ChatMessage.created_at >= week)
    total_answers = answers.count()
    failed = answers.filter(ChatMessage.content.like("[ERROR]%")).count()
    return {
        "questions_today": q.count(),
        "active_users_today": q.with_entities(UsageLog.user_id).distinct().count(),
        "date": date.today().isoformat(),
        # share of agent answers in the last 7 days that passed validation (no error turn)
        "validation_pct": round((total_answers - failed) / total_answers * 100, 1) if total_answers else None,
        "answers_7d": total_answers,
    }
