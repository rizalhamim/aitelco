"""Admin "Statistik" API: mobile-app reach and access.

GET  /api/admin/app-stats?days=30
GET  /api/admin/app-stats/users/{id}     one user's logins, devices and topics
POST /api/admin/app-stats/remind         in-app "please update" notification
POST /api/usage/export                   log a client-side export (XLSX/PDF)
"""
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from .app_update import _load_release
from .auth import get_current_user, require_admin
from .database import (AppClient, AppDownload, AppVersionSeen, LoginAudit, Notification, PasswordReset,
                       UnknownLogin, UsageLog, User, get_db)
from .telemetry import platform_from_user_agent

router = APIRouter(prefix="/api/admin", tags=["admin-stats"])
usage_router = APIRouter(prefix="/api/usage", tags=["usage"])

INACTIVE_AFTER_DAYS = 14

# LoginAudit.action values written by routes_auth for each failure reason.
FAILURE_REASONS = {
    "failed_login": "Kata sandi salah",
    "failed_inactive": "Akun dinonaktifkan",
    "failed_token": "Token kedaluwarsa",
    "failed_locked": "Akun terkunci",
}

# Pages counted in "Pemakaian fitur" (POST /api/usage/view), in the order shown.
FEATURES = [("tanya", "Tanya Agent"), ("dashboard", "Dashboard"), ("performance", "Performance"),
            ("peta", "Peta Agent"), ("laporan", "Laporan"), ("watchlist", "Watchlist dan Alert")]
# A page opened again within this many minutes counts as the same session.
VIEW_SESSION_MINUTES = 30
# Status "Tidak aktif" in the access table: nothing seen for this many days.
ACTIVE_DAYS = 7
REGION_LABEL = {"JAVA": "Circle Java", "WEST JAVA": "West Java", "CENTRAL JAVA": "Central Java", "EAST JAVA": "East Java"}
TOPIC_BUCKETS = [("performance", "Performance"), ("site", "Site productivity"), ("profile", "Profile wilayah")]
_SITE_WORDS = ("productiv", "produktiv", "per site", "/site", "new site", "site baru", "rev/site", "rgu/site", "vlr/site")
_PROFILE_WORDS = ("market share", "penetrasi", "profil", "profile", "demograf", "kompetitor", "competit", "populasi",
                  "household", "rumah tangga", "potensi")


def topic_bucket(domain: str | None, question: str | None) -> str:
    """Performance, Site productivity or Profile wilayah for one agent question."""
    q = (question or "").lower()
    d = (domain or "").lower()
    if any(w in q for w in _SITE_WORDS) or d in ("network", "network_benchmark", "site"):
        return "site"
    if any(w in q for w in _PROFILE_WORDS) or d in ("competitive", "market_share"):
        return "profile"
    return "performance"


def _region_of(u: User) -> str:
    import json
    try:
        key = json.loads(u.preferences or "{}").get("default_region") or "JAVA"
    except (TypeError, ValueError):
        key = "JAVA"
    return REGION_LABEL.get(key, "Circle Java")


