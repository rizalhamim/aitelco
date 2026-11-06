"""Tindak Lanjut: alerts and insights become tasks that close on proven KPI change.

GET    /api/tindak/tasks?view=all|mine|verify|done&region=   board, stats and lanes
POST   /api/tindak/tasks                                     create (from alert, Diagnosa, Brief, pin, Simulasi or manual)
GET    /api/tindak/tasks/{id}                                detail: checklist, photos, verification, history
PATCH  /api/tindak/tasks/{id}                                status, PIC, due date, title
POST   /api/tindak/tasks/{id}/items | PATCH .../items/{iid}  checklist
POST   /api/tindak/tasks/{id}/photos                         field photo (base64 JPEG/PNG, max 2 MB, optional GPS)
GET    /api/tindak/photos/{pid}                              photo file
GET    /api/tindak/tasks/{id}/nearest?lat=&lon=              next site to visit (Android GPS)
GET    /api/tindak/people                                    PIC choices
GET    /api/tindak/export.csv

Verification (no LLM): the KPI of the task's area over the 14 days before the task was
created and the 14 days after its due date (or the day the work was finished, when
later) are compared, both against the 14 days four weeks before the "before" window, so
weekdays line up. "change" criteria pass when the "after" change reaches the threshold,
"per_day" criteria when the daily average does. Criteria the dump cannot measure
(availability per day) are verified by hand. verify_due() runs daily from main.py.
"""
from __future__ import annotations

import base64
import csv
import io
import json
import math
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from . import config
from .auth import get_current_user
from .database import Notification, SessionLocal, Task, TaskEvent, TaskItem, TaskPhoto, User, get_db, utcnow
from .v3_common import (METRICS, WIB, as_date, day_label, daily_series, lower_label, norm, num, pct, region_label, rp_m, tables, title,
                        today_wib)

router = APIRouter(prefix="/api/tindak", tags=["tindak"])

UPLOADS = config.DATA_DIR / "uploads" / "tasks"
MAX_PHOTO = 2 * 1024 * 1024
WINDOW = 14
ORIGIN_LABEL = {"alert": "Dari alert", "diagnosa": "Dari Diagnosa", "brief": "Dari Brief Pagi", "ruang": "Dari Ruang Saya",
                "simulasi": "Dari Simulasi", "manual": "Dibuat manual"}
ORIGIN_ICON = {"alert": "bell", "diagnosa": "spark", "brief": "sun", "ruang": "layers", "simulasi": "up", "manual": "plus"}
ORIGIN_TONE = {"alert": "a", "diagnosa": "d", "brief": "b", "ruang": "p", "simulasi": "p", "manual": "b"}
AVATAR = ["#0E8579", "#6A4CB5", "#FF7A59", "#22B8C9", "#B7791F", "#C23A5B"]
STATUSES = ("baru", "dikerjakan", "verifikasi", "selesai", "batal")
OPS = {">=": "≥", "<=": "≤"}


def avatar_color(name: str) -> str:
    return AVATAR[sum(ord(c) for c in (name or "?")) % len(AVATAR)]


def _j(v, default=None):
    try:
        return json.loads(v) if v else default
    except (TypeError, ValueError):
        return default


def criterion_text(kpi: Optional[dict]) -> Optional[str]:
    """"Selesai jika payload Garut kembali ≥ −3% vs periode sebelum"."""
    if not kpi:
        return None
    if kpi.get("text"):
        return kpi["text"]
    metric = kpi.get("metric", "")
    label = "availability" if metric == "availability" else lower_label(metric)
    where = f" {title(kpi['name'])}" if kpi.get("name") and kpi.get("level") != "circle" else ""
    op = OPS.get(kpi.get("op", ">="), "≥")
    th = kpi.get("threshold", 0)
    mode = kpi.get("mode", "change")
    if mode == "change":
        return f"Selesai jika {label}{where} kembali {op} {num(th, 0 if float(th).is_integer() else 1)}% vs periode sebelum"
    if mode == "per_day":
        return f"Selesai jika {label}{where} {op} {num(th, 0)} per hari"
    days = kpi.get("days")
    return f"Selesai jika {label}{where} {op} {num(th, 1)}%" + (f" selama {days} hari" if days else "")


