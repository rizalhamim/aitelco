"""Ruang Saya: personal boards of pinned answers that stay fresh.

A pin stores what to compute (its spec), never the numbers, so every board open reads
the latest dump. Only a frozen chat answer (type "answer") keeps its table, because it
cannot be recomputed without the agent; it is labelled as saved on its date.

GET    /api/ruang/boards                      boards (own and shared), creates "Ruang Saya" on first use
POST   /api/ruang/boards                      {name}
GET    /api/ruang/boards/{id}                 pins with computed data, members, freshness
PATCH  /api/ruang/boards/{id}                 {name, schedule_weekday, schedule_hour, schedule_minute, schedule_recipients}
DELETE /api/ruang/boards/{id}
PUT    /api/ruang/boards/{id}/order           {columns: [[pin id, ...], ...]} after drag and drop
POST   /api/ruang/boards/{id}/members         {user: username or email, role: view|edit}
DELETE /api/ruang/boards/{id}/members/{uid}
POST   /api/ruang/boards/{id}/send            send the board now (PDF, numbers frozen and dated)
POST   /api/ruang/pins                        {board_id?, kind, title, subtitle, spec, origin}
PATCH  /api/ruang/pins/{id}                   {title, subtitle, board_id}
DELETE /api/ruang/pins/{id}
POST   /api/ruang/pins/{id}/notes             {text}; "@name" notifies a board member

Spec types (spec["type"]):
    daily_compare  {metric, region?, kabupaten?}          MTD per day vs the same days last month
    kpi_watch      {region?}                               sites below target, availability, RGU 90D, revenue per site
    rank_table     {metric, level, region?, order, n}      deepest falls (or best) from Klasemen
    map_change     {metric, kabupaten}                     kecamatan choropleth, MTD vs LMTD
    diagnosa       {metric, region?, kabupaten?, basis}    short Diagnosa answer
    simulasi       {metric, region?}                       month-end estimate and gap
    unavailable    {metric, label}                         kept until the dump has the data
    notes          {for_pin}                               team notes attached to another pin
    answer         {question, text, columns, rows}         frozen agent answer
"""
from __future__ import annotations

import io
import json
import logging
import math
import re
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from . import perf_dump
from .auth import get_current_user
from .database import Board, BoardMember, Notification, Pin, PinNote, SessionLocal, User, get_db
from .tindak import avatar_color
from .v3_common import (DAYS, METRICS, WIB, Window, as_date, complete_month, day_label, f, fmt_value, growth, last_day,
                        month_label, norm, num, pct, rp, rp_m, tables, title, today_wib)

log = logging.getLogger("ruang")
router = APIRouter(prefix="/api/ruang", tags=["ruang"])

SPEC_TYPES = ("daily_compare", "kpi_watch", "rank_table", "map_change", "diagnosa", "simulasi", "unavailable", "notes", "answer")
COLUMNS = 3
ORIGIN_LABEL = {"tanya": "Dari Tanya Agent", "peta": "Dari Peta Agent", "dashboard": "Dari Dashboard", "klasemen": "Dari Klasemen",
                "brief": "Dari Brief Pagi", "diagnosa": "Dari Diagnosa", "simulasi": "Dari Simulasi Target", "performance": "Dari Performance"}
AVAILABLE_LATER = {"market_share": "Market share", "fwa_pen": "Penetrasi FWA", "vlr_site": "VLR per site"}


def _j(v, default=None):
    try:
        return json.loads(v) if v else default
    except (TypeError, ValueError):
        return default


# ── Access ──────────────────────────────────────────────────────────────────

def _role(db: Session, b: Board, user: User) -> Optional[str]:
    if b.owner_id == user.id:
        return "owner"
    m = db.query(BoardMember).filter(BoardMember.board_id == b.id, BoardMember.user_id == user.id).first()
    return m.role if m else None


def _board(db: Session, bid: int, user: User, edit: bool = False) -> tuple[Board, str]:
    b = db.query(Board).filter(Board.id == bid).first()
    role = _role(db, b, user) if b else None
    if not b or not role:
        raise HTTPException(404, "Papan tidak ditemukan")
    if edit and role == "view":
        raise HTTPException(403, "Kamu hanya punya akses lihat di papan ini")
    return b, role


def default_board(db: Session, user: User) -> Board:
    b = db.query(Board).filter(Board.owner_id == user.id).order_by(Board.position, Board.id).first()
    if not b:
        b = Board(owner_id=user.id, name="Ruang Saya")
        db.add(b)
        db.commit()
        db.refresh(b)
    return b


