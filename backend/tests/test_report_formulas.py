from __future__ import annotations

import unittest

from app.report_formulas import (
    comparison_values,
    merge_bags,
    metric_value,
    shift_month_id,
)
from app.report_metric_catalog import FWA_METRICS, FTTH_METRICS, PREPAID_METRICS


class ReportCatalogTests(unittest.TestCase):
    def test_verified_catalog_sizes(self) -> None:
        self.assertEqual(len(PREPAID_METRICS), 17)
        self.assertEqual(len(FWA_METRICS), 64)
        self.assertEqual(len(FTTH_METRICS), 14)

    def test_metric_codes_are_unique(self) -> None:
        for metrics in (PREPAID_METRICS, FWA_METRICS, FTTH_METRICS):
            self.assertEqual(len({metric.code for metric in metrics}), len(metrics))


class ReportFormulaTests(unittest.TestCase):
    def test_shift_month_crosses_year_boundary(self) -> None:
        self.assertEqual(shift_month_id(202601, -1), 202512)
        self.assertEqual(shift_month_id(202601, -2), 202511)
        self.assertEqual(shift_month_id(202512, 1), 202601)

    def test_traffic_share_uses_4g_plus_5g_denominator(self) -> None:
        metric = next(
            item for item in FWA_METRICS if item.code == "fwa_traffic_5g_share"
        )
        value = metric_value(
            metric,
            {"fwa_traffic_5g": 25.0, "fwa_traffic_4g": 75.0},
        )
        self.assertEqual(value, 25.0)

    def test_ratio_is_derived_after_bags_are_summed(self) -> None:
        metric = next(
            item for item in FWA_METRICS if item.code == "fwa_traffic_5g_share"
        )
        bag = merge_bags(
            [
                {"fwa_traffic_5g": 90.0, "fwa_traffic_4g": 10.0},
                {"fwa_traffic_5g": 10.0, "fwa_traffic_4g": 90.0},
            ]
        )
        self.assertEqual(metric_value(metric, bag), 50.0)

    def test_null_is_not_coerced_to_zero(self) -> None:
        metric = next(item for item in FWA_METRICS if item.code == "ga_fwa")
        self.assertIsNone(metric_value(metric, {}))
        self.assertEqual(metric_value(metric, {"ga_fwa": 0}), 0.0)

    def test_growth_uses_absolute_previous_denominator(self) -> None:
        metric = next(item for item in FWA_METRICS if item.code == "ga_fwa")
        values = comparison_values(
            metric,
            {"ga_fwa": -120},
            {"ga_fwa": -100},
            {"ga_fwa": -80},
            {"ga_fwa": -100},
            {"ga_fwa": -80},
        )
        self.assertEqual(values["VAR_PCT"], 20.0)
        self.assertEqual(values["YOY_PCT"], 20.0)


if __name__ == "__main__":
    unittest.main()
