"""Profil page (Redesign v2 page 08): one call for identity, usage, devices,
preferences and the admin shortcuts, plus saving preferences and signing a
device out. Preferences are stored on the user so web and Android share them."""
import json
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from .auth import get_current_user
from .database import AppClient, AppDownload, ChatMessage, ChatSession, LoginAudit, User, get_db
from .routes_stats import _client_label
from .telemetry import platform_from_user_agent

router = APIRouter(prefix="/api/profile", tags=["profile"])

MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]
REGIONS = [("JAVA", "Circle Java"), ("WEST JAVA", "West Java"), ("CENTRAL JAVA", "Central Java"), ("EAST JAVA", "East Java")]
DEPARTMENTS = ["Business Planning", "Sales", "Marketing", "Network", "Finance", "Operations"]
# Notification kinds x channels. In-app is always on, so only email and push are stored.
NOTIFY_KINDS = ("alert_kritis", "alert_peringatan", "laporan", "versi")
DEFAULT_PREFS: dict[str, Any] = {
    "theme": "light", "accent": "teal", "density": "standar", "lang": "id",
    "targetLine": True, "animation": True, "default_region": "JAVA",
    "notify": {
        "alert_kritis": {"email": True, "push": True},
        "alert_peringatan": {"email": False, "push": True},
        "laporan": {"email": True, "push": False},
        "versi": {"email": False, "push": True},
    },
    "quiet_hours": True,
}
_ENUMS = {"theme": {"light", "dark", "system"}, "accent": {"teal", "laut", "zamrud", "amber", "grafit"},
          "density": {"ringkas", "standar", "lega"}, "lang": {"id"}, "default_region": {k for k, _ in REGIONS}}


def _naive(dt: Optional[datetime]) -> Optional[datetime]:
    return dt.astimezone(timezone.utc).replace(tzinfo=None) if dt and dt.tzinfo else dt


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return (_naive(dt).isoformat() + "Z") if dt else None


def prefs_of(user: User) -> dict:
    """Stored preferences over the defaults (unknown keys and bad values dropped)."""
    try:
        raw = json.loads(user.preferences or "{}")
    except (TypeError, ValueError):
        raw = {}
    out = json.loads(json.dumps(DEFAULT_PREFS))
    for k, v in raw.items():
        if k == "notify" and isinstance(v, dict):
            for kind, ch in v.items():
                if kind in NOTIFY_KINDS and isinstance(ch, dict):
                    out["notify"][kind].update({c: bool(ch[c]) for c in ("email", "push") if c in ch})
        elif k in _ENUMS and v in _ENUMS[k]:
            out[k] = v
        elif k in ("targetLine", "animation", "quiet_hours") and isinstance(v, bool):
            out[k] = v
    return out


def wants(user: User, kind: str, channel: str) -> bool:
    """Whether the user wants `kind` notifications on `channel` (email or push)."""
    return bool(prefs_of(user)["notify"].get(kind, {}).get(channel, True))


