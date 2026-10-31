from __future__ import annotations

import unittest
from unittest.mock import patch

from app import reports_ftth_summary, site_fwa


def _ftth_rows(months: list[int]) -> list[dict]:
    rows: list[dict] = []
    for month in months:
        row = {
            "month_id": month,
            "snapshot": f"{month // 100:04d}-{month % 100:02d}-16",
        }
        row.update({field: 1.0 for field in reports_ftth_summary._FIELDS})
        for metric in reports_ftth_summary.FTTH_METRICS:
            if metric.weight:
                row[f"__weighted_{metric.code}"] = 1.0
        rows.append(row)
    return rows


class FtthSummaryTests(unittest.TestCase):
    @patch.object(
        reports_ftth_summary,
        "_latest_month",
        return_value=(202601, "2026-01-16"),
    )
    def test_january_uses_valid_apple_to_apple_windows(self, _latest) -> None:
        requested: list[list[int]] = []

        def fake_query(table, months, circle, filter_type, filter_value):
            requested.append(months)
            return _ftth_rows(months)

        with patch.object(reports_ftth_summary, "_query", side_effect=fake_query):
            response = reports_ftth_summary.build_ftth_summary("ALL", 202601)

        self.assertEqual(len(response["rows"]), 14)
        self.assertEqual(
            sum(len(section["rows"]) for section in response["sections"]),
            14,
        )
        self.assertTrue(
            all(1 <= month % 100 <= 12 for batch in requested for month in batch)
        )
        gross_add = next(
            row for row in response["rows"] if row["code"] == "total_ga"
        )
        self.assertEqual(gross_add["YTD"], 1.0)
        self.assertEqual(gross_add["LYTD"], 1.0)

    @patch.object(
        reports_ftth_summary,
        "_latest_month",
        return_value=(202608, "2026-08-16"),
    )
    def test_ratio_uses_weighted_scope_aggregate(self, _latest) -> None:
        def fake_query(table, months, circle, filter_type, filter_value):
            rows = _ftth_rows(months)
            for row in rows:
                row["homepass"] = 100.0
                row["__weighted_tur"] = 25.0
            return rows

        with patch.object(reports_ftth_summary, "_query", side_effect=fake_query):
            response = reports_ftth_summary.build_ftth_summary("JAVA", 202608)

        tur = next(row for row in response["rows"] if row["code"] == "tur")
        self.assertEqual(tur["MTD"], 25.0)


class SiteFwaTests(unittest.TestCase):
    def test_derive_recalculates_traffic_share_after_aggregation(self) -> None:
        raw = {field: 0.0 for field in site_fwa._PHYSICAL}
        raw.update({"fwa_traffic_5g": 25.0, "fwa_traffic_4g": 75.0})
        derived = site_fwa._derive(raw)
        self.assertIsNotNone(derived)
        self.assertEqual(derived["fwa_traffic_5g_share"], 25.0)

    def test_builder_keeps_complete_catalog_and_sorted_history(self) -> None:
        def source_row(month_id: str) -> dict:
            return {
                "month_id": month_id,
                **{field: 1.0 for field in site_fwa._PHYSICAL},
            }

        def fake_run_query(sql: str, row_limit: int = 0):
            if "MAX(month_id)" in sql:
                return {"rows": [{"month_id": "202601"}]}
            if "rham_fwa_site_wise_mtd" in sql:
                return {
                    "rows": [
                        source_row(month)
                        for month in ("202501", "202511", "202512", "202601")
                    ]
                }
            return {
                "rows": [source_row("202512"), source_row("202511")]
            }

        with patch.object(site_fwa, "run_query", side_effect=fake_run_query):
            response = site_fwa.build_site_fwa("SITE-01", months=2)

        self.assertTrue(response["available"])
        self.assertEqual(len(response["rows"]), 64)
        self.assertEqual(
            sum(len(category["rows"]) for category in response["categories"]),
            64,
        )
        self.assertEqual(
            [row["month_id"] for row in response["history"]],
            ["202511", "202512"],
        )


if __name__ == "__main__":
    unittest.main()
