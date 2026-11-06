"""Brief Pagi: a personal morning brief at 06.00 WIB.

GET  /api/brief                    the brief for the signed-in user (built on request, cached per day)
POST /api/brief/prefs              {topics, regions, push, email}
POST /api/brief/feedback           {vote: up|down}
POST /api/brief/open               {story}: a card was opened (orders future cards)

Numbers come from the dump (MTD vs LMTD on the same days); the sentences are templates
over those numbers, so the brief is the same every time it is opened that day. Three
stories are picked: the biggest fall that needs action, the metric furthest behind its
target run-rate, and the best news. send_due() (hourly from main.py) writes the 06.00
notification, Monday to Saturday, which the Android app shows on the lock screen.
"""
from __future__ import annotations

import json
import logging
from datetime import date, datetime, timedelta, timezone
from statistics import mean
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from . import perf_dump
from .auth import get_current_user
from .database import BriefLog, Notification, ReportSchedule, SessionLocal, Task, User, WatchAlert, get_db
from .simulasi import forecast
from .v3_common import (DAYS, METRICS, MONTHS, REGIONS, WIB, Window, as_date, daily_series, f, fmt_value, growth,
                        last_day, load_targets, lower_label, month_label, norm, num, pct, plain, region_label, region_target, rp, seg,
                        tables, title, today_wib)

log = logging.getLogger("brief")
router = APIRouter(prefix="/api/brief", tags=["brief"])

SEND_HOUR = 6
TOPICS = {"perf": "Performance", "prod": "Site productivity", "prof": "Profile wilayah", "ftth": "FTTH"}
DEFAULT_PREFS = {"topics": ["perf", "prod", "prof"], "regions": ["JAVA"], "send": True, "push": True, "email": False}
TONE = {"k": "Perlu tindakan", "w": "Waspada", "g": "Kabar baik"}
COUNT_WORD = {1: "Satu", 2: "Dua", 3: "Tiga", 4: "Empat", 5: "Lima"}


def prefs_of(user: User) -> dict:
    try:
        p = json.loads(user.preferences or "{}")
    except (TypeError, ValueError):
        p = {}
    b = p.get("brief") if isinstance(p.get("brief"), dict) else {}
    return {**DEFAULT_PREFS, **b}


def _save_prefs(db: Session, user: User, brief: dict):
    try:
        p = json.loads(user.preferences or "{}")
    except (TypeError, ValueError):
        p = {}
    p["brief"] = brief
    user.preferences = json.dumps(p)
    db.commit()


def _focus(prefs: dict) -> list[str]:
    regs = [norm(r) for r in prefs.get("regions") or [] if norm(r) in REGIONS]
    return regs or list(REGIONS)


def _fmt_count(v: float) -> str:
    return num(v, 0)


# ── Stories ─────────────────────────────────────────────────────────────────

def _streak(series: dict, win: Window) -> int:
    """Consecutive latest days below the same day last month."""
    n = 0
    d = win.last
    while d >= win.cur0:
        try:
            lm = win.lm0.replace(day=d.day)
        except ValueError:
            break
        if d in series and lm in series and series[d] < series[lm]:
            n += 1
            d -= timedelta(days=1)
        else:
            break
    return n


def _last(series: dict, last: date, n: int = 10) -> list[float]:
    return [series.get(last - timedelta(days=i), 0.0) for i in range(n - 1, -1, -1)]


