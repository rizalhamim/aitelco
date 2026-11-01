"""Unduh APK v2: release summaries, older APKs by version, and the email link."""
import json
import os
import tempfile

os.environ["TELCO_AI_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import app_update  # noqa: E402
from app.auth import create_access_token, hash_password  # noqa: E402
from app.database import SessionLocal, User, init_db  # noqa: E402

init_db()
app = FastAPI()
app.include_router(app_update.router)
client = TestClient(app)


def test_releases_old_apk_and_send_link(tmp_path, monkeypatch):
    root = tmp_path
    (root / "backend" / "data").mkdir(parents=True)
    (root / "AgentJava-1.50.0.apk").write_bytes(b"new")
    (root / "AgentJava-1.49.1.apk").write_bytes(b"old")
    rel = {"version_name": "1.50.0", "version_code": 69, "apk_filename": "AgentJava-1.50.0.apk", "summary": "Redesign v2, Agent Java",
           "highlights": [{"icon": "map", "title": "Peta Agent", "text": "x"}],
           "history": [{"version_name": "1.49.1", "version_code": 68, "apk_filename": "AgentJava-1.49.1.apk", "notes": "Sesi kedaluwarsa kembali ke login"},
                       {"version_name": "1.48.3", "version_code": 66, "notes": ["Versi sebelum Redesign v1"]}]}
    path = root / "backend" / "data" / "app_release.json"
    path.write_text(json.dumps(rel))
    monkeypatch.setattr(app_update, "_RELEASE_JSON", str(path))
    monkeypatch.setattr(app_update, "_BASE", str(root / "backend"))
    v = client.get("/api/app/version").json()
    assert v["summary"] == "Redesign v2, Agent Java" and v["highlights"][0]["title"] == "Peta Agent"
    r = client.get("/api/app/releases").json()["releases"]
    assert [(x["version_name"], x["version_code"], x["available"]) for x in r] == [("1.50.0", 69, True), ("1.49.1", 68, True), ("1.48.3", 66, False)]
    assert r[1]["summary"] == "Sesi kedaluwarsa kembali ke login" and r[1]["download_url"].endswith("version=1.49.1")
    assert client.get("/api/app/download?version=1.49.1").content == b"old"
    assert client.get("/api/app/download?version=1.48.3").status_code == 404
    db = SessionLocal()
    db.add(User(username="rizal", email="rizal@x.id", full_name="Rizal", hashed_password=hash_password("x")))
    db.commit()
    db.close()
    sent = []
    monkeypatch.setattr("app.email_service.send_notification", lambda *a: sent.append(a) or True)
    tok = create_access_token({"sub": "rizal", "role": "user"})
    j = client.post("/api/app/send-link", headers={"authorization": f"Bearer {tok}"}).json()
    assert j == {"ok": True, "to": "ri***@x.id"} and sent and sent[0][0] == "rizal@x.id" and "/unduh" in sent[0][2]