# ── Pin data ────────────────────────────────────────────────────────────────

class Ctx:
    """Dump tables loaded once per board open."""

    def __init__(self):
        self.t, self.source = tables("kab_daily", "region_daily", "kec_mtd", "kec_month", "site_month", "avail_month")
        self.last = last_day(self.t.get("kab_daily") or self.t.get("region_daily") or [])
        self.win = Window(self.last) if self.last else None


def _scope_rows(ctx: Ctx, region: str, kabupaten: str):
    if kabupaten:
        return [r for r in ctx.t.get("kab_daily") or [] if norm(r.get("kabupaten")) == norm(kabupaten)]
    rows = ctx.t.get("region_daily") or ctx.t.get("kab_daily") or []
    return [r for r in rows if not region or norm(r.get("region")) == norm(region)]


def daily_compare(ctx: Ctx, spec: dict) -> dict:
    metric = spec.get("metric", "revenue")
    col = METRICS.get(metric, {}).get("col")
    if not col or not ctx.win:
        return {"status": "unavailable", "message": "Data harian belum ada di Performance dump"}
    rows = _scope_rows(ctx, spec.get("region", ""), spec.get("kabupaten", ""))
    w = ctx.win
    by: dict = {}
    for r in rows:
        d = as_date(r["dt_id"])
        by[d] = by.get(d, 0.0) + f(r.get(col))
    cur = [by.get(w.cur0 + timedelta(days=i)) for i in range(w.days)]
    prev_n = min(w.days + 1, (w.cur0 - w.lm0).days)
    prev = [by.get(w.lm0 + timedelta(days=i)) for i in range(prev_n)]
    flow = METRICS[metric]["flow"]
    mtd = sum(v or 0 for v in cur) if flow else (cur[-1] or 0)
    lmtd = sum(v or 0 for v in prev[:w.days]) if flow else (prev[w.days - 1] if len(prev) >= w.days else None)
    g = growth(mtd, lmtd)
    unit_idr = METRICS[metric]["unit"] == "IDR"
    return {"status": "ok", "value": mtd, "value_label": fmt_value(metric, mtd), "growth_pct": g,
            "growth_label": f"{pct(g)} vs LMTD" if g is not None else "",
            "cur": cur, "prev": prev, "days": w.days, "month": month_label(w.month, year=False),
            "prev_month": month_label(perf_dump.month_add(w.month, -1), year=False),
            "scale": 1e9 if unit_idr else 1.0, "axis_unit": "Rp miliar per hari" if unit_idr else METRICS[metric]["unit"]}


def kpi_watch(ctx: Ctx, spec: dict) -> dict:
    from .performance import _status
    region = norm(spec.get("region", ""))
    out = []
    # sites below target (status kritis/waspada, Performance rules), latest complete month vs the one before
    site_rows = ctx.t.get("site_month") or []
    kec = ctx.t.get("kec_month") or []
    latest = max((int(r["month_id"]) for r in kec), default=None)
    if latest and site_rows:
        cm = complete_month(latest, ctx.last)
        provinces = {norm(r.get("provinsi")) for r in kec if not region or norm(r.get("region")) == region}

        def below(m):
            pm = perf_dump.month_add(m, -1)
            by: dict = {}
            for r in site_rows:
                if norm(r.get("provinsi")) in provinces and int(r["month_id"]) in (m, pm):
                    by.setdefault(r["site_id"], {})[int(r["month_id"])] = r
            n = 0
            for v in by.values():
                c, p = v.get(m), v.get(pm)
                if c is None:
                    continue
                mom = growth(f(c.get("payload_gb")), f(p.get("payload_gb"))) if p else None
                if _status(mom, c.get("avail")) != "normal":
                    n += 1
            return n
        a, b = below(cm), below(perf_dump.month_add(cm, -1))
        out.append({"label": "Site di bawah target", "short": "Site < target", "value": num(a, 0), "delta": b and (a - b),
                    "delta_label": (("▲" if a >= b else "▼") + num(abs(a - b), 0)) if b else "", "good": a <= b})
    av = [r for r in ctx.t.get("avail_month") or [] if r.get("level") == ("region" if region else "circle")
          and norm(r.get("name")) == (region or "JAVA") and r.get("avail") is not None]
    if av:
        av.sort(key=lambda r: int(r["month_id"]))
        c = float(av[-1]["avail"])
        p = float(av[-2]["avail"]) if len(av) > 1 else None
        d = c - p if p is not None else None
        out.append({"label": "Availability", "short": "Availability", "value": num(c, 2) + "%", "delta": d,
                    "delta_label": (("+" if d >= 0 else "") + num(d, 2) + " pp") if d is not None else "", "short_delta": (("+" if d >= 0 else "") + num(d, 2)) if d is not None else "",
                    "good": d is None or d >= 0})
    if ctx.win:
        rows = _scope_rows(ctx, region, "")
        s_cur = sum(f(r.get("subs")) for r in rows if as_date(r["dt_id"]) == ctx.win.last)
        s_prev = sum(f(r.get("subs")) for r in rows if as_date(r["dt_id"]) == ctx.win.lm_last)
        g = growth(s_cur, s_prev)
        if s_cur:
            out.append({"label": "RGU 90D", "short": "RGU 90D", "value": fmt_value("subs", s_cur), "delta": g, "delta_label": pct(g), "good": (g or 0) >= 0})
    if latest and site_rows:
        cm = complete_month(latest, ctx.last)
        pm = perf_dump.month_add(cm, -1)
        provinces = {norm(r.get("provinsi")) for r in kec if not region or norm(r.get("region")) == region}
        sums = {cm: [0.0, 0], pm: [0.0, 0]}
        for r in site_rows:
            m = int(r["month_id"])
            if m in sums and norm(r.get("provinsi")) in provinces and r.get("revenue") is not None:
                sums[m][0] += f(r["revenue"])
                sums[m][1] += 1
        c = sums[cm][0] / sums[cm][1] if sums[cm][1] else None
        p = sums[pm][0] / sums[pm][1] if sums[pm][1] else None
        if c:
            g = growth(c, p)
            out.append({"label": "Rev per site", "short": "Rev per site", "value": rp(c), "delta": g, "delta_label": pct(g), "good": (g or 0) >= 0})
    return {"status": "ok" if out else "unavailable", "tiles": out}


