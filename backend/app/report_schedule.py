"""Scheduled reports — the agent builds the Performa report and emails it.

GET/POST          /api/report-schedules
PATCH/DELETE      /api/report-schedules/{id}
POST              /api/report-schedules/{id}/send-now
GET               /api/report-schedules/runs      (library entries)

The numbers come from dashboard.build_overview, so the email matches what the
Laporan page shows. `run_due()` is called by the hourly loop in main.py and
sends each active schedule at most once per WIB day.
"""
from __future__ import annotations

import html
import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from . import email_service, reports_cache
from .auth import get_current_user
from .dashboard import build_overview
from .database import ReportLink, ReportRun, ReportSchedule, SessionLocal, User, get_db, utcnow

log = logging.getLogger("report_schedule")
router = APIRouter(prefix="/api/report-schedules", tags=["report-schedules"])

DAYS = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"]
_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _now_wib() -> datetime:
    return datetime.now(timezone.utc) + timedelta(hours=7)


def _recipients(raw: str) -> list[str]:
    return [e.strip() for e in (raw or "").replace(";", ",").split(",") if _EMAIL.match(e.strip())]


def is_due(s: ReportSchedule, now: datetime) -> bool:
    """`now` is WIB. Due once the hour has passed on the scheduled day."""
    if not s.active or now.hour < s.hour or s.last_sent_on == now.date().isoformat():
        return False
    if s.frequency == "bulanan":
        return now.day == s.monthday
    return now.weekday() == s.weekday


def describe(s: ReportSchedule) -> str:
    when = f"tiap {DAYS[s.weekday % 7]}" if s.frequency == "mingguan" else f"tiap tanggal {s.monthday}"
    return f"{when} {s.hour:02d}.00 WIB"


def _fmt(fmt: str, v) -> str:
    if v is None:
        return "–"
    a = abs(v)
    if fmt == "currency":
        body = f"{v / 1e12:.2f} T" if a >= 1e12 else f"{v / 1e9:.1f} M" if a >= 1e9 else f"{v / 1e6:.1f} jt"
        return "Rp " + body.replace(".", ",")
    if fmt == "gb":
        return (f"{v / 1e6:.1f} PB" if a >= 1e6 else f"{v / 1e3:.1f} TB" if a >= 1e3 else f"{v:.1f} GB").replace(".", ",")
    if fmt == "percent":
        return f"{v:.2f}%".replace(".", ",")
    return (f"{v / 1e6:.1f} jt" if a >= 1e6 else f"{v / 1e3:.0f} rb" if a >= 1e3 else f"{v:.0f}").replace(".", ",")


def _delta(v, unit="%") -> str:
    if v is None:
        return ""
    color = "#1F7A3A" if v >= 0 else "#C42B2B"
    arrow = "▲" if v >= 0 else "▼"
    num = f"{abs(v):.{2 if unit == 'pp' else 1}f}".replace(".", ",")
    return f'<span style="color:{color};font-weight:bold;font-size:12px;">{arrow} {num}{" pp" if unit == "pp" else "%"}</span>'


