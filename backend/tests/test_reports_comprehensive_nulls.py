from __future__ import annotations

import unittest
from unittest.mock import patch

from app import reports_comprehensive


class ComprehensiveNullTests(unittest.TestCase):
    def test_sql_does_not_coerce_missing_snapshot_to_zero(self) -> None:
        metric = next(
            item for item in reports_comprehensive._base_metrics()
            if item["code"] == "total_site"
        )
        selection = reports_comprehensive._brand_cols(metric)
        self.assertNotIn("COALESCE", selection)

    @patch.object(reports_comprehensive, "_data_as_of", return_value="2026-01-16")
    @patch.object(reports_comprehensive, "_m2m_query", return_value=({}, None))
    @patch.object(reports_comprehensive, "_latest_month", return_value=202601)
    def test_missing_period_stays_null_while_real_zero_is_preserved(
        self, _latest, _m2m, _as_of
    ) -> None:
        def fake_month(table, metrics, circle, month_id, fc, extra_select=""):
            if month_id == 202601:
                return {
                    "rows": [{
                        "total_site_ioh": None,
                        "total_site_im3": None,
                        "total_site_3id": None,
                        "new_site_ioh": 0,
                        "new_site_im3": 0,
                        "new_site_3id": 0,
                    }]
                }
            if month_id == 202512:
                return {
                    "rows": [{
                        "total_site_ioh": 10,
                        "total_site_im3": 10,
                        "total_site_3id": 10,
                        "new_site_ioh": 1,
                        "new_site_im3": 1,
                        "new_site_3id": 1,
                    }]
                }
            return {"rows": [{}]}

        with patch.object(
            reports_comprehensive, "_wide_one_month", side_effect=fake_month
        ):
            response = reports_comprehensive.build_comprehensive("ALL", 202601)

        metrics = {
            metric["code"]: metric
            for section in response["sections"]
            for metric in section.get("metrics", [])
        }
        site = metrics["total_site"]["ioh"]
        new_site = metrics["new_site"]["ioh"]
        self.assertIsNone(site["mtd"])
        self.assertIsNone(site["var_mom"])
        self.assertIsNone(site["growth_mom_pct"])
        self.assertEqual(new_site["mtd"], 0.0)
        self.assertEqual(new_site["var_mom"], -1.0)


if __name__ == "__main__":
    unittest.main()
