"""Admin "Statistik" API: mobile-app reach and access.

GET  /api/admin/app-stats?days=30
GET  /api/admin/app-stats/users/{id}     one user's logins, devices and topics
POST /api/admin/app-stats/remind         in-app "please update" notification
POST /api/usage/export                   log a client-side export (XLSX/PDF)
"""
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .app_update import _load_release
from .auth import get_current_user, require_admin
from .database import (AppClient, AppDownload, AppVersionSeen, LoginAudit, Notification, UsageLog,
                       User, get_db)
from .telemetry import platform_from_user_agent

router = APIRouter(prefix="/api/admin", tags=["admin-stats"])
usage_router = APIRouter(prefix="/api/usage", tags=["usage"])

INACTIVE_AFTER_DAYS = 14

# LoginAudit.action values written by routes_auth for each failure reason.
FAILURE_REASONS = {
    "failed_login": "Kata sandi salah",
    "failed_inactive": "Akun dinonaktifkan",
    "failed_token": "Token kedaluwarsa",
}

# UsageLog.domain -> topic label shown in the user drawer.
TOPICS = {
    "revenue": "Revenue", "competitive": "Market share", "market_share": "Market share",
    "network": "Site & jaringan", "network_benchmark": "Site & jaringan", "site": "Site & jaringan",
    "sales_distribution": "Distribusi sales", "ftth": "FTTH", "product": "Produk",
    "kpi_summary": "Ringkasan KPI", "report": "Laporan", "export": "Laporan",
    "advisory": "Rekomendasi", "direct_sql": "Query data",
}


def _is_failed(action: str | None) -> bool:
    return bool(action) and action.startswith("failed")


def _topic(domain: str | None) -> str:
    return TOPICS.get((domain or "").lower(), (domain or "Lainnya").replace("_", " ").title())


def _activity_label(action: str, domain: str | None, detail: str | None) -> str:
    """'Query · Revenue', 'Export · XLSX', 'Login'."""
    if action == "export":
        return "Export · " + ((detail or "").split(" · ")[0] or "file")
    if action == "query":
        return "Query · " + _topic(domain)
    return action.title()


def _client_label(ua: str | None) -> str:
    """'Chrome Android', 'Android app', 'curl' … from a User-Agent."""
    u = (ua or "").lower()
    if not u:
        return "tidak diketahui"
    if platform_from_user_agent(ua) == "android":
        return "Android app"
    for key, name in (("curl", "curl"), ("python", "script"), ("postman", "Postman")):
        if key in u:
            return name
    browser = next((n for k, n in (("edg/", "Edge"), ("firefox", "Firefox"), ("chrome", "Chrome"),
                                   ("safari", "Safari")) if k in u), "Browser")
    osname = next((n for k, n in (("android", "Android"), ("iphone", "iOS"), ("windows", "Windows"),
                                  ("mac os", "macOS"), ("linux", "Linux")) if k in u), "")
    return f"{browser} {osname}".strip()


