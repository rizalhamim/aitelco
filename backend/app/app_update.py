"""In-app APK auto-update support.

Exposes:
  GET /api/app/version        -> latest version metadata (JSON)
  GET /api/app/download       -> the latest APK binary (FileResponse)
  GET /api/app/releases       -> release history for the web "Unduh APK" page
  POST /api/app/send-link     -> email the signed-in user the download link

The latest-release metadata lives in data/app_release.json so it can be
updated without touching code. The APK is served from a fixed path on the
backend host. The Android client compares its own build number against
`version_code` and, if the server is higher, prompts the user to download
and install.
"""
import hashlib
import json
import os

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse

from . import telemetry
from .auth import get_current_user
from .database import User

router = APIRouter(prefix="/api/app", tags=["app-update"])

_BASE = os.path.dirname(os.path.dirname(__file__))          # backend/
_RELEASE_JSON = os.path.join(_BASE, "data", "app_release.json")

# Default release metadata — overridden by data/app_release.json if present.
_DEFAULT_RELEASE = {
    "version_name": "1.0.0",
    "version_code": 1,
    "apk_filename": "Bizplan-Java-Agent.apk",
    "notes": "",
    "mandatory": False,
}


def _load_release() -> dict:
    data = dict(_DEFAULT_RELEASE)
    try:
        if os.path.exists(_RELEASE_JSON):
            with open(_RELEASE_JSON, "r", encoding="utf-8") as f:
                data.update(json.load(f))
    except Exception:
        pass
    return data


def _apk_path(rel: dict) -> str:
    """Resolve the APK file path. The file is expected to live one level above
    the backend dir (the repo root) where the build script drops it."""
    fname = rel.get("apk_filename") or _DEFAULT_RELEASE["apk_filename"]
    # repo root is the parent of backend/
    repo_root = os.path.dirname(_BASE)
    return os.path.join(repo_root, fname)


_sha_cache: dict[tuple, str] = {}


def _sha256(path: str) -> str | None:
    """SHA-256 of the APK, cached per (path, mtime, size) so it is hashed once per release."""
    try:
        st = os.stat(path)
    except OSError:
        return None
    key = (path, st.st_mtime_ns, st.st_size)
    if key not in _sha_cache:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        _sha_cache.clear()
        _sha_cache[key] = h.hexdigest()
    return _sha_cache[key]


def _notes_list(notes) -> list[str]:
    if isinstance(notes, list):
        return [str(n).strip() for n in notes if str(n).strip()]
    return [ln.strip(" -•\t") for ln in str(notes or "").splitlines() if ln.strip(" -•\t")]


@router.get("/version")
def app_version():
    """Latest release metadata for the in-app updater."""
    rel = _load_release()
    apk = _apk_path(rel)
    size = os.path.getsize(apk) if os.path.exists(apk) else 0
    # Release date: explicit `released_at` in JSON, else the APK file mtime.
    released_at = rel.get("released_at")
    if not released_at and os.path.exists(apk):
        import datetime
        released_at = datetime.date.fromtimestamp(os.path.getmtime(apk)).isoformat()
    return JSONResponse({
        "version_name": rel.get("version_name"),
        "version_code": int(rel.get("version_code", 1)),
        "notes": rel.get("notes", ""),
        "mandatory": bool(rel.get("mandatory", False)),
        "download_url": rel.get("download_url") or "/api/app/download",
        "size_bytes": size,
        "available": size > 0,
        "released_at": released_at,
        "apk_filename": rel.get("apk_filename") or _DEFAULT_RELEASE["apk_filename"],
        "sha256": _sha256(apk) if size else None,
        "min_android": rel.get("min_android", "8.0"),
        # Unduh APK page: one line per release and the "Apa yang baru" items
        # ([{icon, title, text}]); both optional in data/app_release.json.
        "summary": rel.get("summary") or (_notes_list(rel.get("notes")) or [""])[0],
        "highlights": rel.get("highlights") or [],
    }, headers={"Cache-Control": "no-store, max-age=0"})


@router.get("/releases")
def app_releases():
    """Newest first: the current release, then `history` from data/app_release.json
    ([{version_name, released_at, notes, mandatory}])."""
    rel = _load_release()
    def row(r: dict, latest: bool) -> dict:
        notes = _notes_list(r.get("notes"))
        return {
            "version_name": r.get("version_name"),
            "version_code": r.get("version_code"),
            "released_at": r.get("released_at"),
            "notes": notes,
            "summary": r.get("summary") or (notes[0] if notes else ""),
            "mandatory": bool(r.get("mandatory", False)),
            "latest": latest,
            # Older APKs stay downloadable while their file is kept next to the current one.
            "available": os.path.exists(_apk_path(r)) if latest or r.get("apk_filename") else False,
            "download_url": "/api/app/download" if latest else f"/api/app/download?version={r.get('version_name')}",
        }

    out = [row(rel, True)]
    for h in rel.get("history") or []:
        if not h.get("version_name") or h.get("version_name") == rel.get("version_name"):
            continue
        out.append(row(h, False))
    return {"releases": out}


@router.get("/download")
def app_download(request: Request, src: str | None = None, version: str | None = None):
    """Serve the latest APK binary and log the download.

    Stays reachable without a token: installed apps older than the telemetry
    release call it with no Authorization header, and must still be able to
    update. The web app only links to it from pages behind login.
    """
    rel = _load_release()
    if version and version != rel.get("version_name"):
        old = next((h for h in rel.get("history") or [] if h.get("version_name") == version and h.get("apk_filename")), None)
        if old is None:
            return JSONResponse({"error": "apk not available"}, status_code=404)
        rel = {**old, "version_code": old.get("version_code") or 0}
    apk = _apk_path(rel)
    if not os.path.exists(apk):
        return JSONResponse({"error": "apk not available"}, status_code=404)
    telemetry.record_download(
        request.headers, request.client.host if request.client else None,
        rel.get("version_name"), int(rel.get("version_code", 0) or 0), src)
    return FileResponse(
        apk,
        media_type="application/vnd.android.package-archive",
        filename=rel.get("apk_filename") or "Bizplan-Java-Agent.apk",
    )


@router.post("/send-link")
def send_link(bg: BackgroundTasks, user: User = Depends(get_current_user)):
    """Unduh APK "Kirim ke email saya": the download page link to the user's own email."""
    from . import email_service
    if not user.email or "@" not in user.email:
        raise HTTPException(400, "Email akun belum diisi. Lengkapi di Profil.")
    rel = _load_release()
    url = f"{email_service.APP_URL}/unduh"
    bg.add_task(email_service.send_notification, user.email, f"Unduh Agent Java {rel.get('version_name') or ''} untuk Android".strip(),
                f"Buka link ini di HP Android untuk mengunduh Agent Java: {url}")
    name, _, domain = user.email.partition("@")
    return {"ok": True, "to": f"{name[:2]}***@{domain}"}