def _approved(u: User) -> bool:
    return (u.approval_status or "approved") == "approved"

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
    days: int = Query(30, ge=1, le=365),
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    now = _naive(datetime.now(timezone.utc))
    history_days = max(2 * days, 37)
    since = now - timedelta(days=days)
    release = _load_release()
    latest = release.get("version_name")

    users = db.query(User).all()
    clients = db.query(AppClient).all()
    downloads = db.query(AppDownload).all()
    # Two periods back, so each KPI can be compared with the period before it.
    logins = (db.query(LoginAudit)
              .filter(LoginAudit.created_at >= now - timedelta(days=history_days))
              .all())
    usage = (db.query(UsageLog)
             .filter(UsageLog.created_at >= now - timedelta(days=history_days))
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
    # Statistik v2 always shows the last 14 days (WIB), whatever the period.
    by_day_wib = defaultdict(lambda: {"downloads": 0, "updates": 0})
    for d in downloads:
        t = _naive(d.created_at) + timedelta(hours=7)
        by_day_wib[t.date()]["updates" if d.source == "in_app" else "downloads"] += 1
    downloads_14d = [{"date": ((now + timedelta(hours=7)).date() - timedelta(days=i)).isoformat(),
                      **by_day_wib[(now + timedelta(hours=7)).date() - timedelta(days=i)]} for i in range(13, -1, -1)]
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
    weeks = 7  # Statistik v2: six weeks back and this week
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
    platforms: dict[int, set] = defaultdict(set)
    for l in logins:
        if l.action == "login":
            platforms[l.user_id].add(platform_from_user_agent(l.user_agent))
    for c in clients:
        platforms[c.user_id].add("android" if c.platform == "android" else "web")
    rows = []
    for u in users:
        if not _approved(u):
            continue
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
            "region": _region_of(u),
            "platforms": [p for p in ("web", "android") if p in platforms.get(u.id, set())] or (["android"] if c else ["web"]),
            # Statistik v2 status: Tidak aktif (nothing for ACTIVE_DAYS), else Versi lama (Android not on latest), else Aktif.
            "state": ("tidak_aktif" if not u.is_active or not last_seen or now - last_seen > timedelta(days=ACTIVE_DAYS)
                      else "versi_lama" if c and latest and c.app_version != latest else "aktif"),
        })
    rows.sort(key=lambda r: r["last_login"] or "", reverse=True)

    outdated = [r for r in rows if r["app_version"] and not r["is_latest"]]
    outdated.sort(key=lambda r: _version_key(r["app_version"]))

    # ── Statistik v2 blocks ──
    wib = timedelta(hours=7)
    today0 = datetime.combine((now + wib).date(), datetime.min.time()) - wib
    today_logins = [l for l in logins if l.action == "login" and _naive(l.created_at) >= today0]
    today_platform = Counter(platform_from_user_agent(l.user_agent) for l in today_logins)
    questions = [u for u in usage if u.action == "query"]
    q_period = [u for u in questions if _naive(u.created_at) >= since]
    q_prev = sum(1 for u in questions if prev_since <= _naive(u.created_at) < since)

    # Daily active (DAU) and 7-day rolling (WAU), 30 WIB days, from logins and any logged activity.
    by_day_users: dict = defaultdict(set)
    for u in usage:
        by_day_users[(_naive(u.created_at) + wib).date()].add(u.user_id)
    for l in logins:
        if l.action == "login":
            by_day_users[(_naive(l.created_at) + wib).date()].add(l.user_id)
    today_wib = (now + wib).date()
    daily_active = []
    for i in range(29, -1, -1):
        day = today_wib - timedelta(days=i)
        week = set().union(*(by_day_users.get(day - timedelta(days=k), set()) for k in range(7)))
        daily_active.append({"date": day.isoformat(), "dau": len(by_day_users.get(day, set())), "wau": len(week)})

    views = Counter(u.domain for u in usage if u.action == "view" and _naive(u.created_at) >= since)
    buckets = Counter(topic_bucket(u.domain, u.detail) for u in q_period)

    android_devices = [c for c in clients if c.platform == "android" and getattr(c, "signed_out_at", None) is None]
    on_latest_devices = sum(1 for c in android_devices if latest and c.app_version == latest)
    released = release.get("released_at")
    dl_since_release = sum(1 for d in downloads if latest and d.version_name == latest)

    # Login failures and locks in the period, one line per account (newest first).
    from .routes_auth import LOCK_AFTER, LOCK_MINUTES
    events = []
    fails_by_user: dict[int, list] = defaultdict(list)
    for l in logins:
        if _is_failed(l.action) and _naive(l.created_at) >= since:
            fails_by_user[l.user_id].append(l)
    good_by_user: dict[int, list] = defaultdict(list)
    for l in logins:
        if l.action == "login":
            good_by_user[l.user_id].append(_naive(l.created_at))
    locked_accounts = 0
    for uid, rows_ in fails_by_user.items():
        rows_.sort(key=lambda l: _naive(l.created_at))
        name = by_id[uid].username if uid in by_id else f"#{uid}"
        last = _naive(rows_[-1].created_at)
        pw = [l for l in rows_ if l.action == "failed_login"]
        otp = [l for l in rows_ if l.action == "failed_token"]
        inactive = [l for l in rows_ if l.action == "failed_inactive"]
        locked = any(l.action == "failed_locked" for l in rows_) or any(
            _naive(pw[i + LOCK_AFTER - 1].created_at) - _naive(pw[i].created_at) <= timedelta(minutes=LOCK_MINUTES)
            for i in range(0, max(0, len(pw) - LOCK_AFTER + 1)))
        later = sorted(t for t in good_by_user.get(uid, []) if t > _naive(rows_[0].created_at))
        if locked:
            locked_accounts += 1
            events.append({"tag": "terkunci", "title": f"{name} · {len(pw)} kali salah password", "at": _iso(last),
                           "note": f"akun dikunci {LOCK_MINUTES} menit"})
        elif inactive:
            events.append({"tag": "diblokir", "title": f"{name} · akun nonaktif mencoba masuk", "at": _iso(last),
                           "note": f"{len(inactive)} kali ditolak"})
        elif otp:
            events.append({"tag": "pantau", "title": f"{name} · OTP kedaluwarsa {len(otp)} kali", "at": _iso(last),
                           "note": f"berhasil di percobaan {'ketiga' if len(otp) == 2 else f'ke-{len(otp) + 1}'}"
                           if later else "belum berhasil masuk"})
        elif pw:
            events.append({"tag": "pantau", "title": f"{name} · {len(pw)} kali salah password", "at": _iso(last),
                           "note": "lalu berhasil masuk" if later else "belum berhasil masuk"})
    unknown = (db.query(UnknownLogin).filter(UnknownLogin.created_at >= since)
               .order_by(UnknownLogin.created_at.desc()).all())
    if unknown:
        events.append({"tag": "diblokir", "title": f"Akun tidak dikenal · {len(unknown)} kali", "at": _iso(unknown[0].created_at),
                       "note": "username tidak terdaftar"})
    order = {"terkunci": 0, "pantau": 1, "diblokir": 2}
    events.sort(key=lambda e: (order[e["tag"]], -(datetime.fromisoformat(e["at"][:-1]).timestamp())))

    pending = sorted((u for u in users if (u.approval_status or "approved") == "pending"),
                     key=lambda u: _naive(u.created_at), reverse=True)
    approved_rows = rows
    active_30 = sum(1 for r in approved_rows if r["last_seen"] and now - datetime.fromisoformat(r["last_seen"][:-1]) <= timedelta(days=30))
    outdated_devices = sum(1 for c in android_devices if latest and c.app_version and c.app_version != latest)
    v2 = {
        "active": {"dau": active_since(timedelta(days=1)), "wau": active_since(timedelta(days=7)),
                   "mau": active_since(timedelta(days=30))},
        "logins_today": {"total": len(today_logins), "web": today_platform.get("web", 0),
                         "android": today_platform.get("android", 0)},
        "questions": {"count": len(q_period), "change": change(len(q_period), q_prev)},
        "adoption": {"version": ".".join((latest or "").split(".")[:2]) or None, "devices_on_latest": on_latest_devices,
                     "devices": len(android_devices), "downloads_since_release": dl_since_release, "released_at": released},
        "failed": {"count": len(failed) + len(unknown), "locked_accounts": locked_accounts},
        "daily_active": daily_active,
        "features": [{"key": k, "label": lbl, "sessions": views.get(k, 0)} for k, lbl in FEATURES],
        "topics": [{"key": k, "label": lbl, "count": buckets.get(k, 0),
                    "pct": round(100 * buckets.get(k, 0) / len(q_period)) if q_period else 0} for k, lbl in TOPIC_BUCKETS],
        "pending": [{"id": u.id, "full_name": u.full_name, "email": u.email, "department": u.department,
                     "region": _region_of(u), "requested_at": _iso(u.created_at)} for u in pending],
        "security": events[:8],
        "downloads_14d": downloads_14d,
        "accounts": {"total": len(approved_rows), "active_30d": active_30, "outdated_devices": outdated_devices},
    }

    return {
        "v2": v2,
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


class ViewReq(BaseModel):
    page: str = Field(min_length=2, max_length=30)


@usage_router.post("/view")
def log_view(req: ViewReq, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """One session per page for "Pemakaian fitur": a page opened again within
    VIEW_SESSION_MINUTES is the same session and is not logged twice."""
    keys = {k for k, _ in FEATURES}
    if req.page not in keys:
        return {"ok": False}
    cut = _naive(datetime.now(timezone.utc)) - timedelta(minutes=VIEW_SESSION_MINUTES)
    seen = (db.query(UsageLog.id)
            .filter(UsageLog.user_id == user.id, UsageLog.action == "view", UsageLog.domain == req.page,
                    UsageLog.created_at >= cut).first())
    if not seen:
        db.add(UsageLog(user_id=user.id, action="view", domain=req.page))
        db.commit()
    return {"ok": True, "new": not seen}


def _pending_user(db: Session, user_id: int) -> User:
    u = db.query(User).filter(User.id == user_id).first()
    if u is None or (u.approval_status or "approved") != "pending":
        raise HTTPException(404, "Permintaan akses tidak ditemukan")
    return u


@router.post("/app-stats/pending/{user_id}/approve")
def approve_access(user_id: int, bg: BackgroundTasks, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    """Activates the account and emails a link to set the first password (valid 3 days)."""
    import secrets

    from . import email_service
    u = _pending_user(db, user_id)
    u.approval_status = "approved"
    u.is_active = True
    token = secrets.token_urlsafe(48)
    db.add(PasswordReset(user_id=u.id, token=token, expires_at=datetime.now(timezone.utc) + timedelta(days=3)))
    db.commit()
    if u.email and "@" in u.email:
        bg.add_task(email_service.send_access_approved, u.email, u.username, u.full_name, token)
    return {"ok": True, "username": u.username}


@router.post("/app-stats/pending/{user_id}/reject")
def reject_access(user_id: int, admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    """Keeps the row (so the same email cannot ask again unnoticed) but never lets it sign in."""
    u = _pending_user(db, user_id)
    u.approval_status = "rejected"
    u.is_active = False
    db.commit()
    return {"ok": True}