def rank_table(ctx: Ctx, spec: dict) -> dict:
    from .klasemen import rank_rows
    rows, basis, _ = rank_rows(ctx.t, spec.get("level", "kabupaten"), spec.get("metric", "revenue"), spec.get("region", ""))
    rows = [r for r in rows if r.get("growth_pct") is not None]
    rows.sort(key=lambda r: r["growth_pct"], reverse=spec.get("order") == "best")
    n = int(spec.get("n", 5))
    unit_idr = METRICS.get(spec.get("metric", "revenue"), {}).get("unit") == "IDR"
    return {"status": "ok", "basis": basis["label"], "rows": [
        {"name": r["name"], "pct": r["growth_pct"], "pct_label": pct(r["growth_pct"]),
         "abs_label": (rp_m(r["growth_abs"], sign=True).replace("Rp ", "") if unit_idr else fmt_value(spec.get("metric"), r["growth_abs"]))}
        for r in rows[:n]]}


def _map_color(p: Optional[float]) -> str:
    if p is None:
        return "#ECF3F1"
    if p <= -10:
        return "#C42B2B"
    if p <= -5:
        return "#EF5350"
    if p < -2:
        return "#FAD0D0"
    if p < 0:
        return "#FDECEC"
    return "#E6F4EA"


def map_change(ctx: Ctx, spec: dict, w: int = 370, h: int = 150) -> dict:
    metric = spec.get("metric", "payload")
    col = METRICS.get(metric, {}).get("col")
    kab = norm(spec.get("kabupaten", ""))
    vals: dict = {}
    for r in ctx.t.get("kec_mtd") or []:
        if norm(r.get("kabupaten")) != kab:
            continue
        k = norm(r.get("kecamatan"))
        c, p = vals.get(k, (0.0, 0.0))
        if r.get("period") == "mtd":
            c += f(r.get(col))
        else:
            p += f(r.get(col))
        vals[k] = (c, p)
    if not vals:
        return {"status": "unavailable", "message": "Data kecamatan belum ada di Performance dump"}
    chg = {k: growth(c, p) for k, (c, p) in vals.items()}
    shapes = []
    try:
        from .map_agent import geo
        feats = [g for g in geo().get("kec", []) if norm(g.get("kab")) == kab]
    except Exception as e:  # geometry missing on this server: list only
        log.info(f"map pin without geometry: {e}")
        feats = []
    if feats:
        xs = [c[0] for g in feats for r in g["rings"] for c in r]
        ys = [c[1] for g in feats for r in g["rings"] for c in r]
        lon0, lon1, lat0, lat1 = min(xs), max(xs), min(ys), max(ys)
        cx = math.cos(math.radians((lat0 + lat1) / 2))
        pad = 8
        s = min((w - 2 * pad) / max((lon1 - lon0) * cx, 1e-9), (h - 2 * pad) / max(lat1 - lat0, 1e-9))
        ox, oy = (w - (lon1 - lon0) * cx * s) / 2, (h - (lat1 - lat0) * s) / 2
        for g in feats:
            k = norm(g.get("kec"))
            d = []
            for r in g["rings"]:
                pts = [(ox + (c[0] - lon0) * cx * s, oy + (lat1 - c[1]) * s) for c in r]
                keep = [pts[0]] + [q for i, q in enumerate(pts[1:]) if math.hypot(q[0] - pts[i][0], q[1] - pts[i][1]) >= .8]
                if len(keep) >= 3:
                    d.append("M" + " ".join(f"{x:.1f},{y:.1f}" for x, y in keep) + "Z")
            if d:
                xs2 = [c[0] for r in g["rings"] for c in r]
                ys2 = [c[1] for r in g["rings"] for c in r]
                lx, ly = ox + ((min(xs2) + max(xs2)) / 2 - lon0) * cx * s, oy + (lat1 - (min(ys2) + max(ys2)) / 2) * s
                shapes.append({"name": title(k), "d": "".join(d), "fill": _map_color(chg.get(k)), "pct": chg.get(k), "x": round(lx, 1), "y": round(ly, 1)})
    ranked = sorted((k for k in chg if chg[k] is not None), key=lambda k: chg[k])
    labels = []
    for i, k in enumerate(ranked[:2]):
        labels.append({"name": title(k), "text": f"{title(k)} {pct(chg[k], 0)}" if i == 0 else title(k), "dark": (chg[k] or 0) <= -5})
    if ranked and (chg[ranked[-1]] or 0) >= 0:
        labels.append({"name": title(ranked[-1]), "text": title(ranked[-1]), "dark": False, "good": True})
    return {"status": "ok", "w": w, "h": h, "shapes": shapes, "labels": labels,
            "list": [{"name": title(k), "pct": chg[k], "pct_label": pct(chg[k])} for k in ranked],
            "legend": [{"color": "#C42B2B", "label": "turun > 10%"}, {"color": "#FAD0D0", "label": "0 sd −5%"}, {"color": "#E6F4EA", "label": "naik"}]}


