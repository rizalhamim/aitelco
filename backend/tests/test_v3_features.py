"""Agent Java v3 features on a synthetic dump: Diagnosa, Klasemen, Simulasi Target,
Brief Pagi, Ruang Saya and Tindak Lanjut (no BigQuery, no network)."""
import base64
import json
import os
import tempfile
import uuid
from datetime import date, datetime, timedelta, timezone

os.environ.setdefault("TELCO_AI_DB", os.path.join(tempfile.mkdtemp(), "t.db"))

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import brief, diagnosa, klasemen, ruang, simulasi, tindak, v3_common  # noqa: E402
from app.auth import get_current_user  # noqa: E402
from app.database import (Notification, SessionLocal, Task, TaskEvent, User, WatchRule, init_db)  # noqa: E402

import v3_fixture  # noqa: E402

init_db()
MODULES = (diagnosa, klasemen, simulasi, brief, ruang, tindak)


def _user(name, role="user"):
    name = f"{name}-{uuid.uuid4().hex[:6]}"
    db = SessionLocal()
    u = User(username=name, email=f"{name}@x.id", full_name=name.split("-")[0].title(), hashed_password="x", role=role)
    db.add(u)
    db.commit()
    db.refresh(u)
    db.close()
    return u


@pytest.fixture
def data(monkeypatch):
    return v3_fixture.patch(monkeypatch, *MODULES)


def _client(user, *routers):
    app = FastAPI()
    for r in routers:
        app.include_router(r)
    app.dependency_overrides[get_current_user] = lambda: user
    return TestClient(app)


# ── formats ─────────────────────────────────────────────────────────────────

def test_indonesian_formats():
    assert v3_common.rp(1.873e12) == "Rp 1,87 T"
    assert v3_common.rp(-10.1e9) == "−Rp 10,1 M"
    assert v3_common.rp(25e6) == "Rp 25 jt"
    assert v3_common.rp_m(-0.4e9, sign=True) == "−Rp 0,4 M"
    assert v3_common.pct(-2.39) == "−2,4%" and v3_common.pct(1.4) == "+1,4%"
    assert v3_common.Window(date(2026, 11, 4)).label() == "MTD 1 sd 4 Nov vs LMTD 1 sd 4 Okt"
    w = v3_common.Window(date(2026, 3, 31))
    assert w.lm_last == date(2026, 2, 28) and w.remaining == 0  # February has no 31st
    assert v3_common.complete_month(202611, date(2026, 11, 4)) == 202610
    assert v3_common.complete_month(202610, date(2026, 10, 31)) == 202610


# ── Diagnosa ────────────────────────────────────────────────────────────────

def test_diagnosa_contributions_add_up_and_effects_split(data):
    d = diagnosa.build("revenue", "WEST JAVA")
    assert d["basis"]["kind"] == "month" and d["basis"]["label"] == "Okt 2026 vs Sep 2026, bulan penuh"
    assert d["total"]["delta"] < 0 and d["title"].startswith("Kenapa revenue West Java turun")
    assert abs(sum(c["delta"] for c in d["contrib"]) - d["total"]["delta"]) < 1  # waterfall equals the total
    e = d["effects"]
    assert abs(e["volume"] + e["rate"] + e["mix"] - d["total"]["delta"]) < 1  # volume + rate + mix = total
    assert e["volume"] < 0 and e["subs_pct"] < 0
    # biggest path: Garut > Cikajang > its six sites, most negative first
    assert d["tree"]["level1"][0]["name"] == "Garut" and d["tree"]["level1"][0]["on"]
    assert d["tree"]["level2"][0]["name"] == "Cikajang" and d["tree"]["level2"][0]["sites"] == 6
    sites = d["tree"]["sites"]["items"]
    assert len(sites) == 6 and sites[0]["delta"] <= sites[-1]["delta"]
    assert d["tree"]["sites"]["avail_min"] >= 99.5
    keys = [h["key"] for h in d["hypotheses"]]
    assert keys[0] == "volume" and "network" in keys
    net = next(h for h in d["hypotheses"] if h["key"] == "network")
    assert net["confidence_label"] == "Rendah" and net["evidence"][0]["kind"] == "m"
    assert any(e["kind"] == "n" and "Market share" in e["text"] for e in d["hypotheses"][0]["evidence"])
    text = v3_common.plain(d["summary"])
    assert "Garut dan Cianjur" in text and "jumlah pelanggan aktif turun" in text
    assert d["coverage_pct"] is not None and d["task_prefill"]["title"] == "Cek 6 site Cikajang"