def _anchor(t: Task) -> date:
    due = date.fromisoformat(t.due_date) if t.due_date else as_date(t.created_at)
    done = (t.done_at.replace(tzinfo=timezone.utc).astimezone(WIB).date() if t.done_at else None)
    return max(due, done) if done else due


def windows(t: Task) -> dict:
    created = t.created_at.replace(tzinfo=timezone.utc).astimezone(WIB).date() if t.created_at else today_wib()
    b0, b1 = created - timedelta(days=WINDOW), created - timedelta(days=1)
    a = _anchor(t)
    a0, a1 = a + timedelta(days=1), a + timedelta(days=WINDOW)
    return {"before": (b0, b1), "after": (a0, a1), "base": (b0 - timedelta(days=28), b1 - timedelta(days=28))}


def _wsum(series: dict, w: tuple, flow: bool) -> tuple[Optional[float], int]:
    days = [w[0] + timedelta(days=i) for i in range((w[1] - w[0]).days + 1)]
    have = [series[d] for d in days if d in series]
    if not have:
        return None, 0
    return (sum(have) if flow else sum(have) / len(have)), len(have)


def measure(t: Task, kpi: dict, tbls: Optional[dict] = None) -> dict:
    """Before/after values of the task KPI from the daily dump tables."""
    metric = kpi.get("metric")
    if metric not in METRICS or kpi.get("mode") == "level":
        return {"result": "manual", "reason": "Data harian untuk kriteria ini belum ada di Performance dump"}
    if tbls is None:
        tbls, _ = tables("kab_daily", "region_daily")
    col, flow = METRICS[metric]["col"], METRICS[metric]["flow"]
    level, name = kpi.get("level") or ("kabupaten" if t.kabupaten else ("region" if t.region else "circle")), kpi.get("name") or t.kabupaten or t.region
    if level == "kabupaten":
        series = daily_series(tbls.get("kab_daily") or [], col, lambda r: norm(r.get("kabupaten")) == norm(name))
    elif level == "region":
        series = daily_series(tbls.get("region_daily") or tbls.get("kab_daily") or [], col, lambda r: norm(r.get("region")) == norm(name))
    else:
        series = daily_series(tbls.get("region_daily") or [], col)
    if not series:
        return {"result": "manual", "reason": "Data harian untuk wilayah ini belum ada di Performance dump"}
    w = windows(t)
    base, n0 = _wsum(series, w["base"], flow)
    before, nb = _wsum(series, w["before"], flow)
    if n0 < WINDOW:  # a partial baseline would distort every percentage
        base = None
    if nb < WINDOW:
        before = None
    after, na = _wsum(series, w["after"], flow)
    out = {"before_window": [w["before"][0].isoformat(), w["before"][1].isoformat()],
           "after_window": [w["after"][0].isoformat(), w["after"][1].isoformat()],
           "before_pct": (before / base - 1) * 100 if before and base else None,
           "after_days": na, "after_pct": (after / base - 1) * 100 if after and base and na == WINDOW else None,
           "after_vs_before_pct": (after / before - 1) * 100 if after and before and na == WINDOW else None,
           "result": None}
    if na < WINDOW:
        return out
    op = kpi.get("op", ">=")
    if kpi.get("mode", "change") == "per_day":
        val = after / WINDOW if flow else after
        out["after_per_day"] = val
        ok = val >= kpi.get("threshold", 0) if op == ">=" else val <= kpi.get("threshold", 0)
    else:
        val = out["after_pct"]
        ok = val is not None and (val >= kpi.get("threshold", 0) if op == ">=" else val <= kpi.get("threshold", 0))
    out["result"] = "terbukti" if ok else "tidak"
    return out