def report_html(ov: dict, name: str, shared_until: Optional[datetime] = None) -> str:
    """Email body for one report, table-based for Outlook. Also served as the shared-link page."""
    scope = (ov["scope"].get("region") or "Jawa").title()
    summary = html.escape(ov["summary"]["text"]).replace("**", "")
    tiles = "".join(
        f'<td width="25%" valign="top" style="padding:12px;background:#F5F9F8;border:4px solid #fff;border-radius:12px;">'
        f'<div style="font-size:12px;color:#5A6B68;">{html.escape(k["label"])}</div>'
        f'<div style="font-size:20px;font-weight:bold;color:#0F1F1D;padding:2px 0;">{_fmt(k["format"], k["value"])}</div>'
        f'{_delta(k["pct_change"], k.get("change_unit", "%"))}</td>'
        for k in ov["kpis"])
    rows = "".join(
        f'<tr><td style="padding:8px 6px;border-top:1px solid #E1E9E7;font-size:13px;">{html.escape(r["region"].title())}</td>'
        f'<td align="right" style="padding:8px 6px;border-top:1px solid #E1E9E7;font-size:13px;">{_fmt("currency", r["revenue"])}</td>'
        f'<td align="right" style="padding:8px 6px;border-top:1px solid #E1E9E7;">{_delta(r["mom_pct"])}</td>'
        f'<td align="right" style="padding:8px 6px;border-top:1px solid #E1E9E7;font-size:13px;">{_fmt("number", r["subs"])}</td>'
        f'<td align="right" style="padding:8px 6px;border-top:1px solid #E1E9E7;font-size:13px;">{_fmt("gb", r["payload_gb"])}</td></tr>'
        for r in ov["regions"])
    if shared_until is not None:
        until = (shared_until + timedelta(hours=7)).strftime("%d/%m/%Y %H.%M")
        footer = f"Angka MTD dibandingkan bulan lalu, dari BigQuery. Tautan ini berlaku sampai {until} WIB."
    else:
        footer = (f"Angka MTD dibandingkan bulan lalu, dari BigQuery. Anda menerima email ini karena terdaftar "
                  f'di jadwal "{html.escape(name)}".')
    content = f"""
<div class="eyebrow" style="color:#0E8579;margin-top:0;">Laporan performa · {html.escape(name)}</div>
<h2>{html.escape(scope)} · {html.escape(ov["month_label"])}</h2>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>{tiles}</tr></table>
<p style="background:#E6F7F5;border-radius:12px;padding:12px 14px;color:#074D45;"><strong>Ringkasan oleh agent.</strong> {summary}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:8px;">
<tr><td style="font-size:11px;color:#5A6B68;font-weight:bold;padding:6px;">REGION</td><td align="right" style="font-size:11px;color:#5A6B68;font-weight:bold;padding:6px;">REVENUE</td>
<td align="right" style="font-size:11px;color:#5A6B68;font-weight:bold;padding:6px;">MOM</td><td align="right" style="font-size:11px;color:#5A6B68;font-weight:bold;padding:6px;">PELANGGAN</td>
<td align="right" style="font-size:11px;color:#5A6B68;font-weight:bold;padding:6px;">PAYLOAD</td></tr>
{rows}
</table>
<p style="text-align:center;margin-top:22px;"><a class="btn" href="{email_service.APP_URL}/reports">Buka laporan lengkap</a></p>
<p class="muted">{footer}</p>
"""
    return email_service._base_html(content)


def send(db: Session, s: ReportSchedule, user: Optional[User] = None) -> dict:
    to = _recipients(s.recipients)
    if not to and user is not None:
        to = [user.email]
    ov = reports_cache.get_or_build("dashboard", f"{s.region}|6", lambda: build_overview(s.region, 6))
    if not isinstance(ov, dict) or "error" in ov:
        raise RuntimeError((ov or {}).get("error", "data belum tersedia"))
    body = report_html(ov, s.name)
    subject = f"{s.name} · {ov['month_label']}"
    sent = sum(1 for addr in to if email_service._send(addr, subject, body))
    run = ReportRun(user_id=s.user_id, schedule_id=s.id, title=s.name, kind=s.frequency, region=s.region,
                    recipients=sent, status="terkirim" if sent else "gagal")
    db.add(run)
    s.last_sent_on = _now_wib().date().isoformat()
    db.commit()
    return {"sent": sent, "recipients": len(to)}


def run_due() -> int:
    """Send every schedule that is due now. Returns how many were sent."""
    now = _now_wib()
    db = SessionLocal()
    n = 0
    try:
        for s in db.query(ReportSchedule).filter(ReportSchedule.active.is_(True)).all():
            if not is_due(s, now):
                continue
            try:
                send(db, s, db.query(User).get(s.user_id))
                n += 1
            except Exception as e:
                log.warning(f"schedule {s.id}: {e}")
    finally:
        db.close()
    return n


