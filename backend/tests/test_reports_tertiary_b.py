"""Execute the report's SQL against component values and check derived ratios."""
import sqlite3

import pytest

from app import reports_comprehensive as report


@pytest.mark.parametrize("inner,outer,total", [
    (4, 6, 10),
    (None, 6, 6),
    (4, None, 4),
    (None, None, None),
    (0, 0, 0),
])
def test_tertiary_b_uses_components_per_brand_period_and_scope(
    monkeypatch, inner, outer, total
):
    trade = next(s for s in report.SECTIONS if s["title"] == "Trade")
    codes = {"secondary_nat", "tertiary_b", "tertiary_b_inner", "tertiary_b_outer", "st_ratio"}
    monkeypatch.setattr(report, "SECTIONS", [{
        **trade, "metrics": [m for m in trade["metrics"] if m["code"] in codes],
    }])
    monkeypatch.setattr(report, "_m2m_query", lambda *args: ({}, None))
    monkeypatch.setattr(report, "_data_as_of", lambda: "2026-01-16")

    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    try:
        db.execute("CREATE TABLE territory (kec_id TEXT, circle TEXT, region TEXT)")
        db.executemany("INSERT INTO territory VALUES (?, ?, ?)", [
            ("east", "JAVA", "EAST JAVA"), ("other", "JAVA", "CENTRAL JAVA"),
        ])
        db.execute("""CREATE TABLE snapshots (
            kec_id TEXT, month_id INTEGER, brand TEXT, tertiary_b REAL,
            tertiary_b_inner REAL, tertiary_b_outer REAL, secondary REAL
        )""")
        # The raw total deliberately disagrees with the components.
        db.executemany("INSERT INTO snapshots VALUES (?, ?, ?, ?, ?, ?, ?)", [
            ("east", 202601, "IM3", 999, 20, 30, 100),
            ("east", 202601, "3ID", 999, inner, outer, 20),
            ("east", 202512, "IM3", 999, 12, 18, 60),
            ("east", 202512, "3ID", 999, 3, 7, 20),
            ("east", 202511, "IM3", 999, 10, 10, 40),
            ("east", 202511, "3ID", 999, 2, 3, 10),
            ("east", 202501, "IM3", 999, 100, 100, 400),
            ("east", 202501, "3ID", 999, 20, 30, 100),
            ("other", 202601, "IM3", 999, 5000, 5000, 20000),
        ])

        def run_sql(sql, **kwargs):
            sql = sql.replace(report._MTD, "snapshots").replace(report._TERR, "territory")
            return {"rows": [dict(row) for row in db.execute(sql)]}

        monkeypatch.setattr(report, "run_query", run_sql)
        response = report.build_comprehensive("JAVA", 202601, "region", "EAST JAVA")
    finally:
        db.close()

    metrics = {m["code"]: m for s in response["sections"] for m in s.get("metrics", [])}
    expected = {
        "ioh": {"mtd": 50 + (total or 0), "lmtd": 40, "llmtd": 25, "lytd": 250},
        "im3": {"mtd": 50, "lmtd": 30, "llmtd": 20, "lytd": 200},
        "3id": {"mtd": total, "lmtd": 10, "llmtd": 5, "lytd": 50},
    }
    for brand, periods in expected.items():
        periods["ytd"] = periods["mtd"]
        for period, value in periods.items():
            assert metrics["tertiary_b"][brand][period] == value
            secondary = metrics["secondary_nat"][brand][period]
            ratio = secondary / value if value not in (None, 0) else None
            assert metrics["st_ratio"][brand][period] == ratio
        current = periods["mtd"]
        assert metrics["tertiary_b"][brand]["var_mom"] == (
            current - periods["lmtd"] if current is not None else None
        )
