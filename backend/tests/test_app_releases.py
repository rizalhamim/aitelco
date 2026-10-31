"""Release history + checksum for the Unduh APK page."""
import hashlib
import json
import os
import tempfile

os.environ.setdefault("TELCO_AI_DB", os.path.join(tempfile.mkdtemp(), "t.db"))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import app_update  # noqa: E402


def test_releases_and_checksum(tmp_path, monkeypatch):
    apk = tmp_path / "app.apk"
    apk.write_bytes(b"apk-bytes")
    rel = {"version_name": "1.43.1", "version_code": 51, "released_at": "2026-10-21", "apk_filename": "app.apk",
           "notes": "Grafik bisa di-drill-down\n- Peta lebih cepat", "history": [
               {"version_name": "1.43.0", "released_at": "2026-10-06", "mandatory": True, "notes": ["Login kantor"]},
               {"version_name": "1.43.1", "notes": "duplikat diabaikan"}]}
    f = tmp_path / "app_release.json"
    f.write_text(json.dumps(rel))
    monkeypatch.setattr(app_update, "_RELEASE_JSON", str(f))
    monkeypatch.setattr(app_update, "_apk_path", lambda r: str(apk))
    app = FastAPI()
    app.include_router(app_update.router)
    c = TestClient(app)
    r = c.get("/api/app/releases").json()["releases"]
    assert [x["version_name"] for x in r] == ["1.43.1", "1.43.0"]
    assert r[0]["notes"] == ["Grafik bisa di-drill-down", "Peta lebih cepat"] and r[0]["latest"]
    assert r[1]["mandatory"] and r[1]["notes"] == ["Login kantor"]
    v = c.get("/api/app/version").json()
    assert v["sha256"] == hashlib.sha256(b"apk-bytes").hexdigest() and v["min_android"] == "8.0"
