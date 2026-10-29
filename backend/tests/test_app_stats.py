"""App-stats + telemetry against a throwaway SQLite DB."""
import os
import tempfile
from datetime import datetime, timedelta, timezone

os.environ["TELCO_AI_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import telemetry  # noqa: E402
from app.auth import create_access_token, require_admin  # noqa: E402
from app.database import (AppDownload, LoginAudit, SessionLocal, User,  # noqa: E402
                          init_db)
from app.routes_stats import router  # noqa: E402

init_db()
app = FastAPI()
app.include_router(router)
app.dependency_overrides[require_admin] = lambda: None
client = TestClient(app)


def _user(name):
    db = SessionLocal()
    u = User(username=name, email=f"{name}@x.id", full_name=name.title(), hashed_password="x",
             login_count=3, last_login=datetime.now(timezone.utc))
    db.add(u)
    db.commit()
    db.refresh(u)
    db.close()
    return u


def test_stats_end_to_end(monkeypatch):
    monkeypatch.setattr("app.routes_stats._load_release",
                        lambda: {"version_name": "1.44.0", "version_code": 50})
    a, b = _user("ani"), _user("budi")
    tok = lambda u: "Bearer " + create_access_token({"sub": u.username})
    telemetry.record_client({"x-client-platform": "android", "x-app-version": "1.44.0",
                             "x-app-build": "50", "x-device-model": "Samsung A54",
                             "authorization": tok(a)})
    telemetry.record_client({"x-client-platform": "android", "x-app-version": "1.43.1",
                             "x-device-model": "Oppo A78", "authorization": tok(b)})
    # throttled duplicate does not add a row
    telemetry.record_client({"x-client-platform": "android", "x-app-version": "1.43.1",
                             "x-device-model": "Oppo A78", "authorization": tok(b)})
    telemetry.record_download({"user-agent": "Dart/3.6 (dart:io)"}, "1.2.3.4", "1.44.0", 50)
    telemetry.record_download({"user-agent": "Mozilla/5.0", "authorization": tok(a)}, "1.2.3.5",
                              "1.44.0", 50, "web")
    db = SessionLocal()
    db.add(LoginAudit(user_id=a.id, action="login", user_agent="Dart/3.6 (dart:io)"))
    db.add(LoginAudit(user_id=b.id, action="login", user_agent="Mozilla/5.0 Chrome"))
    db.add(LoginAudit(user_id=b.id, action="failed_login", ip_address="9.9.9.9"))
    db.commit()
    assert db.query(AppDownload).filter(AppDownload.user_id == a.id).one().source == "web"
    db.close()

    r = client.get("/api/admin/app-stats?days=30")
    assert r.status_code == 200, r.text
    j = r.json()
    k = j["kpis"]
    assert k["downloads_total"] == 2 and k["devices_installed"] == 2
    assert k["pct_on_latest"] == 50.0
    assert k["logins_android"] == 1 and k["logins_web"] == 1 and k["failed_logins"] == 1
    assert k["mau"] >= 2
    # nothing happened in the period before, so there is no baseline to compare with
    assert set(j["trend"]) == {"downloads_period", "devices_installed", "dau", "failed_logins"}
    assert j["trend"]["downloads_period"] is None
    assert all(r["last_seen"] for r in j["users"] if r["username"] in ("ani", "budi"))
    assert [o["full_name"] for o in j["outdated_users"]] == ["Budi"]
    assert sum(d["updates"] for d in j["downloads_timeline"]) == 1
    assert sum(map(sum, j["login_heatmap"])) == 2
    by = {u["username"]: u for u in j["users"]}
    assert by["ani"]["is_latest"] and by["ani"]["device_model"] == "Samsung A54"
    assert by["budi"]["status"] == "aktif"
    fs = j["failed_summary"]
    assert fs["total"] == 1 and fs["attempts"] == 3
    assert {r["key"]: r["count"] for r in fs["reasons"]}["failed_login"] == 1
    rec = j["failed_logins_recent"][0]
    assert rec["email"] == "budi@x.id" and rec["reason"] == "Kata sandi salah"

    # drawer + reminder
    db = SessionLocal()
    from app.database import Notification, UsageLog
    db.add(UsageLog(user_id=b.id, action="query", domain="revenue"))
    db.add(UsageLog(user_id=b.id, action="query", domain="revenue"))
    db.add(UsageLog(user_id=b.id, action="query", domain="site"))
    db.add(UsageLog(user_id=b.id, action="export", domain="revenue", detail="XLSX · Revenue Jawa Barat"))
    db.commit()
    d = client.get(f"/api/admin/app-stats/users/{b.id}").json()
    assert d["stats"] == {"logins_30d": 1, "login_total": 3, "queries": 3, "exports": 1}
    assert d["app_version"] == "1.43.1" and not d["is_latest"]
    assert [(x["device_model"], x["app_version"]) for x in d["devices"]] == [("Oppo A78", "1.43.1")]
    assert j["version_adoption"][-1]["versions"] == {"1.44.0": 1, "1.43.1": 1}
    assert d["topics"][0] == {"topic": "Revenue", "count": 2, "pct": 67}
    kinds = {t["kind"]: t for t in d["timeline"]}
    assert {"login", "failed", "export"} <= set(kinds)
    assert kinds["export"]["title"] == "Export XLSX · Revenue Jawa Barat"
    assert kinds["failed"]["title"] == "Login gagal · kata sandi salah"
    assert kinds["login"]["title"].startswith("Web · Chrome")
    assert client.get("/api/admin/app-stats/users/9999").status_code == 404
    r = client.post("/api/admin/app-stats/remind", json={"user_ids": [b.id, 9999]})
    assert r.json() == {"sent": 1}
    assert db.query(Notification).filter(Notification.user_id == b.id).count() == 1
    db.close()


def test_record_client_ignores_anonymous():
    telemetry.record_client({"x-client-platform": "android"})  # no token: no crash, no row


def test_trend_compares_with_previous_period(monkeypatch):
    monkeypatch.setattr("app.routes_stats._load_release", lambda: {"version_name": "1.44.0", "version_code": 50})
    db = SessionLocal()
    now = datetime.now(timezone.utc)
    before = db.query(AppDownload).count()
    for days_ago in (40, 45, 3, 4, 5):  # 2 in the previous 30 days, 3 in this one
        db.add(AppDownload(created_at=now - timedelta(days=days_ago), source="web", version_name="1.44.0"))
    db.commit()
    db.close()
    j = client.get("/api/admin/app-stats?days=30").json()
    cur = j["kpis"]["downloads_period"]
    assert before + 5 >= cur >= 3
    assert j["trend"]["downloads_period"] == round(100 * (cur - 2) / 2, 1)