def _ago(dt: Optional[datetime], now: datetime) -> str:
    if not dt:
        return ""
    m = int((now - _naive(dt)).total_seconds() // 60)
    if m < 5:
        return "aktif sekarang"
    if m < 60:
        return f"{m} menit lalu"
    if m < 60 * 24:
        return f"{m // 60} jam lalu"
    return f"{m // (60 * 24)} hari lalu"


def _devices(db: Session, user: User, request: Request, now: datetime) -> list[dict]:
    ua = request.headers.get("user-agent")
    platform = (request.headers.get("x-client-platform") or platform_from_user_agent(ua)).lower()
    model = (request.headers.get("x-device-model") or "").strip()[:120]
    out: list[dict] = []
    current_label = None
    if platform != "android":
        current_label = _client_label(ua)
        out.append({"id": None, "kind": "web", "name": current_label.replace(" ", " · ", 1) if " " in current_label else current_label,
                    "sub": "aktif sekarang", "current": True, "can_sign_out": False})
    since = now - timedelta(days=60)
    apps = (db.query(AppClient)
            .filter(AppClient.user_id == user.id, AppClient.platform == "android", AppClient.signed_out_at.is_(None),
                    AppClient.last_seen >= since)
            .order_by(AppClient.last_seen.desc()).all())
    for a in apps:
        cur = platform == "android" and a.device_model == model
        out.append({"id": a.id, "kind": "android", "name": "Android · Agent Java",
                    "sub": " · ".join(x for x in (a.device_model, "aktif sekarang" if cur else _ago(a.last_seen, now)) if x),
                    "current": cur, "can_sign_out": not cur, "app_version": a.app_version})
    # Other browsers that signed in during the last 30 days (shown, cannot be signed out one by one).
    seen = {current_label}
    rows = (db.query(LoginAudit.user_agent, func.max(LoginAudit.created_at))
            .filter(LoginAudit.user_id == user.id, LoginAudit.action == "login", LoginAudit.created_at >= now - timedelta(days=30))
            .group_by(LoginAudit.user_agent).order_by(func.max(LoginAudit.created_at).desc()).limit(20).all())
    for agent, last in rows:
        if platform_from_user_agent(agent) == "android":
            continue
        label = _client_label(agent)
        if label in seen:
            continue
        seen.add(label)
        out.append({"id": None, "kind": "web", "name": label.replace(" ", " · ", 1) if " " in label else label,
                    "sub": f"masuk {_ago(last, now)}", "current": False, "can_sign_out": False})
    return out[:6]


@router.get("")
def profile(request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    month0 = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    questions = (db.query(func.count(ChatMessage.id))
                 .join(ChatSession, ChatSession.id == ChatMessage.session_id)
                 .filter(ChatSession.user_id == user.id, ChatMessage.role == "user", ChatMessage.created_at >= month0)
                 .scalar() or 0)
    changed = _naive(user.password_changed_at)
    installed = (db.query(func.count(AppClient.id))
                 .filter(AppClient.user_id == user.id, AppClient.platform == "android", AppClient.signed_out_at.is_(None))
                 .scalar() or 0)
    prefs = prefs_of(user)
    out = {
        "user": {
            "id": user.id, "username": user.username, "full_name": user.full_name, "email": user.email,
            "department": user.department, "role": user.role,
            "default_region": prefs["default_region"],
            "default_region_label": dict(REGIONS)[prefs["default_region"]],
            "updated_at": _iso(user.updated_at),
        },
        "stats": {"last_login": _iso(user.last_login), "login_count": user.login_count or 0,
                  "questions_month": questions, "month_short": MONTHS[now.month - 1]},
        "security": {"password_changed_at": _iso(changed),
                     "password_days": (now - changed).days if changed else None},
        "devices": _devices(db, user, request, now),
        "apk": {"installed_devices": installed},
        "prefs": prefs,
        "options": {"regions": [{"key": k, "label": v} for k, v in REGIONS],
                    "departments": sorted({*DEPARTMENTS, *(d for (d,) in db.query(User.department).distinct() if d)})},
    }
    if user.role == "admin":
        week = now - timedelta(days=7)
        active = {uid for (uid,) in db.query(LoginAudit.user_id).filter(LoginAudit.created_at >= week).distinct()}
        active |= {uid for (uid,) in db.query(AppClient.user_id).filter(AppClient.last_seen >= week).distinct()}
        latest = db.query(func.max(AppDownload.version_name)).scalar()
        from .app_update import _load_release
        version = _load_release().get("version_name") or latest
        # NULL counts as approved (accounts created before access requests existed).
        approved = (User.approval_status.is_(None)) | (User.approval_status == "approved")
        out["admin"] = {
            "active_users_7d": len(active),
            "version_name": version,
            "downloads_current": db.query(func.count(AppDownload.id)).filter(AppDownload.version_name == version).scalar() or 0,
            "accounts": db.query(func.count(User.id)).filter(approved).scalar() or 0,
            "inactive": db.query(func.count(User.id)).filter(approved, User.is_active.is_(False)).scalar() or 0,
            "pending": db.query(func.count(User.id)).filter(User.approval_status == "pending").scalar() or 0,
        }
    return out


class PrefsIn(BaseModel):
    prefs: dict


@router.put("/prefs")
def save_prefs(body: PrefsIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Merge a partial preference object (e.g. {"theme": "dark"} or {"notify": {"laporan": {"push": true}}})."""
    cur = prefs_of(user)
    patch = body.prefs
    merged = {**cur, **{k: v for k, v in patch.items() if k != "notify"}}
    if isinstance(patch.get("notify"), dict):
        merged["notify"] = {k: {**cur["notify"][k], **(patch["notify"].get(k) or {})} for k in NOTIFY_KINDS}
    user.preferences = json.dumps(merged)
    clean = prefs_of(user)
    user.preferences = json.dumps(clean)
    db.commit()
    return {"prefs": clean}


@router.post("/devices/{device_id}/sign-out")
def sign_out_device(device_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Signs an Android device out: its tokens stop working until it signs in again."""
    row = db.query(AppClient).filter(AppClient.id == device_id, AppClient.user_id == user.id).first()
    if row is None:
        raise HTTPException(404, "Perangkat tidak ditemukan")
    row.signed_out_at = datetime.now(timezone.utc)
    db.commit()
    return {"ok": True}