def _story_fall(t: dict, win: Window, focus: list[str], topics: list[str]) -> Optional[dict]:
    kd = [r for r in t.get("kab_daily") or [] if norm(r.get("region")) in focus]
    if not kd or "perf" not in topics:
        return None
    best = None
    kabs = {norm(r["kabupaten"]) for r in kd if r.get("kabupaten")}
    rev_all = []
    for k in kabs:
        rows = [r for r in kd if norm(r.get("kabupaten")) == k]
        for metric in ("payload", "revenue"):
            col = METRICS[metric]["col"]
            s = daily_series(rows, col)
            cur = sum(v for d, v in s.items() if win.in_cur(d))
            prev = sum(v for d, v in s.items() if win.in_prev(d))
            g = growth(cur, prev)
            rs = daily_series(rows, "revenue")
            rcur = sum(v for d, v in rs.items() if win.in_cur(d))
            rprev = sum(v for d, v in rs.items() if win.in_prev(d))
            rev_all.append(rprev)
            if g is None or g >= -3:
                continue
            impact = abs(rcur - rprev) if metric == "revenue" else abs(g) / 100 * rprev
            if best is None or impact > best["impact"]:
                best = {"kab": k, "metric": metric, "g": g, "impact": impact, "series": s, "rows": rows, "region": norm(rows[0].get("region")), "rprev": rprev}
    if not best:
        return None
    med = sorted(rev_all)[len(rev_all) // 2] if rev_all else 0
    if best["rprev"] < med * 0.2:
        return None
    k, metric = best["kab"], best["metric"]
    name = title(k)
    streak = _streak(best["series"], win)
    label = METRICS[metric]["label"]
    head = f"{label} {name} turun {streak} hari berturut-turut" if streak >= 3 else f"{label} {name} turun {pct(abs(best['g']))} MTD"
    # kecamatan behind the fall
    col = METRICS[metric]["col"]
    kc: dict = {}
    for r in t.get("kec_mtd") or []:
        if norm(r.get("kabupaten")) != k:
            continue
        c, p = kc.get(r.get("kecamatan"), (0.0, 0.0))
        if r.get("period") == "mtd":
            c += f(r.get(col))
        else:
            p += f(r.get(col))
        kc[r.get("kecamatan")] = (c, p)
    deltas = sorted(((c - p) for c, p in kc.values()))
    total = sum(deltas)
    take, acc = 0, 0.0
    for d in deltas:
        if d >= 0 or take >= 3:
            break
        take += 1
        acc += d
        if total and acc / total >= .7:
            break
    text = f"{take} kecamatan menyumbang {round(acc / total * 100)}% penurunan. " if take and total < 0 else ""
    av = [r for r in t.get("avail_month") or [] if r.get("level") == "kabkot" and norm(r.get("name")) == k and r.get("avail") is not None]
    if av:
        a = float(max(av, key=lambda r: int(r["month_id"]))["avail"])
        text += ("Availability normal, jadi kemungkinan bukan gangguan jaringan." if a >= 99.5
                 else f"Availability {num(a, 2)}%, cek gangguan jaringan.")
    return {"tone": "k", "topic": "Performance", "metric": metric, "title": head, "value": best["g"], "value_label": pct(best["g"]),
            "value_note": "MTD vs LMTD", "spark": _last(best["series"], win.last), "text": text.strip(),
            "peek": f"{name} {pct(best['g'])} MTD", "short_title": f"{label} {name}",
            "region": best["region"], "kabupaten": k, "impact": best["impact"],
            "diagnosa": {"metric": metric, "region": best["region"], "kabupaten": k, "basis": "mtd"},
            "pin": {"kind": "chart", "title": f"{label} harian {name}", "subtitle": f"{month_label(win.month, year=False)} MTD vs {month_label(perf_dump.month_add(win.month, -1), year=False)}",
                    "spec": {"type": "daily_compare", "metric": metric, "kabupaten": k}, "origin": "brief"},
            "task": {"title": f"Cek {label.lower()} {name}", "origin": "brief", "region": best["region"], "kabupaten": k,
                     "kpi": {"metric": metric, "mode": "change", "op": ">=", "threshold": -3, "level": "kabupaten", "name": k}}}


def _story_runrate(t: dict, win: Window, focus: list[str], targets: dict) -> Optional[dict]:
    worst = None
    for metric in ("fwa_gross_add", "gross_add", "revenue"):
        col = METRICS[metric]["col"]
        for rg in focus:
            tg = region_target(targets, metric, rg)
            if not tg:
                continue
            rows = [r for r in (t.get("kab_daily") if metric == "fwa_gross_add" else (t.get("region_daily") or t.get("kab_daily"))) or []
                    if norm(r.get("region")) == rg]
            s = daily_series(rows, col)
            if not s:
                continue
            mtd = sum(v for d, v in s.items() if win.in_cur(d))
            ach = mtd / win.days * win.dim / tg * 100
            if ach >= 95 or (worst and ach >= worst["ach"]):
                continue
            daily_tg = tg / win.dim
            spark = []
            for i in range(9, -1, -1):
                d = win.last - timedelta(days=i)
                wk = [s.get(d - timedelta(days=j)) for j in range(7)]
                wk = [v for v in wk if v is not None]
                spark.append(mean(wk) / daily_tg * 100 if wk else 0)
            need = (tg - mtd) / win.remaining if win.remaining else 0
            recent = [s.get(win.last - timedelta(days=j)) for j in range(min(win.days, 4))]
            recent = [v for v in recent if v is not None]
            avg = mean(recent) if recent else 0
            worst = {"metric": metric, "region": rg, "ach": ach, "need": need, "avg": avg, "spark": spark, "n": len(recent)}
    if not worst:
        return None
    metric, rg = worst["metric"], worst["region"]
    label = METRICS[metric]["label"]
    unit_idr = METRICS[metric]["unit"] == "IDR"
    fmt = rp if unit_idr else _fmt_count
    mon = MONTHS[win.month % 100 - 1]
    return {"tone": "w", "topic": "Performance", "metric": metric, "title": f"{label} {region_label(rg)} di bawah run-rate",
            "value": worst["ach"], "value_label": f"{round(worst['ach'])}%", "value_note": "dari run-rate target",
            "spark": worst["spark"], "short_title": label,
            "text": f"Perlu {fmt(worst['need'])} {'' if unit_idr else lower_label(metric) + ' '}per hari sampai {win.dim} {mon} untuk menutup gap. "
                    f"Rata-rata {worst['n']} hari terakhir {fmt(worst['avg'])} per hari.",
            "peek": f"{label} {region_label(rg)} {round(worst['ach'])}% dari run-rate",
            "region": rg, "kabupaten": None, "impact": 0, "simulasi": {"metric": metric, "region": rg},
            "diagnosa": {"metric": "revenue" if metric == "revenue" else "subs", "region": rg, "basis": "mtd"},
            "pin": {"kind": "kpi", "title": f"Simulasi {label} {region_label(rg)}", "subtitle": "Estimasi akhir bulan",
                    "spec": {"type": "simulasi", "metric": metric, "region": rg}, "origin": "brief"},
            "task": {"title": f"Kejar {label.lower()} {region_label(rg)}", "origin": "brief", "region": rg,
                     "kpi": {"metric": metric, "mode": "per_day", "op": ">=", "threshold": round(worst["need"]), "level": "region", "name": rg}}}


def _story_good(t: dict, win: Window, focus: list[str]) -> Optional[dict]:
    rd = t.get("region_daily") or []
    best = None
    worst = None
    for rg in REGIONS:
        s = daily_series(rd, "revenue", lambda r, rg=rg: norm(r.get("region")) == rg)
        cur = sum(v for d, v in s.items() if win.in_cur(d))
        prev = sum(v for d, v in s.items() if win.in_prev(d))
        g = growth(cur, prev)
        if g is None:
            continue
        if rg in focus and (best is None or g > best["g"]):
            best = {"region": rg, "g": g, "series": s}
        if worst is None or g < worst["g"]:
            worst = {"region": rg, "g": g}
    if not best or best["g"] <= 0:
        return None
    kd = [r for r in t.get("kab_daily") or [] if norm(r.get("region")) == best["region"]]
    kabs = {}
    for r in kd:
        d = as_date(r["dt_id"])
        c, p = kabs.get(norm(r["kabupaten"]), (0.0, 0.0))
        if win.in_cur(d):
            c += f(r.get("revenue"))
        elif win.in_prev(d):
            p += f(r.get("revenue"))
        kabs[norm(r["kabupaten"])] = (c, p)
    top = sorted((k for k, (c, p) in kabs.items() if p), key=lambda k: kabs[k][0] / kabs[k][1], reverse=True)[:2]
    text = f"{' dan '.join(title(k) for k in top)} naik paling tinggi." if top else ""
    if worst and worst["region"] != best["region"]:
        text += f" Pola yang sama bisa diuji di {region_label(worst['region'])}."
    rg = best["region"]
    return {"tone": "g", "topic": "Revenue", "metric": "revenue", "title": f"{region_label(rg)} memimpin pertumbuhan revenue",
            "value": best["g"], "value_label": pct(best["g"]), "value_note": "MTD vs LMTD", "spark": _last(best["series"], win.last),
            "text": text.strip(), "peek": f"{region_label(rg)} {pct(best['g'])} vs LMTD", "short_title": "Revenue",
            "region": rg, "kabupaten": None, "impact": 0,
            "diagnosa": {"metric": "revenue", "region": rg, "basis": "mtd"},
            "pin": {"kind": "chart", "title": f"Revenue harian {region_label(rg)}", "subtitle": f"{month_label(win.month, year=False)} MTD vs {month_label(perf_dump.month_add(win.month, -1), year=False)}",
                    "spec": {"type": "daily_compare", "metric": "revenue", "region": rg}, "origin": "brief"},
            "task": {"title": f"Uji pola {region_label(rg)} di {region_label(worst['region']) if worst else 'region lain'}", "origin": "brief",
                     "region": worst["region"] if worst else rg, "kpi": {"metric": "revenue", "mode": "change", "op": ">=", "threshold": 2, "level": "region",
                                                                        "name": worst["region"] if worst else rg}}}


# ── Targets ─────────────────────────────────────────────────────────────────

def _target_bars(t: dict, win: Window, focus: list[str], targets: dict) -> tuple[list[dict], Optional[list]]:
    bars = []
    say = None
    specs = [("revenue", "Revenue", "#0E8579"), ("subs", "Pelanggan aktif", "#22B8C9"), ("fwa_gross_add", "Gross add FWA", "#F5A623"),
             ("gross_add", "Gross add", "#F5A623")]
    for metric, label, color in specs:
        tvals = [region_target(targets, metric, r) for r in focus]
        if not tvals or not all(tvals):
            continue
        tg = sum(tvals)
        col = METRICS[metric]["col"]
        rows = [r for r in ((t.get("kab_daily") if metric == "fwa_gross_add" else (t.get("region_daily") or t.get("kab_daily"))) or [])
                if norm(r.get("region")) in focus]
        s = daily_series(rows, col)
        if not s:
            continue
        if METRICS[metric]["flow"]:
            fc = forecast(s, win.last)
            mid, lo, hi, real = fc["estimate"], fc["lo"], fc["hi"], fc["mtd"]
        else:
            real = s.get(win.last, 0.0)
            prev = s.get(win.last - timedelta(days=7))
            slope = (real - prev) / 7 if prev else 0.0
            mid = real + slope * win.remaining
            lo = hi = mid
        p_mid, p_lo, p_hi = mid / tg * 100, lo / tg * 100, hi / tg * 100
        fmt = (lambda v: rp(v)) if METRICS[metric]["unit"] == "IDR" else (lambda v: fmt_value(metric, v))
        if METRICS[metric]["flow"]:
            note = (f"Realisasi MTD {fmt(real)} · " if metric == "revenue" else "") + \
                   f"{'proyeksi' if metric == 'revenue' else 'Proyeksi'} {num(p_mid, 1)}% (rentang {num(p_lo, 1 if metric == 'revenue' else 0)}% sd {num(p_hi, 1 if metric == 'revenue' else 0)}%)"
        else:
            note = f"Proyeksi {num(p_mid, 1)}%" + (" · sudah di atas target" if p_mid >= 100 else "")
        warn = p_mid < 95
        bars.append({"metric": metric, "label": label, "value_label": f"{fmt(mid)} dari {fmt(tg)}",
                     "real_pct": min(real / tg * 100, 100), "band_pct": min(p_hi, 100), "tick_pct": min(p_mid, 100),
                     "color": "#F5A623" if warn and metric != "revenue" else color, "note": note, "pct": p_mid})
        if metric == "revenue" and win.remaining:
            need = (tg - real) / win.remaining
            per_day = real / win.days
            gap = mid - tg
            mon = MONTHS[win.month % 100 - 1]
            say = seg(("b", "Kata agent:"), f" Revenue perlu {rp(need)} per hari sampai {win.dim} {mon}, "
                      f"{'di atas' if need > per_day else 'di bawah'} rata-rata {win.days} hari terakhir {rp(per_day)}. "
                      f"Estimasi akhir bulan {rp(mid)}, {'gap' if gap < 0 else 'lebih'} sekitar {rp(abs(gap))}. Ini estimasi, bukan realisasi.")
    return bars[:3], say


# ── Agenda ──────────────────────────────────────────────────────────────────

def _agenda(db: Session, user: User, today: date) -> list[dict]:
    out = []
    users = {}
    tasks = db.query(Task).filter(Task.status.in_(["baru", "dikerjakan"]), Task.due_date <= today.isoformat(),
                                  (Task.assignee_id == user.id) | (Task.created_by == user.id)).order_by(Task.due_date).limit(5).all()
    for t in tasks:
        if t.assignee_id and t.assignee_id not in users:
            users[t.assignee_id] = db.query(User).filter(User.id == t.assignee_id).first()
        u = users.get(t.assignee_id)
        pic = ((u.full_name or u.username) if u else (t.assignee_name or "")).split()[0] if (u or t.assignee_name) else None
        late = (today - date.fromisoformat(t.due_date)).days
        out.append({"kind": "task", "icon": "check", "title": t.title, "sub": "Tindak lanjut" + (f" · PIC {pic}" if pic else ""),
                    "time": "Hari ini" if late == 0 else f"Terlambat {late} hari", "urgent": True, "task_id": t.id})
    for s in db.query(ReportSchedule).filter(ReportSchedule.user_id == user.id, ReportSchedule.active.is_(True)).all():
        due = (s.frequency == "bulanan" and today.day == s.monthday) or (s.frequency == "mingguan" and today.weekday() == s.weekday)
        if due:
            n = len([e for e in (s.recipients or "").split(",") if e.strip()]) or 1
            out.append({"kind": "report", "icon": "file", "title": s.name, "sub": f"Laporan terjadwal · {n} penerima",
                        "time": f"{s.hour:02d}.00", "urgent": False})
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    for a in db.query(WatchAlert).filter(WatchAlert.user_id == user.id, WatchAlert.created_at >= since.replace(tzinfo=None),
                                         WatchAlert.acknowledged_at.is_(None)).order_by(WatchAlert.created_at.desc()).limit(3).all():
        w = a.created_at.replace(tzinfo=timezone.utc).astimezone(WIB)
        sev = {"kritis": "Kritis", "peringatan": "Peringatan", "pulih": "Pulih"}.get(a.severity, a.severity)
        out.append({"kind": "alert", "icon": "bell", "title": a.title, "sub": f"Alert baru · {sev}", "time": f"{w:%H.%M}", "urgent": False,
                    "alert_id": a.id})
    return out


# ── Build ───────────────────────────────────────────────────────────────────

def build(db: Session, user: User, now: Optional[datetime] = None) -> dict:
    now = (now or datetime.now(timezone.utc)).astimezone(WIB)
    today = now.date()
    prefs = prefs_of(user)
    focus = _focus(prefs)
    topics = prefs.get("topics") or DEFAULT_PREFS["topics"]
    t, source = tables("kab_daily", "region_daily", "kec_mtd", "avail_month", "kec_month")
    last = last_day(t.get("region_daily") or t.get("kab_daily") or [])
    if not last:
        raise HTTPException(409, "Data harian belum ada di Performance dump")
    win = Window(last)
    targets = load_targets()
    stories = [s for s in (_story_fall(t, win, focus, topics), _story_runrate(t, win, focus, targets), _story_good(t, win, focus)) if s]
    for i, s in enumerate(stories):
        s["n"] = i + 1
        s["tone_label"] = TONE[s["tone"]]
        s["key"] = f"{s['tone']}-{s['metric']}-{s.get('kabupaten') or s.get('region')}"
        s["share"] = f"{s['title']}: {s['value_label']} {s['value_note']}. {s['text']}"
    bars, say = _target_bars(t, win, focus, targets)
    agenda = _agenda(db, user, today)
    due_today = sum(1 for a in agenda if a["kind"] == "task")
    name = (user.full_name or user.username or "").split()[0]
    scope = "Circle Java" if len(focus) == 3 else " dan ".join(region_label(r) for r in focus)
    # headline
    rd = [r for r in t.get("region_daily") or [] if norm(r.get("region")) in focus]
    s = daily_series(rd, "revenue")
    g = growth(sum(v for d, v in s.items() if win.in_cur(d)), sum(v for d, v in s.items() if win.in_prev(d)))
    rev_bar = next((b for b in bars if b["metric"] == "revenue"), None)
    parts: list = [f"Revenue {scope} MTD ", ("b", f"{'naik' if (g or 0) >= 0 else 'turun'} {num(abs(g or 0), 1)}% vs LMTD")]
    if rev_bar:
        parts.append(", sejalan dengan target. " if rev_bar["pct"] >= 97 else ", di bawah jalur target. ")
    else:
        parts.append(". ")
    attn = [x for x in stories if x["tone"] in ("k", "w")]
    n_attn = len(attn) + (1 if due_today else 0)
    if n_attn:
        parts.append(f"{COUNT_WORD.get(n_attn, str(n_attn))} hal butuh perhatian: ")
        bits: list = []
        for x in attn:
            where = title(x["kabupaten"]) if x.get("kabupaten") else region_label(x["region"])
            bits.append([("e", f"{lower_label(x['metric'])} {where}"), " masih turun" if x["tone"] == "k" else " tertinggal dari run-rate"])
        if due_today:
            bits.append([f"{due_today} tindak lanjut jatuh tempo hari ini"])
        for i, b in enumerate(bits):
            if i:
                parts.append((" dan " if len(bits) == 2 else ", dan ") if i == len(bits) - 1 else ", ")
            parts += b
        parts.append(".")
    headline = seg(*parts)
    audio = plain(headline) + " " + " ".join(f"{x['title']}. {x['text']}" for x in stories)
    log_row = db.query(BriefLog).filter(BriefLog.user_id == user.id, BriefLog.day == today.isoformat()).first()
    return {
        "greeting": f"Selamat pagi, {name}" if now.hour < 11 else f"Halo, {name}",
        "subtitle": f"Disusun agent untuk {name} · {DAYS[today.weekday()]}, {today.day} {MONTHS[today.month - 1]} {today.year} {SEND_HOUR:02d}.00 WIB",
        "date_short": f"{DAYS[today.weekday()]}, {today.day} {MONTHS[today.month - 1]} · {SEND_HOUR:02d}.00",
        "headline": headline,
        "month_chip": month_label(win.month),
        "audio": {"text": audio, "seconds": max(20, round(len(audio.split()) / 2.3))},
        "basis": {"dump": source.get("label_wib"), "period": win.label(), "period_short": win.label().replace("MTD ", "MTD ").replace(" vs LMTD", "\nvs LMTD"),
                  "focus": f"Fokus: {scope}" + (", semua region" if len(focus) == 3 else "")},
        "source": source,
        "stories": stories, "targets": bars, "agent_says": say,
        "target_title": f"Posisi terhadap target {month_label(win.month, year=False, long=True)}",
        "target_sub": f"Proyeksi akhir bulan dari run-rate {win.days} hari, rentang 80% ditunjukkan arsiran",
        "agenda": agenda,
        "prefs": {**prefs, "send_label": f"Kirim jam {SEND_HOUR:02d}.00", "days_label": "Senin sampai Sabtu",
                  "email_label": f"{(user.email or '').split('@')[0][:5]}@... · versi lengkap"},
        "topics": [{"key": k, "label": v, "on": k in (prefs.get("topics") or [])} for k, v in TOPICS.items()],
        "regions": [{"key": "JAVA", "label": "Circle Java", "on": len(focus) == 3}] +
                   [{"key": r, "label": region_label(r), "on": len(focus) < 3 and r in focus} for r in ("WEST JAVA", "CENTRAL JAVA", "EAST JAVA")],
        "vote": log_row.vote if log_row else None,
        "notification": notification_text(name, headline, stories),
    }


def notification_text(name: str, headline: list, stories: list) -> dict:
    first = stories[0] if stories else None
    body = plain(headline)
    if first:
        body = f"{first['title']} ({first['value_label']}). " + (f"{len(stories) - 1} kartu lain menunggu." if len(stories) > 1 else "")
    return {"title": f"Brief Pagi untuk {name}", "body": body[:180]}


# ── API ─────────────────────────────────────────────────────────────────────

class PrefsIn(BaseModel):
    topics: Optional[list[str]] = None
    regions: Optional[list[str]] = None
    send: Optional[bool] = None
    push: Optional[bool] = None
    email: Optional[bool] = None


class VoteIn(BaseModel):
    vote: str = Field(..., pattern="^(up|down)$")


class OpenIn(BaseModel):
    story: str = Field(..., max_length=120)


@router.get("")
def get_brief(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return build(db, user)


@router.post("/prefs")
def set_prefs(body: PrefsIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    p = prefs_of(user)
    if body.topics is not None:
        p["topics"] = [x for x in body.topics if x in TOPICS] or ["perf"]
    if body.regions is not None:
        regs = [norm(r) for r in body.regions]
        p["regions"] = ["JAVA"] if "JAVA" in regs or not regs else [r for r in regs if r in REGIONS]
    if body.send is not None:
        p["send"] = body.send
    if body.push is not None:
        p["push"] = body.push
    if body.email is not None:
        p["email"] = body.email
    _save_prefs(db, user, p)
    return {"prefs": p}


def _log(db: Session, user: User) -> BriefLog:
    day = today_wib().isoformat()
    row = db.query(BriefLog).filter(BriefLog.user_id == user.id, BriefLog.day == day).first()
    if not row:
        row = BriefLog(user_id=user.id, day=day)
        db.add(row)
    return row


@router.post("/feedback")
def feedback(body: VoteIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = _log(db, user)
    row.vote = body.vote
    db.commit()
    return {"vote": row.vote}


@router.post("/open")
def opened(body: OpenIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = _log(db, user)
    try:
        seen = json.loads(row.opened or "[]")
    except ValueError:
        seen = []
    if body.story not in seen:
        seen.append(body.story)
    row.opened = json.dumps(seen[-30:])
    db.commit()
    return {"ok": True}


def send_due(now: Optional[datetime] = None) -> int:
    """From the main loop: write today's brief notification once, at 06.00 WIB or later, Mon to Sat."""
    now = (now or datetime.now(timezone.utc)).astimezone(WIB)
    if now.hour < SEND_HOUR or now.weekday() == 6:
        return 0
    db = SessionLocal()
    n = 0
    try:
        day = now.date().isoformat()
        done = {r.user_id for r in db.query(BriefLog).filter(BriefLog.day == day, BriefLog.sent_at.isnot(None)).all()}
        for u in db.query(User).filter(User.is_active.is_(True)).all():
            if u.id in done:
                continue
            p = prefs_of(u)
            if not p.get("send", True) or (not p.get("push") and not p.get("email")):
                continue
            try:
                b = build(db, u, now)
            except HTTPException:
                return n  # no daily data today: try again next loop
            except Exception as e:
                log.warning(f"brief {u.id}: {e}")
                continue
            row = db.query(BriefLog).filter(BriefLog.user_id == u.id, BriefLog.day == day).first() or BriefLog(user_id=u.id, day=day)
            row.sent_at = datetime.now(timezone.utc).replace(tzinfo=None)
            db.add(row)
            if p.get("push"):
                db.add(Notification(user_id=u.id, title=b["notification"]["title"], message=b["notification"]["body"], kind="brief", link="/brief", push=True))
            if p.get("email") and u.email:
                try:
                    from . import email_service
                    email_service.send_notification(u.email, b["notification"]["title"], plain(b["headline"]))
                except Exception as e:
                    log.warning(f"brief email {u.id}: {e}")
            db.commit()
            n += 1
    finally:
        db.close()
    return n
