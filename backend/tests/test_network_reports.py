from __future__ import annotations

import unittest
from unittest.mock import patch

from app import reports_competitive, reports_internal


class NetworkCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = reports_internal.load_network_report_catalog()

    def test_catalog_has_locked_counts_and_structure(self) -> None:
        competitive = self.catalog["pages"]["competitive"]
        internal = self.catalog["pages"]["internal"]
        self.assertEqual(len(competitive["metrics"]), 51)
        self.assertEqual(len(competitive["sections"]), 9)
        self.assertEqual(len(internal["metrics"]), 229)
        self.assertEqual(len(internal["sections"]), 24)
        self.assertEqual(len(self.catalog["internal_domains"]), 6)

    def test_catalog_contains_corrected_registry_transforms(self) -> None:
        metrics = {
            metric["metric_id"]: metric
            for page in self.catalog["pages"].values()
            for metric in page["metrics"]
        }
        self.assertEqual(metrics["p1_s07_m02"]["transform"], "avg_mtd_cutover")
        self.assertEqual(metrics["p1_s07_m02"]["source_columns"]["mtd_from"], "2026-05")
        self.assertEqual(metrics["p2_s14_m13"]["transform"], "ratio_prev_base")
        self.assertEqual(
            metrics["p2_s14_m13"]["source_columns"]["prev_base_column"],
            "rgu90d_mtd",
        )
        self.assertTrue(all(metric.get("definition") for metric in metrics.values()))

    def test_kecamatan_capability_is_per_metric_and_provider(self) -> None:
        metrics = self.catalog["pages"]["competitive"]["metrics"]
        supported = [
            metric
            for metric in metrics
            if metric["capabilities"]["kecamatan"]["available"]
        ]
        self.assertEqual(len(supported), 25)
        ookla = [metric for metric in metrics if metric["section_order"] >= 7]
        self.assertEqual(len(ookla), 21)
        self.assertTrue(
            all(
                metric["capabilities"]["kecamatan"]["reason"]
                == "No verified Ookla kecamatan source"
                for metric in ookla
            )
        )


class NetworkReportBuilderTests(unittest.TestCase):
    def test_period_plan_keeps_missing_calendar_month_as_null_slot(self) -> None:
        periods, basis = reports_internal._period_plan(
            [{"2025-12": "2025-12-31", "2026-06": "2026-06-30", "2026-08": "2026-08-31"}],
            3,
        )
        self.assertEqual(periods, ["2026-06", "2026-07", "2026-08"])
        self.assertEqual(basis, "2025-12")

    def test_standard_query_compiles_ratio_of_sums_and_scales_value(self) -> None:
        metric = next(
            metric
            for metric in reports_internal.load_network_report_catalog()["pages"]["competitive"]["metrics"]
            if metric["metric_id"] == "p1_s01_m02"
        )
        captured: list[str] = []

        def fake_query(sql: str, row_limit: int = 100):
            captured.append(sql)
            return {
                "rows": [
                    {"period": "2026-08-01", "brand": "IOH", "p1_s01_m02": 12.5}
                ]
            }

        with patch.object(reports_internal, "run_query", side_effect=fake_query):
            values = reports_internal._standard_query(
                "rham_network_comp",
                "dt_id",
                [metric],
                ["2026-08-31"],
                "TRUE",
                with_brand=True,
                distinct_source=True,
            )

        self.assertIn("SAFE_DIVIDE", captured[0])
        self.assertIn("SELECT DISTINCT", captured[0])
        self.assertEqual(values[("p1_s01_m02", "IOH", "2026-08")], 12.5)

    def test_internal_response_preserves_all_metrics_and_empty_periods(self) -> None:
        def fake_query(sql: str, row_limit: int = 100):
            if "INFORMATION_SCHEMA.PARTITIONS" in sql:
                return {
                    "rows": [
                        {"snapshot": "2025-12-31"},
                        {"snapshot": "2026-06-30"},
                        {"snapshot": "2026-08-31"},
                    ]
                }
            return {"rows": [{"period": "2026-08-01"}]}

        with patch.object(reports_internal, "run_query", side_effect=fake_query):
            payload = reports_internal.build_internal("JAVA", period_count=3)

        self.assertEqual(payload["periods"], ["2026-06", "2026-07", "2026-08"])
        self.assertEqual(len(payload["sections"]), 24)
        metrics = [metric for section in payload["sections"] for metric in section["metrics"]]
        self.assertEqual(len(metrics), 229)
        unmapped = next(metric for metric in metrics if metric["transform"] == "unmapped")
        self.assertEqual(unmapped["availability"], "unsupported")
        self.assertIsNone(unmapped["series"]["IOH"][1]["value"])

    def test_competitive_kecamatan_keeps_unsupported_metrics_reachable(self) -> None:
        fb_snapshots = {"2026-08": "2026-08-29"}
        os_snapshots = {"2026-08": "2026-08-31"}

        def snapshots(source: str):
            return fb_snapshots if source.startswith("rham_fb") else os_snapshots

        with (
            patch.object(reports_competitive, "_snapshot_map", side_effect=snapshots),
            patch.object(reports_competitive, "_facebook_query", return_value={}),
            patch.object(reports_competitive, "_standard_query", return_value={}),
        ):
            payload = reports_competitive.build_competitive(
                "JAVA", "kecamatan", "ADIWERNA|KAB. TEGAL", period_count=1
            )

        metrics = [metric for section in payload["sections"] for metric in section["metrics"]]
        self.assertEqual(len(metrics), 51)
        ookla = next(metric for metric in metrics if metric["metric_id"] == "p1_s07_m02")
        self.assertEqual(ookla["availability"], "unsupported")
        self.assertEqual(ookla["unavailable_reason"], "No verified Ookla kecamatan source")
        self.assertIsNone(ookla["series"]["IOH"][0]["value"])


if __name__ == "__main__":
    unittest.main()