class ScheduleIn(BaseModel):
    name: Optional[str] = Field(None, max_length=160)
    region: str = ""
    frequency: str = Field("mingguan", pattern="^(mingguan|bulanan)$")
    weekday: int = Field(0, ge=0, le=6)
    monthday: int = Field(1, ge=1, le=28)
    hour: int = Field(8, ge=0, le=23)
    recipients: str = ""
    active: bool = True


class SchedulePatch(BaseModel):
    name: Optional[str] = Field(None, max_length=160)
    frequency: Optional[str] = Field(None, pattern="^(mingguan|bulanan)$")
    weekday: Optional[int] = Field(None, ge=0, le=6)
    monthday: Optional[int] = Field(None, ge=1, le=28)
    hour: Optional[int] = Field(None, ge=0, le=23)
    recipients: Optional[str] = None
    active: Optional[bool] = None


def _json(s: ReportSchedule) -> dict:
    return {
        "id": s.id, "name": s.name, "region": s.region, "frequency": s.frequency, "weekday": s.weekday,
        "monthday": s.monthday, "hour": s.hour, "recipients": _recipients(s.recipients), "active": s.active,
        "description": describe(s), "last_sent_on": s.last_sent_on,
    }


def _own(db: Session, user: User, sid: int) -> ReportSchedule:
    s = db.query(ReportSchedule).filter(ReportSchedule.id == sid, ReportSchedule.user_id == user.id).first()
    if not s:
        raise HTTPException(404, "Jadwal tidak ditemukan")
    return s