def pin_data(ctx: Ctx, db: Session, pin: Pin) -> dict:
    spec = _j(pin.spec, {}) or {}
    t = spec.get("type")
    try:
        if t == "daily_compare":
            return daily_compare(ctx, spec)
        if t == "kpi_watch":
            return kpi_watch(ctx, spec)
        if t == "rank_table":
            return rank_table(ctx, spec)
        if t == "map_change":
            return map_change(ctx, spec)
        if t == "diagnosa":
            from .diagnosa import build
            d = build(spec.get("metric", "revenue"), spec.get("region", ""), spec.get("kabupaten", ""), spec.get("basis", "month"))
            return {"status": "ok", "title": d["title"], "delta": d["total"]["delta"], "summary": d["summary_short"], "basis": d["basis"]["label"]}
        if t == "simulasi":
            from .simulasi import build
            d = build(spec.get("metric", "revenue"), spec.get("region", ""))
            return {"status": "ok", "estimate": d["estimate"], "target": d["target"], "gap": d["gap"], "need_per_day": d["need_per_day"],
                    "per_day": d["per_day"], "metric": d["metric"]}
        if t == "unavailable":
            metric = spec.get("metric")
            if metric in METRICS and ctx.win:  # the dump has it now: show it
                return daily_compare(ctx, {**spec, "type": "daily_compare"})
            return {"status": "unavailable", "message": "Belum tersedia di Performance dump",
                    "detail": "Pin tetap disimpan dan akan terisi otomatis saat data masuk dump." + (f" {spec['suggest']}" if spec.get("suggest") else ""),
                    "short": "Akan terisi otomatis saat data masuk."}
        if t == "notes":
            target = db.query(Pin).filter(Pin.id == spec.get("for_pin")).first()
            notes = db.query(PinNote).filter(PinNote.pin_id == (target.id if target else pin.id)).order_by(PinNote.created_at).all()
            users = {u.id: u for u in db.query(User).filter(User.id.in_([n.user_id for n in notes])).all()} if notes else {}
            return {"status": "ok", "for_title": target.title if target else None, "notes": [_note(n, users) for n in notes]}
        if t == "answer":
            return {"status": "frozen", **{k: spec.get(k) for k in ("question", "text", "columns", "rows", "chart", "asked_at")}}
    except HTTPException as e:
        return {"status": "unavailable", "message": str(e.detail)}
    except Exception as e:  # one broken pin never breaks the board
        log.warning(f"pin {pin.id}: {e}")
        return {"status": "error", "message": "Pin ini gagal dihitung"}
    return {"status": "error", "message": "Jenis pin tidak dikenal"}


