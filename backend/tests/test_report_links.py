"""Shared report links against a throwaway SQLite DB."""
import os
import tempfile
from datetime import timedelta

os.environ["TELCO_AI_DB"] = os.path.join(tempfile.mkdtemp(), "t.db")

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import report_schedule  # noqa: E402
from app.auth import get_current_user  # noqa: E402
from app.database import ReportLink, SessionLocal, User, init_db, utcnow  # noqa: E402

init_db()
db = SessionLocal()
_u = User(username="link_owner", email="link_owner@x.id", full_name="Link Owner", hashed_password="x")
db.add(_u)
db.commit()
db.refresh(_u)
db.close()

app = FastAPI()
app.include_router(report_schedule.links_router)
app.dependency_overrides[get_current_user] = lambda: _u
client = TestClient(app)

OV = {
    "scope": {"region": None}, "month_label": "Okt 2026",
    "summary": {"text": "Revenue Jawa **naik 1,2% MoM**."},
    "kpis": [{"label": "Revenue", "format": "currency", "value": 1.84e12, "pct_change": 1.2}],
    "regions": [{"region": "JAWA TIMUR", "revenue": 788e9, "mom_pct": 2.1, "subs": 17.6e6, "payload_gb": 36.4e6}],
}


def test_link_opens_report_until_expiry(monkeypatch):
    monkeypatch.setattr(report_schedule.reports_cache, "get_or_build", lambda *a, **k: OV)
    r = client.post("/api/report-links", json={"title": "Revenue Jawa Barat vs September"})
    assert r.status_code == 200 and r.json()["days"] == 7
    path = r.json()["path"]
    page = client.get(path)
    assert page.status_code == 200
    assert "Rp 1,84 T" in page.text and "Revenue Jawa Barat vs September" in page.text and "berlaku sampai" in page.text

    # expired links show a notice instead of data
    s = SessionLocal()
    link = s.query(ReportLink).filter(ReportLink.token == path.rsplit("/", 1)[1]).one()
    assert link.views == 1
    link.expires_at = utcnow() - timedelta(minutes=1)
    s.commit()
    s.close()
    gone = client.get(path)
    assert gone.status_code == 404 and "Rp 1,84 T" not in gone.text


def test_unknown_token_is_404():
    assert client.get("/api/report-links/nope").status_code == 404


def test_adhoc_link_shows_snapshot_table():
    r = client.post("/api/report-links", json={"title": "Top <kab>", "columns": ["kabupaten", "revenue"],
                                               "rows": [{"kabupaten": "Garut", "revenue": 1234567.5}]})
    page = client.get(r.json()["path"])
    assert page.status_code == 200
    assert "Garut" in page.text and "1.234.567,50" in page.text and "Top &lt;kab&gt;" in page.text
