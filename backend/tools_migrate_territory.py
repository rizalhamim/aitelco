"""Build an auditable review for the October territory/source migration.

Uses the live saved catalog; never changes warehouse data or rebuilds history.
Run prepare, apply the generated review, promote reviewed schemas, then facts.
"""
import argparse
import copy
import json
from pathlib import Path

from app import config
from tools_kb_edit import save
from tools_knowledge_refresh import _atomic_json

REVIEW = Path(__file__).parent / "governance/review_2026_10_04_territory.json"
REPLACEMENTS = {
    **{f"rham_site_data_rev_{family}_{period}": f"rham_kec_data_rev_{family}_{period}"
       for family in ("channel", "price_slab", "product") for period in ("daily", "mtd", "mth")},
    "rham_outlet_ga_quality": "rham_outlet_ga",
    "rham_outlet_ga_quality_dtu": "rham_outlet_ga_dtu",
    "rham_outlet_ga_quality_mtd": "rham_outlet_ga_mtd",
    "rham_outlet_ga_quality_mth": "rham_outlet_ga_mth",
    "rham_site_fwa_daily": "rham_fwa_site_wise_daily",
    "rham_ga_new_imei_mtd": "rham_mkt_highlevel_mtd",
    "rham_ga_new_imei_mth": "rham_mkt_highlevel_mth",
    "rham_site_traffic_usage_mtd": "rham_site_wise_mtd",
    "rham_site_traffic_usage_mth": "rham_site_wise_monthly",
}
TERRITORY_FACT = (
    "Operational hierarchy from 2026-10: Circle > Region > Area > District. "
    "The former Area is abolished and its area/area_im3 column is NULL. "
    "New Area uses rham_ref_territory.branch_im3 or zz_territory_kecamatan.branch; "
    "new District uses micro_cluster_im3 or im3_mc. Alias branch AS area and "
    "micro_cluster_im3/im3_mc AS district in result columns. Legacy branch means "
    "current Area; MC/microcluster means District. Kab/Kota and Kecamatan are "
    "administrative geographic views. Never filter the old area column. "
    "FTTH retains its native sales_region/province/city/kecamatan vocabulary. "
    "Routing and rephrasing must preserve the requested aggregation grain. Per District means "
    "GROUP BY the reference MC field AS district, not one row per Kecamatan. Per Area means GROUP BY the reference branch field AS area."
)


