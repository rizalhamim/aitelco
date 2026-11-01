"""Profil page API: overview, preferences, and signing an Android device out."""
import os
import tempfile

os.environ["TELCO_AI_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.auth import hash_password  # noqa: E402
from app.database import AppClient, SessionLocal, User, init_db  # noqa: E402
from app.profile_api import prefs_of, router as profile_router, wants  # noqa: E402
from app.routes_auth import router as auth_router  # noqa: E402

init_db()
app = FastAPI()
app.include_router(auth_router)
app.include_router(profile_router)
client = TestClient(app)
PHONE = {"x-client-platform": "android", "x-device-model": "Samsung SM-A556E", "user-agent": "Dart/3.5 (dart:io)"}
WEB = {"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0 Safari/537.36"}


def _login(headers: dict) -> dict:
    r = client.post("/api/auth/login", json={"username": "rizal", "password": "rahasia1"}, headers=headers)
    assert r.status_code == 200
    return r.json()


def setup_module():
    db = SessionLocal()
    db.add(User(username="rizal", email="rizal@x.id", full_name="Rizal", role="admin", department="Business Planning",
                hashed_password=hash_password("rahasia1")))
    db.commit()
    db.close()


def test_overview_prefs_and_device_sign_out():
    phone = _login(PHONE)
    web = _login(WEB)
    db = SessionLocal()
    uid = db.query(User).filter_by(username="rizal").one().id
    db.add(AppClient(user_id=uid, platform="android", device_model="Samsung SM-A556E", app_version="1.50.0"))
    db.commit()

    auth_web = {**WEB, "authorization": f"Bearer {web['access_token']}"}
    d = client.get("/api/profile", headers=auth_web).json()
    assert d["user"]["department"] == "Business Planning" and d["user"]["default_region_label"] == "Circle Java"
    assert d["devices"][0] == {"id": None, "kind": "web", "name": "Chrome · Windows", "sub": "aktif sekarang",
                               "current": True, "can_sign_out": False}
    phone_row = next(x for x in d["devices"] if x["kind"] == "android")
    assert phone_row["can_sign_out"] and phone_row["sub"].startswith("Samsung SM-A556E")
    assert d["apk"]["installed_devices"] == 1 and d["admin"]["accounts"] >= 1
    assert d["security"]["password_days"] is None

    r = client.put("/api/profile/prefs", headers=auth_web,
                   json={"prefs": {"theme": "dark", "accent": "pink", "notify": {"laporan": {"push": True}}}})
    p = r.json()["prefs"]
    assert p["theme"] == "dark" and p["accent"] == "teal" and p["notify"]["laporan"] == {"email": True, "push": True}
    assert p["notify"]["alert_peringatan"]["email"] is False

    # Sign the phone out: its token stops working, the web session keeps working.
    auth_phone = {**PHONE, "authorization": f"Bearer {phone['access_token']}"}
    assert client.get("/api/profile", headers=auth_phone).status_code == 200
    assert client.post(f"/api/profile/devices/{phone_row['id']}/sign-out", headers=auth_web).status_code == 200
    assert client.get("/api/profile", headers=auth_phone).status_code == 401
    assert client.post("/api/auth/refresh", json={"refresh_token": phone["refresh_token"]}, headers=PHONE).status_code == 401
    assert client.get("/api/profile", headers=auth_web).status_code == 200
    # Signing in again on the phone lets it back in.
    again = _login(PHONE)
    assert client.get("/api/profile", headers={**PHONE, "authorization": f"Bearer {again['access_token']}"}).status_code == 200
    db.close()


def test_prefs_defaults_and_wants():
    u = User(username="x", email="x@x", full_name="X", hashed_password="-", preferences='{"lang": "en", "quiet_hours": false}')
    p = prefs_of(u)
    assert p["lang"] == "id" and p["quiet_hours"] is False and p["default_region"] == "JAVA"
    assert wants(u, "alert_kritis", "email") and not wants(u, "alert_peringatan", "email")