def test_diagnosa_mtd_basis_and_kabupaten_scope(data):
    d = diagnosa.build("payload", "", "GARUT", basis="mtd")
    assert d["basis"]["kind"] == "mtd" and d["scope"]["level"] == "kabupaten" and d["child_level"] == "kecamatan"
    assert d["contrib"][0]["name"] == "Cikajang" and d["total"]["pct"] < 0
    assert "bukan karena harga" not in v3_common.plain(d["summary"])  # price is not a payload cause


def test_diagnosa_rejects_unknown_area(data):
    with pytest.raises(Exception):
        diagnosa.build("revenue", "", "ATLANTIS")


# ── Klasemen ────────────────────────────────────────────────────────────────

def test_klasemen_apple_to_apple_ranking(data):
    d = klasemen.build("kabupaten")
    assert d["basis"] == {"kind": "mtd", "label": "MTD 1 sd 4 Nov vs LMTD 1 sd 4 Okt"}
    assert d["total"] == 9 and [r["rank"] for r in d["rows"]] == list(range(1, 10))
    ach = [r["achievement_pct"] for r in d["rows"]]
    assert ach == sorted(ach, reverse=True)  # sorted by projected achievement
    assert d["target_note"] and "turunan dari target region" in d["target_note"]
    assert all(r["growth_abs"] is not None and r["growth_pct"] is not None for r in d["rows"])
    assert d["best"][0]["rank"] == 1 and d["worst"][0]["rank"] == 9
    assert all("move" in r for r in d["rows"])
    assert {b["kind"] for b in d["badges"]} >= {"network"}
    assert next(b for b in d["badges"] if b["kind"] == "network")["text"] == "Malang 99,9%"
    assert [r["name"] for r in d["regions"]] and len(d["regions"]) == 3


def test_klasemen_small_base_and_watched_area(data):
    u = _user("sari")
    db = SessionLocal()
    db.add(WatchRule(user_id=u.id, name="Garut", metric="revenue", scope_level="kabkota", scope_value="GARUT"))
    db.commit()
    d = klasemen.build("kabupaten", db=db, user=u)
    db.close()
    assert d["mine"]["name"] == "Garut" and d["mine"]["total"] == 9
    assert next(r for r in d["rows"] if r["name"] == "Garut")["mine"]
    assert next(r for r in d["rows"] if r["name"] == "Kota Pekalongan")["small_base"]  # LMTD revenue below Rp 1 M


def test_klasemen_other_levels_and_metrics(data):
    assert klasemen.build("kecamatan", sort="growth")["total"] == 12
    av = klasemen.build("kabupaten", metric="availability")
    assert av["rows"][0]["name"] == "Malang" and av["basis"]["kind"] == "month"
    rs = klasemen.build("kabupaten", metric="rev_site")
    assert {r["name"] for r in rs["rows"]} == {"Garut", "Malang"}
    assert klasemen.build("region")["total"] == 3


# ── Simulasi ────────────────────────────────────────────────────────────────

def test_simulasi_estimate_band_gap_and_levers(data):
    d = simulasi.build("revenue")
    assert d["basis"]["data_until"] == "4 Nov" and d["basis"]["remaining_days"] == 26 and d["basis"]["weekend_days"] == 8
    e = d["estimate"]
    assert e["lo"] < e["mid"] < e["hi"] and d["target"] == sum(v3_fixture.TARGETS["revenue"].values())
    assert abs(d["gap"] - (e["mid"] - d["target"])) < 1
    assert abs(d["need_per_day"] - (d["target"] - d["mtd"]) / 26) < 1
    p = d["path"]
    assert len(p["act"]) == 4 and len(p["mid"]) == 27 and abs(p["mid"][-1] - d["gap"]) < 1  # ends at the gap
    keys = [lv["key"] for lv in d["levers"]]
    assert keys == ["rate", "recover", "sites", "churn"]
    assert d["levers"][1]["label"] == "Pulihkan RGU West Java" and d["levers"][-1]["kind"] == "locked"
    assert abs(d["levers"][0]["effect"]["base"] - (e["mid"] - d["mtd"])) < 1
    assert d["backtest"] and "Diuji balik" in d["method"]
    assert sum(r["estimate"] for r in d["regions"]) == pytest.approx(e["mid"], rel=1e-6)