def _note(n: PinNote, users: dict) -> dict:
    u = users.get(n.user_id)
    name = ((u.full_name or u.username) if u else "Pengguna").split()[0]
    return {"id": n.id, "user": name, "initial": name[:1].upper(), "color": avatar_color(name), "text": n.text,
            "at": n.created_at.isoformat(), "at_label": _when(n.created_at)}


def _when(dt: datetime) -> str:
    w = dt.replace(tzinfo=timezone.utc).astimezone(WIB)
    d = (today_wib() - w.date()).days
    day = "Hari ini" if d == 0 else "Kemarin" if d == 1 else day_label(w.date())
    return f"{day} {w:%H.%M}"


# ── Serialisation ───────────────────────────────────────────────────────────

def _pin_json(p: Pin, data: Optional[dict] = None) -> dict:
    spec = _j(p.spec, {}) or {}
    return {"id": p.id, "board_id": p.board_id, "kind": p.kind, "title": p.title, "subtitle": p.subtitle, "origin": p.origin,
            "origin_label": ORIGIN_LABEL.get(p.origin, "Dari Agent") + (f", {day_label(p.created_at.date())}" if p.origin == "tanya" else ""),
            "spec": spec, "col": p.col, "position": p.position, "data": data,
            "ask": (spec.get("question") or p.title) if p.kind != "notes" else None,
            "notes_count": None}


def _schedule_text(b: Board) -> Optional[str]:
    if b.schedule_weekday is None:
        return None
    return f"{DAYS[b.schedule_weekday % 7]} {b.schedule_hour:02d}.{b.schedule_minute:02d}"


def _members(db: Session, b: Board) -> list[dict]:
    rows = db.query(BoardMember).filter(BoardMember.board_id == b.id).order_by(BoardMember.id).all()
    ids = [b.owner_id] + [m.user_id for m in rows]
    users = {u.id: u for u in db.query(User).filter(User.id.in_(ids)).all()}
    out = []
    for uid, role in [(b.owner_id, "owner")] + [(m.user_id, m.role) for m in rows]:
        u = users.get(uid)
        if not u:
            continue
        name = (u.full_name or u.username).split()[0]
        out.append({"id": uid, "name": u.full_name or u.username, "initial": name[:1].upper(), "color": avatar_color(name), "role": role})
    return out


def board_summary(db: Session, b: Board, user: User) -> dict:
    n = db.query(Pin).filter(Pin.board_id == b.id).count()
    return {"id": b.id, "name": b.name, "pins": n, "shared": b.owner_id != user.id}


def board_detail(db: Session, b: Board, user: User, role: str) -> dict:
    pins = db.query(Pin).filter(Pin.board_id == b.id).order_by(Pin.col, Pin.position, Pin.id).all()
    ctx = Ctx()
    out = []
    notes_by = {}
    if pins:
        for pid, in db.query(PinNote.pin_id).filter(PinNote.pin_id.in_([p.id for p in pins])).all():
            notes_by[pid] = notes_by.get(pid, 0) + 1
    for p in pins:
        j = _pin_json(p, pin_data(ctx, db, p))
        j["notes_count"] = notes_by.get(p.id, 0)
        out.append(j)
    members = _members(db, b)
    sched = _schedule_text(b)
    recips = len([e for e in (b.schedule_recipients or "").split(",") if e.strip()]) + len(members)
    parts = [f"{len(pins)} pin"]
    if len(members) > 1:
        parts.append(f"dibagikan ke {len(members) - 1} orang")
    if sched:
        parts.append(f"dikirim ke email setiap {sched}")
    fresh = ctx.source.get("kind") in ("dump", "bigquery")
    return {"id": b.id, "name": b.name, "role": role, "owner_id": b.owner_id, "summary": " · ".join(parts),
            "pins": out, "members": members, "columns": COLUMNS,
            "schedule": {"weekday": b.schedule_weekday, "hour": b.schedule_hour, "minute": b.schedule_minute, "label": sched,
                         "recipients": recips, "format": "PDF"} if sched else None,
            "fresh": {"ok": fresh, "label": ("Segar · " if fresh else "Belum segar · ") + _dump_short(ctx.source)},
            "source": ctx.source}