@router.get("")
def list_schedules(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(ReportSchedule).filter(ReportSchedule.user_id == user.id).order_by(ReportSchedule.created_at).all()
    return {"schedules": [_json(s) for s in rows]}


@router.post("")
def create_schedule(body: ScheduleIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if db.query(ReportSchedule).filter(ReportSchedule.user_id == user.id).count() >= 10:
        raise HTTPException(400, "Maksimal 10 jadwal per pengguna")
    bad = [e for e in body.recipients.replace(";", ",").split(",") if e.strip() and not _EMAIL.match(e.strip())]
    if bad:
        raise HTTPException(422, f"Email tidak valid: {', '.join(bad)}")
    scope = body.region.title() if body.region else "Jawa"
    name = (body.name or "").strip() or f"Performa {'mingguan' if body.frequency == 'mingguan' else 'bulanan'} {scope}"
    s = ReportSchedule(user_id=user.id, name=name, region=body.region.strip(), frequency=body.frequency,
                       weekday=body.weekday, monthday=body.monthday, hour=body.hour,
                       recipients=",".join(_recipients(body.recipients)) or user.email, active=body.active)
    db.add(s)
    db.commit()
    db.refresh(s)
    return _json(s)


@router.patch("/{sid}")
def update_schedule(sid: int, body: SchedulePatch, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    s = _own(db, user, sid)
    data = body.model_dump(exclude_unset=True)
    if "recipients" in data:
        data["recipients"] = ",".join(_recipients(data["recipients"])) or user.email
    for k, v in data.items():
        setattr(s, k, v)
    db.commit()
    return _json(s)


@router.delete("/{sid}")
def delete_schedule(sid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    s = _own(db, user, sid)
    db.delete(s)
    db.commit()
    return {"ok": True}


@router.post("/{sid}/send-now")
def send_now(sid: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    s = _own(db, user, sid)
    try:
        return send(db, s, user)
    except Exception as e:
        raise HTTPException(502, f"Laporan gagal dibuat: {str(e)[:200]}")


@router.get("/runs")
def list_runs(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = (db.query(ReportRun).filter(ReportRun.user_id == user.id)
            .order_by(ReportRun.created_at.desc()).limit(30).all())
    return {"runs": [{
        "id": r.id, "schedule_id": r.schedule_id, "title": r.title, "kind": r.kind, "region": r.region,
        "recipients": r.recipients, "status": r.status,
        "created_at": r.created_at.isoformat() + "Z" if r.created_at else None,
    } for r in rows]}


# ── Share links ("Bagikan tautan · berlaku 7 hari") ──

links_router = APIRouter(prefix="/api/report-links", tags=["report-links"])
LINK_DAYS = 7


class LinkIn(BaseModel):
    title: str = Field("Performa Bulanan Region Jawa", max_length=200)
    region: str = Field("", max_length=120)
    # An ad-hoc agent answer is shared as a snapshot of its table instead of the live report.
    columns: Optional[list[str]] = Field(None, max_length=60)
    rows: Optional[list[dict]] = Field(None, max_length=2000)


def table_html(title: str, columns: list[str], rows: list[dict], until: str) -> str:
    """Shared page for an ad-hoc answer: its table as it was when shared."""
    def cell(v) -> str:
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            txt = f"{v:,.0f}" if float(v).is_integer() else f"{v:,.2f}"
            return txt.replace(",", "·").replace(".", ",").replace("·", ".")
        return html.escape("" if v is None else str(v))
    head = "".join(f'<td style="font-size:11px;color:#5A6B68;font-weight:bold;padding:6px;">'
                   f'{html.escape(c.replace("_", " ").upper())}</td>' for c in columns)
    body = "".join("<tr>" + "".join(
        f'<td style="padding:7px 6px;border-top:1px solid #E1E9E7;font-size:13px;">{cell(r.get(c))}</td>' for c in columns) + "</tr>"
        for r in rows)
    content = f"""
<div class="eyebrow" style="color:#0E8579;margin-top:0;">Laporan ad-hoc dari agent</div>
<h2>{html.escape(title)}</h2>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>{head}</tr>{body}</table>
<p class="muted">{len(rows)} baris, disalin saat dibagikan. Sumber: BigQuery · Bizplan Java Agent. Tautan ini berlaku sampai {until} WIB.</p>
"""
    return email_service._base_html(content)


@links_router.post("")
def create_link(body: LinkIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """A link anyone can open for 7 days. The page is rebuilt from current data on each view."""
    import secrets
    if db.query(ReportLink).filter(ReportLink.user_id == user.id,
                                   ReportLink.created_at >= utcnow() - timedelta(days=1)).count() >= 50:
        raise HTTPException(429, "Terlalu banyak tautan hari ini")
    expires = utcnow() + timedelta(days=LINK_DAYS)
    payload = None
    if body.columns is not None:
        import json
        payload = json.dumps({"columns": body.columns, "rows": body.rows or []}, default=str)
        if len(payload) > 2_000_000:
            raise HTTPException(413, "Tabel terlalu besar untuk dibagikan; ekspor sebagai XLSX.")
    link = ReportLink(token=secrets.token_urlsafe(24), user_id=user.id, title=body.title.strip() or "Laporan",
                      region=body.region.strip(), payload=payload, expires_at=expires)
    db.add(link)
    db.commit()
    return {"path": f"/api/report-links/{link.token}", "expires_at": expires.isoformat().replace("+00:00", "Z"),
            "days": LINK_DAYS}


@links_router.get("/{token}", response_class=HTMLResponse)
def open_link(token: str, db: Session = Depends(get_db)):
    link = db.query(ReportLink).filter(ReportLink.token == token).first()
    expires = link.expires_at.replace(tzinfo=timezone.utc) if link and link.expires_at.tzinfo is None else (link.expires_at if link else None)
    if not link or expires < utcnow():
        return HTMLResponse(email_service._base_html(
            "<h2>Tautan tidak berlaku</h2><p>Tautan laporan ini sudah kedaluwarsa atau tidak ditemukan. "
            "Minta tautan baru ke pengirimnya.</p>"), status_code=404)
    link.views = (link.views or 0) + 1
    db.commit()
    if link.payload:
        import json
        data = json.loads(link.payload)
        until = (expires + timedelta(hours=7)).strftime("%d/%m/%Y %H.%M")
        return HTMLResponse(table_html(link.title, data["columns"], data["rows"], until))
    ov = reports_cache.get_or_build("dashboard", f"{link.region}|6", lambda: build_overview(link.region, 6))
    if not isinstance(ov, dict) or "error" in ov:
        raise HTTPException(503, "Data laporan belum tersedia, coba lagi nanti.")
    return HTMLResponse(report_html(ov, link.title, shared_until=expires))
