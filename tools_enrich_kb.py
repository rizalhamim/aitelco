#!/usr/bin/env python3
"""Merge schemas from /tmp/unmapped_schemas.json into knowledge_base.json.

Strategy:
1. Build a column-description dictionary from existing KB (column name → most
   common description across tables).
2. For each unmapped table, slot it into a domain (see TABLE_TO_DOMAIN below)
   and write a tableblock with: rows, description (table-level, hand-curated),
   columns (reuse desc from dict where available; else short stub from name).
3. Skip tables marked SKIP (deprecated, oversized raw, or zero rows).
4. If a new domain is needed ("forecast"), inject it.

This script is idempotent: re-running overwrites the same entries.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

KB_PATH = Path("/home/ubuntu/telco-ai/backend/data/knowledge_base.json")
SCHEMAS_PATH = Path("/tmp/unmapped_schemas.json")

# Table → (domain_key, table_description, skip_reason)
# Domain mapping per plan. Tables we deliberately leave OUT have skip_reason set.
TABLE_TO_DOMAIN = {
    # KPI Summary (highest impact — confirmed missing by tests)
    "rham_kpi_highlevel_dly": ("kpi_summary",
        "KPI high-level harian (kecamatan x brand). Source untuk overview revenue/RGU/churn/gross-add per kecamatan per hari. 36 kolom, 12M rows. Pakai untuk pertanyaan top-line KPI di grain harian.", None),
    "rham_kpi_highlevel_mtd": ("kpi_summary",
        "KPI high-level MTD (kecamatan x brand) — month-to-date accumulator. 129 kolom mencakup semua metrik headline (revenue VSD, RGU 30/60/90d, gross add, churn, voice/data/sms, ARPU). Pakai untuk pertanyaan 'bulan ini' apple-to-apple dengan _mth bulan lalu.", None),
    "rham_kpi_highlevel_mth": ("kpi_summary",
        "KPI high-level bulanan (kecamatan x brand). 133 kolom; mirror dari _mtd tapi full month closed. Pakai untuk perbandingan MoM/YoY periode penuh. Untuk MTD vs MTD apple-to-apple WAJIB gunakan _mtd bukan _mth.", None),

    # Desa (ward) performance
    "rham_desa_perf_history": ("kpi_summary",
        "Performance desa (ward) histori — 136 kolom termasuk revenue, RGU, gross/churn per desa per periode.", None),
    "rham_desa_perf_monthly": ("kpi_summary",
        "Performance desa bulanan. Pakai untuk roll-up bulanan per desa.", None),
    "rham_desa_perf_mtd": ("kpi_summary",
        "Performance desa MTD (month-to-date). Pakai untuk 'bulan berjalan' grain desa.", None),

    # Forecast (new domain)
    "rham_forecast_daily_branch_output": ("forecast",
        "Forecast revenue harian per branch (v1). Output prediksi model untuk revenue per hari per branch.", None),
    "rham_forecast_daily_branch_output_v3": ("forecast",
        "Forecast revenue harian per branch (v3, latest model). Gunakan ini untuk forecast branch terbaru — 11 kolom inti.", None),
    "rham_forecast_daily_branch_source": ("forecast",
        "Input/source data yang dipakai model forecast harian branch — actual history + features (30 kolom).", None),
    "rham_forecast_daily_kabkota_output": ("forecast",
        "Forecast revenue harian per kabupaten/kota (v1).", None),
    "rham_forecast_daily_kabkota_output_v3": ("forecast",
        "Forecast revenue harian per kabupaten/kota (v3 latest). Gunakan untuk kabkota-level forecast terbaru.", None),
    "rham_forecast_daily_kabkota_source": ("forecast",
        "Source/input data forecast kabkota (actual + features).", None),
    "rham_forecast_daily_mc_output": ("forecast",
        "Forecast revenue harian per micro-cluster (v1).", None),
    "rham_forecast_daily_mc_output_v3": ("forecast",
        "Forecast revenue harian per micro-cluster (v3 latest). Pakai untuk forecast level MC terbaru.", None),
    "rham_forecast_daily_mc_source": ("forecast",
        "Source/input data forecast micro-cluster.", None),
    "rham_forecast_daily_rev_mc_input": ("forecast",
        "Input revenue micro-cluster untuk pipeline forecast (raw actual sebelum agregasi).", None),
    "rham_forecast_daily_rev_mc_output": ("forecast",
        "Output revenue micro-cluster pipeline forecast (post-processed).", None),
    "rham_forecast_monthly_branch_output_v3": ("forecast",
        "Forecast revenue bulanan per branch (v3 latest, 10 kolom).", None),
    "rham_forecast_monthly_kabkota_output_v3": ("forecast",
        "Forecast revenue bulanan per kabupaten/kota (v3 latest).", None),
    "rham_forecast_monthly_mc_output_v3": ("forecast",
        "Forecast revenue bulanan per micro-cluster (v3 latest).", None),

    # FWA additions
    "rham_fwa_site_raw": ("fwa",
        "Raw site-level FWA data (5 kolom inti). Drill-down sumber dari aggregator FWA lain.", None),
    "rham_master_tracker_fwa": ("fwa",
        "Master tracker site FWA — status, lokasi, dan metadata 176K site FWA. Pakai untuk pertanyaan status/inventaris FWA.", None),

    # Site performance addition
    "rham_site_wise_addr_java_perf_yoy": ("site_performance",
        "Site performance YoY (year-over-year) per alamat site. 175 kolom — banyak metrik historis. Gunakan untuk pertanyaan YoY growth/decline per site.", None),

    # Facebook market share — only the age one (v2 kabkota/kecamatan deprecated)
    "rham_fb_ms_age": ("competitive",
        "Market share Facebook by age group (33 kolom). Pakai untuk pertanyaan market share per segmen usia.", None),

    # Territory reference additions
    "rham_ref_territory": ("territory_reference",
        "Reference territory utama — 28 kolom mapping desa→kecamatan→kabkota→branch→region→circle. Source kanonik untuk hierarki territory.", None),
    "rham_ref_site_desa": ("territory_reference",
        "Mapping site→desa (5 kolom). Pakai untuk drill site ke desa.", None),
    "rham_zz_ref_holiday": ("territory_reference",
        "Kalender hari libur (338 rows, 2 kolom). Pakai untuk filter hari kerja vs libur.", None),

    # ---- SKIP (low priority / deprecated / oversized) ----
    "rham_fb_ms_kabkota_v2": (None, None, "deprecated (per SQL_SYS line 323)"),
    "rham_fb_ms_kecamatan_v2": (None, None, "deprecated"),
    "rham_site_wise_daily_raw": (None, None, "raw 482M rows — too large for ad-hoc agent queries; agent should use aggregated tables"),
    "rham_ref_territory2": (None, None, "alternate territory ref; primary rham_ref_territory covers it"),
    "rham_ref_territory_3id_static": (None, None, "static 3ID-specific snapshot; covered by main territory ref"),
    "rham_ref_territory_zz": (None, None, "experimental/legacy territory ref"),
    "rham_ref_super88": (None, None, "small reference (514 rows) — domain unclear, defer"),
    "rham_project_desa_java": (None, None, "project-specific snapshot (1.3K rows) — domain unclear, defer"),
}

# Heuristic descriptions for common column patterns (extend as we discover gaps)
COLUMN_PATTERNS = [
    (re.compile(r"^dt_id$", re.I), "Tanggal data (harian, partition column)."),
    (re.compile(r"^month_id$", re.I), "Periode bulan dalam format YYYYMM (e.g. 202606)."),
    (re.compile(r"^brand$", re.I), "Brand IOH: 'IM3' atau '3ID' (Tri). IOH = IM3 + 3ID."),
    (re.compile(r"^circle(_nm)?$", re.I), "Nama circle (JAVA, JAKARTA RAYA, dll)."),
    (re.compile(r"^region(_nm)?$", re.I), "Nama region IM3 (e.g. 'central java', 'east java', 'bali nusra')."),
    (re.compile(r"^area(_nm)?$", re.I), "Nama area."),
    (re.compile(r"^branch(_nm)?$", re.I), "Nama branch."),
    (re.compile(r"^kabkota(_nm)?$", re.I), "Nama kabupaten/kota."),
    (re.compile(r"^kabkota_id$", re.I), "ID kabupaten/kota (numeric/string code)."),
    (re.compile(r"^kecamatan(_nm)?$", re.I), "Nama kecamatan."),
    (re.compile(r"^kec_id$", re.I), "ID kecamatan. Normalisasi via UPPER+TRIM saat join (codes vary by source)."),
    (re.compile(r"^desa(_nm)?$", re.I), "Nama desa/kelurahan."),
    (re.compile(r"^province(_nm)?$", re.I), "Nama provinsi."),
    (re.compile(r"^site_id$", re.I), "ID site (cell tower / node)."),
    (re.compile(r"^site_nm$", re.I), "Nama/label site."),
    (re.compile(r"^cluster(_nm)?$", re.I), "Nama cluster."),
    (re.compile(r"^microcluster(_nm)?$", re.I), "Nama micro-cluster."),
    (re.compile(r"^mc(_nm)?$", re.I), "Micro-cluster identifier."),
    (re.compile(r"^revenue", re.I), "Revenue (Rp)."),
    (re.compile(r"^total_rev", re.I), "Total revenue (Rp)."),
    (re.compile(r"^arpu", re.I), "ARPU — Average Revenue Per User (Rp)."),
    (re.compile(r"^rgu", re.I), "RGU — Revenue-Generating Unit (active subscriber count)."),
    (re.compile(r"^ga(_|_total|$)", re.I), "Gross Add — new subscriber acquisition."),
    (re.compile(r"^churn", re.I), "Churn / lost subscribers."),
    (re.compile(r"^na_", re.I), "Net Add — net subscriber change (gross add − churn)."),
    (re.compile(r"^net_add", re.I), "Net Add subscribers."),
    (re.compile(r"^soga", re.I), "Share Of Gross Add — % gross add captured vs total market."),
    (re.compile(r"^ms_", re.I), "Market Share metric."),
    (re.compile(r"^market_share", re.I), "Market share (%)."),
    (re.compile(r"^operator(_nm)?$", re.I), "Nama operator (IOH, Telkomsel, XL, SmartFren, dll)."),
    (re.compile(r"^age_group$", re.I), "Kelompok usia (e.g. '18-24', '25-34')."),
    (re.compile(r"^channel(_nm)?$", re.I), "Channel akuisisi atau channel revenue."),
    (re.compile(r"^channel_detail$", re.I), "Channel detail (sub-channel breakdown)."),
    (re.compile(r"^price_slab$", re.I), "Price slab — pengelompokan harga produk."),
    (re.compile(r"^traffic_5g", re.I), "Traffic 5G."),
    (re.compile(r"^device_5g", re.I), "Device 5G count."),
    (re.compile(r"^availability", re.I), "Availability (%)."),
    (re.compile(r"^download_speed", re.I), "Download speed (Mbps)."),
    (re.compile(r"^upload_speed", re.I), "Upload speed (Mbps)."),
    (re.compile(r"^latency", re.I), "Latency (ms)."),
    (re.compile(r"^forecast", re.I), "Hasil prediksi model forecast."),
    (re.compile(r"^actual_", re.I), "Nilai aktual (vs forecast)."),
    (re.compile(r"^year$|^yr$", re.I), "Tahun."),
    (re.compile(r"^load_dt", re.I), "Tanggal load/ETL data."),
    (re.compile(r"^sales_region", re.I), "Sales region (FTTH-style territory: e.g. '04. Central Java')."),
    (re.compile(r"^homepass$", re.I), "Homepass — jumlah rumah ter-cover infrastruktur FTTH."),
    (re.compile(r"^so_", re.I), "Service Order (FTTH funnel stage)."),
    (re.compile(r"^sa_", re.I), "Service Active (FTTH funnel stage)."),
    (re.compile(r"^pa_", re.I), "Permanent Active / billing (FTTH funnel stage)."),
    (re.compile(r"^holiday", re.I), "Tanggal/keterangan hari libur."),
]


def build_existing_desc_dict(kb):
    """Scan KB; for each column name, pick the most common existing description."""
    bag = {}
    for dom in kb["domains"].values():
        for tname, tdata in dom.get("tables", {}).items():
            for col in tdata.get("columns", []):
                desc = (col.get("desc") or "").strip()
                if not desc:
                    continue
                bag.setdefault(col["name"], Counter())[desc] += 1
    # collapse to most common
    return {name: cnt.most_common(1)[0][0] for name, cnt in bag.items()}


def describe(col_name: str, existing_dict: dict) -> str:
    # 1. Exact column name in existing KB
    if col_name in existing_dict:
        return existing_dict[col_name]
    # 2. Pattern match
    for rx, desc in COLUMN_PATTERNS:
        if rx.match(col_name):
            return desc
    # 3. Stub
    return ""


def main():
    kb = json.loads(KB_PATH.read_text())
    schemas = json.loads(SCHEMAS_PATH.read_text())["tables"]

    existing_desc = build_existing_desc_dict(kb)
    print(f"Existing column-desc dict: {len(existing_desc)} unique column names", file=sys.stderr)

    # Ensure new "forecast" domain exists
    if "forecast" not in kb["domains"]:
        kb["domains"]["forecast"] = {
            "label": "Forecast (Revenue Prediction)",
            "description": (
                "Forecast revenue (prediksi) di grain branch / kabupaten / micro-cluster. "
                "Tabel _v3 adalah model terbaru — preferensi v3 untuk semua pertanyaan forecast. "
                "Tabel _source berisi actual history + features input model; _output berisi hasil prediksi."
            ),
            "tables": {},
            "table_count": 0,
            "agent": "forecast_agent",
        }

    added = 0
    skipped = []
    not_in_bq = []

    for tname, (domain, table_desc, skip_reason) in TABLE_TO_DOMAIN.items():
        if skip_reason:
            skipped.append((tname, skip_reason))
            continue
        if tname not in schemas:
            not_in_bq.append(tname)
            continue
        sch = schemas[tname]
        cols_out = []
        for c in sch["columns"]:
            cols_out.append({
                "name": c["name"],
                "type": c["type"],
                "nullable": c["nullable"],
                "partition": c["partition"],
                "desc": c["desc"] or describe(c["name"], existing_desc),
            })
        kb["domains"][domain]["tables"][tname] = {
            "rows": sch["rows"],
            "description": table_desc,
            "columns": cols_out,
        }
        added += 1

    # Update table_count on touched domains
    for dom in kb["domains"].values():
        dom["table_count"] = len(dom.get("tables", {}))

    # Pretty-print to stable order
    KB_PATH.write_text(json.dumps(kb, indent=2, ensure_ascii=False))
    print(f"\nAdded {added} tables to KB.")
    print(f"Skipped {len(skipped)}:")
    for t, r in skipped:
        print(f"  {t}: {r}")
    if not_in_bq:
        print(f"Listed in TABLE_TO_DOMAIN but not in BQ: {not_in_bq}")

    # Per-domain summary
    print("\nKB after enrichment:")
    for dom_key in sorted(kb["domains"].keys()):
        d = kb["domains"][dom_key]
        print(f"  {dom_key:<22} {d['table_count']:>3} tables")


if __name__ == "__main__":
    main()