def verify_due(db: Optional[Session] = None) -> int:
    """Daily: measure every task waiting for verification; close the ones with a full window."""
    own = db is None
    db = db or SessionLocal()
    n = 0
    try:
        tbls, _ = tables("kab_daily", "region_daily")
        for t in db.query(Task).filter(Task.status == "verifikasi").all():
            kpi = _j(t.kpi, {})
            res = measure(t, kpi, tbls) if kpi else {"result": "manual"}
            t.verify = json.dumps(res)
            if res.get("result") in ("terbukti", "tidak"):
                t.status = "selesai"
                t.verified_on = today_wib().isoformat()
                db.add(TaskEvent(task_id=t.id, user_id=None, text=_verdict(res, kpi)))
                for uid in {t.created_by, t.assignee_id} - {None}:
                    db.add(Notification(user_id=uid, title=f"Tugas diverifikasi: {t.title}", message=_verdict(res, kpi),
                                        kind="success" if res["result"] == "terbukti" else "warn",
                                        link=f"/tindak?task={t.id}", push=True))
                n += 1
        db.commit()
    finally:
        if own:
            db.close()
    return n


def _verdict(res: dict, kpi: dict) -> str:
    label = METRICS.get(kpi.get("metric"), {}).get("label", "KPI")
    if res.get("result") == "terbukti":
        return f"Terbukti: {label} {pct(res.get('after_vs_before_pct'))} vs sebelum"
    if res.get("result") == "tidak":
        return f"Belum terbukti: {label} {pct(res.get('after_vs_before_pct'))} vs sebelum"
    return "Perlu verifikasi manual"


# ── Serialisation ───────────────────────────────────────────────────────────

def _person(t: Task, users: dict) -> dict:
    u = users.get(t.assignee_id) if t.assignee_id else None
    name = (u.full_name or u.username) if u else (t.assignee_name or "Belum ada PIC")
    first = name.split()[0] if name else "?"
    return {"id": t.assignee_id, "name": first, "full_name": name, "unit": t.assignee_unit, "initial": first[:1].upper(), "color": avatar_color(first)}


def _due(t: Task, today: date) -> dict:
    if not t.due_date:
        return {"label": None, "urgent": False}
    d = date.fromisoformat(t.due_date)
    late = (today - d).days
    if late == 0:
        return {"label": "Hari ini", "long": f"Hari ini, {day_label(d)}", "urgent": True, "late_days": 0}
    if late > 0:
        return {"label": f"Terlambat {late} hari", "long": f"Terlambat {late} hari, {day_label(d)}", "urgent": True, "late_days": late}
    return {"label": day_label(d), "long": day_label(d), "urgent": False, "late_days": late}


def card(t: Task, users: dict, items: list, photos: int, today: date) -> dict:
    kpi = _j(t.kpi, {})
    ver = _j(t.verify, {}) or {}
    done_items = sum(1 for i in items if i.done)
    out = {"id": t.id, "title": t.title, "status": t.status, "origin": t.origin, "origin_label": ORIGIN_LABEL.get(t.origin, "Tugas"),
           "origin_icon": ORIGIN_ICON.get(t.origin, "check"), "origin_tone": ORIGIN_TONE.get(t.origin, "b"),
           "criterion": criterion_text(kpi), "progress": (done_items / len(items)) if items else None,
           "items_done": done_items, "items_total": len(items), "photos": photos, "pic": _person(t, users), "due": _due(t, today),
           "region": t.region, "kabupaten": t.kabupaten, "priority": t.priority, "impact": t.impact,
           "mine": False, "verify": None}
    if t.status in ("verifikasi", "selesai") and kpi:
        if ver.get("result") in ("terbukti", "tidak"):
            out["verify"] = {"text": _verdict(ver, kpi), "ok": ver["result"] == "terbukti"}
        elif ver.get("result") == "manual":
            out["verify"] = {"text": "Perlu verifikasi manual", "ok": None}
        else:
            out["verify"] = {"text": f"Data sesudah: {ver.get('after_days', 0)} dari {WINDOW} hari", "ok": None}
    if t.done_at:
        out["done_label"] = f"Selesai {day_label(t.done_at.replace(tzinfo=timezone.utc).astimezone(WIB).date())}"
    return out