def prepare():
    catalog = json.loads(config.TABLE_CATALOG_PATH.read_text())
    governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
    kb = json.loads(config.KB_PATH.read_text())
    live = {t["name"]: t for t in catalog["tables"]}
    decisions = {}
    for name, record in governed.items():
        if record.get("review_id") == "territory-migration-2026-10-04":
            history = record["decision_history"][-1]
            decisions[name] = {k: record.get(k) for k in ("lifecycle", "domain", "replacement_table", "reason")}
            decisions[name]["evidence"] = history.get("evidence", "Live catalog 2026-10-04.")
    for name, record in governed.items():
        if record["lifecycle"] != "approved":
            continue
        replacement = REPLACEMENTS.get(name)
        if name not in live:
            decisions[name] = {
                "lifecycle": "superseded" if replacement else "rejected",
                "domain": None, "replacement_table": replacement,
                "reason": "Source no longer exists after the warehouse migration. "
                          + (f"Use {replacement} at its declared grain." if replacement else "No verified replacement is available."),
                "evidence": "BigQuery list_tables and live catalog 2026-10-04: source absent.",
            }
        else:
            decisions[name] = {
                "lifecycle": "approved", "domain": record["domain"],
                "reason": "Refresh reviewed live schema and partition metadata after territory migration; preserve existing domain ownership.",
                "evidence": f"Live schema: {len(live[name]['columns'])} columns; partition={live[name].get('partition_field')}; rows={live[name].get('rows')}.",
            }
    existing = {n: (d, t) for d, domain in kb["domains"].items() for n, t in domain.get("tables", {}).items()}
    for old, new in REPLACEMENTS.items():
        if new not in live or new in decisions:
            continue
        if old not in existing:
            continue
        domain, table = existing[old]
        decisions[new] = {
            "lifecycle": "approved", "domain": domain,
            "reason": f"Verified successor of {old}. " + ("Kecamatan grain, no site_id; never allocate its revenue to a site." if "kec_data_rev" in new else "Preserve aggregate acquisition metrics and declared grain."),
            "evidence": f"Live schema and bounded profiling 2026-10-04; partition={live[new].get('partition_field')}; columns=" + ",".join(c["name"] for c in live[new]["columns"]),
        }
        # Preserve reviewed business metadata, while physical grain and schema
        # are refreshed by the normal promotion tool.
        copied = copy.deepcopy(table)
        copied["grain"] = "date_x_kecamatan_x_brand_x_product_dimensions" if "kec_data_rev" in new else "month_x_brand_x_outlet"
        copied["description"] = decisions[new]["reason"]
        copied["use_constraints"] = [
            "Filter the actual partition column with literal dates. LIMIT does not reduce scanned bytes.",
            "Use only the columns in this schema. NULL is unavailable, never zero.",
        ] + (["Kecamatan aggregate, no site_id. Join territory using kec_id; never infer site revenue."] if "kec_data_rev" in new else ["m1s/m2s/m3s are counts; survival = SUM(m1s)/SUM(rgu_ga). Validate outlet coordinates before mapping."])
        kb["domains"][domain]["tables"][new] = copied
    for name, item in live.items():
        if name in governed or name in decisions:
            continue
        backup = any(s in name.lower() for s in ("_bak", "_candidate", "_stg", "_backup"))
        decisions[name] = {
            "lifecycle": "quarantined" if backup else "candidate", "domain": None,
            "reason": "Backup/staging object excluded from runtime." if backup else "Discovered during migration; awaits a separate semantic review.",
            "evidence": "BigQuery live catalog 2026-10-04; no automatic promotion of unknown sources.",
        }
    for name, record in governed.items():
        replacement = record.get("replacement_table")
        if record["lifecycle"] == "superseded" and replacement in REPLACEMENTS:
            decisions[name] = {"lifecycle": "superseded", "domain": None,
                "replacement_table": REPLACEMENTS[replacement],
                "reason": "Follow the replacement chain after the October source retirement.",
                "evidence": f"{replacement} is absent; current successor is {REPLACEMENTS[replacement]}."}
    _atomic_json(REVIEW, {"review_id": "territory-migration-2026-10-04", "reviewed_at": "2026-10-04",
        "reviewer": "Business Planning Circle Java", "scope": "Current approved schema refresh, retired missing sources, reviewed successors and discovery quarantine.",
        "decisions": decisions})
    print("KB backup:", save(kb))
    print("Review:", REVIEW, "decisions:", len(decisions))