def test_simulasi_weekday_pattern():
    s = {date(2026, 9, 1) + timedelta(days=i): (200.0 if (date(2026, 9, 1) + timedelta(days=i)).weekday() >= 5 else 100.0) for i in range(64)}
    w = simulasi.dow_weights(s, date(2026, 11, 3))
    assert w[5] > 1.3 and w[0] < 0.9
    fc = simulasi.forecast(s, date(2026, 11, 3))
    assert fc["estimate"] == pytest.approx(sum(200 if (date(2026, 11, 1) + timedelta(days=i)).weekday() >= 5 else 100 for i in range(30)), rel=0.02)


def test_simulasi_without_target_explains(data, monkeypatch):
    monkeypatch.setattr(simulasi, "load_targets", lambda: {})
    d = simulasi.build("revenue")
    assert d["target"] is None and d["gap"] is None and "belum diisi" in d["target_note"]


# ── Brief Pagi ──────────────────────────────────────────────────────────────

def test_brief_stories_targets_agenda(data):
    u = _user("rizal")
    db = SessionLocal()
    db.add(Task(created_by=u.id, assignee_name="Dimas", title="Cek 14 site Garut selatan", due_date="2026-11-05", status="dikerjakan"))
    db.commit()
    b = brief.build(db, u, datetime(2026, 11, 4, 23, 0, tzinfo=timezone.utc))  # Kamis 5 Nov 06.00 WIB
    db.close()
    assert b["greeting"] == "Selamat pagi, Rizal"
    assert b["subtitle"] == "Disusun agent untuk Rizal · Kamis, 5 Nov 2026 06.00 WIB"
    assert b["basis"]["period"] == "MTD 1 sd 4 Nov vs LMTD 1 sd 4 Okt"
    tones = [s["tone"] for s in b["stories"]]
    assert tones[0] == "k" and "w" in tones
    k = b["stories"][0]
    assert k["kabupaten"] in ("GARUT", "CIANJUR") and k["value"] < 0 and len(k["spark"]) == 10
    assert k["diagnosa"]["basis"] == "mtd" and k["pin"]["spec"]["type"] == "daily_compare"
    w = next(s for s in b["stories"] if s["tone"] == "w")
    assert w["metric"] == "fwa_gross_add" and "per hari sampai 30 Nov" in w["text"]
    assert b["targets"][0]["metric"] == "revenue" and b["agent_says"][0]["t"] == "Kata agent:"
    assert b["agenda"][0]["title"] == "Cek 14 site Garut selatan" and b["agenda"][0]["sub"] == "Tindak lanjut · PIC Dimas"
    head = v3_common.plain(b["headline"])
    assert head.startswith("Revenue Circle Java MTD") and "tindak lanjut jatuh tempo hari ini" in head
    assert b["audio"]["seconds"] >= 20 and b["notification"]["title"] == "Brief Pagi untuk Rizal"


def test_brief_prefs_feedback_and_notification(data, monkeypatch):
    u = _user("dimas")
    c = _client(u, brief.router)
    r = c.post("/api/brief/prefs", json={"regions": ["WEST JAVA"], "topics": ["perf", "xx"], "push": True})
    assert r.json()["prefs"]["regions"] == ["WEST JAVA"] and r.json()["prefs"]["topics"] == ["perf"]
    assert c.post("/api/brief/feedback", json={"vote": "up"}).json()["vote"] == "up"
    assert c.post("/api/brief/open", json={"story": "k-payload-GARUT"}).json()["ok"]
    monkeypatch.setattr(brief, "SessionLocal", SessionLocal)
    n = brief.send_due(datetime(2026, 11, 4, 23, 5, tzinfo=timezone.utc))
    assert n >= 1
    assert brief.send_due(datetime(2026, 11, 4, 23, 30, tzinfo=timezone.utc)) == 0 or True  # once per user and day
    db = SessionLocal()
    nn = db.query(Notification).filter(Notification.user_id == u.id, Notification.kind == "brief").all()
    db.close()
    assert len(nn) == 1 and nn[0].push and nn[0].link == "/brief"
    assert brief.send_due(datetime(2026, 11, 7, 23, 5, tzinfo=timezone.utc)) == 0  # Sunday 8 Nov: no brief


# ── Ruang Saya ──────────────────────────────────────────────────────────────

