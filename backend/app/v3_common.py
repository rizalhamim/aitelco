"""Shared data layer for the Agent Java v3 features (Diagnosa, Klasemen, Brief Pagi,
Simulasi Target, Ruang Saya, Tindak Lanjut).

Every number comes from the daily Performance dump (perf_dump.py). Without a dump on
disk the dump queries run live on BigQuery once and are kept for LIVE_TTL, like the
Performance page. Nothing here calls an LLM: sentences are templates over computed
numbers, so answers are fast and repeatable.

Comparison bases (written on every screen):
    month   latest complete month vs the month before (full months)
    mtd     day 1 to the latest dumped day vs the same days last month (apple-to-apple)
"""
from __future__ import annotations

import calendar
import json
import os
import re
import threading
import time
from datetime import date, datetime, timedelta, timezone
from typing import Iterable, Optional

from . import perf_dump

WIB = timezone(timedelta(hours=7))
LIVE_TTL = 6 * 3600
MONTHS = perf_dump.MONTHS_ID
MONTHS_LONG = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"]
DAYS = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"]
MINUS = "−"

REGIONS = ["EAST JAVA", "CENTRAL JAVA", "WEST JAVA"]
REGION_LABEL = {"EAST JAVA": "East Java", "CENTRAL JAVA": "Central Java", "WEST JAVA": "West Java", "JAVA": "Circle Java"}
REGION_COLOR = {"EAST JAVA": "#0E8579", "CENTRAL JAVA": "#22B8C9", "WEST JAVA": "#6A4CB5"}

METRICS = {
    "revenue": {"label": "Revenue", "unit": "IDR", "col": "revenue", "flow": True},
    "payload": {"label": "Payload", "unit": "GB", "col": "payload_gb", "flow": True},
    "subs": {"label": "RGU 90D", "unit": "subs", "col": "subs", "flow": False},
    "gross_add": {"label": "Gross add", "unit": "subs", "col": "gross_add", "flow": True},
    "fwa_gross_add": {"label": "Gross add FWA", "unit": "subs", "col": "fwa_gross_add", "flow": True},
}

LOWER = {"revenue": "revenue", "payload": "payload", "subs": "RGU 90D", "gross_add": "gross add", "fwa_gross_add": "gross add FWA"}


def lower_label(metric: str) -> str:
    """Label inside a sentence: "gross add FWA", never "gross add fwa"."""
    return LOWER.get(metric, METRICS.get(metric, {}).get("label", metric).lower())


_TARGETS = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "targets.json")

_live: dict = {}
_live_lock = threading.Lock()


# ── Names and formats ───────────────────────────────────────────────────────

def norm(name: Optional[str]) -> str:
    """Comparable area name: "KAB. GARUT", "Kabupaten Garut" and "garut" all become "GARUT"."""
    s = re.sub(r"\s+", " ", str(name or "").upper()).strip()
    return re.sub(r"^(KABUPATEN|KAB\.?)\s+", "", s)


def title(name: Optional[str]) -> str:
    s = " ".join(w.capitalize() for w in norm(name).lower().split())
    return re.sub(r"\bDiy\b", "DIY", s)


def region_label(r: Optional[str]) -> str:
    return REGION_LABEL.get(norm(r), title(r))


def num(v: float, d: int = 1) -> str:
    """Indonesian number: 1234.5 -> "1.234,5"; the minus sign is U+2212."""
    s = f"{abs(v):,.{d}f}".replace(",", "_").replace(".", ",").replace("_", ".")
    return (MINUS if v < 0 and round(abs(v), d) else "") + s


def pct(v: Optional[float], d: int = 1, sign: bool = True) -> str:
    if v is None:
        return "–"
    return ("+" if sign and v > 0 and round(v, d) else "") + num(v, d) + "%"