def _dump_short(src: dict) -> str:
    created = src.get("created_at")
    if src.get("kind") == "bigquery" or not created:
        return src.get("label") or ""
    w = datetime.fromisoformat(created).astimezone(WIB)
    return f"dump {w.day} {perf_dump.MONTHS_ID[w.month - 1]} {w:%H.%M}"


# ── API ─────────────────────────────────────────────────────────────────────

class BoardIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)


class BoardPatch(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=120)
    schedule_weekday: Optional[int] = Field(None, ge=-1, le=6)  # -1 clears the schedule
    schedule_hour: Optional[int] = Field(None, ge=0, le=23)
    schedule_minute: Optional[int] = Field(None, ge=0, le=59)
    schedule_recipients: Optional[str] = Field(None, max_length=1000)


class OrderIn(BaseModel):
    columns: list[list[int]]


class MemberIn(BaseModel):
    user: str = Field(..., min_length=2, max_length=160)
    role: str = Field("view", pattern="^(view|edit)$")


class PinIn(BaseModel):
    board_id: Optional[int] = None
    kind: str = Field("chart", pattern="^(chart|map|table|kpi|notes|answer)$")
    title: str = Field(..., min_length=1, max_length=200)
    subtitle: Optional[str] = Field(None, max_length=255)
    spec: dict
    origin: str = Field("tanya", max_length=20)


