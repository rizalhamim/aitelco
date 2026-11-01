"""Watchlist evaluation and dashboard assembly, with BigQuery stubbed out."""
import os
import tempfile
import uuid

os.environ.setdefault("TELCO_AI_DB", os.path.join(tempfile.mkdtemp(), "t.db"))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import dashboard, watchlist  # noqa: E402
from app.auth import get_current_user  # noqa: E402
from app.database import Notification, SessionLocal, User, WatchAlert, init_db  # noqa: E402

init_db()


def _user(name):
    # unique per run: when another test module imported app.database first, TELCO_AI_DB above
    # is ignored and the (persistent) default database already holds users from earlier runs
    name = f"{name}-{uuid.uuid4().hex[:8]}"
    db = SessionLocal()
    u = User(username=name, email=f"{name}@x.id", full_name=name.title(), hashed_password="x")
    db.add(u)
    db.commit()
    db.refresh(u)
    db.close()
    return u


def test_conditions():
    hist = [(202608, 100.0), (202609, 100.0), (202610, 91.0)]
    v, level = watchlist.observed("payload", "turun", hist)
    assert round(v, 1) == -9.0 and level == 91.0
    assert watchlist.breached("turun", 5, v) and not watchlist.breached("naik", 5, v)
    assert watchlist.breached("berubah", 5, v)
    assert watchlist.severity("turun", 5, v) == "kritis"
    assert watchlist.severity("turun", 5, -6) == "peringatan"
    # availability: change is in percentage points, levels for absolute rules
    av = [(202609, 99.6), (202610, 98.9)]
    assert round(watchlist.observed("availability", "turun", av)[0], 2) == -0.7
    assert watchlist.breached("di_bawah", 99, watchlist.observed("availability", "di_bawah", av)[0])
    assert watchlist.fmt_value("payload", "turun", -9.1) == "−9,1%"


