import json

from app import app_update


def test_version_metadata_is_fresh_and_supports_legacy_https_download(monkeypatch, tmp_path):
    apk = tmp_path / "release.apk"
    apk.write_bytes(b"apk")
    monkeypatch.setattr(app_update, "_apk_path", lambda release: str(apk))
    monkeypatch.setattr(app_update, "_load_release", lambda: {
        "version_name": "1.48.1", "version_code": 64,
        "released_at": "2026-10-04",
        "download_url": "https://agent.bizplan-java.com/api/app/download",
    })
    response = app_update.app_version()
    data = json.loads(response.body)
    assert data["version_code"] == 64 and data["available"] is True
    assert data["download_url"] == "https://agent.bizplan-java.com/api/app/download"
    assert response.headers["cache-control"] == "no-store, max-age=0"


def test_version_metadata_retains_relative_download_default(monkeypatch, tmp_path):
    monkeypatch.setattr(app_update, "_apk_path", lambda release: str(tmp_path / "missing.apk"))
    monkeypatch.setattr(app_update, "_load_release", lambda: {"version_code": 64})
    data = json.loads(app_update.app_version().body)
    assert data["download_url"] == "/api/app/download"
    assert data["available"] is False