class PinPatch(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    subtitle: Optional[str] = Field(None, max_length=255)
    board_id: Optional[int] = None


class NoteIn(BaseModel):
    text: str = Field(..., min_length=1, max_length=2000)


@router.get("/boards")
def list_boards(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    default_board(db, user)
    own = db.query(Board).filter(Board.owner_id == user.id).order_by(Board.position, Board.id).all()
    shared_ids = [m.board_id for m in db.query(BoardMember).filter(BoardMember.user_id == user.id).all()]
    shared = db.query(Board).filter(Board.id.in_(shared_ids)).order_by(Board.id).all() if shared_ids else []
    return {"boards": [board_summary(db, b, user) for b in own], "shared": [board_summary(db, b, user) for b in shared],
            "shared_pins": sum(db.query(Pin).filter(Pin.board_id == b.id).count() for b in shared)}


@router.post("/boards")
def create_board(body: BoardIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    n = db.query(Board).filter(Board.owner_id == user.id).count()
    if n >= 20:
        raise HTTPException(400, "Maksimal 20 papan")
    b = Board(owner_id=user.id, name=body.name.strip(), position=n)
    db.add(b)
    db.commit()
    db.refresh(b)
    return board_summary(db, b, user)


@router.get("/boards/{bid}")
def get_board(bid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, role = _board(db, bid, user)
    return board_detail(db, b, user, role)


@router.patch("/boards/{bid}")
def patch_board(bid: int, body: BoardPatch, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, role = _board(db, bid, user, edit=True)
    if body.name:
        b.name = body.name.strip()
    if body.schedule_weekday is not None:
        if role != "owner":
            raise HTTPException(403, "Hanya pemilik papan yang bisa mengatur jadwal kirim")
        b.schedule_weekday = None if body.schedule_weekday < 0 else body.schedule_weekday
    if body.schedule_hour is not None:
        b.schedule_hour = body.schedule_hour
    if body.schedule_minute is not None:
        b.schedule_minute = body.schedule_minute
    if body.schedule_recipients is not None:
        b.schedule_recipients = ",".join(e.strip() for e in body.schedule_recipients.split(",") if re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", e.strip()))
    db.commit()
    return board_detail(db, b, user, role)


@router.delete("/boards/{bid}")
def delete_board(bid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, role = _board(db, bid, user)
    if role != "owner":
        raise HTTPException(403, "Hanya pemilik yang bisa menghapus papan")
    db.query(PinNote).filter(PinNote.pin_id.in_(db.query(Pin.id).filter(Pin.board_id == bid))).delete(synchronize_session=False)
    db.query(Pin).filter(Pin.board_id == bid).delete()
    db.query(BoardMember).filter(BoardMember.board_id == bid).delete()
    db.delete(b)
    db.commit()
    return {"ok": True}


@router.put("/boards/{bid}/order")
def order_board(bid: int, body: OrderIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, _ = _board(db, bid, user, edit=True)
    pins = {p.id: p for p in db.query(Pin).filter(Pin.board_id == bid).all()}
    for c, ids in enumerate(body.columns[:COLUMNS]):
        for i, pid in enumerate(ids):
            if pid in pins:
                pins[pid].col, pins[pid].position = c, i
    db.commit()
    return {"ok": True}


@router.post("/boards/{bid}/members")
def add_member(bid: int, body: MemberIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, role = _board(db, bid, user)
    if role != "owner":
        raise HTTPException(403, "Hanya pemilik yang bisa membagikan papan")
    who = body.user.strip().lower()
    u = db.query(User).filter((User.username == who) | (User.email == who)).first()
    if not u or not u.is_active:
        raise HTTPException(404, "Pengguna tidak ditemukan")
    if u.id == b.owner_id:
        raise HTTPException(400, "Pemilik papan sudah punya akses")
    m = db.query(BoardMember).filter(BoardMember.board_id == bid, BoardMember.user_id == u.id).first()
    if m:
        m.role = body.role
    else:
        db.add(BoardMember(board_id=bid, user_id=u.id, role=body.role))
        db.add(Notification(user_id=u.id, title=f"Papan dibagikan: {b.name}", kind="info",
                            message=f"{(user.full_name or user.username).split()[0]} membagikan papan Ruang Saya ke kamu ({'edit' if body.role == 'edit' else 'lihat'}).",
                            link=f"/ruang?board={bid}", push=True))
    db.commit()
    return {"members": _members(db, b)}


@router.delete("/boards/{bid}/members/{uid}")
def remove_member(bid: int, uid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, role = _board(db, bid, user)
    if role != "owner" and uid != user.id:
        raise HTTPException(403, "Hanya pemilik yang bisa mengatur akses")
    db.query(BoardMember).filter(BoardMember.board_id == bid, BoardMember.user_id == uid).delete()
    db.commit()
    return {"members": _members(db, b)}


@router.post("/pins")
def create_pin(body: PinIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if body.spec.get("type") not in SPEC_TYPES:
        raise HTTPException(400, "Jenis pin tidak dikenal")
    if len(json.dumps(body.spec)) > 200_000:
        raise HTTPException(413, "Pin terlalu besar")
    b = _board(db, body.board_id, user, edit=True)[0] if body.board_id else default_board(db, user)
    counts = [db.query(Pin).filter(Pin.board_id == b.id, Pin.col == c).count() for c in range(COLUMNS)]
    col = counts.index(min(counts))
    p = Pin(board_id=b.id, kind=body.kind, title=body.title.strip(), subtitle=body.subtitle, spec=json.dumps(body.spec),
            origin=body.origin, col=col, position=counts[col], created_by=user.id)
    db.add(p)
    db.commit()
    db.refresh(p)
    return {"pin": _pin_json(p), "board": board_summary(db, b, user)}


@router.patch("/pins/{pid}")
def patch_pin(pid: int, body: PinPatch, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    p = db.query(Pin).filter(Pin.id == pid).first()
    if not p:
        raise HTTPException(404, "Pin tidak ditemukan")
    _board(db, p.board_id, user, edit=True)
    if body.title:
        p.title = body.title.strip()
    if body.subtitle is not None:
        p.subtitle = body.subtitle
    if body.board_id and body.board_id != p.board_id:
        _board(db, body.board_id, user, edit=True)
        p.board_id, p.col, p.position = body.board_id, 0, 0
    db.commit()
    return {"pin": _pin_json(p)}


@router.delete("/pins/{pid}")
def delete_pin(pid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    p = db.query(Pin).filter(Pin.id == pid).first()
    if not p:
        raise HTTPException(404, "Pin tidak ditemukan")
    _board(db, p.board_id, user, edit=True)
    db.query(PinNote).filter(PinNote.pin_id == pid).delete()
    db.delete(p)
    db.commit()
    return {"ok": True}


@router.post("/pins/{pid}/notes")
def add_note(pid: int, body: NoteIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    p = db.query(Pin).filter(Pin.id == pid).first()
    if not p:
        raise HTTPException(404, "Pin tidak ditemukan")
    b, _ = _board(db, p.board_id, user)
    n = PinNote(pin_id=pid, user_id=user.id, text=body.text.strip())
    db.add(n)
    members = {m["name"].split()[0].lower(): m["id"] for m in _members(db, b)}
    for name in set(re.findall(r"@(\w+)", body.text.lower())):
        uid = members.get(name)
        if uid and uid != user.id:
            db.add(Notification(user_id=uid, title=f"Kamu disebut di {b.name}", kind="info",
                                message=f"{(user.full_name or user.username).split()[0]}: {body.text.strip()[:180]}",
                                link=f"/ruang?board={b.id}", push=True))
    db.commit()
    db.refresh(n)
    return {"note": _note(n, {user.id: user})}


# ── Scheduled send ──────────────────────────────────────────────────────────

def _pdf(detail: dict) -> Optional[bytes]:
    try:
        from reportlab.lib.pagesizes import A4
        from reportlab.pdfgen import canvas
        from .email_service import _ensure_fonts
    except Exception:
        return None
    has_fonts = _ensure_fonts()
    bold, body = ("Poppins-SemiBold", "Prompt") if has_fonts else ("Helvetica-Bold", "Helvetica")
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    W, H = A4
    y = H - 56

    def line(text, font, size, color=(0.06, 0.12, 0.11), dy=None):
        nonlocal y
        if y < 60:
            c.showPage()
            y = H - 56
        try:
            c.setFont(font, size)
        except KeyError:
            c.setFont("Helvetica", size)
        c.setFillColorRGB(*color)
        c.drawString(48, y, text[:110])
        y -= dy or size * 1.6

    line(detail["name"], bold, 18)
    line(f"Agent Java · Ruang Saya · {detail['fresh']['label']} · angka dibekukan saat dikirim", body, 9.5, (0.35, 0.42, 0.41), 26)
    for p in detail["pins"]:
        d = p.get("data") or {}
        line(p["title"], bold, 12.5, dy=17)
        if p.get("subtitle"):
            line(p["subtitle"], body, 9.5, (0.35, 0.42, 0.41), 15)
        st = d.get("status")
        if st == "ok" and d.get("value_label"):
            line(f"{d['value_label']}   {d.get('growth_label', '')}", body, 11)
        elif st == "ok" and d.get("tiles"):
            for t in d["tiles"]:
                line(f"{t['label']}: {t['value']} {t.get('delta_label', '')}", body, 10.5, dy=15)
        elif st == "ok" and d.get("rows"):
            for r in d["rows"]:
                line(f"{r['name']}: {r['pct_label']} ({r['abs_label']})", body, 10.5, dy=15)
        elif st == "ok" and d.get("list"):
            for r in d["list"][:8]:
                line(f"{r['name']}: {r['pct_label']}", body, 10.5, dy=15)
        elif st == "ok" and d.get("notes") is not None:
            for nn in d["notes"][-3:]:
                line(f"{nn['user']} ({nn['at_label']}): {nn['text']}", body, 10, dy=15)
        elif st == "frozen":
            line(f"Jawaban tersimpan: {(d.get('text') or d.get('question') or '')[:100]}", body, 10)
        elif d.get("message"):
            line(d["message"], body, 10, (0.72, 0.47, 0.12))
        y -= 8
    c.save()
    return buf.getvalue()


def send_board(db: Session, b: Board, user: User) -> dict:
    from . import email_service
    detail = board_detail(db, b, user, "owner")
    to = {m["id"] for m in detail["members"]}
    emails = [u.email for u in db.query(User).filter(User.id.in_(to)).all() if u.email]
    emails += [e.strip() for e in (b.schedule_recipients or "").split(",") if e.strip()]
    pdf = _pdf(detail)
    html = email_service._base_html(f"<h2>{b.name}</h2><p>Papan Ruang Saya dengan {len(detail['pins'])} pin. "
                                    f"Angka dibekukan saat dikirim ({detail['fresh']['label']}). PDF terlampir.</p>")
    sent = 0
    for e in dict.fromkeys(emails):
        try:
            if email_service._send_with_pdf(e, f"{b.name} · Ruang Saya", html, pdf, f"ruang-saya-{today_wib().isoformat()}.pdf"):
                sent += 1
        except Exception as ex:
            log.warning(f"board {b.id} to {e}: {ex}")
    b.last_sent_on = today_wib().isoformat()
    db.commit()
    return {"sent": sent, "recipients": len(set(emails))}


@router.post("/boards/{bid}/send")
def send_now(bid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    b, role = _board(db, bid, user)
    if role != "owner":
        raise HTTPException(403, "Hanya pemilik yang bisa mengirim papan")
    return send_board(db, b, user)


def send_due() -> int:
    """Hourly from main.py: send boards whose weekday and time have passed today (WIB)."""
    now = datetime.now(WIB)
    db = SessionLocal()
    n = 0
    try:
        for b in db.query(Board).filter(Board.schedule_weekday.isnot(None)).all():
            if b.last_sent_on == now.date().isoformat() or now.weekday() != b.schedule_weekday:
                continue
            if (now.hour, now.minute) < (b.schedule_hour, b.schedule_minute):
                continue
            owner = db.query(User).filter(User.id == b.owner_id).first()
            if owner:
                send_board(db, b, owner)
                n += 1
    finally:
        db.close()
    return n