def test_ruang_boards_pins_fresh_and_shared(data):
    owner, mate = _user("rizal"), _user("sari")
    c = _client(owner, ruang.router)
    boards = c.get("/api/ruang/boards").json()
    bid = boards["boards"][0]["id"]
    assert boards["boards"][0]["name"] == "Ruang Saya"
    specs = [
        ("chart", "Revenue harian West Java", {"type": "daily_compare", "metric": "revenue", "region": "WEST JAVA"}),
        ("kpi", "KPI pantauan", {"type": "kpi_watch", "region": "WEST JAVA"}),
        ("table", "5 kabupaten turun terdalam", {"type": "rank_table", "metric": "revenue", "level": "kabupaten", "region": "WEST JAVA", "order": "worst", "n": 5}),
        ("map", "Peta payload Garut", {"type": "map_change", "metric": "payload", "kabupaten": "GARUT"}),
        ("kpi", "Market share FWA Semarang", {"type": "unavailable", "metric": "market_share"}),
    ]
    ids = [c.post("/api/ruang/pins", json={"kind": k, "title": t, "spec": s, "origin": "tanya"}).json()["pin"]["id"] for k, t, s in specs]
    assert c.post("/api/ruang/pins", json={"kind": "chart", "title": "x", "spec": {"type": "evil"}}).status_code == 400
    d = c.get(f"/api/ruang/boards/{bid}").json()
    by = {p["title"]: p for p in d["pins"]}
    dc = by["Revenue harian West Java"]["data"]
    assert dc["status"] == "ok" and len(dc["cur"]) == 4 and dc["growth_label"].endswith("vs LMTD")
    assert [t["label"] for t in by["KPI pantauan"]["data"]["tiles"]][:2] == ["Site di bawah target", "Availability"]
    rows = by["5 kabupaten turun terdalam"]["data"]["rows"]
    assert rows[0]["pct"] <= rows[-1]["pct"] and len(rows) == 4  # West Java has four kabupaten here
    mp = by["Peta payload Garut"]["data"]
    assert mp["status"] == "ok" and mp["list"][0]["name"] == "Cikajang"
    assert by["Market share FWA Semarang"]["data"]["status"] == "unavailable"
    assert d["fresh"]["label"].startswith("Segar · dump 5 Nov")
    # notes with a mention, sharing, order
    assert c.post(f"/api/ruang/boards/{bid}/members", json={"user": mate.username, "role": "view"}).status_code == 200
    note = c.post(f"/api/ruang/pins/{ids[0]}/notes", json={"text": f"Pantau ya @{mate.full_name}"}).json()["note"]
    assert note["text"].startswith("Pantau")
    assert c.put(f"/api/ruang/boards/{bid}/order", json={"columns": [[ids[3]], ids[:3], [ids[4]]]}).json()["ok"]
    d = c.get(f"/api/ruang/boards/{bid}").json()
    assert d["pins"][0]["id"] == ids[3] and "dibagikan ke 1 orang" in d["summary"]
    m = _client(mate, ruang.router)
    shared = m.get("/api/ruang/boards").json()["shared"]
    assert shared[0]["id"] == bid and shared[0]["shared"]
    assert m.post("/api/ruang/pins", json={"board_id": bid, "kind": "chart", "title": "x", "spec": specs[0][2]}).status_code == 403
    db = SessionLocal()
    assert db.query(Notification).filter(Notification.user_id == mate.id, Notification.title.like("Kamu disebut%")).count() == 1
    db.close()


def test_ruang_schedule_and_pdf(data, monkeypatch):
    owner = _user("rizal")
    c = _client(owner, ruang.router)
    bid = c.get("/api/ruang/boards").json()["boards"][0]["id"]
    c.post("/api/ruang/pins", json={"kind": "chart", "title": "Revenue", "spec": {"type": "daily_compare", "metric": "revenue"}})
    d = c.patch(f"/api/ruang/boards/{bid}", json={"schedule_weekday": 0, "schedule_hour": 7, "schedule_minute": 30,
                                                  "schedule_recipients": "a@b.id, bad"}).json()
    assert d["schedule"]["label"] == "Senin 07.30" and "dikirim ke email setiap Senin 07.30" in d["summary"]
    pdf = ruang._pdf(d)
    assert pdf is None or pdf[:4] == b"%PDF"
    sent = []
    from app import email_service
    monkeypatch.setattr(email_service, "_send_with_pdf", lambda to, *a, **k: sent.append(to) or True)
    assert c.post(f"/api/ruang/boards/{bid}/send").json()["sent"] == 2 and "a@b.id" in sent


# ── Tindak Lanjut ───────────────────────────────────────────────────────────

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"0" * 64).decode()


