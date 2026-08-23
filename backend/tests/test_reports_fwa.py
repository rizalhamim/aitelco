from __future__ import annotations

import unittest
from unittest.mock import patch

from app import reports_fwa


def _source_rows(months: list[int]) -> list[dict]:
    rows = []
    for month in months:
        for brand in ("IM3", "3ID"):
            row = {
                "month_id": month,
                "brand": brand,
                "snapshot": f"{month // 100:04d}-{month % 100:02d}-16",
            }
            row.update({field: 1.0 for field in reports_fwa._FIELDS})
            rows.append(row)
    return rows


class FwaReportTests(unittest.TestCase):
    def _fake_query(self, table, months, circle, filter_type, filter_value):
        return _source_rows(months)

    @patch.object(reports_fwa, "_source_state", return_value=(202601, "2026-01-16"))
    def test_mtd_response_exposes_all_metrics_and_categories(self, _state) -> None:
        with patch.object(reports_fwa, "_query_months", side_effect=self._fake_query):
            response = reports_fwa.build_fwa("ALL", 202601, basis="mtd")

        self.assertEqual(len(response["rows"]), 64)
        self.assertEqual(
            sum(len(section["metrics"]) for section in response["sections"]),
            64,
        )
        traffic_share = next(
            row for row in response["rows"] if row["code"] == "fwa_traffic_5g_share"
        )
        self.assertEqual(traffic_share["brands"]["IOH"]["MTD"], 50.0)
        self.assertEqual(response["scope"]["month_id"], 202601)

    @patch.object(reports_fwa, "_source_state", return_value=(202601, "2026-01-16"))
    def test_full_month_projects_flow_but_not_snapshot(self, _state) -> None:
        with patch.object(reports_fwa, "_query_months", side_effect=self._fake_query):
            response = reports_fwa.build_fwa("ALL", 202601, basis="monthly")

        gross_add = next(row for row in response["rows"] if row["code"] == "ga_fwa")
        rgu = next(row for row in response["rows"] if row["code"] == "fwa_rgu90")
        self.assertAlmostEqual(gross_add["brands"]["IM3"]["MTD"], 31 / 16)
        self.assertEqual(rgu["brands"]["IM3"]["MTD"], 1.0)


if __name__ == "__main__":
    unittest.main()