def rp(v: Optional[float], sign: bool = False) -> str:
    """"Rp 1,87 T", "Rp 10,1 M", "Rp 25 jt"; sign adds +/− in front."""
    if v is None:
        return "–"
    pre = ("+" if v > 0 else MINUS if v < 0 else "") if sign else (MINUS if v < 0 else "")
    a = abs(v)
    for div, unit, d in ((1e12, "T", 2), (1e9, "M", 1), (1e6, "jt", 0)):
        if a >= div * (0.995 if d == 2 else 0.95):
            return f"{pre}Rp {num(a / div, d)} {unit}"
    return f"{pre}Rp {num(a, 0)}"


def rp_m(v: Optional[float], d: int = 1, sign: bool = False) -> str:
    """Always in Rp miliar: "Rp 0,4 M"."""
    if v is None:
        return "–"
    pre = ("+" if v > 0 else MINUS if v < 0 else "") if sign else (MINUS if v < 0 else "")
    return f"{pre}Rp {num(abs(v) / 1e9, d)} M"


def fmt_value(metric: str, v: Optional[float]) -> str:
    if v is None:
        return "–"
    unit = METRICS.get(metric, {}).get("unit")
    if unit == "IDR":
        return rp(v)
    if unit == "GB":
        if abs(v) >= 1e6:
            return f"{num(v / 1e6, 2)} PB"
        if abs(v) >= 1e3:
            return f"{num(v / 1e3, 1)} TB"
        return f"{num(v, 1)} GB"
    if abs(v) >= 1e6:
        return f"{num(v / 1e6, 1)} jt"
    return num(v, 0)


def fmt_delta(metric: str, v: Optional[float]) -> str:
    if v is None:
        return "–"
    unit = METRICS.get(metric, {}).get("unit")
    if unit == "IDR":
        return rp_m(v, sign=True)
    return ("+" if v > 0 else MINUS if v < 0 else "") + fmt_value(metric, abs(v))


def growth(cur: Optional[float], prev: Optional[float]) -> Optional[float]:
    if cur is None or not prev:
        return None
    return (cur / prev - 1) * 100


def day_label(d: date) -> str:
    return f"{d.day} {MONTHS[d.month - 1]}"


def month_label(mid: int, year: bool = True, long: bool = False) -> str:
    y, m = divmod(int(mid), 100)
    name = (MONTHS_LONG if long else MONTHS)[m - 1]
    return f"{name} {y}" if year else name


def month_of(d: date) -> int:
    return d.year * 100 + d.month


def days_in(mid: int) -> int:
    y, m = divmod(int(mid), 100)
    return calendar.monthrange(y, m)[1]


def today_wib() -> date:
    return datetime.now(WIB).date()


def seg(*parts) -> list[dict]:
    """Rich text as segments: plain strings, ("b", text) lime, ("e", text) peach."""
    out = []
    for p in parts:
        if isinstance(p, tuple):
            out.append({"t": p[1], "s": p[0]})
        elif p:
            out.append({"t": p})
    return out


def plain(segs: list[dict]) -> str:
    return "".join(s["t"] for s in segs)


# ── Targets ─────────────────────────────────────────────────────────────────

