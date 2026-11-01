"""Performance dump: query shapes, Parquet round trip, freshness and the dashboard reader."""
import json
from datetime import date, datetime, timedelta, timezone

import pytest

pa = pytest.importorskip("pyarrow")
import pyarrow.parquet as pq  # noqa: E402

from app import dashboard, perf_dump  # noqa: E402

COLS = {
    perf_dump.T_ZZ: {"kec_id", "kabkota", "province", "kecamatan"},
    perf_dump.T_MTD: {"kec_id", "month_id", "rev_prepaid", "rgu_90d", "usg_data_gb", "gross_add"},
    perf_dump.T_DLY: {"kec_id", "dt_id", "rev_prepaid", "usg_data_gb"},
    perf_dump.T_SITE: {"site_id", "month_id", "usg_data_gb", "rev_total"},
    perf_dump.T_ADDR: {"site_id", "site_name"},
    perf_dump.T_SITE_AV: {"site_id", "month_id", "avg_avail_pct_4g"},
}


def test_queries_use_literal_partitions_and_probed_columns():
    q = perf_dump.build_queries(202610, date(2026, 10, 31), lambda t: COLS.get(t, set()))
    assert set(q) == {"kec_month", "avail_month", "region_daily", "site_month"}
    assert "BETWEEN 202410 AND 202610" in q["kec_month"]
    assert "ANY_VALUE(z.kecamatan) AS kecamatan" in q["kec_month"]
    assert "DATE '2026-08-23' AND DATE '2026-10-31'" in q["region_daily"]
    # the daily table lacks rgu_90d and gross_add: only the measures it has are summed
    assert "rgu_90d" not in q["region_daily"] and "SUM(x.usg_data_gb) AS payload_gb" in q["region_daily"]
    assert "IN (202610, 202609, 202510)" in q["site_month"] and "SUM(rev_total) AS revenue" in q["site_month"]


def test_optional_tables_are_skipped_when_missing():
    cols = dict(COLS)
    cols[perf_dump.T_DLY] = set()
    cols[perf_dump.T_SITE] = set()
    q = perf_dump.build_queries(202610, None, lambda t: cols.get(t, set()))
    assert set(q) == {"kec_month", "avail_month"}


def _write_dump(root, created: datetime, kec_rows, daily_rows=()):
    d = root / "20261101-0500"
    d.mkdir(parents=True)
    pq.write_table(pa.Table.from_pylist(list(kec_rows)), d / "kec_month.parquet")
    if daily_rows:
        pq.write_table(pa.Table.from_pylist(list(daily_rows)), d / "region_daily.parquet")
    (d / "manifest.json").write_text(json.dumps({"created_at": created.isoformat(), "latest_month": 202610, "tables": {}}))
    (root / "current").write_text(d.name)


@pytest.fixture
def dump_root(tmp_path, monkeypatch):
    monkeypatch.setattr(perf_dump, "DUMP_ROOT", tmp_path)
    perf_dump._cache.clear()
    return tmp_path


def _kec(month, region, rev, kec="K1"):
    return {"month_id": month, "kec_id": kec, "region": region, "kabupaten": "KAB A", "provinsi": "P",
            "kecamatan": "X", "revenue": rev, "subs": 10.0, "payload_gb": 5.0, "gross_add": 1.0}


def test_label_and_daily_spark(dump_root):
    created = datetime(2026, 10, 31, 22, 0, tzinfo=timezone.utc)  # 1 Nov 05.00 WIB
    days = [{"dt_id": f"2026-10-{d:02d}", "region": "EAST JAVA", "revenue": float(d), "payload_gb": 1.0} for d in range(18, 32)]
    _write_dump(dump_root, created, [_kec(202610, "EAST JAVA", 100.0), _kec(202610, "WEST JAVA", 50.0, "K2")], days)
    st = perf_dump.status()
    assert st["available"] and st["label"] == "Dump Performance 1 Nov 05.00"
    assert len(perf_dump.load("kec_month", allow_stale=True)) == 2
    vals, labels = dashboard._daily_spark(days, ["EAST JAVA"], "revenue")
    assert vals == [float(d) for d in range(22, 32)] and labels[0] == "22 Okt" and labels[-1] == "31 Okt"
    assert dashboard._daily_spark(days, ["EAST JAVA"], "subs") == (None, None)
    wk, wl = dashboard._weekly_spark(days, ["EAST JAVA"], "revenue")
    # 18 Okt is a Sunday: weeks start 12, 19 and 26 Okt
    assert wl == ["12 Okt", "19 Okt", "26 Okt"] and wk == [18.0, sum(range(19, 26)), sum(range(26, 32))]


def test_stale_dump_is_not_used(dump_root, monkeypatch):
    _write_dump(dump_root, datetime.now(timezone.utc) - timedelta(hours=31), [_kec(202610, "EAST JAVA", 1.0)])
    assert perf_dump.status()["fresh"] is False
    assert perf_dump.load("kec_month") is None
    assert dashboard._from_dump(12) is None


def test_fresh_dump_aggregates_region_month(dump_root):
    _write_dump(dump_root, datetime.now(timezone.utc) - timedelta(hours=2),
                [_kec(202610, "EAST JAVA", 100.0), _kec(202610, "EAST JAVA", 20.0, "K9"), _kec(202609, "EAST JAVA", 80.0)])
    latest, months, rows, avail, daily, st = dashboard._from_dump(12)
    assert latest == 202610 and months[-1] == 202610 and len(months) == 12
    by = {(r["month_id"], r["region"]): r for r in rows}
    assert by[(202610, "EAST JAVA")]["revenue"] == 120.0 and by[(202610, "EAST JAVA")]["payload"] == 10.0
    assert st["fresh"] and daily == []


def test_due_runs_once_after_five_wib(dump_root):
    wib = perf_dump.WIB
    assert perf_dump.due(datetime(2026, 11, 1, 4, 59, tzinfo=wib)) is False
    assert perf_dump.due(datetime(2026, 11, 1, 5, 1, tzinfo=wib)) is True
    _write_dump(dump_root, datetime(2026, 11, 1, 5, 2, tzinfo=wib), [_kec(202610, "EAST JAVA", 1.0)])
    assert perf_dump.due(datetime(2026, 11, 1, 9, 0, tzinfo=wib)) is False
    assert perf_dump.due(datetime(2026, 11, 2, 5, 30, tzinfo=wib)) is True


def test_kabupaten_drill_down(dump_root):
    rows = [_kec(202610, "EAST JAVA", 100.0), _kec(202609, "EAST JAVA", 80.0), _kec(202610, "WEST JAVA", 50.0, "K2")]
    rows[0]["kabupaten"] = "KAB MALANG"
    _write_dump(dump_root, datetime.now(timezone.utc), rows)
    out = dashboard._kabupaten_series("East Java", [202609, 202610])
    assert out["labels"] == ["Sep", "Okt"] and out["total"] == 2
    assert out["series"][0] == {"name": "Kab Malang", "values": [0.0, 100.0]}