def facts():
    kb = json.loads(config.KB_PATH.read_text())
    def replace(value):
        if isinstance(value, dict):
            return {REPLACEMENTS.get(k, k): replace(v) for k, v in value.items()}
        if isinstance(value, list):
            return [replace(v) for v in value]
        if isinstance(value, str):
            for old, new in REPLACEMENTS.items():
                value = value.replace(old, new)
            return value.replace("\u2014", ";")
        return value
    kb = replace(kb)
    kb["data_facts"]["territory_hierarchy"] = TERRITORY_FACT
    kb["data_facts"]["geography"]["grain_hierarchy"] = "circle > region > area (physical branch) > district (physical MC); administrative kabkota > kecamatan > desa; infrastructure site_id"
    kb["data_facts"]["table_grains"]["monthly_tables"] = "rham_site_wise_monthly, rham_mkt_highlevel_mth, rham_kec_data_rev_*_mth; use month_id and the retrieved physical partition field. Forecast sources are retired, no verified successor."
    kb["data_facts"]["table_routing_constraints"]["site_tables_restriction"] = (
        "Use site_wise tables for explicitly per-site infrastructure/performance. General headline KPIs use market highlevel at Kecamatan x brand grain. "
        "Channel/product/price-slab breakdown uses rham_kec_data_rev_* at Kecamatan grain, never site_id; this family is valid for general commercial breakdowns."
    )
    kb["data_facts"]["source_grain_migration"] = (
        "Data revenue channel/price_slab/product uses rham_kec_data_rev_* at Kecamatan grain. "
        "These schemas have no site_id and no service_type; use kec_id and only retrieved columns. "
        "Site infrastructure and site_wise performance remain site grain. "
        "GA new/old IMEI metrics now use gaq_* columns of rham_mkt_highlevel_mtd/mth at Kecamatan grain. "
        "For per-site new-IMEI acquisition, rham_site_ga_quality_mtd retains ga_new_imei/ga_old_imei/ga_imei_unknown; use its own schema. "
        "Legacy FWA acquisition split columns ga_fwa_4g/5g/all and channel-specific ga_fwa_* are absent from current monthly sources; retain N/A, not zero. "
        "Legacy site_traffic_usage quota/utilization fields and forecast tables are unavailable; "
        "do not fabricate replacements or forecasts. Outlet GA uses rham_outlet_ga_* aggregate sources."
    )
    kb["data_facts"]["query_cost_policy"] = (
        "Every fact query needs a bounded period and only needed columns. Prefer literal partition "
        "filters: mth_dt >= DATE 'YYYY-MM-01' AND mth_dt < next-month date, together with month_id. "
        "Use exact dt_id bounds for daily data. Never wrap partition fields in CAST/FORMAT_DATE; "
        "LIMIT only bounds results, not scan cost. Latest periods can be resolved separately. "
        "Query execution estimates bytes and rejects over-budget scans before execution. "
        "Preserve the requested period, MTD cutoff symmetry and full-month-plus-MTD YTD rules."
    )
    for key, domain in kb["domains"].items():
        agent = domain.get("agent")
        if isinstance(agent, dict):
            agent.setdefault("key_facts", [])
            if TERRITORY_FACT not in agent["key_facts"]:
                agent["key_facts"].append(TERRITORY_FACT)
        if key in ("product", "revenue"):
            domain["description"] = domain["description"].replace("site-level", "kecamatan-level").replace("per site", "per kecamatan")
        for table in domain.get("tables", {}).values():
            names = {c["name"] for c in table["columns"]}
            if not {"site_id", "service_type"}.intersection(names) and "kec_id" in names:
                table.setdefault("use_constraints", []).append("This is Kecamatan grain; no site_id or service_type unless explicitly listed in the schema.")
    for name, table in kb["domains"]["sales_distribution"]["tables"].items():
        if name.startswith("rham_outlet_ga_") or name == "rham_outlet_ga":
            table.setdefault("warning_columns", []).extend(["outlet_latitude", "outlet_longitude"])
            table.setdefault("use_constraints", []).append("Outlet coordinates are corrupt in some rows (latitude -619 observed). Use validated outlet reference coordinates, never these for proximity.")
    for name in ("rham_mkt_highlevel_mtd", "rham_mkt_highlevel_mth"):
        table = kb["domains"]["kpi_summary"]["tables"][name]
        table["description"] = "Kecamatan KPI snapshot including prepaid revenue, subscriber base, gross add and gaq_* new/old IMEI device mix."
        table["aliases"] = list(dict.fromkeys(table.get("aliases", []) + ["imei baru", "device baru", "gross add device baru", "ga imei"]))
        rule = "One dt_id_snapshot per month_id, plus gaq_dt_id acquisition cutoff. Never sum repeated cutoffs or double count IMEI subsets. GA new devices = SUM(gaq_ga_new_imei), total = SUM(gaq_rgu_ga)."
        table["use_constraints"] = list(dict.fromkeys([*table.get("use_constraints", []), rule]))
    for name in ("rham_site_wise_mtd", "rham_site_wise_monthly"):
        table = kb["domains"]["site_performance"]["tables"][name]
        table["description"] = "Observed site performance including revenue and usg_data_gb; legacy quota utilization detail is unavailable."
        table["aliases"] = list(dict.fromkeys(table.get("aliases", []) + ["site traffic", "traffic usage", "pemakaian data site"]))
    # These superseded site-only dimensions no longer exist in the new family.
    product = kb["domains"]["product"]["agent"]
    product["key_facts"] = [f.replace("service_type -> ", "").replace("site-grain", "kecamatan-grain") for f in product["key_facts"]]
    for domain in kb["domains"].values():
        for table in domain.get("tables", {}).values():
            for field in ("use_constraints", "warning_columns"):
                if field in table:
                    table[field] = list(dict.fromkeys(table[field]))
    print("KB backup:", save(kb))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=("prepare", "facts"))
    action = p.parse_args().action
    prepare() if action == "prepare" else facts()