def load_targets() -> dict:
    """data/targets.json: {"revenue": {"EAST JAVA": idr_per_month, ...}, "gross_add": {...},
    optional "kabupaten": {"revenue": {"GARUT": ...}}, optional "new_site_revenue": idr}."""
    try:
        with open(_TARGETS, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def region_target(targets: dict, metric: str, region: str) -> Optional[float]:
    tg = targets.get(metric) or {}
    v = tg.get(norm(region)) or tg.get(region) or tg.get(region_label(region))
    return float(v) if v else None


# ── Data source ─────────────────────────────────────────────────────────────

def _live_tables() -> dict:
    with _live_lock:
        if _live and time.time() - _live["at"] < LIVE_TTL:
            return _live
    from .bigquery_tool import run_query
    latest = perf_dump._latest_month()
    qs = perf_dump.build_queries(latest, perf_dump._latest_day(), perf_dump._columns, perf_dump._column_types)
    out = {"at": time.time(), "latest": latest}
    for name, sql in qs.items():
        try:
            out[name] = run_query(sql, row_limit=perf_dump._ROW_CAP)["rows"]
        except Exception:
            out[name] = []
    with _live_lock:
        _live.clear()
        _live.update(out)
    return out


def tables(*names: str) -> tuple[dict, dict]:
    """({name: rows}, source) from the dump, or from live BigQuery when no dump exists."""
    st = perf_dump.status()
    if st.get("available") and perf_dump.load("kec_month", allow_stale=True):
        out = {n: perf_dump.load(n, allow_stale=True) or [] for n in names}
        created = datetime.fromisoformat(st["created_at"])
        return out, {"kind": "dump" if st.get("fresh") else "stale", "label": st.get("label"),
                     "label_wib": (st.get("label") or "") + " WIB", "short": "Dump " + day_label(created.astimezone(WIB).date()),
                     "created_at": st.get("created_at"), "age_hours": st.get("age_hours")}
    live = _live_tables()
    at = datetime.fromtimestamp(live["at"], timezone.utc)
    return ({n: live.get(n) or [] for n in names},
            {"kind": "bigquery", "label": "BigQuery langsung", "label_wib": "BigQuery langsung", "short": "BigQuery",
             "created_at": at.isoformat()})


def as_date(v) -> date:
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    return date.fromisoformat(str(v)[:10])


def f(v) -> float:
    try:
        return float(v) if v is not None else 0.0
    except (TypeError, ValueError):
        return 0.0


# ── Daily windows ───────────────────────────────────────────────────────────

class Window:
    """MTD (day 1..D of the latest month) and LMTD (same days of the month before)."""

    def __init__(self, last: date):
        self.last = last
        self.cur0 = last.replace(day=1)
        lm_end = self.cur0 - timedelta(days=1)
        self.lm0 = lm_end.replace(day=1)
        self.lm_last = self.lm0.replace(day=min(last.day, lm_end.day))
        self.month = month_of(last)
        self.days = last.day
        self.dim = days_in(self.month)
        self.remaining = self.dim - self.days

    def label(self) -> str:
        """"MTD 1 sd 4 Nov vs LMTD 1 sd 4 Okt"."""
        return (f"MTD 1 sd {self.last.day} {MONTHS[self.last.month - 1]} vs "
                f"LMTD 1 sd {self.lm_last.day} {MONTHS[self.lm_last.month - 1]}")

    def in_cur(self, d: date) -> bool:
        return self.cur0 <= d <= self.last

    def in_prev(self, d: date) -> bool:
        return self.lm0 <= d <= self.lm_last


def last_day(rows: Iterable[dict]) -> Optional[date]:
    best = None
    for r in rows:
        if r.get("dt_id") is None:
            continue
        d = as_date(r["dt_id"])
        if best is None or d > best:
            best = d
    return best


def complete_month(latest: int, last: Optional[date]) -> int:
    """Latest month with full data: the month before when the latest one is still running."""
    ref = last or today_wib()
    if month_of(ref) == latest and ref.day < days_in(latest):
        return perf_dump.month_add(latest, -1)
    if month_of(ref) < latest:  # dump month ahead of the daily table: treat as running
        return perf_dump.month_add(latest, -1)
    return latest


def mtd_sums(daily: list[dict], win: Window, key, col: str, flow: bool = True) -> dict:
    """{group: (mtd, lmtd)} for one measure; stock measures take the last day of each window."""
    out: dict = {}
    for r in daily:
        d = as_date(r["dt_id"])
        g = key(r)
        if g is None:
            continue
        cur, prev = out.get(g, (0.0, 0.0))
        v = f(r.get(col))
        if win.in_cur(d) and (flow or d == win.last):
            cur += v
        elif win.in_prev(d) and (flow or d == win.lm_last):
            prev += v
        out[g] = (cur, prev)
    return out


def daily_series(daily: list[dict], col: str, keep=lambda r: True) -> dict[date, float]:
    s: dict[date, float] = {}
    for r in daily:
        if keep(r):
            d = as_date(r["dt_id"])
            s[d] = s.get(d, 0.0) + f(r.get(col))
    return s


def has_col(rows: list[dict], col: str) -> bool:
    return any(r.get(col) is not None for r in rows[:200])
