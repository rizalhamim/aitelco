"""In-app APK auto-update support.

Exposes:
  GET /api/app/version        -> latest version metadata (JSON)
  GET /api/app/download       -> the latest APK binary (FileResponse)
  GET /api/app/releases       -> release history for the web "Unduh APK" page

The latest-release metadata lives in data/app_release.json so it can be
updated without touching code. The APK is served from a fixed path on the
backend host. The Android client compares its own build number against
`version_code` and, if the server is higher, prompts the user to download
and install.
"""
import hashlib
import json
import os

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, JSONResponse

from . import telemetry

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
    }, headers={"Cache-Control": "no-store, max-age=0"})


@router.get("/releases")
def app_releases():
    """Newest first: the current release, then `history` from data/app_release.json
    ([{version_name, released_at, notes, mandatory}])."""
    rel = _load_release()
    out = [{
        "version_name": rel.get("version_name"),
        "released_at": rel.get("released_at"),
        "notes": _notes_list(rel.get("notes")),
        "mandatory": bool(rel.get("mandatory", False)),
        "latest": True,
    }]
    for h in rel.get("history") or []:
        if not h.get("version_name") or h.get("version_name") == rel.get("version_name"):
            continue
        out.append({
            "version_name": h["version_name"],
            "released_at": h.get("released_at"),
            "notes": _notes_list(h.get("notes")),
            "mandatory": bool(h.get("mandatory", False)),
            "latest": False,
        })
    return {"releases": out}


@router.get("/download")
def app_download(request: Request, src: str | None = None):
    """Serve the latest APK binary and log the download.

    Stays reachable without a token: installed apps older than the telemetry
    release call it with no Authorization header, and must still be able to
    update. The web app only links to it from pages behind login.
    """
    rel = _load_release()
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
