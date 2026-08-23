#!/usr/bin/env python3
"""Audit java_precalc and promote reviewed tables into the runtime knowledge KB.

Discovery is report-only by default. It never promotes a table automatically.
Use ``--bootstrap-governance`` once to create explicit lifecycle decisions, then
``--promote-reviewed`` to apply only entries marked approved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app import config  # noqa: E402
from app.knowledge_graph import write_graph_atomic  # noqa: E402


TOOL_VERSION = "1.0"
REVIEW_ID = "five-agent-panel-2026-08-19"

APPROVED_NEW: dict[str, str] = {
    # 5G rollout and competitive experience
    "rham_5g_nr2600": "5g",
    "rham_fb_network_5g": "network_benchmark",
    "rham_network_comp": "network_benchmark",
    "rham_network_comp_kec": "network_benchmark",
    # Internal network and commercial performance
    "rham_network_internal": "network",
    "rham_network_internal_kec": "network",
    # FTTH observed operational summaries
    "rham_ftth_kec_wise_daily": "ftth",
    "rham_ftth_kec_wise_mtd": "ftth",
    "rham_ftth_kec_wise_mth": "ftth",
    "rham_ftth_site_wise_daily": "ftth",
    "rham_ftth_site_wise_mtd": "ftth",
    "rham_ftth_site_wise_mth": "ftth",
    # FWA observed aggregate performance
    "rham_fwa_kec_wise_daily": "fwa",
    "rham_fwa_kec_wise_mtd": "fwa",
    "rham_fwa_kec_wise_mth": "fwa",
    "rham_fwa_monthly": "fwa",
    "rham_fwa_monthly_kpi": "fwa",
    "rham_fwa_site_wise_daily": "fwa",
    "rham_fwa_site_wise_mtd": "fwa",
    "rham_fwa_site_wise_mth": "fwa",
    # Aggregate demand and digital behavior
    "rham_cohort_voucher_mobotrade": "customer_demand",
    "rham_data_rev_digicommerce_daily": "customer_demand",
    "rham_demand_inner_outer": "customer_demand",
    "rham_demand_inner_outer_mtd": "customer_demand",
    "rham_demand_inner_outer_mth": "customer_demand",
    "rham_game_daily": "customer_demand",
    "rham_game_mtd": "customer_demand",
    "rham_game_mth": "customer_demand",
    "rham_ssd_details_mtd": "customer_demand",
    "rham_ssd_details_mth": "customer_demand",
    "rham_subs_traffic_agg_geo_mtd_lmtd": "customer_demand",
    "rham_subs_traffic_agg_migration_matrix_monthly": "customer_demand",
    "rham_subs_traffic_agg_segment_mtd_lmtd": "customer_demand",
    # Outlet and distribution intelligence
    "rham_outlet_junction_java": "sales_distribution",
    "rham_outlet_population_java": "sales_distribution",
    "rham_outlet_road_java": "sales_distribution",
    "rham_outlet_spacing_java": "sales_distribution",
    "rham_outlet_transaction_java": "sales_distribution",
    "rham_outlet_wise_mtd": "sales_distribution",
    "rham_outlet_wise_mth": "sales_distribution",
    "rham_outletwise_daily_pjp": "sales_distribution",
    "rham_snd_kpi_highlevel_mtd": "sales_distribution",
    "rham_snd_kpi_highlevel_mth": "sales_distribution",
    # Aggregate acquisition intelligence
    "rham_sellin_ga_location": "acquisition",
    "rham_site_acquisition_rev": "acquisition",
}

PREVIOUSLY_REJECTED = {
    "rham_fb_ms_kabkota_v2": "Deprecated market-share source. Use rham_report_fb_ms_*.",
    "rham_fb_ms_kecamatan_v2": "Deprecated market-share source. Use rham_report_fb_ms_*.",
    "rham_site_wise_daily_raw": "Oversized raw source. Use approved daily or monthly aggregates.",
    "rham_ref_territory2": "Alternate territory reference rejected in favor of canonical references.",
    "rham_ref_territory_3id_static": "Duplicate static territory reference.",
    "rham_ref_territory_zz": "Experimental or legacy territory reference.",
    "rham_ref_super88": "Previously deferred because the semantics were not verified.",
    "rham_project_desa_java": "Previously deferred because the semantics were not verified.",
}

QUARANTINE_EXACT = {
    "rham_fwa_site_raw": "Raw FWA source superseded by governed aggregate summaries.",
    "rham_fwa_lead_scores": "Customer-level lead scoring is unavailable to general chat.",
    "rham_fwa_subscriber_base": "Customer-level FWA base is unavailable to general chat.",
    "rham_fwa_integrity_flags": "Detailed integrity records require a separate reviewed use case.",
    "rham_ga_recharge": "Contains GA subscriber identifiers. Use aggregate acquisition tables.",
    "rham_msisdn_ucg_program": "Subscriber-level program membership is unavailable to general chat.",
    "rham_subs_traffic_dim_subs_segment_monthly": "Subscriber-grain table is unavailable to general chat.",
    "rham_subs_traffic_fact_subs_mtd_lmtd": "Subscriber-grain table is unavailable to general chat.",
    "rham_subs_traffic_raw_purchase_txn": "Raw customer transaction data is unavailable to general chat.",
    "rham_subs_traffic_raw_subs_daily": "Raw customer daily data is unavailable to general chat.",
    "rham_hvc_revenue": "Very large source requires a reviewed aggregate contract before use.",
}

DOMAIN_METADATA = {
    "customer_demand": {
        "label": "Customer Demand & Digital Behavior",
        "description": (
            "Aggregate origin-destination demand, product and channel migration, "
            "gaming, SSD, voucher cohorts, digicommerce, and subscriber traffic segments."
        ),
        "agent": {
            "name": "Customer Demand Analyst",
            "persona": (
                "Analyze only aggregate customer behavior. Separate movement, purchase, "
                "traffic, revenue, cohort, and channel metrics. Never infer an individual."
            ),
            "key_facts": [
                "Use only aggregate tables in this domain. Customer or MSISDN-level sources are blocked.",
                "Demand inner/outer is an origin-to-destination flow. Keep source_kec_id and dest_kec_id distinct.",
                "Migration matrices describe movement between pack or channel buckets, not customer causality.",
                "For MTD comparisons use the aligned MTD and LMTD columns already supplied by aggregate tables.",
                "Revenue, traffic, transaction, subscriber, and quota metrics have different units and must not be mixed.",
            ],
        },
    }
}

DESCRIPTIONS = {
    "rham_5g_nr2600": "5G NR2600 rollout inventory by site, program, vendor, geography, and rollout status.",
    "rham_fb_network_5g": "Facebook-derived 5G customer and experience benchmark by date, brand, and kabkota.",
    "rham_network_comp": "Competitive 4G and 5G network experience by date, brand, and kabkota.",
    "rham_network_comp_kec": "Competitive network experience summary at kecamatan grain.",
    "rham_network_internal": "Internal commercial and network driver metrics by date and kabkota.",
    "rham_network_internal_kec": "Internal commercial and network driver metrics at kecamatan grain.",
    "rham_ftth_kec_wise_daily": "Observed FTTH daily performance at kecamatan grain.",
    "rham_ftth_kec_wise_mtd": "Observed FTTH cutoff-aligned MTD snapshot at kecamatan grain.",
    "rham_ftth_kec_wise_mth": "Observed FTTH monthly snapshot at kecamatan grain.",
    "rham_ftth_site_wise_daily": "Observed FTTH daily performance at site grain.",
    "rham_ftth_site_wise_mtd": "Observed FTTH cutoff-aligned MTD snapshot at site grain.",
    "rham_ftth_site_wise_mth": "Observed FTTH monthly snapshot at site grain.",
    "rham_fwa_kec_wise_daily": "Observed FWA daily performance at kecamatan grain.",
    "rham_fwa_kec_wise_mtd": "Observed FWA MTD performance at kecamatan grain.",
    "rham_fwa_kec_wise_mth": "Observed FWA monthly performance at kecamatan grain.",
    "rham_fwa_monthly": "Observed FWA monthly performance by operational area.",
    "rham_fwa_monthly_kpi": "FWA acquisition, retention, productivity, and quality KPIs by month and area.",
    "rham_fwa_site_wise_daily": "Observed FWA daily performance at site grain.",
    "rham_fwa_site_wise_mtd": "Observed FWA MTD performance at site grain.",
    "rham_fwa_site_wise_mth": "Observed FWA monthly performance at site grain.",
    "rham_cohort_voucher_mobotrade": "Aggregate voucher and MOBO cohort retention and revenue by activity month.",
    "rham_data_rev_digicommerce_daily": "Daily digicommerce data revenue and transaction hits by channel and outlet.",
    "rham_demand_inner_outer": "Daily aggregate origin-destination demand flow by kecamatan and category.",
    "rham_demand_inner_outer_mtd": "MTD aggregate origin-destination demand flow by kecamatan and category.",
    "rham_demand_inner_outer_mth": "Monthly aggregate origin-destination demand flow by kecamatan and category.",
    "rham_game_daily": "Daily aggregate gaming revenue and transactions by content provider and territory.",
    "rham_game_mtd": "MTD aggregate gaming revenue and transactions by content provider and territory.",
    "rham_game_mth": "Monthly aggregate gaming revenue and transactions by content provider and territory.",
    "rham_ssd_details_mtd": "MTD SSD product demand, hits, and net revenue at kecamatan grain.",
    "rham_ssd_details_mth": "Monthly SSD product demand, hits, and net revenue at kecamatan grain.",
    "rham_subs_traffic_agg_geo_mtd_lmtd": "Aggregate MTD versus LMTD subscriber traffic and revenue by serving geography segment.",
    "rham_subs_traffic_agg_migration_matrix_monthly": "Aggregate monthly migration between pack and channel buckets.",
    "rham_subs_traffic_agg_segment_mtd_lmtd": "Aggregate MTD, LMTD, and LYTD traffic and revenue by subscriber segment.",
    "rham_outlet_junction_java": "Outlet-to-road-junction proximity reference for outlet access analysis.",
    "rham_outlet_population_java": "Outlet population coverage reference.",
    "rham_outlet_road_java": "Outlet road-access classification and distance reference.",
    "rham_outlet_spacing_java": "Outlet spacing, nearest-neighbor, density, and coordinate-quality metrics.",
    "rham_outlet_transaction_java": "Aggregate outlet transaction and location attributes.",
    "rham_outlet_wise_mtd": "MTD outlet-level sales and distribution performance.",
    "rham_outlet_wise_mth": "Monthly outlet-level sales and distribution performance.",
    "rham_outletwise_daily_pjp": "Daily outlet PJP and distribution performance.",
    "rham_snd_kpi_highlevel_mtd": "MTD SND distribution KPI aggregate at kecamatan and brand grain.",
    "rham_snd_kpi_highlevel_mth": "Monthly SND distribution KPI aggregate at kecamatan and brand grain.",
    "rham_sellin_ga_location": "Aggregate sell-in to gross-add location relationship by month and territory.",
    "rham_site_acquisition_rev": "Daily site acquisition revenue and hits by product and channel.",
}

ALIASES = {
    "rham_5g_nr2600": ["nr2600", "5g rollout", "5g deployment", "5g site rollout"],
    "rham_fb_network_5g": ["facebook 5g", "5g competitor", "5g experience"],
    "rham_network_comp": ["competitive network", "competitor speed", "ioh vs tsel vs xlsmart"],
    "rham_network_internal": ["internal performance", "internal network", "network driver tree"],
    "rham_demand_inner_outer_mtd": ["inner outer", "asal tujuan", "origin destination", "demand flow"],
    "rham_demand_inner_outer_mth": ["inner outer monthly", "asal tujuan bulanan", "origin destination"],
    "rham_subs_traffic_agg_migration_matrix_monthly": ["migration matrix", "pack movement", "channel switch"],
    "rham_subs_traffic_agg_segment_mtd_lmtd": ["traffic segment", "subscriber segment", "growth contribution"],
    "rham_cohort_voucher_mobotrade": ["voucher cohort", "rebuy cohort", "mobotrade cohort"],
    "rham_ssd_details_mtd": ["ssd", "ssd product demand"],
    "rham_ssd_details_mth": ["ssd monthly", "ssd product demand"],
}


def _atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    temp.replace(path)


def _schema_hash(item: dict[str, Any]) -> str:
    fields = [
        {"name": col.get("name"), "type": col.get("type"), "mode": col.get("mode")}
        for col in item.get("columns", [])
    ]
    return hashlib.sha256(
        json.dumps(fields, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _object_class(name: str, item: dict[str, Any]) -> str:
    lower = name.lower()
    if item.get("type") == "VIEW":
        return "view"
    if "__bak" in lower or lower.endswith("_backup") or "_bak_" in lower:
        return "backup"
    if lower.endswith("_raw") or "_raw_" in lower:
        return "raw"
    if lower.endswith("_stg") or lower.endswith("_upd"):
        return "staging"
    if lower.startswith("zz_") or "rejected_records" in lower or lower.endswith("_params"):
        return "helper"
    return "aggregate"


def _decision_for(
    name: str, item: dict[str, Any], existing_tables: dict[str, str]
) -> dict[str, Any]:
    object_class = _object_class(name, item)
    if name in PREVIOUSLY_REJECTED:
        return {
            "lifecycle": "rejected",
            "policy": "hard_block",
            "domain": None,
            "reason": PREVIOUSLY_REJECTED[name],
        }
    if name in QUARANTINE_EXACT:
        return {
            "lifecycle": "quarantined",
            "policy": "hard_block",
            "domain": None,
            "reason": QUARANTINE_EXACT[name],
        }
    if name in APPROVED_NEW:
        return {
            "lifecycle": "approved",
            "policy": "runtime_allowed",
            "domain": APPROVED_NEW[name],
            "reason": "Reviewed aggregate or observed source approved by the design panel.",
        }
    if name in existing_tables:
        return {
            "lifecycle": "approved",
            "policy": "runtime_allowed",
            "domain": existing_tables[name],
            "reason": "Existing runtime KB table retained after governance audit.",
        }
    if object_class in {"backup", "raw", "staging", "helper"}:
        return {
            "lifecycle": "quarantined",
            "policy": "hard_block",
            "domain": None,
            "reason": f"Object class {object_class} is unavailable to general chat.",
        }
    if name.startswith("rham_ftth_ins_") or name.startswith("rham_pag_") or name.startswith("v_dashboard_"):
        return {
            "lifecycle": "candidate",
            "policy": "not_runtime_allowed",
            "domain": "ftth" if name.startswith("rham_ftth") else "kpi_summary",
            "reason": "Derived or recommendation output requires formula ownership and backtest review.",
        }
    if name in {"rham_fwa_area_score", "rham_fwa_outlet_score"}:
        return {
            "lifecycle": "candidate",
            "policy": "not_runtime_allowed",
            "domain": "fwa",
            "reason": "Scoring output requires formula ownership and validation before promotion.",
        }
    return {
        "lifecycle": "candidate",
        "policy": "not_runtime_allowed",
        "domain": None,
        "reason": "New object discovered. Semantic and business-value review is pending.",
    }


def _live_inventory() -> dict[str, Any]:
    from app.bigquery_tool import get_client

    client = get_client()
    dataset_ref = f"{config.BQ_PROJECT}.{config.BQ_DATASET}"
    tables = []
    for summary in client.list_tables(dataset_ref):
        table = client.get_table(summary.reference)
        tables.append({
            "name": table.table_id,
            "type": summary.table_type,
            "rows": int(table.num_rows or 0),
            "bytes": int(table.num_bytes or 0),
            "modified": table.modified.isoformat() if table.modified else None,
            "partition_field": getattr(table.time_partitioning, "field", None),
            "partition_type": str(getattr(table.time_partitioning, "type_", "")) or None,
            "clustering_fields": table.clustering_fields or [],
            "description": table.description,
            "columns": [
                {
                    "name": field.name,
                    "type": field.field_type,
                    "mode": field.mode,
                    "description": field.description,
                }
                for field in table.schema
            ],
        })
    return {"project": config.BQ_PROJECT, "dataset": config.BQ_DATASET, "tables": tables}


def load_inventory(path: Path | None) -> dict[str, Any]:
    return json.loads(path.read_text()) if path else _live_inventory()


def _existing_table_domains(kb: dict[str, Any]) -> dict[str, str]:
    return {
        name: domain_key
        for domain_key, domain in kb.get("domains", {}).items()
        for name in domain.get("tables", {})
    }


def build_governance(inventory: dict[str, Any], kb: dict[str, Any]) -> dict[str, Any]:
    existing = _existing_table_domains(kb)
    records = {}
    for item in sorted(inventory.get("tables", []), key=lambda row: row["name"]):
        name = item["name"]
        decision = _decision_for(name, item, existing)
        records[name] = {
            "lifecycle": decision["lifecycle"],
            "object_class": _object_class(name, item),
            "policy": decision["policy"],
            "domain": decision["domain"],
            "reason": decision["reason"],
            "review_id": REVIEW_ID,
            "schema_hash": _schema_hash(item),
            "decision_history": [{
                "review_id": REVIEW_ID,
                "decision": decision["lifecycle"],
                "reason": decision["reason"],
                "reviewed_at": "2026-08-19",
            }],
            "replacement_table": (
                "rham_report_fb_ms_kabkota" if name == "rham_fb_ms_kabkota_v2"
                else "rham_report_fb_ms_kecamatan" if name == "rham_fb_ms_kecamatan_v2"
                else None
            ),
        }
    return {
        "schema_version": 1,
        "tool_version": TOOL_VERSION,
        "project": inventory.get("project"),
        "dataset": inventory.get("dataset"),
        "review_id": REVIEW_ID,
        "reversal_policy": (
            "A rejected or quarantined decision can change only through a new reviewed "
            "history entry with reviewer, evidence, and explicit override=true."
        ),
        "objects": records,
    }


def merge_catalog(
    inventory: dict[str, Any], governance: dict[str, Any]
) -> dict[str, Any]:
    governed = governance.get("objects", {})
    tables = []
    for item in sorted(inventory.get("tables", []), key=lambda row: row["name"]):
        decision = governed.get(item["name"])
        if decision is None:
            decision = {
                "lifecycle": "candidate",
                "object_class": _object_class(item["name"], item),
                "policy": "not_runtime_allowed",
                "domain": None,
                "reason": "Discovered after the last review. Promotion is pending.",
                "review_id": None,
                "schema_hash": _schema_hash(item),
            }
        tables.append({**item, "governance": decision})
    live_names = {item["name"] for item in inventory.get("tables", [])}
    missing = sorted(set(governed) - live_names)
    return {
        "schema_version": 1,
        "tool_version": TOOL_VERSION,
        "project": inventory.get("project"),
        "dataset": inventory.get("dataset"),
        "audited_at": datetime.now(timezone.utc).isoformat(),
        "tables": tables,
        "missing_governed_objects": missing,
        "summary": {
            "live_objects": len(tables),
            "approved": sum(t["governance"]["lifecycle"] == "approved" for t in tables),
            "candidate": sum(t["governance"]["lifecycle"] == "candidate" for t in tables),
            "quarantined": sum(t["governance"]["lifecycle"] == "quarantined" for t in tables),
            "rejected": sum(t["governance"]["lifecycle"] == "rejected" for t in tables),
        },
    }


def _normalize_type(value: str) -> str:
    return {
        "INTEGER": "INT64",
        "FLOAT": "FLOAT64",
        "BOOLEAN": "BOOL",
    }.get(value, value)


def _column_description(name: str) -> str:
    lower = name.lower()
    exact = {
        "dt_id": "Tanggal data.",
        "month_id": "Periode bulan.",
        "mth_dt": "Tanggal awal bulan dan kolom partisi bila ditandai.",
        "site_id": "ID site.",
        "kec_id": "ID unik kecamatan.",
        "kabkot": "Nama kabupaten atau kota.",
        "kabkot_nm": "Nama kabupaten atau kota.",
        "brand": "Brand atau operator pada baris.",
        "revenue": "Revenue dalam rupiah.",
        "hit": "Jumlah transaksi.",
    }
    if lower in exact:
        return exact[lower]
    if "revenue" in lower or lower.startswith("rev_"):
        return "Metrik revenue. Jaga unit rupiah dan grain table."
    if "traffic" in lower:
        return "Metrik traffic. Gunakan unit yang dinyatakan oleh nama kolom."
    if "ratio" in lower or "rate" in lower or "pct" in lower or "share" in lower:
        return "Rasio atau persentase. Jangan dijumlahkan antar baris."
    if "sample" in lower:
        return "Jumlah sampel untuk pembobotan atau validasi coverage."
    if lower.startswith("sum_") or lower.startswith("total_"):
        return "Metrik agregat pada grain table."
    return ""


def _infer_grain(name: str, columns: list[dict[str, Any]]) -> str:
    names = {col.get("name", "").lower() for col in columns}
    if {"source_kec_id", "dest_kec_id"}.issubset(names):
        return "origin_destination_kecamatan"
    for column, grain in (
        ("outlet_id", "outlet"),
        ("site_id", "site"),
        ("kec_id", "kecamatan"),
        ("kecamatan", "kecamatan"),
        ("kabkot_nm", "kabkota"),
        ("kabkot", "kabkota"),
        ("branch", "branch"),
        ("area_id", "area"),
    ):
        if column in names:
            return grain
    if "segment" in name:
        return "subscriber_segment"
    if "migration_matrix" in name:
        return "pack_channel_migration"
    return "declared_dimensions"


def _infer_period(name: str, columns: list[dict[str, Any]]) -> str:
    if "_mtd" in name:
        return "mtd_cutoff_aligned"
    if name.endswith("_mth") or "monthly" in name:
        return "monthly"
    if "daily" in name or any(col.get("name") == "dt_id" for col in columns):
        return "daily"
    if "snapshot" in name:
        return "snapshot"
    return "latest_available"


def _infer_metrics(name: str, columns: list[dict[str, Any]]) -> list[str]:
    text = name + " " + " ".join(col.get("name", "") for col in columns)
    mapping = {
        "5g rollout": ["nr2600", "wbs_status", "rollout"],
        "5g experience": ["5g", "dl_speed", "latency"],
        "availability": ["avail", "downtime"],
        "acquisition": ["gross_add", "total_ga", "acquisition", "sellin"],
        "churn": ["churn"],
        "competitive network": ["network_comp", "fb_network"],
        "demand flow": ["source_kec_id", "dest_kec_id", "inner_outer"],
        "ftth": ["ftth", "homepass", "tur"],
        "fwa": ["fwa"],
        "gaming": ["game", "cp_name"],
        "outlet distribution": ["outlet", "uro", "sso", "snd"],
        "product demand": ["product", "ssd", "voucher"],
        "retention": ["retention", "surv_"],
        "revenue": ["revenue", "rev_"],
        "subscriber segment": ["subs_traffic", "segment_"],
        "traffic": ["traffic", "gb"],
    }
    lower = text.lower()
    metrics = [label for label, needles in mapping.items() if any(n in lower for n in needles)]
    return metrics or ["domain metrics"]


def _cost_tier(item: dict[str, Any]) -> str:
    size = int(item.get("bytes") or 0)
    if size >= 50 * 1024**3:
        return "very_high"
    if size >= 5 * 1024**3:
        return "high"
    if size >= 500 * 1024**2:
        return "medium"
    return "low"


def _contract(name: str, item: dict[str, Any]) -> dict[str, Any]:
    columns = item.get("columns", [])
    source_kind = "observed"
    if "forecast" in name:
        source_kind = "modelled"
    elif any(token in name for token in ("opensignal", "fb_ms", "fb_network", "network_comp")):
        source_kind = "proxy"
    ratios = [
        col.get("name") for col in columns
        if any(token in col.get("name", "").lower() for token in ("ratio", "rate", "pct", "share", "tur"))
    ]
    partition = item.get("partition_field")
    constraints = []
    if partition:
        constraints.append(f"Always filter partition column {partition} to a bounded period.")
    if source_kind == "proxy":
        constraints.append("Label this source as proxy and use sample columns for weighting when available.")
    if ratios:
        constraints.append("Do not sum ratio columns. Recompute from components when available.")
    priority = "high" if any(token in name for token in (
        "_mtd", "_mth", "monthly", "internal", "network_comp", "fb_network_5g"
    )) else "standard"
    return {
        "status": "approved",
        "source_kind": source_kind,
        "grain": _infer_grain(name, columns),
        "period_semantics": _infer_period(name, columns),
        "aggregation_rule": "sum_components_then_recompute_ratio" if ratios else "sum_additive_metrics",
        "territory_vocabulary": "ftth_native" if "ftth" in name else "ioh_java",
        "priority": priority,
        "cost_tier": _cost_tier(item),
        "metric_families": _infer_metrics(name, columns),
        "use_constraints": constraints,
        "warning_columns": [
            col.get("name") for col in columns
            if "warning" in col.get("name", "").lower()
        ],
        "sensitive_dimensions": [],
        "aliases": ALIASES.get(name, []),
        "schema_hash": _schema_hash(item),
        "object_type": item.get("type", "TABLE"),
    }


def _kb_table(item: dict[str, Any]) -> dict[str, Any]:
    partition = item.get("partition_field")
    table = {
        "rows": int(item.get("rows") or 0),
        "bytes": int(item.get("bytes") or 0),
        "description": item.get("description") or DESCRIPTIONS.get(item["name"], ""),
        "columns": [],
    }
    for column in item.get("columns", []):
        description = column.get("description") or _column_description(column["name"])
        output = {
            "name": column["name"],
            "type": _normalize_type(column["type"]),
            "nullable": column.get("mode", "NULLABLE") != "REQUIRED",
            "partition": column["name"] == partition,
        }
        if description:
            output["desc"] = description
        table["columns"].append(output)
    table.update(_contract(item["name"], item))
    return table


def _catalog_items(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {item["name"]: item for item in catalog.get("tables", [])}


def _clean_rejected_references(value: Any) -> Any:
    """Remove contradictory positive guidance for hard-blocked sources."""
    if isinstance(value, dict):
        return {
            key: _clean_rejected_references(item)
            for key, item in value.items()
            if key not in PREVIOUSLY_REJECTED
        }
    if isinstance(value, list):
        return [_clean_rejected_references(item) for item in value]
    if not isinstance(value, str):
        return value
    text = re.sub(
        r"or use rham_fb_ms_kecamatan_v2 \([^)]*\)\.",
        "Use the approved branch-level rham_report_fb_ms_branch_im3 or rham_report_fb_ms_branch_3id source for branch analysis.",
        value,
    )
    text = text.replace(
        "rham_fb_ms_kecamatan_v2, rham_fb_ms_kabkota_v2, ",
        "",
    )
    text = text.replace(
        "(e.g. rham_report_fb_ms_circle, rham_fb_ms_kecamatan_v2, rham_site_data_rev_product_mth)",
        "(e.g. rham_report_fb_ms_circle, rham_site_data_rev_product_mth)",
    )
    text = text.replace("competitive/reporting domain", "competitive domain")
    text = text.replace("rham_5g_territory_dly", "rham_5g_territory_daily")
    return text


def promote(kb: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    items = _catalog_items(catalog)
    decisions = {
        name: item.get("governance", {}) for name, item in items.items()
    }

    kb["domains"] = _clean_rejected_references(kb.get("domains", {}))

    for domain_key, metadata in DOMAIN_METADATA.items():
        kb["domains"].setdefault(domain_key, {**metadata, "tables": {}, "table_count": 0})

    # Remove sources that are now explicitly rejected or quarantined.
    for domain in kb.get("domains", {}).values():
        for name in list(domain.get("tables", {})):
            decision = decisions.get(name)
            if decision and decision.get("lifecycle") != "approved":
                del domain["tables"][name]

    for name, decision in decisions.items():
        if decision.get("lifecycle") != "approved":
            continue
        domain_key = decision.get("domain")
        item = items[name]
        if not domain_key or domain_key not in kb["domains"]:
            raise ValueError(f"Approved table {name} has no valid domain")
        # Ensure one owner if a reviewed decision moves a table.
        for other_key, other_domain in kb["domains"].items():
            if other_key != domain_key:
                other_domain.get("tables", {}).pop(name, None)
        current = kb["domains"][domain_key].setdefault("tables", {}).get(name)
        refreshed = _kb_table(item)
        if current:
            # Preserve curated descriptions, while refreshing physical metadata and contracts.
            for column in refreshed["columns"]:
                existing_column = next(
                    (old for old in current.get("columns", []) if old.get("name") == column["name"]),
                    None,
                )
                if existing_column and existing_column.get("desc"):
                    column["desc"] = existing_column["desc"]
            if current.get("description"):
                refreshed["description"] = current["description"]
        kb["domains"][domain_key]["tables"][name] = refreshed

    for domain in kb["domains"].values():
        domain["table_count"] = len(domain.get("tables", {}))

    facts = _clean_rejected_references(kb.get("data_facts", {}))
    facts["banned_tables"] = {
        "competitive_fb_ms": {
            "tables": ["rham_fb_ms_kabkota_v2", "rham_fb_ms_kecamatan_v2"],
            "reason": "Deprecated and hard-blocked. Use rham_report_fb_ms_* matched to territory grain.",
            "alternative_domain": "competitive",
            "replacement_table": "rham_report_fb_ms_kabkota or rham_report_fb_ms_kecamatan",
        },
        "governance_rejections": {
            "tables": sorted(PREVIOUSLY_REJECTED),
            "reason": "Rejected decisions persist until an explicit reviewed governance version reverses them.",
        },
    }
    facts["knowledge_governance"] = {
        "authority": "knowledge_base.json plus table_governance.json",
        "discovery": "Offline report-only metadata audit. New objects enter candidate state.",
        "promotion": "Only reviewed approved objects may become SQL candidates.",
        "rejection_precedence": "Rejected and quarantined objects are blocked before BigQuery dry run.",
    }
    facts["runtime_graph"] = {
        "authority": "Compiled only from approved runtime KB content.",
        "developer_graph_boundary": "FastAPI never reads graphify-out.",
        "retrieval": "Normally 4 tables, bounded expansion to 6 for complex domains.",
        "learning": "Successful approved queries create candidate term-to-table evidence. Three unique successes activate only an existing edge.",
        "prohibited_learning": "User text cannot create facts, tables, columns, joins, or formulas.",
    }
    facts["customer_demand_tables"] = {
        "flow": [
            "rham_demand_inner_outer",
            "rham_demand_inner_outer_mtd",
            "rham_demand_inner_outer_mth",
        ],
        "digital": ["rham_data_rev_digicommerce_daily", "rham_game_mtd", "rham_game_mth"],
        "product": ["rham_ssd_details_mtd", "rham_ssd_details_mth", "rham_cohort_voucher_mobotrade"],
        "subscriber_aggregates": [
            "rham_subs_traffic_agg_geo_mtd_lmtd",
            "rham_subs_traffic_agg_migration_matrix_monthly",
            "rham_subs_traffic_agg_segment_mtd_lmtd",
        ],
        "privacy": "Only aggregate sources are approved. Subscriber-grain and raw transaction sources are blocked.",
    }
    kb["data_facts"] = facts
    kb["knowledge_version"] = "2026-08-19.1"
    kb["updated_at"] = datetime.now(timezone.utc).isoformat()
    kb["governance_review_id"] = REVIEW_ID
    return kb


def validate_state(kb: dict[str, Any], governance: dict[str, Any]) -> list[str]:
    errors = []
    objects = governance.get("objects", {})
    valid_states = {"approved", "candidate", "quarantined", "rejected", "superseded"}
    for name, decision in objects.items():
        if decision.get("lifecycle") not in valid_states:
            errors.append(f"{name}: invalid lifecycle {decision.get('lifecycle')}")
        if decision.get("lifecycle") in {"rejected", "quarantined"} and decision.get("policy") != "hard_block":
            errors.append(f"{name}: blocked lifecycle must use hard_block policy")
        history = decision.get("decision_history") or []
        if not history or history[-1].get("decision") != decision.get("lifecycle"):
            errors.append(f"{name}: decision history does not match current lifecycle")
        previously_blocked = any(
            entry.get("decision") in {"rejected", "quarantined"}
            for entry in history[:-1]
        )
        if previously_blocked and decision.get("lifecycle") == "approved":
            last = history[-1]
            if not (last.get("override") is True and last.get("reviewer") and last.get("evidence")):
                errors.append(f"{name}: blocked lifecycle reversal lacks reviewed override evidence")
    kb_tables = _existing_table_domains(kb)
    for name in PREVIOUSLY_REJECTED:
        if name in kb_tables:
            errors.append(f"Rejected table remains in KB: {name}")
    for name, domain in kb_tables.items():
        decision = objects.get(name)
        if decision and decision.get("lifecycle") != "approved":
            errors.append(f"KB table is not approved: {name}")
        if decision and decision.get("domain") != domain:
            errors.append(f"Domain mismatch for {name}: {domain} vs {decision.get('domain')}")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, help="Read a saved inventory instead of BigQuery")
    parser.add_argument("--bootstrap-governance", action="store_true")
    parser.add_argument("--rebuild-governance", action="store_true")
    parser.add_argument("--write-catalog", action="store_true")
    parser.add_argument("--promote-reviewed", action="store_true")
    parser.add_argument("--compile-graph", action="store_true")
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    kb = json.loads(config.KB_PATH.read_text())
    inventory = load_inventory(args.inventory)

    if args.bootstrap_governance or args.rebuild_governance:
        if config.TABLE_GOVERNANCE_PATH.exists() and not args.rebuild_governance:
            raise SystemExit("Governance exists. Use --rebuild-governance for an explicit reviewed replacement.")
        governance = build_governance(inventory, kb)
        _atomic_json(config.TABLE_GOVERNANCE_PATH, governance)
    else:
        governance = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())

    catalog = merge_catalog(inventory, governance)
    if args.write_catalog or args.promote_reviewed:
        _atomic_json(config.TABLE_CATALOG_PATH, catalog)

    if args.promote_reviewed:
        backup = config.KB_PATH.with_name(
            config.KB_PATH.name + ".bak" + datetime.now().strftime("%Y%m%d%H%M%S")
        )
        shutil.copy2(config.KB_PATH, backup)
        promoted = promote(kb, catalog)
        errors = validate_state(promoted, governance)
        if errors:
            raise SystemExit("Promotion validation failed:\n- " + "\n- ".join(errors))
        _atomic_json(config.KB_PATH, promoted)
        kb = promoted

    if args.compile_graph or args.promote_reviewed:
        write_graph_atomic(kb)

    errors = validate_state(kb, governance)
    summary = catalog["summary"]
    print(json.dumps({
        "summary": summary,
        "kb_tables": len(_existing_table_domains(kb)),
        "governance_objects": len(governance.get("objects", {})),
        "errors": errors,
        "catalog_written": bool(args.write_catalog or args.promote_reviewed),
        "promoted": bool(args.promote_reviewed),
    }, indent=2))
    if args.check and errors:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