def test_rule_fires_after_streak_and_recovers(monkeypatch):
    u = _user("wati")
    app = FastAPI()
    app.include_router(watchlist.router)
    app.dependency_overrides[get_current_user] = lambda: SessionLocal().get(User, u.id)
    client = TestClient(app)

    level = {"v": 91.0}
    monkeypatch.setattr(watchlist, "metric_history",
                        lambda m, l, v, months=13: [(202609, 100.0), (202610, level["v"])])
    days = iter(["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
    today = {"d": next(days)}
    monkeypatch.setattr(watchlist, "_today_wib", lambda: today["d"])

    r = client.post("/api/watchlist/rules", json={
        "metric": "payload", "scope_level": "kabkota", "scope_value": "GARUT",
        "condition": "turun", "threshold": 5, "days": 2})
    assert r.status_code == 200, r.text
    rule = r.json()
    assert rule["value_label"] == "−9,0%" and rule["threshold_label"] == "< −5%"
    assert rule["threshold_sub"] == "selama 2 hari" and rule["group"] == "perf" and rule["title"] == "Payload MoM"
    assert rule["status"] == "normal" and rule["breach_streak"] == 1   # needs 2 days

    today["d"] = next(days)
    rules = client.get("/api/watchlist/rules").json()["rules"]
    assert rules[0]["status"] == "kritis"
    assert client.get("/api/watchlist/alerts/count").json()["active"] == 1
    alerts = client.get("/api/watchlist/alerts").json()["alerts"]
    assert alerts[0]["severity"] == "kritis" and alerts[0]["title"].startswith("Payload Garut turun")
    assert alerts[0]["kabupaten"] == "GARUT" and alerts[0]["group_label"] == "Performance"
    db = SessionLocal()
    assert db.query(Notification).filter(Notification.user_id == u.id, Notification.kind == "alert").count() == 1
    db.close()

    # same day again: no re-check, no duplicate alert
    client.get("/api/watchlist/rules")
    assert client.get("/api/watchlist/alerts/count").json()["active"] == 1

    # back to normal → episode closes with a "pulih" alert
    level["v"] = 99.0
    today["d"] = next(days)
    rules = client.get("/api/watchlist/rules").json()["rules"]
    assert rules[0]["status"] == "normal"
    assert client.get("/api/watchlist/alerts/count").json()["active"] == 0
    db = SessionLocal()
    assert db.query(WatchAlert).filter(WatchAlert.rule_id == rule["id"], WatchAlert.severity == "pulih").count() == 1
    db.close()

    assert client.delete(f"/api/watchlist/rules/{rule['id']}").json() == {"ok": True}


def test_dashboard_overview(monkeypatch):
    def fake_query(sql, row_limit=None):
        if "MAX(month_id)" in sql:
            return {"rows": [{"m": 202610}]}
        if "rham_avail_stat_territory_monthly" in sql:
            return {"rows": [
                {"territory_level": "circle", "territory_name": "JAVA", "month_id": 202609, "avail": 99.5, "below_sla": 40},
                {"territory_level": "circle", "territory_name": "JAVA", "month_id": 202610, "avail": 99.62, "below_sla": 37}]}
        rows = []
        for i, mid in enumerate([202511, 202512, 202601, 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609, 202610]):
            for rg, base in (("JAWA TIMUR", 700e9), ("JAWA BARAT", 420e9)):
                drop = 0.97 if (rg == "JAWA BARAT" and mid == 202610) else 1.0
                rows.append({"month_id": mid, "region": rg, "revenue": (base + i * 5e9) * drop,
                             "subs": 1e7 + i, "payload": 2e7 * (0.9 if mid == 202610 else 1), "gross_add": 1e5})
        return {"rows": rows}

    monkeypatch.setattr(dashboard, "run_query", fake_query)
    monkeypatch.setattr(dashboard.reports_cache, "data_marker", lambda fam, force=False: "m1")
    monkeypatch.setattr(dashboard.perf_dump, "status", lambda: {"available": False, "fresh": False})
    monkeypatch.setattr(dashboard.perf_dump, "load", lambda name, allow_stale=False: None)
    out = dashboard.build_overview()
    assert out["source"]["kind"] == "bigquery"
    assert out["month_label"] == "Okt 2026" and out["prev_label"] == "Sep"
    keys = [k["key"] for k in out["kpis"]]
    assert keys == ["revenue", "subs", "payload", "availability"]
    av = out["kpis"][-1]
    assert round(av["pct_change"], 2) == 0.12 and av["change_unit"] == "pp"
    assert len(out["kpis"][0]["spark"]) == 12
    assert out["regions"][0]["region"] == "JAWA TIMUR"
    jb = next(r for r in out["regions"] if r["region"] == "JAWA BARAT")
    assert jb["mom_pct"] < 0 and jb["achievement_pct"] is None and 0 < jb["share_pct"] < 50
    assert len(out["revenue_by_region"]["labels"]) == 6
    text = out["summary"]["text"].replace("**", "").lower()
    assert "revenue circle java turun" in text and "terutama dari jawa barat" in text
    assert "payload data turun 10,0%" in text


def test_near_threshold_and_formats():
    r = watchlist.WatchRule(metric="revenue", scope_level="region", scope_value="WEST JAVA", condition="turun", threshold=3, days=1)
    assert watchlist.near(r, -2.4) and not watchlist.near(r, -1.0) and not watchlist.near(r, -3.5)
    assert watchlist.fmt_threshold(r) == "< −3%" and watchlist.fmt_period(r) == "bulanan"
    assert watchlist.scope_label(r) == "West Java"
    a = watchlist.WatchRule(metric="availability", scope_level="circle", scope_value="JAVA", condition="di_bawah", threshold=99.0, days=1)
    assert not watchlist.near(a, 99.31) and watchlist.near(a, 99.1)
    assert watchlist.fmt_threshold(a) == "< 99,0%" and watchlist.fmt_period(a) == "harian" and watchlist.scope_label(a) == "Circle Java"
    g = watchlist.WatchRule(metric="rgu_site", scope_level="kabkota", scope_value="GARUT", condition="di_bawah", threshold=1800, days=60)
    assert watchlist.near(g, 1900) and watchlist.fmt_threshold(g) == "< 1,8 rb" and watchlist.fmt_period(g) == "selama 2 bulan"
    m = watchlist.WatchRule(metric="market_share", scope_level="kabkota", scope_value="CIANJUR", condition="turun", threshold=0.5, days=1)
    assert watchlist.fmt_threshold(m) == "turun > 0,5 pp" and not watchlist.available("market_share")


def test_parse_sentence():
    d = watchlist.parse_sentence("Kabari saya kalau revenue per site di Kab. Garut turun di bawah Rp 180 jt selama 2 bulan")
    assert (d["metric"], d["scope_level"], d["scope_value"], d["condition"], d["threshold"], d["days"]) == \
        ("rev_site", "kabkota", "GARUT", "di_bawah", 180e6, 60)
    assert d["metric_label"] == "Revenue / site" and d["group_label"] == "Site productivity"
    assert d["condition_label"] == "< Rp 180 jt, 2 bulan" and not d["missing"]
    d = watchlist.parse_sentence("payload West Java turun lebih dari 5% selama 3 hari")
    assert (d["metric"], d["scope_value"], d["condition"], d["threshold"], d["days"]) == ("payload", "WEST JAVA", "turun", 5.0, 3)
    assert watchlist.parse_sentence("tolong pantau ya")["missing"] == ["metric", "condition", "threshold"]


def test_unavailable_metric_and_stats(monkeypatch):
    u = _user("stat")
    app = FastAPI()
    app.include_router(watchlist.router)
    app.dependency_overrides[get_current_user] = lambda: SessionLocal().get(User, u.id)
    client = TestClient(app)
    r = client.post("/api/watchlist/rules", json={"metric": "vlr_site", "scope_level": "region", "scope_value": "CENTRAL JAVA",
                                                  "condition": "di_bawah", "threshold": 3000, "notify_push": True})
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "nodata" and r.json()["notify_push"] is True and r.json()["available"] is False
    st = client.get("/api/watchlist/stats").json()
    assert st["alerts_30d"] == 0 and [g["label"] for g in st["by_group"]] == ["Performance", "Site productivity", "Profile wilayah"]
    assert client.post("/api/watchlist/parse", json={"text": "availability Kota Semarang di bawah 99%"}).json()["scope_label"].startswith("Kota Semarang")
