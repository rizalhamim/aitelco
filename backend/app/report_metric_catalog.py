"""Versioned metric metadata for additive Performance Outlook reports.

This module is intentionally self-contained. The runtime does not import the
Technocom application or any files outside this repository.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable


CATALOG_SCHEMA_VERSION = 1


@dataclass(frozen=True)
class MetricSpec:
    """A calculation and presentation contract for one report metric."""

    code: str
    label: str
    category: str
    unit: str
    kind: str = "flow"
    format: str = "num0"
    source: str | None = None
    scale: float = 1.0
    numerator: str | None = None
    denominator: str | None = None
    denominator_terms: tuple[str, ...] = ()
    weight: str | None = None
    temporal: str = "sum"
    source_grain: str = "kecamatan"
    network: bool = False

    def __post_init__(self) -> None:
        if self.kind not in {"flow", "snapshot", "ratio"}:
            raise ValueError(f"unsupported metric kind: {self.kind}")
        if self.temporal not in {"sum", "last"}:
            raise ValueError(f"unsupported temporal rule: {self.temporal}")
        weighted_mode = bool(self.source and self.weight)
        raw_mode = bool(self.source and not self.weight)
        ratio_mode = bool(self.numerator and (self.denominator or self.denominator_terms))
        modes = sum((weighted_mode, raw_mode, ratio_mode))
        if modes != 1:
            raise ValueError(f"metric {self.code} must declare one calculation mode")

    @property
    def raw_fields(self) -> tuple[str, ...]:
        fields: list[str] = []
        for field in (
            self.source,
            self.weight,
            self.numerator,
            self.denominator,
            *self.denominator_terms,
        ):
            if field and field not in fields:
                fields.append(field)
        return tuple(fields)

    def as_dict(self) -> dict[str, Any]:
        return {
            "code": self.code,
            "label": self.label,
            "category": self.category,
            "unit": self.unit,
            "kind": self.kind,
            "format": self.format,
            "source": self.source,
            "scale": self.scale,
            "numerator": self.numerator,
            "denominator": self.denominator,
            "denominator_terms": list(self.denominator_terms),
            "weight": self.weight,
            "temporal": self.temporal,
            "source_grain": self.source_grain,
            "network": self.network,
        }


def raw(
    code: str,
    label: str,
    category: str,
    unit: str,
    *,
    source: str | None = None,
    kind: str = "flow",
    format: str = "num0",
    scale: float = 1.0,
    temporal: str | None = None,
    network: bool = False,
) -> MetricSpec:
    return MetricSpec(
        code=code,
        label=label,
        category=category,
        unit=unit,
        kind=kind,
        format=format,
        source=source or code,
        scale=scale,
        temporal=temporal or ("last" if kind == "snapshot" else "sum"),
        network=network,
    )


def ratio(
    code: str,
    label: str,
    category: str,
    unit: str,
    numerator: str,
    denominator: str | None = None,
    *,
    denominator_terms: tuple[str, ...] = (),
    format: str = "pct1",
    scale: float = 100.0,
    temporal: str = "last",
) -> MetricSpec:
    return MetricSpec(
        code=code,
        label=label,
        category=category,
        unit=unit,
        kind="ratio",
        format=format,
        numerator=numerator,
        denominator=denominator,
        denominator_terms=denominator_terms,
        scale=scale,
        temporal=temporal,
    )


def weighted(
    code: str,
    label: str,
    category: str,
    unit: str,
    weight: str,
    *,
    format: str = "num1",
    scale: float = 1.0,
) -> MetricSpec:
    return MetricSpec(
        code=code,
        label=label,
        category=category,
        unit=unit,
        kind="ratio",
        format=format,
        source=code,
        weight=weight,
        scale=scale,
        temporal="last",
    )


FWA_METRICS = (
    raw("ga_fwa", "GA FWA", "Acquisition", "Subs"),
    raw("ga_fwa_4g", "GA FWA 4G", "Acquisition", "Subs"),
    raw("ga_fwa_5g", "GA FWA 5G", "Acquisition", "Subs"),
    raw("ga_fwa_mpx_sdp", "GA MPX / SDP", "Acquisition", "Subs"),
    raw("ga_fwa_partner", "GA Partner", "Acquisition", "Subs"),
    raw("ga_fwa_digital", "GA Digital", "Acquisition", "Subs"),
    raw("ga_fwa_retail", "GA Retail", "Acquisition", "Subs"),
    raw("ga_fwa_others", "GA Others", "Acquisition", "Subs"),
    raw("ga_fwa_all", "GA FWA All", "Acquisition", "Subs"),
    raw("fwa_rgu90", "RGU 90D", "Subscriber & Movement", "Subs", kind="snapshot"),
    raw("fwa_rgu90_closing", "Closing RGU 90D", "Subscriber & Movement", "Subs", kind="snapshot"),
    raw("fwa_cb90", "Churn Back 90D", "Subscriber & Movement", "Subs"),
    raw("fwa_gc90", "Gross Churn 90D", "Subscriber & Movement", "Subs"),
    raw("fwa_net_churn90", "Net Churn 90D", "Subscriber & Movement", "Subs"),
    raw("fwa_net_add_acq", "Net Add Acquisition", "Subscriber & Movement", "Subs"),
    raw("fwa_net_add_subs", "Net Add Subscribers", "Subscriber & Movement", "Subs"),
    raw("fwa_rev_regular", "Revenue Regular", "Revenue: Legacy", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_fwa_pack", "Revenue FWA Pack", "Revenue: Legacy", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_sim", "Revenue SIM", "Revenue: Legacy", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_total", "Revenue Total", "Revenue: Legacy", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_sim_v2", "Revenue SIM V2", "Revenue: Current Definition", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_non_data_v2", "Revenue Non-Data V2", "Revenue: Current Definition", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_fwa_pack_v2", "Revenue FWA Pack V2", "Revenue: Current Definition", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_fwa_data_pack_v2", "Revenue FWA Data Pack V2", "Revenue: Current Definition", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_regular_pack_v2", "Revenue Regular Pack V2", "Revenue: Current Definition", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rev_total_v2", "Revenue Total V2", "Revenue: Current Definition", "B Rp", format="num2", scale=1e-9),
    raw("fwa_rgu90_5g", "RGU 90D 5G", "4G / 5G Mix", "Subs", kind="snapshot"),
    raw("fwa_rgu90_4g", "RGU 90D 4G", "4G / 5G Mix", "Subs", kind="snapshot"),
    raw("fwa_traffic_5g", "Traffic 5G", "4G / 5G Mix", "GB", format="num1"),
    raw("fwa_traffic_4g", "Traffic 4G", "4G / 5G Mix", "GB", format="num1"),
    raw("fwa_traffic_5g_dly", "Daily Traffic 5G", "4G / 5G Mix", "GB", kind="snapshot", format="num1"),
    raw("fwa_traffic_4g_dly", "Daily Traffic 4G", "4G / 5G Mix", "GB", kind="snapshot", format="num1"),
    raw("fwa_qsc_100", "QSC >=100 MB", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_qsc_500", "QSC >=500 MB", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_qsc_1gb", "QSC >=1 GB", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_qsc_2gb", "QSC >=2 GB", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_qsc_5gb", "QSC >=5 GB", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_qsc_10gb", "QSC >=10 GB", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_subs_usg_10gb_30d", "Subs Usage >=10 GB 30D", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_subs_usg_20gb_30d", "Subs Usage >=20 GB 30D", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_subs_usg_50gb_30d", "Subs Usage >=50 GB 30D", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_data_uu_5g", "Data UU 5G", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_data_uu_4g", "Data UU 4G", "Usage Quality", "Subs", kind="snapshot"),
    raw("fwa_vlr", "VLR", "VLR & Tenure", "Subs", kind="snapshot"),
    raw("fwa_vlr_no_fu", "VLR No FU", "VLR & Tenure", "Subs", kind="snapshot"),
    raw("fwa_vlr_less_90d", "VLR <90D", "VLR & Tenure", "Subs", kind="snapshot"),
    raw("fwa_vlr_91d_180d", "VLR 91-180D", "VLR & Tenure", "Subs", kind="snapshot"),
    raw("fwa_vlr_above_180d", "VLR >180D", "VLR & Tenure", "Subs", kind="snapshot"),
    raw("fwa_all_packsubs", "All Pack Subscribers", "Pack Subscribers", "Subs", kind="snapshot"),
    raw("fwa_fwa_packsubs", "FWA Pack Subscribers", "Pack Subscribers", "Subs", kind="snapshot"),
    raw("fwa_regular_packsubs", "Regular Pack Subscribers", "Pack Subscribers", "Subs", kind="snapshot"),
    raw("fwa_sim_packsubs", "SIM Pack Subscribers", "Pack Subscribers", "Subs", kind="snapshot"),
    raw("fwa_hit_sim_v2", "SIM Pack Hits V2", "Pack Hits", "Hits"),
    raw("fwa_hit_non_data", "Non-Data Hits", "Pack Hits", "Hits"),
    raw("fwa_hit_fwa_pack", "FWA Pack Hits", "Pack Hits", "Hits"),
    raw("fwa_hit_dwa_data_pack", "FWA Data Pack Hits", "Pack Hits", "Hits"),
    raw("fwa_hit_regular_pack", "Regular Pack Hits", "Pack Hits", "Hits"),
    raw("fwa_hit_total", "Total Pack Hits", "Pack Hits", "Hits"),
    ratio("fwa_arpu_total", "ARPU FWA V2", "Derived Ratios", "Rp", "fwa_rev_total_v2", "fwa_rgu90", format="num0", scale=1.0),
    ratio("fwa_rgu_5g_share", "5G RGU Share", "Derived Ratios", "%", "fwa_rgu90_5g", "fwa_rgu90"),
    ratio(
        "fwa_traffic_5g_share",
        "5G Traffic Share",
        "Derived Ratios",
        "%",
        "fwa_traffic_5g",
        denominator_terms=("fwa_traffic_5g", "fwa_traffic_4g"),
        temporal="sum",
    ),
    ratio("fwa_vlr_no_fu_rate", "VLR No FU Rate", "Derived Ratios", "%", "fwa_vlr_no_fu", "fwa_vlr"),
    ratio("fwa_gross_churn_rate", "Gross Churn Rate", "Derived Ratios", "%", "fwa_gc90", "fwa_rgu90"),
    ratio("fwa_pack_penetration", "Pack Subscriber Penetration", "Derived Ratios", "%", "fwa_all_packsubs", "fwa_rgu90"),
)


PREPAID_METRICS = (
    raw("revenue_prepaid", "Revenue Prepaid", "Revenue", "B Rp", source="rev_prepaid", format="num2", scale=1e-9),
    raw("revenue_vsd", "Revenue VSD", "Revenue", "B Rp", source="rev_vsd", format="num2", scale=1e-9),
    raw("revenue_data_trade", "Revenue Data Trade", "Revenue", "B Rp", source="rev_data_mobo_trade", format="num2", scale=1e-9),
    raw("revenue_data_digital", "Revenue Data Digital", "Revenue", "B Rp", source="rev_data_mobo_non_trade", format="num2", scale=1e-9),
    raw("revenue_data_organic", "Revenue Data Organic", "Revenue", "B Rp", source="rev_data_organic", format="num2", scale=1e-9),
    raw("gross_add", "Gross Add", "Acquisition", "Subs", source="ga_total"),
    raw("vlr_daily", "VLR Daily", "Subscriber", "Subs", source="avg_vlr_daily", kind="snapshot"),
    raw("data_uu_daily", "Data Users Daily", "Subscriber", "Subs", kind="snapshot"),
    raw("rgu_30d", "RGU 30D", "Subscriber", "Subs", kind="snapshot"),
    raw("rgu_90d", "RGU 90D", "Subscriber", "Subs", kind="snapshot"),
    raw("traffic_gb", "Data Traffic", "Usage", "GB", source="usg_data_gb", format="num1"),
    raw("net_add_90d", "Net Add 90D", "Subscriber", "Subs"),
    raw("net_add_30d", "Net Add 30D", "Subscriber", "Subs"),
    raw("total_site", "Total Site", "Network", "Sites", kind="snapshot", network=True),
    raw("subs_hvc", "Subscriber HVC", "HVC", "Subs", kind="snapshot"),
    raw("hvc_revenue_total", "Revenue HVC Total", "HVC", "B Rp", source="hvc_rev_total", format="num2", scale=1e-9),
    ratio("arpu_90d", "ARPU 90D", "Revenue", "Rp", "rev_prepaid", "rgu_90d", format="num0", scale=1.0),
)


FTTH_METRICS = (
    raw("n_site", "Total Sites", "Footprint", "Sites", kind="snapshot"),
    raw("homepass", "Homepass", "Footprint", "Homes", kind="snapshot"),
    weighted("tur", "Take-Up Rate", "Footprint", "%", "homepass", format="pct1", scale=100.0),
    raw("subs_eom_pre", "Subscribers Opening", "Subscriber Base", "Subs", kind="snapshot"),
    raw("subs_tday", "Subscribers Today", "Subscriber Base", "Subs", kind="snapshot"),
    raw("total_ga", "Gross Add", "Acquisition", "Subs"),
    raw("acq_revenue", "Acquisition Revenue", "Acquisition", "B Rp", format="num2", scale=1e-9),
    weighted("acq_arpu", "Acquisition ARPU", "Acquisition", "Rp", "total_ga", format="num0"),
    raw("total_churn", "Total Churn", "Churn", "Subs"),
    raw("total_rejoin", "Total Rejoin", "Churn", "Subs"),
    raw("nett_churn", "Net Churn", "Churn", "Subs"),
    weighted("churn_rate", "Churn Rate", "Churn", "%", "subs_eom_pre", format="pct1", scale=100.0),
    raw("revenue", "Revenue", "Revenue & ARPU", "B Rp", format="num2", scale=1e-9),
    weighted("arpu", "ARPU", "Revenue & ARPU", "Rp", "subs_tday", format="num0"),
)


REPORT_CATALOGS = {
    "prepaid": PREPAID_METRICS,
    "fwa": FWA_METRICS,
    "ftth": FTTH_METRICS,
}


def metric_fields(metrics: Iterable[MetricSpec]) -> tuple[str, ...]:
    fields: list[str] = []
    for metric in metrics:
        for field in metric.raw_fields:
            if field not in fields:
                fields.append(field)
    return tuple(fields)


def categories(metrics: Iterable[MetricSpec]) -> tuple[str, ...]:
    return tuple(dict.fromkeys(metric.category for metric in metrics))


def catalog_payload(report: str) -> dict[str, Any]:
    metrics = REPORT_CATALOGS[report]
    return {
        "schema_version": CATALOG_SCHEMA_VERSION,
        "report": report,
        "categories": list(categories(metrics)),
        "metrics": [metric.as_dict() for metric in metrics],
    }


assert len(FWA_METRICS) == 64
assert len(PREPAID_METRICS) == 17
assert len(FTTH_METRICS) == 14
assert all(len({metric.code for metric in metrics}) == len(metrics) for metrics in REPORT_CATALOGS.values())