def _load(db: Session, tasks: list[Task]):
    ids = [t.id for t in tasks]
    items: dict = {}
    photos: dict = {}
    if ids:
        for i in db.query(TaskItem).filter(TaskItem.task_id.in_(ids)).order_by(TaskItem.position, TaskItem.id).all():
            items.setdefault(i.task_id, []).append(i)
        for p in db.query(TaskPhoto).filter(TaskPhoto.task_id.in_(ids)).all():
            photos[p.task_id] = photos.get(p.task_id, 0) + 1
    uids = {t.assignee_id for t in tasks} | {t.created_by for t in tasks}
    users = {u.id: u for u in db.query(User).filter(User.id.in_([u for u in uids if u])).all()} if uids else {}
    return items, photos, users


def board(db: Session, user: User, view: str = "all", region: str = "") -> dict:
    today = today_wib()
    q = db.query(Task).filter(Task.status != "batal")
    if region:
        q = q.filter(Task.region == norm(region))
    tasks = q.order_by(Task.due_date.is_(None), Task.due_date, Task.id).all()
    items, photos, users = _load(db, tasks)
    cards = []
    for t in tasks:
        c = card(t, users, items.get(t.id, []), photos.get(t.id, 0), today)
        c["mine"] = user.id in (t.assignee_id, t.created_by)
        cards.append(c)
    mine_only = [c for c in cards if c["mine"]]
    pool = mine_only if view == "mine" else cards
    open_ = [c for c in cards if c["status"] in ("baru", "dikerjakan")]
    due_today = [c for c in open_ if c["due"].get("late_days") is not None and c["due"]["late_days"] >= 0]
    late = [c for c in due_today if c["due"]["late_days"] > 0]
    waiting = [c for c in cards if c["status"] == "verifikasi"]
    since = (today - timedelta(days=30)).isoformat()
    verified = [t for t in tasks if t.status == "selesai" and t.verified_on and t.verified_on >= since]
    proven = [t for t in verified if (_j(t.verify, {}) or {}).get("result") == "terbukti"]
    recent_done = (today - timedelta(days=3)).isoformat()
    lanes = {
        "baru": [c for c in pool if c["status"] == "baru"],
        "dikerjakan": [c for c in pool if c["status"] == "dikerjakan"],
        "verifikasi": [c for c in pool if c["status"] == "verifikasi"]
        + [c for c, t in zip(cards, tasks) if c in pool and t.status == "selesai" and t.verified_on and t.verified_on >= recent_done],
    }
    done_total = sum(1 for c in pool if c["status"] == "selesai")
    return {
        "stats": {
            "open": len(open_), "open_mine": sum(1 for c in open_ if c["mine"]),
            "due_today": len(due_today), "late": len(late), "late_days": max((c["due"]["late_days"] for c in late), default=0),
            "waiting": len(waiting), "proven": len(proven), "verified": len(verified),
        },
        "lanes": lanes, "done_total": done_total,
        "mine": [c for c in mine_only if c["status"] in ("baru", "dikerjakan", "verifikasi")],
        "today": today.isoformat(),
    }


