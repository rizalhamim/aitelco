"""Admin "Statistik" API: mobile-app reach and access.

GET /api/admin/app-stats?days=30
"""
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from .app_update import _load_release
from .auth import require_admin
from .database import AppClient, AppDownload, LoginAudit, UsageLog, User, get_db
from .telemetry import platform_from_user_agent

router = APIRouter(prefix="/api/admin", tags=["admin-stats"])

INACTIVE_AFTER_DAYS = 14


def _naive(dt: datetime | None) -> datetime | None:
    """SQLite hands datetimes back without tzinfo; compare everything as naive UTC."""
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).replace(tzinfo=None) if dt.tzinfo else dt


def _iso(dt: datetime | None) -> str | None:
    dt = _naive(dt)
    return dt.isoformat() + "Z" if dt else None


def _version_key(v: str | None) -> tuple:
    parts = []
    for p in (v or "").split("."):
        parts.append(int(p) if p.isdigit() else 0)
    return tuple(parts)


@router.get("/app-stats")
def app_stats(
    days: int = Query(30, ge=7, le=365),
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    now = _naive(datetime.now(timezone.utc))
    since = now - timedelta(days=days)
    release = _load_release()
    latest = release.get("version_name")

    users = db.query(User).all()
    clients = db.query(AppClient).all()
    downloads = db.query(AppDownload).all()
    logins = (db.query(LoginAudit)
              .filter(LoginAudit.created_at >= now - timedelta(days=max(days, 30)))
              .all())
    usage = (db.query(UsageLog)
             .filter(UsageLog.created_at >= now - timedelta(days=30))
             .all())

    # ── Installs & versions (latest android client per user) ──
    android_by_user: dict[int, AppClient] = {}
    for c in clients:
        if c.platform != "android":
            continue
        cur = android_by_user.get(c.user_id)
        if cur is None or _naive(c.last_seen) > _naive(cur.last_seen):
            android_by_user[c.user_id] = c
    installed = len({(c.user_id, c.device_model) for c in clients if c.platform == "android"})
    on_latest = sum(1 for c in android_by_user.values() if latest and c.app_version == latest)
    version_counts = Counter(c.app_version or "unknown" for c in android_by_user.values())

    # ── Activity ──
    def active_since(delta: timedelta) -> int:
        cut = now - delta
        ids = {u.user_id for u in usage if _naive(u.created_at) >= cut}
        ids |= {l.user_id for l in logins if l.action == "login" and _naive(l.created_at) >= cut}
        ids |= {c.user_id for c in clients if _naive(c.last_seen) >= cut}
        return len(ids)

    period_logins = [l for l in logins if l.action == "login" and _naive(l.created_at) >= since]
    login_platform = Counter(platform_from_user_agent(l.user_agent) for l in period_logins)
    failed = [l for l in logins if l.action == "failed_login" and _naive(l.created_at) >= since]

    # ── Download timeline (daily) ──
    timeline = []
    by_day = defaultdict(lambda: {"downloads": 0, "updates": 0})
    for d in downloads:
        t = _naive(d.created_at)
        if t >= since:
            by_day[t.date()]["updates" if d.source == "in_app" else "downloads"] += 1
    for i in range(days - 1, -1, -1):
        day = (now - timedelta(days=i)).date()
        timeline.append({"date": day.isoformat(), **by_day[day]})

    # ── Version adoption by week (users whose latest-seen android version that week) ──
    weeks = min(12, max(1, days // 7))
    adoption = []
    for w in range(weeks - 1, -1, -1):
        end = now - timedelta(days=7 * w)
        seen = Counter()
        for c in clients:
            if c.platform == "android" and _naive(c.first_seen) <= end:
                seen[c.app_version or "unknown"] += 1
        adoption.append({"week_end": end.date().isoformat(), "versions": dict(seen)})

    # ── Login heatmap (weekday 0=Mon × hour, UTC+7 / WIB) ──
    heat = [[0] * 24 for _ in range(7)]
    for l in period_logins:
        t = _naive(l.created_at) + timedelta(hours=7)
        heat[t.weekday()][t.hour] += 1

    # ── Per-user table ──
    last_activity: dict[int, tuple] = {}
    for u in usage:
        t = _naive(u.created_at)
        if u.user_id not in last_activity or t > last_activity[u.user_id][0]:
            last_activity[u.user_id] = (t, u.action, u.domain)
    rows = []
    for u in users:
        c = android_by_user.get(u.id)
        last_login = _naive(u.last_login)
        act = last_activity.get(u.id)
        last_seen = max([x for x in (last_login, _naive(c.last_seen) if c else None,
                                     act[0] if act else None) if x], default=None)
        rows.append({
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "department": u.department,
            "role": u.role,
            "is_active": u.is_active,
            "platform": "android" if c else "web",
            "app_version": c.app_version if c else None,
            "is_latest": bool(c and latest and c.app_version == latest),
            "device_model": c.device_model if c else None,
            "os_version": c.os_version if c else None,
            "last_login": _iso(last_login),
            "login_count": u.login_count or 0,
            "last_activity": ({"at": _iso(act[0]), "action": act[1], "domain": act[2]} if act else None),
            "status": ("aktif" if last_seen and now - last_seen <= timedelta(days=INACTIVE_AFTER_DAYS)
                       else "tidak_aktif"),
        })
    rows.sort(key=lambda r: r["last_login"] or "", reverse=True)

    outdated = [r for r in rows if r["app_version"] and not r["is_latest"]]
    outdated.sort(key=lambda r: _version_key(r["app_version"]))

    return {
        "generated_at": _iso(now),
        "period_days": days,
        "latest_release": {
            "version_name": latest,
            "version_code": release.get("version_code"),
            "mandatory": bool(release.get("mandatory")),
            "released_at": release.get("released_at"),
        },
        "kpis": {
            "downloads_total": len(downloads),
            "downloads_period": sum(1 for d in downloads if _naive(d.created_at) >= since),
            "devices_installed": installed,
            "android_users": len(android_by_user),
            "pct_on_latest": round(100 * on_latest / len(android_by_user), 1) if android_by_user else None,
            "dau": active_since(timedelta(days=1)),
            "wau": active_since(timedelta(days=7)),
            "mau": active_since(timedelta(days=30)),
            "logins_android": login_platform.get("android", 0),
            "logins_web": login_platform.get("web", 0),
            "failed_logins": len(failed),
        },
        "versions": [{"version": v, "users": n}
                     for v, n in sorted(version_counts.items(), key=lambda kv: _version_key(kv[0]), reverse=True)],
        "version_adoption": adoption,
        "downloads_timeline": timeline,
        "login_heatmap": heat,
        "failed_logins_recent": [
            {"user_id": l.user_id, "at": _iso(l.created_at), "ip": l.ip_address}
            for l in sorted(failed, key=lambda l: _naive(l.created_at), reverse=True)[:10]
        ],
        "outdated_users": [{"id": r["id"], "full_name": r["full_name"], "app_version": r["app_version"],
                            "device_model": r["device_model"], "last_login": r["last_login"]}
                           for r in outdated],
        "users": rows,
    }
