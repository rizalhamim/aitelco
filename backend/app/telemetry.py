"""Mobile-app telemetry: which users run which app version on which device,
and every APK download.

Clients identify themselves with request headers (all optional):
    X-Client-Platform   android | web
    X-App-Version       e.g. 1.44.0
    X-App-Build         e.g. 50
    X-Device-Model      e.g. Samsung SM-A546E
    X-OS-Version        e.g. Android 14 (SDK 34)

`record_client` upserts one `app_clients` row per user + platform + device,
throttled so a busy session writes at most once every few minutes.
"""
import logging
import threading
import time
from datetime import datetime, timezone

from jose import jwt

from .auth import ALGORITHM, SECRET_KEY
from .database import AppClient, AppDownload, AppVersionSeen, SessionLocal, User

log = logging.getLogger("telemetry")

_THROTTLE_S = 300
_seen: dict[tuple, float] = {}
_lock = threading.Lock()


def _now():
    return datetime.now(timezone.utc)


def _username_from_auth(auth_header: str | None) -> str | None:
    if not auth_header or not auth_header.lower().startswith("bearer "):
        return None
    try:
        payload = jwt.decode(auth_header[7:], SECRET_KEY, algorithms=[ALGORITHM])
        sub = payload.get("sub")
        return str(sub) if sub else None
    except Exception:
        return None


def _resolve_user(db, username: str | None):
    if not username:
        return None
    return db.query(User).filter(User.username == username).first()


def _clip(v: str | None, n: int) -> str | None:
    return v.strip()[:n] if v and v.strip() else None


def platform_from_user_agent(ua: str | None) -> str:
    """Best-effort platform for requests without X-Client-Platform (older app builds)."""
    ua = (ua or "").lower()
    if "dart" in ua or "okhttp" in ua or "bizplan-java-agent" in ua:
        return "android"
    return "web"


def record_client(headers) -> None:
    """Upsert the caller's app_clients row from request headers. Never raises."""
    platform = _clip(headers.get("x-client-platform"), 20)
    if not platform:
        return
    username = _username_from_auth(headers.get("authorization"))
    if not username:
        return
    model = _clip(headers.get("x-device-model"), 120) or ""
    version = _clip(headers.get("x-app-version"), 32)
    key = (username, platform.lower(), model, version)
    now = time.monotonic()
    with _lock:
        if now - _seen.get(key, 0) < _THROTTLE_S:
            return
        _seen[key] = now

    db = SessionLocal()
    try:
        user = _resolve_user(db, username)
        if not user:
            return
        row = (db.query(AppClient)
               .filter(AppClient.user_id == user.id,
                       AppClient.platform == platform.lower(),
                       AppClient.device_model == model)
               .first())
        if row is None:
            row = AppClient(user_id=user.id, platform=platform.lower(), device_model=model,
                            first_seen=_now())
            db.add(row)
        row.app_version = version or row.app_version
        build = headers.get("x-app-build")
        if build and build.isdigit():
            row.app_build = int(build)
        row.os_version = _clip(headers.get("x-os-version"), 60) or row.os_version
        row.last_seen = _now()
        if version:
            seen = (db.query(AppVersionSeen)
                    .filter(AppVersionSeen.user_id == user.id,
                            AppVersionSeen.platform == platform.lower(),
                            AppVersionSeen.device_model == model,
                            AppVersionSeen.app_version == version)
                    .first())
            if seen is None:
                db.add(AppVersionSeen(user_id=user.id, platform=platform.lower(), device_model=model,
                                      app_version=version, first_seen=_now(), last_seen=_now()))
            else:
                seen.last_seen = _now()
        db.commit()
    except Exception as e:  # telemetry must never break a request
        db.rollback()
        log.warning(f"record_client failed: {e}")
    finally:
        db.close()


def record_download(headers, client_ip: str | None, version_name: str | None,
                    version_code: int | None, source: str | None = None) -> None:
    """Log one APK download. Never raises."""
    db = SessionLocal()
    try:
        user = _resolve_user(db, _username_from_auth(headers.get("authorization")))
        ua = headers.get("user-agent")
        if source not in ("web", "in_app"):
            source = "in_app" if platform_from_user_agent(ua) == "android" else "web"
        db.add(AppDownload(
            user_id=user.id if user else None,
            version_name=version_name, version_code=version_code,
            source=source, ip_address=_clip(client_ip, 45), user_agent=_clip(ua, 500),
        ))
        db.commit()
    except Exception as e:
        db.rollback()
        log.warning(f"record_download failed: {e}")
    finally:
        db.close()
