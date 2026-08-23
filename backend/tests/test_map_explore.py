from __future__ import annotations

import unittest
from unittest.mock import patch

from app import routes_reports


class MapExploreTests(unittest.TestCase):
    @patch.object(routes_reports, "_latest_month", return_value=202601)
    @patch.object(routes_reports, "_level_summary")
    def test_inverse_metric_ranking_and_color_contract(
        self, summary, _latest
    ) -> None:
        summary.return_value = {
            "rows": [
                {
                    "name": "A",
                    "mtd_ioh": 90.0,
                    "lmtd_ioh": 100.0,
                    "abs_growth_ioh": -10.0,
                    "growth_pct": -10.0,
                },
                {
                    "name": "B",
                    "mtd_ioh": 110.0,
                    "lmtd_ioh": 100.0,
                    "abs_growth_ioh": 10.0,
                    "growth_pct": 10.0,
                },
                {
                    "name": "C",
                    "mtd_ioh": 45.0,
                    "lmtd_ioh": 50.0,
                    "abs_growth_ioh": -5.0,
                    "growth_pct": -10.0,
                },
            ],
            "bytes_processed": 123,
        }

        response = routes_reports.map_explore(
            metric="gross_churn_90d",
            circle="JAVA",
            level="kecamatan",
            brand="ioh",
            value_mode="growth",
            filter_type="all",
            filter_value="",
            month_id=None,
        )

        rows = {row["territory_name"]: row for row in response["rows"]}
        self.assertTrue(rows["A"]["favorable"])
        self.assertFalse(rows["B"]["favorable"])
        self.assertEqual(rows["A"]["rank"], 1)
        self.assertEqual(rows["C"]["rank"], 1)
        self.assertEqual(rows["B"]["rank"], 3)
        self.assertEqual(response["map_spec"]["coloring"], "favorable_sign")
        self.assertTrue(response["meta"]["complete_grain"])
        self.assertEqual(response["scope"]["comparison_month_id"], 202512)


if __name__ == "__main__":
    unittest.main()