def detail(db: Session, t: Task) -> dict:
    today = today_wib()
    items, photos, users = _load(db, [t])
    c = card(t, users, items.get(t.id, []), photos.get(t.id, 0), today)
    kpi = _j(t.kpi, {})
    w = windows(t)
    ver = _j(t.verify, {}) or {}
    if kpi and not ver and t.status in ("baru", "dikerjakan", "verifikasi"):
        try:
            ver = measure(t, kpi)
        except Exception:
            ver = {}
    ev = db.query(TaskEvent).filter(TaskEvent.task_id == t.id).order_by(TaskEvent.created_at).all()
    ev_users = {u.id: u for u in db.query(User).filter(User.id.in_([e.user_id for e in ev if e.user_id])).all()} if ev else {}
    ph = db.query(TaskPhoto).filter(TaskPhoto.task_id == t.id).order_by(TaskPhoto.created_at).all()
    creator = users.get(t.created_by)
    ref = _j(t.origin_ref, {}) or {}
    c.update({
        "origin_long": f"{ORIGIN_LABEL.get(t.origin, 'Tugas')} {day_label(t.created_at.replace(tzinfo=timezone.utc).astimezone(WIB).date())}",
        "scope_label": t.scope_label or (title(t.kabupaten) if t.kabupaten else region_label(t.region) if t.region else "Circle Java"),
        "priority_label": t.priority.capitalize() + (f" · {rp_m(t.impact, sign=True)}" if t.impact else ""),
        "items": [{"id": i.id, "text": i.text, "done": i.done} for i in items.get(t.id, [])],
        "photos_list": [{"id": p.id, "caption": p.caption, "lat": p.lat, "lon": p.lon, "created_at": p.created_at.isoformat()} for p in ph],
        "kpi": kpi, "sites": _j(t.sites, []) or [],
        "verify_detail": {
            "metric_label": METRICS.get(kpi.get("metric"), {}).get("label") if kpi else None,
            "before_label": f"Sebelum · {day_label(w['before'][0])} sd {day_label(w['before'][1])}",
            "after_label": f"Sesudah · {day_label(w['after'][0])} sd {day_label(w['after'][1])}",
            "before_pct": ver.get("before_pct"), "after_pct": ver.get("after_pct"), "after_days": ver.get("after_days", 0),
            "result": ver.get("result"), "window": WINDOW, "reason": ver.get("reason"),
        } if kpi else None,
        "history": [{"user": (ev_users[e.user_id].full_name or ev_users[e.user_id].username).split()[0] if e.user_id in ev_users else "Agent",
                     "text": e.text, "at": e.created_at.isoformat(),
                     "at_label": _at_label(e.created_at)} for e in ev],
        "created_by_name": (creator.full_name or creator.username) if creator else None,
        "origin_ref": ref,
    })
    return c


def _at_label(dt: datetime) -> str:
    w = dt.replace(tzinfo=timezone.utc).astimezone(WIB)
    return f"{day_label(w.date())} {w:%H.%M}"


# ── API ─────────────────────────────────────────────────────────────────────

class KpiIn(BaseModel):
    metric: str
    mode: str = Field("change", pattern="^(change|per_day|level)$")
    op: str = Field(">=", pattern="^(>=|<=)$")
    threshold: float = 0
    level: Optional[str] = None
    name: Optional[str] = None
    days: Optional[int] = None
    text: Optional[str] = Field(None, max_length=200)


