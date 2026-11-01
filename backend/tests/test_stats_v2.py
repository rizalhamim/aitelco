"""Statistik v2: access requests and approval, account lock after wrong passwords,
page sessions, and the v2 block of /api/admin/app-stats."""
import os
import tempfile

os.environ["TELCO_AI_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.auth import hash_password  # noqa: E402
from app.database import PasswordReset, SessionLocal, UsageLog, User, init_db  # noqa: E402
from app.routes_auth import router as auth_router  # noqa: E402
from app.routes_stats import router as stats_router, topic_bucket, usage_router  # noqa: E402

init_db()
app = FastAPI()
app.include_router(auth_router)
app.include_router(stats_router)
app.include_router(usage_router)
client = TestClient(app)
WEB = {"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0 Safari/537.36"}


def setup_module():
    db = SessionLocal()
    db.add(User(username="boss", email="boss@x.id", full_name="Boss", role="admin", hashed_password=hash_password("rahasia1")))
    db.add(User(username="lina", email="lina@x.id", full_name="Lina", role="end_user", hashed_password=hash_password("rahasia1")))
    db.commit()
    db.close()


def _token(user: str) -> dict:
    r = client.post("/api/auth/login", json={"username": user, "password": "rahasia1"}, headers=WEB)
    assert r.status_code == 200, r.text
    return {**WEB, "authorization": f"Bearer {r.json()['access_token']}"}


def test_request_access_approve_and_set_password():
    r = client.post("/api/auth/request-access", json={"full_name": "Fajar Nugroho", "email": "Fajar.N@x.id",
                                                      "department": "Network", "region": "EAST JAVA"})
    assert r.status_code == 200
    # Same answer for a known email, and no second account.
    assert client.post("/api/auth/request-access", json={"full_name": "Xy", "email": "fajar.n@x.id"}).json() == r.json()
    admin = _token("boss")
    v2 = client.get("/api/admin/app-stats?days=7", headers=admin).json()["v2"]
    p = v2["pending"]
    assert len(p) == 1 and p[0]["region"] == "East Java" and p[0]["department"] == "Network"
    # Pending accounts cannot sign in and are not listed as users.
    assert client.post("/api/auth/login", json={"username": "fajar.n", "password": "x"}).status_code == 403
    assert client.post(f"/api/admin/app-stats/pending/{p[0]['id']}/approve", headers=admin).json()["username"] == "fajar.n"
    db = SessionLocal()
    token = db.query(PasswordReset).filter_by(user_id=p[0]["id"]).one().token
    db.close()
    assert client.post("/api/auth/reset-password", json={"token": token, "new_password": "baru1234"}).status_code == 200
    assert client.post("/api/auth/login", json={"username": "fajar.n", "password": "baru1234"}).status_code == 200
    assert client.post(f"/api/admin/app-stats/pending/{p[0]['id']}/reject", headers=admin).status_code == 404


def test_lock_after_wrong_passwords_and_security_lines():
    for _ in range(5):
        assert client.post("/api/auth/login", json={"username": "lina", "password": "salah"}, headers=WEB).status_code == 401
    r = client.post("/api/auth/login", json={"username": "lina", "password": "rahasia1"}, headers=WEB)
    assert r.status_code == 423 and "dikunci" in r.json()["detail"]
    client.post("/api/auth/login", json={"username": "hantu", "password": "x"}, headers=WEB)
    v2 = client.get("/api/admin/app-stats?days=7", headers=_token("boss")).json()["v2"]
    # Other test modules share this database, so look for our lines rather than exact totals.
    assert any(s["tag"] == "terkunci" and s["title"] == "lina · 5 kali salah password" for s in v2["security"])
    assert any(s["tag"] == "diblokir" and s["title"].startswith("Akun tidak dikenal · ") for s in v2["security"])
    assert v2["failed"]["locked_accounts"] >= 1 and v2["failed"]["count"] >= 7


def test_page_sessions_topics_and_shape():
    admin = _token("boss")
    assert client.post("/api/usage/view", json={"page": "dashboard"}, headers=admin).json()["new"] is True
    assert client.post("/api/usage/view", json={"page": "dashboard"}, headers=admin).json()["new"] is False
    assert client.post("/api/usage/view", json={"page": "rahasia"}, headers=admin).json() == {"ok": False}
    before = client.get("/api/admin/app-stats?days=1", headers=admin).json()["v2"]
    db = SessionLocal()
    uid = db.query(User).filter_by(username="boss").one().id
    for q in ("payload Garut bulan ini", "revenue per site baru West Java", "market share Cianjur"):
        db.add(UsageLog(user_id=uid, action="query", domain="kpi_summary", detail=q))
    db.commit()
    db.close()
    v2 = client.get("/api/admin/app-stats?days=1", headers=admin).json()["v2"]
    assert next(f for f in v2["features"] if f["key"] == "dashboard")["sessions"] == 1
    assert [a["count"] - b["count"] for a, b in zip(v2["topics"], before["topics"])] == [1, 1, 1]
    assert v2["questions"]["count"] - before["questions"]["count"] == 3
    assert len(v2["daily_active"]) == 30 and v2["daily_active"][-1]["dau"] >= 1
    assert len(v2["downloads_14d"]) == 14 and v2["logins_today"]["web"] >= 1
    assert topic_bucket("network", "") == "site" and topic_bucket(None, "Penetrasi FWA") == "profile"