def _release_markers(clients: list, since: datetime) -> list[dict]:
    """Release dates: data/app_release.json `history` when present, otherwise the
    day each version was first seen on a device."""
    rel = _load_release()
    out = []
    for h in rel.get("history") or []:
        if h.get("version_name") and h.get("released_at"):
            out.append({"version": h["version_name"], "date": str(h["released_at"])[:10],
                        "mandatory": bool(h.get("mandatory"))})
    if rel.get("version_name") and rel.get("released_at") and not any(
            m["version"] == rel["version_name"] for m in out):
        out.append({"version": rel["version_name"], "date": str(rel["released_at"])[:10],
                    "mandatory": bool(rel.get("mandatory"))})
    if not out:
        first: dict[str, datetime] = {}
        for c in clients:
            if c.platform == "android" and c.app_version:
                t = _naive(c.first_seen)
                if c.app_version not in first or t < first[c.app_version]:
                    first[c.app_version] = t
        out = [{"version": v, "date": t.date().isoformat(),
                "mandatory": bool(rel.get("mandatory")) and v == rel.get("version_name")}
               for v, t in first.items()]
    cut = since.date().isoformat()
    return sorted((m for m in out if m["date"] >= cut), key=lambda m: m["date"])


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
    # Two periods back, so each KPI can be compared with the period before it.
    logins = (db.query(LoginAudit)
              .filter(LoginAudit.created_at >= now - timedelta(days=max(2 * days, 30)))
              .all())
    usage = (db.query(UsageLog)
             .filter(UsageLog.created_at >= now - timedelta(days=max(2 * days, 30)))
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

    def active_between(start: datetime, end: datetime) -> int:
        ids = {u.user_id for u in usage if start <= _naive(u.created_at) < end}
        ids |= {l.user_id for l in logins if l.action == "login" and start <= _naive(l.created_at) < end}
        return len(ids)

    prev_since = since - timedelta(days=days)

    def change(cur: float, prev: float) -> float | None:
        return round(100 * (cur - prev) / prev, 1) if prev else None

    period_logins = [l for l in logins if l.action == "login" and _naive(l.created_at) >= since]
    login_platform = Counter(platform_from_user_agent(l.user_agent) for l in period_logins)
    failed = [l for l in logins if _is_failed(l.action) and _naive(l.created_at) >= since]
    by_id = {u.id: u for u in users}

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

    # ── Version adoption by week: the version each android device ran at each week's end ──
    history = db.query(AppVersionSeen).filter(AppVersionSeen.platform == "android").all()
    if not history:  # deployments from before version history was kept
        history = [AppVersionSeen(user_id=c.user_id, device_model=c.device_model, app_version=c.app_version or "unknown",
                                  first_seen=c.first_seen, last_seen=c.last_seen)
                   for c in clients if c.platform == "android"]
    by_device = defaultdict(list)
    for h in history:
        by_device[(h.user_id, h.device_model)].append(h)
    weeks = min(12, max(1, days // 7))
    adoption = []
    for w in range(weeks - 1, -1, -1):
        end = now - timedelta(days=7 * w)
        seen = Counter()
        for rows_ in by_device.values():
            ran = [h for h in rows_ if _naive(h.first_seen) <= end]
            if ran:
                seen[max(ran, key=lambda h: _naive(h.first_seen)).app_version] += 1
        adoption.append({"week_end": end.date().isoformat(), "versions": dict(seen)})

    # ── Login heatmap (weekday 0=Mon × hour, UTC+7 / WIB) ──
    heat = [[0] * 24 for _ in range(7)]
    for l in period_logins:
        t = _naive(l.created_at) + timedelta(hours=7)
        heat[t.weekday()][t.hour] += 1

    # ── Per-user table ──
    web_client: dict[int, str] = {}
    for l in sorted(logins, key=lambda l: _naive(l.created_at)):
        if l.action == "login" and l.user_agent and platform_from_user_agent(l.user_agent) == "web":
            web_client[l.user_id] = _client_label(l.user_agent)
    last_activity: dict[int, tuple] = {}
    for u in usage:
        t = _naive(u.created_at)
        if u.user_id not in last_activity or t > last_activity[u.user_id][0]:
            last_activity[u.user_id] = (t, u.action, u.domain, u.detail)
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
            "email": u.email,
            "department": u.department,
            "role": u.role,
            "is_active": u.is_active,
            "platform": "android" if c else "web",
            "app_version": c.app_version if c else None,
            "is_latest": bool(c and latest and c.app_version == latest),
            "device_model": c.device_model if c else web_client.get(u.id),
            "os_version": c.os_version if c else None,
            "last_login": _iso(last_login),
            "login_count": u.login_count or 0,
            "last_activity": ({"at": _iso(act[0]), "action": act[1], "domain": act[2],
                               "label": _activity_label(act[1], act[2], act[3])} if act else None),
            "status": ("aktif" if last_seen and now - last_seen <= timedelta(days=INACTIVE_AFTER_DAYS)
                       else "tidak_aktif"),
            "last_seen": _iso(last_seen),
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
        # Percent change of each KPI against the period before it (None without a baseline).
        "trend": {
            "downloads_period": change(sum(1 for d in downloads if _naive(d.created_at) >= since),
                                       sum(1 for d in downloads if prev_since <= _naive(d.created_at) < since)),
            "devices_installed": change(installed, len({(c.user_id, c.device_model) for c in clients
                                                        if c.platform == "android" and _naive(c.first_seen) < since})),
            "dau": change(active_between(now - timedelta(days=1), now), active_between(since - timedelta(days=1), since)),
            "failed_logins": change(len(failed), sum(1 for l in logins if _is_failed(l.action)
                                                     and prev_since <= _naive(l.created_at) < since)),
        },
        "versions": [{"version": v, "users": n}
                     for v, n in sorted(version_counts.items(), key=lambda kv: _version_key(kv[0]), reverse=True)],
        "version_adoption": adoption,
        "downloads_timeline": timeline,
        "login_heatmap": heat,
        "release_markers": _release_markers(clients, since),
        "failed_summary": {
            "total": len(failed),
            "attempts": len(failed) + len(period_logins),
            "reasons": [{"key": k, "label": lbl, "count": sum(1 for l in failed if l.action == k)}
                        for k, lbl in FAILURE_REASONS.items()],
        },
        "failed_logins_recent": [
            {"user_id": l.user_id,
             "username": by_id[l.user_id].username if l.user_id in by_id else None,
             "email": by_id[l.user_id].email if l.user_id in by_id else None,
             "reason": FAILURE_REASONS.get(l.action, "Login gagal"),
             "at": _iso(l.created_at), "ip": l.ip_address, "client": _client_label(l.user_agent)}
            for l in sorted(failed, key=lambda l: _naive(l.created_at), reverse=True)[:10]
        ],
        "outdated_users": [{"id": r["id"], "full_name": r["full_name"], "department": r["department"],
                            "app_version": r["app_version"],
                            "device_model": r["device_model"], "last_login": r["last_login"]}
                           for r in outdated],
        "users": rows,
    }


@router.get("/app-stats/users/{user_id}")
def app_stats_user(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Drawer data for one user: counts, a merged login/activity timeline,
    every device + version seen, and the topics they ask about."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(404, "User not found")
    now = _naive(datetime.now(timezone.utc))
    month = now - timedelta(days=30)
    latest = _load_release().get("version_name")

    audits = (db.query(LoginAudit).filter(LoginAudit.user_id == user_id)
              .order_by(LoginAudit.created_at.desc()).limit(200).all())
    usage = (db.query(UsageLog).filter(UsageLog.user_id == user_id)
             .order_by(UsageLog.created_at.desc()).limit(2000).all())
    clients = (db.query(AppClient).filter(AppClient.user_id == user_id)
               .order_by(AppClient.last_seen.desc()).all())

    android = next((c for c in clients if c.platform == "android"), None)
    queries = [x for x in usage if x.action == "query"]
    exports = [x for x in usage if x.action == "export"]

    def device_at(t: datetime) -> AppClient | None:
        """The android install in use at time t (latest one first seen before t)."""
        seen = [c for c in clients if c.platform == "android" and _naive(c.first_seen) <= t]
        return max(seen, key=lambda c: _naive(c.first_seen)) if seen else None

    timeline = []
    chron = sorted(audits[:60], key=lambda a: _naive(a.created_at))
    last_login_at: datetime | None = None
    for a in chron:
        t = _naive(a.created_at)
        plat = platform_from_user_agent(a.user_agent) if a.user_agent else None
        meta = []
        if _is_failed(a.action):
            kind, title = "failed", "Login gagal · " + FAILURE_REASONS.get(a.action, "lainnya").lower()
            if a.ip_address:
                meta.append(f"IP {a.ip_address}")
            meta.append(_client_label(a.user_agent))
        elif a.action == "logout":
            kind = "logout"
            if last_login_at:
                mins = int((t - last_login_at).total_seconds() // 60)
                title = f"{'Android' if plat == 'android' else 'Web'} · sesi {mins // 60} j {mins % 60} m"
            else:
                title = "Logout"
            if a.ip_address:
                meta.append(f"IP {a.ip_address}")
        else:
            kind = "login"
            last_login_at = t
            if plat == "android":
                d = device_at(t)
                title = " · ".join(x for x in ("Android", d and d.device_model, d and d.app_version and f"v{d.app_version}") if x)
            else:
                title = "Web · " + " · ".join(_client_label(a.user_agent).split(" ", 1))
            if a.ip_address:
                meta.append(f"IP {a.ip_address}")
        timeline.append({"at": _iso(t), "kind": kind, "title": title, "meta": meta})
    for x in exports[:20]:
        timeline.append({
            "at": _iso(x.created_at), "kind": "export",
            "title": f"Export {x.detail.strip()}" if x.detail else "Export",
            "meta": ["usage_log"],
        })
    timeline.sort(key=lambda t: t["at"] or "", reverse=True)

    history = (db.query(AppVersionSeen).filter(AppVersionSeen.user_id == user_id)
               .order_by(AppVersionSeen.first_seen.desc()).all())
    devices = [{
        "platform": h.platform, "device_model": h.device_model or None, "app_version": h.app_version,
        "is_latest": bool(latest and h.app_version == latest),
        "first_seen": _iso(h.first_seen), "last_seen": _iso(h.last_seen),
    } for h in history] or [{
        "platform": c.platform, "device_model": c.device_model or None, "app_version": c.app_version,
        "is_latest": bool(latest and c.app_version == latest),
        "first_seen": _iso(c.first_seen), "last_seen": _iso(c.last_seen),
    } for c in clients]

    topic_counts = Counter(_topic(x.domain) for x in queries)
    total_q = sum(topic_counts.values())
    last_seen = max([t for t in (_naive(u.last_login), _naive(clients[0].last_seen) if clients else None,
                                 _naive(usage[0].created_at) if usage else None) if t], default=None)

    return {
        "id": u.id,
        "username": u.username,
        "full_name": u.full_name,
        "email": u.email,
        "department": u.department,
        "role": u.role,
        "is_active": u.is_active,
        "status": ("aktif" if last_seen and now - last_seen <= timedelta(days=INACTIVE_AFTER_DAYS)
                   else "tidak_aktif"),
        "app_version": android.app_version if android else None,
        "is_latest": bool(android and latest and android.app_version == latest),
        "latest_version": latest,
        "stats": {
            "logins_30d": sum(1 for a in audits if a.action == "login" and _naive(a.created_at) >= month),
            "login_total": u.login_count or 0,
            "queries": len(queries),
            "exports": len(exports),
        },
        "timeline": timeline[:30],
        "devices": devices,
        "topics": [{"topic": t, "count": n, "pct": round(100 * n / total_q)}
                   for t, n in topic_counts.most_common(6)],
    }


class RemindReq(BaseModel):
    user_ids: list[int] = Field(min_length=1, max_length=1000)


@router.post("/app-stats/remind")
def remind_update(
    req: RemindReq,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Leave an in-app notification asking each user to update to the latest APK."""
    latest = _load_release().get("version_name")
    ids = {i for (i,) in db.query(User.id).filter(User.id.in_(req.user_ids)).all()}
    for uid in ids:
        db.add(Notification(
            user_id=uid, kind="warn",
            title="Perbarui aplikasi Android",
            message=(f"Versi terbaru v{latest} sudah tersedia. Buka menu Unduh APK untuk memperbarui."
                     if latest else "Versi terbaru sudah tersedia. Buka menu Unduh APK untuk memperbarui."),
        ))
    db.commit()
    return {"sent": len(ids)}


class ExportReq(BaseModel):
    format: str = Field(min_length=2, max_length=10)
    title: str = Field(default="", max_length=180)
    domain: str | None = Field(default=None, max_length=50)


@usage_router.post("/export")
def log_export(req: ExportReq, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Exports are built in the browser, so the client reports them here."""
    detail = f"{req.format.upper()} · {req.title}".strip(" ·")
    db.add(UsageLog(user_id=user.id, action="export", domain=req.domain, detail=detail))
    db.commit()
    return {"ok": True}