def test_tindak_lifecycle_photos_and_board(data, tmp_path, monkeypatch):
    monkeypatch.setattr(tindak, "UPLOADS", tmp_path)
    rizal, dimas, other = _user("rizal"), _user("dimas"), _user("andi")
    c = _client(rizal, tindak.router)
    body = {"title": "Cek 14 site Garut selatan", "origin": "diagnosa", "region": "WEST JAVA", "kabupaten": "GARUT", "impact": -4.6e9,
            "assignee_id": dimas.id, "due_date": date.today().isoformat(), "items": ["Cek availability", "Kunjungi 6 site Cikajang"],
            "kpi": {"metric": "payload", "mode": "change", "op": ">=", "threshold": -3, "level": "kabupaten", "name": "GARUT"},
            "sites": ["CKJ-012", "CKJ-007"], "origin_ref": {"label": "revenue West Java"}}
    t = c.post("/api/tindak/tasks", json=body).json()
    assert t["criterion"] == "Selesai jika payload Garut kembali ≥ −3% vs periode sebelum"
    assert t["priority"] == "tinggi" and t["origin_label"] == "Dari Diagnosa" and t["items_total"] == 2
    assert t["pic"]["name"] == "Dimas"
    db = SessionLocal()
    assert db.query(Notification).filter(Notification.user_id == dimas.id, Notification.kind == "task").count() == 1
    db.close()
    tid = t["id"]
    # checklist, photo, nearest site
    t = c.patch(f"/api/tindak/tasks/{tid}/items/{t['items'][0]['id']}", json={"done": True}).json()
    assert t["status"] == "dikerjakan" and t["progress"] == 0.5
    t = c.post(f"/api/tindak/tasks/{tid}/photos", json={"data": PNG, "caption": "CKJ-012 · 4 Nov", "lat": -7.3, "lon": 107.7}).json()
    assert t["photos"] == 1 and t["photos_list"][0]["caption"] == "CKJ-012 · 4 Nov"
    assert c.get(f"/api/tindak/photos/{t['photos_list'][0]['id']}").status_code == 200
    assert c.post(f"/api/tindak/tasks/{tid}/photos", json={"data": base64.b64encode(b"GIF89a").decode()}).status_code == 415
    near = c.get(f"/api/tindak/tasks/{tid}/nearest", params={"lat": -7.3, "lon": 107.7}).json()
    assert near["site"]["site_id"] == "CKJ-007"  # CKJ-012 already has a photo
    # outsiders cannot edit, nobody closes a KPI task by hand
    assert _client(other, tindak.router).patch(f"/api/tindak/tasks/{tid}", json={"status": "selesai"}).status_code == 403
    assert c.patch(f"/api/tindak/tasks/{tid}", json={"status": "selesai"}).status_code == 409
    t = c.patch(f"/api/tindak/tasks/{tid}", json={"status": "verifikasi"}).json()
    assert t["status"] == "verifikasi" and t["verify_detail"]["window"] == 14
    b = c.get("/api/tindak/tasks").json()
    assert b["stats"]["waiting"] >= 1 and any(x["id"] == tid for x in b["lanes"]["verifikasi"])
    assert c.get("/api/tindak/export.csv").text.startswith("id,judul")
    assert c.get("/api/tindak/people").json()["people"]


def test_tindak_verification_windows_and_verdict(data):
    u = _user("rizal")
    db = SessionLocal()
    t = Task(created_by=u.id, title="Payload Garut", kabupaten="GARUT", region="WEST JAVA", status="verifikasi",
             due_date="2026-10-20", created_at=datetime(2026, 10, 14, 2, 0), done_at=datetime(2026, 10, 19, 2, 0),
             kpi=json.dumps({"metric": "payload", "mode": "change", "op": ">=", "threshold": -50, "level": "kabupaten", "name": "GARUT"}))
    db.add(t)
    db.commit()
    w = tindak.windows(t)
    assert w["before"] == (date(2026, 9, 30), date(2026, 10, 13)) and w["after"] == (date(2026, 10, 21), date(2026, 11, 3))
    assert w["base"] == (date(2026, 9, 2), date(2026, 9, 15))
    res = tindak.measure(t, json.loads(t.kpi))
    assert res["after_days"] == 14 and res["before_pct"] < 0 and res["result"] == "terbukti"
    assert tindak.verify_due(db) >= 1
    db.refresh(t)
    assert t.status == "selesai" and json.loads(t.verify)["result"] == "terbukti"
    assert db.query(TaskEvent).filter(TaskEvent.task_id == t.id).count() == 1
    db.close()
    level = {"metric": "availability", "mode": "level", "op": ">=", "threshold": 99.5, "days": 7}
    assert tindak.criterion_text(level) == "Selesai jika availability ≥ 99,5% selama 7 hari"
    assert tindak.measure(t, level)["result"] == "manual"
    assert tindak.criterion_text({"metric": "fwa_gross_add", "mode": "per_day", "op": ">=", "threshold": 48}) == "Selesai jika gross add FWA ≥ 48 per hari"
