"""Login writes login_audit rows the Statistik page reads."""
import os
import tempfile

os.environ["TELCO_AI_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.auth import hash_password  # noqa: E402
from app.database import LoginAudit, SessionLocal, User, init_db  # noqa: E402
from app.routes_auth import router  # noqa: E402

init_db()
app = FastAPI()
app.include_router(router)
client = TestClient(app)


def test_login_success_and_failures_are_audited():
    db = SessionLocal()
    db.add(User(username="sari", email="sari@x.id", full_name="Sari", hashed_password=hash_password("rahasia1")))
    db.add(User(username="off", email="off@x.id", full_name="Off", hashed_password=hash_password("rahasia1"),
                is_active=False))
    db.commit()
    ua = {"user-agent": "Mozilla/5.0 (Linux; Android 14) Chrome/120", "x-forwarded-for": "10.1.2.3, 10.0.0.1"}
    assert client.post("/api/auth/login", json={"username": "sari", "password": "salah"}, headers=ua).status_code == 401
    assert client.post("/api/auth/login", json={"username": "sari", "password": "rahasia1"}, headers=ua).status_code == 200
    assert client.post("/api/auth/login", json={"username": "off", "password": "rahasia1"}).status_code == 403
    assert client.post("/api/auth/login", json={"username": "nobody", "password": "x"}).status_code == 401
    ids = [u.id for u in db.query(User).filter(User.username.in_(["sari", "off"]))]
    rows = db.query(LoginAudit).filter(LoginAudit.user_id.in_(ids)).order_by(LoginAudit.id).all()
    assert [r.action for r in rows] == ["failed_login", "login", "failed_inactive"]
    assert rows[0].ip_address == "10.1.2.3" and "Android" in rows[0].user_agent
    db.close()