class TaskIn(BaseModel):
    title: str = Field(..., min_length=3, max_length=200)
    origin: str = Field("manual", pattern="^(alert|diagnosa|brief|ruang|simulasi|manual)$")
    origin_ref: Optional[dict] = None
    region: Optional[str] = None
    kabupaten: Optional[str] = None
    scope_label: Optional[str] = Field(None, max_length=160)
    impact: Optional[float] = None
    assignee_id: Optional[int] = None
    assignee_name: Optional[str] = Field(None, max_length=120)
    assignee_unit: Optional[str] = Field(None, max_length=120)
    due_date: Optional[str] = Field(None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    kpi: Optional[KpiIn] = None
    items: list[str] = []
    sites: list[str] = []


class TaskPatch(BaseModel):
    title: Optional[str] = Field(None, min_length=3, max_length=200)
    status: Optional[str] = None
    assignee_id: Optional[int] = None
    assignee_name: Optional[str] = Field(None, max_length=120)
    due_date: Optional[str] = Field(None, pattern=r"^\d{4}-\d{2}-\d{2}$")


class ItemIn(BaseModel):
    text: str = Field(..., min_length=1, max_length=255)


class ItemPatch(BaseModel):
    done: Optional[bool] = None
    text: Optional[str] = Field(None, min_length=1, max_length=255)


class PhotoIn(BaseModel):
    data: str                                  # base64, optionally a data: URL
    caption: Optional[str] = Field(None, max_length=160)
    lat: Optional[float] = None
    lon: Optional[float] = None


def _priority(impact: Optional[float]) -> str:
    a = abs(impact or 0)
    return "tinggi" if a >= 1e9 else "sedang" if a >= 2e8 else "rendah"


def _get(db: Session, tid: int) -> Task:
    t = db.query(Task).filter(Task.id == tid).first()
    if not t:
        raise HTTPException(404, "Tugas tidak ditemukan")
    return t


def _can_edit(t: Task, user: User):
    if user.id not in (t.created_by, t.assignee_id) and user.role != "admin":
        raise HTTPException(403, "Hanya pembuat, PIC, atau admin yang bisa mengubah tugas ini")


def _name(u: User) -> str:
    return (u.full_name or u.username or "").split()[0] if u else "Seseorang"


def create_task(db: Session, user: User, body: TaskIn) -> Task:
    if body.assignee_id and not db.query(User).filter(User.id == body.assignee_id).first():
        raise HTTPException(400, "PIC tidak ditemukan")
    t = Task(created_by=user.id, title=body.title.strip(), origin=body.origin, origin_ref=json.dumps(body.origin_ref) if body.origin_ref else None,
             region=norm(body.region) or None, kabupaten=norm(body.kabupaten) or None, scope_label=body.scope_label, impact=body.impact,
             priority=_priority(body.impact), assignee_id=body.assignee_id, assignee_name=body.assignee_name, assignee_unit=body.assignee_unit,
             due_date=body.due_date, kpi=json.dumps(body.kpi.model_dump(exclude_none=True)) if body.kpi else None,
             sites=json.dumps(body.sites[:60]) if body.sites else None)
    db.add(t)
    db.flush()
    for i, text in enumerate(body.items[:20]):
        db.add(TaskItem(task_id=t.id, text=text.strip()[:255], position=i))
    src = {"diagnosa": "Diagnosa", "alert": "alert", "brief": "Brief Pagi", "ruang": "Ruang Saya", "simulasi": "Simulasi Target"}.get(body.origin)
    db.add(TaskEvent(task_id=t.id, user_id=user.id, text=f"membuat tugas{' dari ' + src if src else ''}"
                     + (f" {body.origin_ref.get('label')}" if body.origin_ref and body.origin_ref.get("label") else "")))
    if t.assignee_id and t.assignee_id != user.id:
        db.add(Notification(user_id=t.assignee_id, title=f"Tugas baru untuk kamu: {t.title}",
                            message=f"Dari {_name(user)}" + (f", tenggat {day_label(date.fromisoformat(t.due_date))}" if t.due_date else ""),
                            kind="task", link=f"/tindak?task={t.id}", push=True))
    db.commit()
    db.refresh(t)
    return t


@router.get("/tasks")
def list_tasks(view: str = Query("all", pattern="^(all|mine)$"), region: str = Query(""),
               user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return board(db, user, view, region)


@router.post("/tasks")
def new_task(body: TaskIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return detail(db, create_task(db, user, body))


@router.get("/tasks/{tid}")
def get_task(tid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return detail(db, _get(db, tid))


@router.patch("/tasks/{tid}")
def patch_task(tid: int, body: TaskPatch, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    t = _get(db, tid)
    _can_edit(t, user)
    if body.title:
        t.title = body.title.strip()
    if body.due_date:
        t.due_date = body.due_date
        db.add(TaskEvent(task_id=t.id, user_id=user.id, text=f"mengubah tenggat ke {day_label(date.fromisoformat(body.due_date))}"))
    if body.assignee_id is not None or body.assignee_name is not None:
        if body.assignee_id and not db.query(User).filter(User.id == body.assignee_id).first():
            raise HTTPException(400, "PIC tidak ditemukan")
        t.assignee_id, t.assignee_name = body.assignee_id or None, body.assignee_name
        if t.assignee_id and t.assignee_id != user.id:
            db.add(Notification(user_id=t.assignee_id, title=f"Tugas untuk kamu: {t.title}", message=f"Dari {_name(user)}",
                                        kind="task", link=f"/tindak?task={t.id}", push=True))
    if body.status and body.status != t.status:
        if body.status not in STATUSES:
            raise HTTPException(400, "Status tidak dikenal")
        kpi = _j(t.kpi, {})
        if body.status == "verifikasi":
            t.done_at = utcnow()
            db.add(TaskEvent(task_id=t.id, user_id=user.id, text="menandai pekerjaan selesai, verifikasi KPI dimulai"))
        elif body.status == "selesai":
            res = _j(t.verify, {}) or {}
            if kpi and kpi.get("mode") != "level" and res.get("result") not in ("terbukti", "tidak") and user.role != "admin":
                raise HTTPException(409, "Tugas ini ditutup otomatis setelah verifikasi KPI 14 hari")
            t.done_at = t.done_at or utcnow()
            t.verify = json.dumps({**res, "result": res.get("result") or "manual", "closed_by": user.id})
            t.verified_on = today_wib().isoformat()
            db.add(TaskEvent(task_id=t.id, user_id=user.id, text="menutup tugas"))
        else:
            db.add(TaskEvent(task_id=t.id, user_id=user.id, text=f"memindah tugas ke {body.status}"))
        t.status = body.status
    db.commit()
    return detail(db, t)


@router.post("/tasks/{tid}/items")
def add_item(tid: int, body: ItemIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    t = _get(db, tid)
    _can_edit(t, user)
    n = db.query(TaskItem).filter(TaskItem.task_id == tid).count()
    db.add(TaskItem(task_id=tid, text=body.text.strip(), position=n))
    db.commit()
    return detail(db, t)


@router.patch("/tasks/{tid}/items/{iid}")
def patch_item(tid: int, iid: int, body: ItemPatch, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    t = _get(db, tid)
    _can_edit(t, user)
    it = db.query(TaskItem).filter(TaskItem.id == iid, TaskItem.task_id == tid).first()
    if not it:
        raise HTTPException(404, "Item tidak ditemukan")
    if body.text:
        it.text = body.text.strip()
    if body.done is not None and body.done != it.done:
        it.done = body.done
        if body.done:
            db.add(TaskEvent(task_id=tid, user_id=user.id, text=f"menyelesaikan \"{it.text}\""))
        if t.status == "baru" and body.done:
            t.status = "dikerjakan"
    db.commit()
    return detail(db, t)


def _decode_image(data: str) -> tuple[bytes, str]:
    if data.startswith("data:"):
        data = data.split(",", 1)[-1]
    try:
        raw = base64.b64decode(data, validate=True)
    except Exception:
        raise HTTPException(400, "Foto tidak valid")
    if len(raw) > MAX_PHOTO:
        raise HTTPException(413, "Foto lebih dari 2 MB")
    if raw[:3] == b"\xff\xd8\xff":
        return raw, "jpg"
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        return raw, "png"
    raise HTTPException(415, "Hanya foto JPEG atau PNG")


@router.post("/tasks/{tid}/photos")
def add_photo(tid: int, body: PhotoIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    t = _get(db, tid)
    _can_edit(t, user)
    raw, ext = _decode_image(body.data)
    folder = UPLOADS / str(tid)
    folder.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}.{ext}"
    (folder / name).write_bytes(raw)
    caption = (body.caption or "").strip() or None
    if not caption:
        caption = f"{day_label(today_wib())}"
    db.add(TaskPhoto(task_id=tid, user_id=user.id, path=f"{tid}/{name}", caption=caption, lat=body.lat, lon=body.lon))
    db.add(TaskEvent(task_id=tid, user_id=user.id, text="menambah foto bukti" + (f" {caption}" if body.caption else "")))
    if t.status == "baru":
        t.status = "dikerjakan"
    db.commit()
    return detail(db, t)


@router.get("/photos/{pid}")
def get_photo(pid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    p = db.query(TaskPhoto).filter(TaskPhoto.id == pid).first()
    if not p:
        raise HTTPException(404, "Foto tidak ditemukan")
    path = (UPLOADS / p.path).resolve()
    if UPLOADS.resolve() not in path.parents or not path.exists():
        raise HTTPException(404, "Foto tidak ditemukan")
    return FileResponse(path, media_type="image/png" if path.suffix == ".png" else "image/jpeg",
                        headers={"Cache-Control": "private, max-age=86400"})


def _km(lat1, lon1, lat2, lon2) -> float:
    p = math.pi / 180
    a = math.sin((lat2 - lat1) * p / 2) ** 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * math.sin((lon2 - lon1) * p / 2) ** 2
    return 12742 * math.asin(math.sqrt(a))


@router.get("/tasks/{tid}/nearest")
def nearest_site(tid: int, lat: float = Query(..., ge=-90, le=90), lon: float = Query(..., ge=-180, le=180),
                 user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    t = _get(db, tid)
    wanted = set(_j(t.sites, []) or [])
    visited = {(p.caption or "").split(" ")[0] for p in db.query(TaskPhoto).filter(TaskPhoto.task_id == tid).all()}
    tbl, _ = tables("site_month")
    rows = tbl.get("site_month") or []
    latest = max((int(r["month_id"]) for r in rows), default=None)
    best = None
    seen = set()
    for r in rows:
        sid = str(r["site_id"])
        if int(r["month_id"]) != latest or sid in seen or r.get("lat") is None or r.get("lon") is None:
            continue
        seen.add(sid)
        if wanted and sid not in wanted:
            continue
        if not wanted and t.kabupaten and norm(r.get("kabupaten")) != t.kabupaten:
            continue
        if sid in visited:
            continue
        d = _km(lat, lon, float(r["lat"]), float(r["lon"]))
        if best is None or d < best["km"]:
            best = {"site_id": sid, "site_name": r.get("site_name"), "km": d, "lat": r["lat"], "lon": r["lon"], "kecamatan": title(r.get("kecamatan"))}
    if not best:
        return {"site": None, "text": "Semua site tugas ini sudah dikunjungi" if wanted or t.kabupaten else "Tugas ini tidak punya daftar site"}
    best["text"] = f"Kamu {num(best['km'], 1)} km dari {best['site_id']}, site berikutnya"
    return {"site": best, "text": best["text"]}


@router.get("/people")
def people(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    us = db.query(User).filter(User.is_active.is_(True)).order_by(User.full_name).all()
    return {"people": [{"id": u.id, "name": u.full_name or u.username, "initial": (u.full_name or u.username or "?")[:1].upper(),
                        "color": avatar_color((u.full_name or u.username or "?").split()[0])} for u in us]}


@router.get("/export.csv")
def export_csv(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    tasks = db.query(Task).order_by(Task.id).all()
    items, photos, users = _load(db, tasks)
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["id", "judul", "status", "asal", "wilayah", "pic", "tenggat", "kriteria", "checklist", "foto", "hasil verifikasi"])
    for t in tasks:
        c = card(t, users, items.get(t.id, []), photos.get(t.id, 0), today_wib())
        w.writerow([t.id, t.title, t.status, c["origin_label"], t.scope_label or t.kabupaten or t.region or "", c["pic"]["full_name"],
                    t.due_date or "", c["criterion"] or "", f"{c['items_done']}/{c['items_total']}", c["photos"],
                    (c["verify"] or {}).get("text", "")])
    return Response(buf.getvalue(), media_type="text/csv",
                    headers={"Content-Disposition": f"attachment; filename=tindak-lanjut-{today_wib().isoformat()}.csv"})
