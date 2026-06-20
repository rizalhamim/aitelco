#!/usr/bin/env python3
"""Batch test runner for telco-ai agent — sends questions via streaming API,
collects results, and writes a CSV report."""

import json
import time
import sys
import csv
import requests
import uuid
from pathlib import Path

# Force unbuffered output
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

API = "http://localhost:8000/api/chat/stream"
TIMEOUT = 180  # 3 min per question
RESULTS_DIR = Path("/home/ubuntu/telco-ai/test_results")
RESULTS_DIR.mkdir(exist_ok=True)

# ── 200 test questions across 13 domains ──
QUESTIONS = [
    # ═══ SITE PERFORMANCE (20 questions) ═══
    {"q": "Top 10 site dengan revenue tertinggi 30 hari terakhir", "domain": "site_performance", "id": 1},
    {"q": "Berapa total revenue per region 1 bulan terakhir?", "domain": "site_performance", "id": 2},
    {"q": "Site mana yang mengalami penurunan revenue terbesar bulan ini vs bulan lalu?", "domain": "site_performance", "id": 3},
    {"q": "Rata-rata ARPU per site di East Java bulan terakhir", "domain": "site_performance", "id": 4},
    {"q": "Top 5 kecamatan dengan revenue data tertinggi 30 hari terakhir", "domain": "site_performance", "id": 5},
    {"q": "Berapa total subscriber aktif per branch di Central Java?", "domain": "site_performance", "id": 6},
    {"q": "Trend revenue harian top 5 site selama 7 hari terakhir", "domain": "site_performance", "id": 7},
    {"q": "Site dengan RGU 30d tertinggi di Bali Nusra", "domain": "site_performance", "id": 8},
    {"q": "Bandingkan revenue voice vs data per region bulan terakhir", "domain": "site_performance", "id": 9},
    {"q": "Berapa jumlah site yang revenue-nya turun >20% MoM?", "domain": "site_performance", "id": 10},
    {"q": "Total gross add per site di Surabaya 30 hari terakhir", "domain": "site_performance", "id": 11},
    {"q": "Top 10 site dengan churn tertinggi bulan ini", "domain": "site_performance", "id": 12},
    {"q": "Revenue per price slab di Central Java bulan terakhir", "domain": "site_performance", "id": 13},
    {"q": "Rata-rata usage data per site di East Java MTD", "domain": "site_performance", "id": 14},
    {"q": "Berapa total revenue channel digital vs physical per region?", "domain": "site_performance", "id": 15},
    {"q": "Site dengan pertumbuhan revenue tertinggi 3 bulan terakhir", "domain": "site_performance", "id": 16},
    {"q": "Distribusi revenue per price slab secara nasional", "domain": "site_performance", "id": 17},
    {"q": "Top 20 site dengan subscriber terbanyak di Java", "domain": "site_performance", "id": 18},
    {"q": "Perbandingan revenue MTD vs bulan lalu full month per region", "domain": "site_performance", "id": 19},
    {"q": "Site yang memiliki ARPU di atas 50000 di Central Java", "domain": "site_performance", "id": 20},

    # ═══ NETWORK QUALITY (18 questions) ═══
    {"q": "Berapa total traffic 5G per region di bulan terakhir?", "domain": "network", "id": 21},
    {"q": "Top 10 site 5G dengan traffic tertinggi", "domain": "network", "id": 22},
    {"q": "Trend traffic 5G harian selama 7 hari terakhir", "domain": "network", "id": 23},
    {"q": "Berapa jumlah site 5G aktif per region?", "domain": "network", "id": 24},
    {"q": "Availability rate per territory bulan terakhir", "domain": "network", "id": 25},
    {"q": "Perbandingan traffic 5G bulan ini vs bulan lalu per region", "domain": "network", "id": 26},
    {"q": "Site 5G dengan pertumbuhan traffic tertinggi MoM", "domain": "network", "id": 27},
    {"q": "Total user 5G per territory di East Java", "domain": "network", "id": 28},
    {"q": "OpenSignal download speed rata-rata per region", "domain": "network", "id": 29},
    {"q": "Berapa availability 4G per kabkota di Central Java?", "domain": "network", "id": 30},
    {"q": "Top 5 territory dengan traffic 5G tertinggi MTD", "domain": "network", "id": 31},
    {"q": "Network experience score per region dari OpenSignal", "domain": "network", "id": 32},
    {"q": "Site 5G yang traffic-nya turun >30% dalam seminggu terakhir", "domain": "network", "id": 33},
    {"q": "Rata-rata latency per region dari OpenSignal", "domain": "network", "id": 34},
    {"q": "Jumlah site 5G baru yang aktif bulan ini", "domain": "network", "id": 35},
    {"q": "Traffic 5G per branch di East Java MTD", "domain": "network", "id": 36},
    {"q": "Perbandingan upload vs download speed antar operator dari OpenSignal", "domain": "network", "id": 37},
    {"q": "Coverage 5G per kecamatan di Surabaya", "domain": "network", "id": 38},

    # ═══ COMPETITIVE INTELLIGENCE (18 questions) ═══
    {"q": "Bandingkan market share IM3 vs Telkomsel per kabkota di bulan terakhir", "domain": "competitive", "id": 39},
    {"q": "Market share IOH per age group bulan terakhir", "domain": "competitive", "id": 40},
    {"q": "Trend market share IM3 selama 6 bulan terakhir", "domain": "competitive", "id": 41},
    {"q": "Kabkota mana yang market share IOH di bawah 20%?", "domain": "competitive", "id": 42},
    {"q": "Perbandingan market share semua operator per region", "domain": "competitive", "id": 43},
    {"q": "Top 10 kecamatan dengan market share IM3 tertinggi", "domain": "competitive", "id": 44},
    {"q": "Network insight IOH vs Telkomsel per minggu terakhir", "domain": "competitive", "id": 45},
    {"q": "Kecamatan mana yang market share IM3 naik >5% MoM?", "domain": "competitive", "id": 46},
    {"q": "Market share per operator di Semarang", "domain": "competitive", "id": 47},
    {"q": "Trend market share XL di East Java 6 bulan terakhir", "domain": "competitive", "id": 48},
    {"q": "Perbandingan gross add IOH vs Telkomsel per kabkota", "domain": "competitive", "id": 49},
    {"q": "Market share amount per operator di Central Java", "domain": "competitive", "id": 50},
    {"q": "Kecamatan dengan market share SmartFren tertinggi", "domain": "competitive", "id": 51},
    {"q": "Network quality comparison IOH vs XL dari Facebook data", "domain": "competitive", "id": 52},
    {"q": "Churn rate perbandingan IOH vs Telkomsel per region", "domain": "competitive", "id": 53},
    {"q": "Market share IM3 di segmen usia 18-24 tahun", "domain": "competitive", "id": 54},
    {"q": "Top 5 kabkota dimana IOH kalah market share dari XL", "domain": "competitive", "id": 55},
    {"q": "Penetrasi 3ID per kecamatan di East Java", "domain": "competitive", "id": 56},

    # ═══ REVENUE FORECAST (16 questions) ═══
    {"q": "Tampilkan forecast revenue untuk top 5 micro-cluster bulan depan", "domain": "forecast", "id": 57},
    {"q": "Forecast revenue per branch di Central Java bulan depan", "domain": "forecast", "id": 58},
    {"q": "Akurasi forecast vs actual revenue bulan lalu per kabkota", "domain": "forecast", "id": 59},
    {"q": "Micro-cluster mana yang forecast revenue-nya naik >10%?", "domain": "forecast", "id": 60},
    {"q": "Forecast daily revenue minggu depan per branch", "domain": "forecast", "id": 61},
    {"q": "Perbandingan forecast v1 vs v3 per branch", "domain": "forecast", "id": 62},
    {"q": "Total forecast revenue seluruh Java bulan depan", "domain": "forecast", "id": 63},
    {"q": "Branch mana yang forecast revenue-nya paling rendah?", "domain": "forecast", "id": 64},
    {"q": "Trend forecast revenue 3 bulan ke depan per region", "domain": "forecast", "id": 65},
    {"q": "Forecast source data availability per branch", "domain": "forecast", "id": 66},
    {"q": "Kabkota dengan gap terbesar antara forecast dan actual", "domain": "forecast", "id": 67},
    {"q": "Forecast revenue micro-cluster di Surabaya", "domain": "forecast", "id": 68},
    {"q": "Apakah forecast revenue bulan ini on track?", "domain": "forecast", "id": 69},
    {"q": "Top 10 kabkota forecast revenue tertinggi bulan depan", "domain": "forecast", "id": 70},
    {"q": "Daily forecast trend untuk branch Semarang", "domain": "forecast", "id": 71},
    {"q": "Micro-cluster dengan forecast paling akurat 3 bulan terakhir", "domain": "forecast", "id": 72},

    # ═══ FIXED BROADBAND (12 questions) ═══
    {"q": "Berapa total FTTH provisioning bulan ini?", "domain": "fixed_broadband", "id": 73},
    {"q": "Status service order FTTH per region", "domain": "fixed_broadband", "id": 74},
    {"q": "Jumlah FWA site aktif per region", "domain": "fixed_broadband", "id": 75},
    {"q": "Trend sales FTTH harian 30 hari terakhir", "domain": "fixed_broadband", "id": 76},
    {"q": "Top 10 kecamatan dengan FTTH sales terbanyak", "domain": "fixed_broadband", "id": 77},
    {"q": "Completion rate service order FTTH per branch", "domain": "fixed_broadband", "id": 78},
    {"q": "FTTH provisioning pending vs completed bulan ini", "domain": "fixed_broadband", "id": 79},
    {"q": "FWA site tracker status per region", "domain": "fixed_broadband", "id": 80},
    {"q": "Average time to complete FTTH service order", "domain": "fixed_broadband", "id": 81},
    {"q": "Sales FTTH bulan ini vs bulan lalu per branch", "domain": "fixed_broadband", "id": 82},
    {"q": "Top 5 branch dengan growth FTTH tertinggi", "domain": "fixed_broadband", "id": 83},
    {"q": "Berapa total FTTH SA (service agreement) yang aktif?", "domain": "fixed_broadband", "id": 84},

    # ═══ HIGH VALUE CUSTOMER (14 questions) ═══
    {"q": "Total HVC subscriber per region bulan terakhir", "domain": "customer_hvc", "id": 85},
    {"q": "Revenue HVC vs non-HVC per kecamatan", "domain": "customer_hvc", "id": 86},
    {"q": "Top 10 site dengan HVC subscriber terbanyak", "domain": "customer_hvc", "id": 87},
    {"q": "Trend HVC revenue harian 30 hari terakhir", "domain": "customer_hvc", "id": 88},
    {"q": "Kecamatan dengan HVC churn tertinggi bulan ini", "domain": "customer_hvc", "id": 89},
    {"q": "ARPU HVC per region MTD", "domain": "customer_hvc", "id": 90},
    {"q": "Perbandingan HVC subscriber bulan ini vs bulan lalu", "domain": "customer_hvc", "id": 91},
    {"q": "HVC revenue contribution per branch di East Java", "domain": "customer_hvc", "id": 92},
    {"q": "Site dengan HVC ARPU tertinggi di Central Java", "domain": "customer_hvc", "id": 93},
    {"q": "Gross add HVC per kecamatan bulan terakhir", "domain": "customer_hvc", "id": 94},
    {"q": "HVC retention rate per region", "domain": "customer_hvc", "id": 95},
    {"q": "Top 5 kecamatan dengan pertumbuhan HVC terbesar MoM", "domain": "customer_hvc", "id": 96},
    {"q": "Revenue per HVC tier (premium/gold/silver) per region", "domain": "customer_hvc", "id": 97},
    {"q": "HVC usage pattern: voice vs data per region", "domain": "customer_hvc", "id": 98},

    # ═══ KPI SUMMARY (14 questions) ═══
    {"q": "Ringkasan KPI utama: revenue, RGU, churn bulan ini", "domain": "kpi_summary", "id": 99},
    {"q": "KPI highlevel per kecamatan di Surabaya MTD", "domain": "kpi_summary", "id": 100},
    {"q": "Trend revenue harian selama 30 hari terakhir", "domain": "kpi_summary", "id": 101},
    {"q": "Perbandingan KPI bulan ini vs bulan lalu per region", "domain": "kpi_summary", "id": 102},
    {"q": "Top 10 kecamatan dengan RGU tertinggi", "domain": "kpi_summary", "id": 103},
    {"q": "Churn rate per region bulan terakhir", "domain": "kpi_summary", "id": 104},
    {"q": "ARPU trend 6 bulan terakhir per region", "domain": "kpi_summary", "id": 105},
    {"q": "Kecamatan dengan penurunan revenue terbesar MTD", "domain": "kpi_summary", "id": 106},
    {"q": "Total gross add bulan ini vs target", "domain": "kpi_summary", "id": 107},
    {"q": "Revenue per kecamatan di branch Semarang", "domain": "kpi_summary", "id": 108},
    {"q": "KPI summary per circle bulan terakhir", "domain": "kpi_summary", "id": 109},
    {"q": "Trend churn harian 2 minggu terakhir", "domain": "kpi_summary", "id": 110},
    {"q": "Perbandingan ARPU antar region 3 bulan terakhir", "domain": "kpi_summary", "id": 111},
    {"q": "Revenue growth MoM per kecamatan top 20", "domain": "kpi_summary", "id": 112},

    # ═══ GEOGRAPHY & TERRITORY (14 questions) ═══
    {"q": "Performance 5G per branch bulan terakhir", "domain": "geo", "id": 113},
    {"q": "Berapa jumlah desa yang ter-cover IOH di Central Java?", "domain": "geo", "id": 114},
    {"q": "Branch performance ranking berdasarkan revenue", "domain": "geo", "id": 115},
    {"q": "Territory mapping: berapa site per kecamatan di East Java?", "domain": "geo", "id": 116},
    {"q": "Desa dengan performance terendah di branch Semarang", "domain": "geo", "id": 117},
    {"q": "Perbandingan 5G performance antar branch", "domain": "geo", "id": 118},
    {"q": "Gross add per branch harian 7 hari terakhir", "domain": "geo", "id": 119},
    {"q": "Territory 5G coverage per branch di Bali Nusra", "domain": "geo", "id": 120},
    {"q": "Branch mana yang 5G traffic-nya naik paling tinggi MoM?", "domain": "geo", "id": 121},
    {"q": "Desa performance history: trend 6 bulan terakhir Surabaya", "domain": "geo", "id": 122},
    {"q": "Top 10 branch berdasarkan 5G territory count", "domain": "geo", "id": 123},
    {"q": "Payung data per kecamatan di Central Java", "domain": "geo", "id": 124},
    {"q": "Branch dengan growth gross add tertinggi bulan ini", "domain": "geo", "id": 125},
    {"q": "Perbandingan desa performance antar region", "domain": "geo", "id": 126},

    # ═══ MARKETING KPI (12 questions) ═══
    {"q": "Marketing KPI highlight bulan ini: awareness, acquisition", "domain": "marketing", "id": 127},
    {"q": "Trend marketing KPI harian 30 hari terakhir", "domain": "marketing", "id": 128},
    {"q": "Marketing KPI per region MTD", "domain": "marketing", "id": 129},
    {"q": "Perbandingan marketing KPI bulan ini vs bulan lalu", "domain": "marketing", "id": 130},
    {"q": "Top performing region berdasarkan marketing acquisition", "domain": "marketing", "id": 131},
    {"q": "Marketing spend efficiency per region", "domain": "marketing", "id": 132},
    {"q": "Conversion rate marketing campaign per branch", "domain": "marketing", "id": 133},
    {"q": "Marketing KPI monthly trend 6 bulan terakhir", "domain": "marketing", "id": 134},
    {"q": "Region dengan marketing ROI tertinggi", "domain": "marketing", "id": 135},
    {"q": "Detail marketing KPI untuk East Java MTD", "domain": "marketing", "id": 136},
    {"q": "Marketing highlevel: semua metrik utama bulan terakhir", "domain": "marketing", "id": 137},
    {"q": "Perbandingan marketing performance antar circle", "domain": "marketing", "id": 138},

    # ═══ SALES & DISTRIBUTION (12 questions) ═══
    {"q": "Total sales per kecamatan di East Java bulan terakhir", "domain": "sales_distribution", "id": 139},
    {"q": "Jumlah outlet NBS aktif per region", "domain": "sales_distribution", "id": 140},
    {"q": "SND KPI highlevel harian minggu terakhir", "domain": "sales_distribution", "id": 141},
    {"q": "Top 10 kecamatan dengan sales tertinggi MTD", "domain": "sales_distribution", "id": 142},
    {"q": "Outlet NBS performance ranking per branch", "domain": "sales_distribution", "id": 143},
    {"q": "Trend sales MTD per region", "domain": "sales_distribution", "id": 144},
    {"q": "Kecamatan dengan penurunan sales terbesar MoM", "domain": "sales_distribution", "id": 145},
    {"q": "Sales per channel distribution per region", "domain": "sales_distribution", "id": 146},
    {"q": "Outlet density per kecamatan di Central Java", "domain": "sales_distribution", "id": 147},
    {"q": "SND KPI: gross add vs churn per branch bulan ini", "domain": "sales_distribution", "id": 148},
    {"q": "Top 5 branch dengan outlet terbanyak", "domain": "sales_distribution", "id": 149},
    {"q": "Perbandingan sales performance bulan ini vs target per region", "domain": "sales_distribution", "id": 150},

    # ═══ MARKET SHARE REPORTS (16 questions) ═══
    {"q": "Market share IM3 per area bulan terakhir", "domain": "reporting", "id": 151},
    {"q": "Market share per branch untuk brand 3ID", "domain": "reporting", "id": 152},
    {"q": "Report market share nasional trend 6 bulan", "domain": "reporting", "id": 153},
    {"q": "Market share per circle di East Java", "domain": "reporting", "id": 154},
    {"q": "Market share IM3 vs 3ID per cluster", "domain": "reporting", "id": 155},
    {"q": "Report market share per kabkota di Central Java", "domain": "reporting", "id": 156},
    {"q": "Trend market share nasional semua operator 12 bulan", "domain": "reporting", "id": 157},
    {"q": "Market share per age group secara nasional", "domain": "reporting", "id": 158},
    {"q": "Market share area ranking top 10", "domain": "reporting", "id": 159},
    {"q": "Report FB market share per kecamatan di Surabaya", "domain": "reporting", "id": 160},
    {"q": "Market share branch ranking di Bali Nusra", "domain": "reporting", "id": 161},
    {"q": "Perbandingan market share IM3 antar region trend 6 bulan", "domain": "reporting", "id": 162},
    {"q": "Market share 3ID per cluster di East Java", "domain": "reporting", "id": 163},
    {"q": "National market share: IOH total (IM3+3ID) vs competitors", "domain": "reporting", "id": 164},
    {"q": "Market share circle ranking berdasarkan growth MoM", "domain": "reporting", "id": 165},
    {"q": "Report market share kecamatan dengan sample terbesar", "domain": "reporting", "id": 166},

    # ═══ REFERENCE / LOOKUP (10 questions) ═══
    {"q": "Berapa jumlah kecamatan per region di Java?", "domain": "reference", "id": 167},
    {"q": "List semua branch beserta region-nya", "domain": "reference", "id": 168},
    {"q": "Mapping site ke desa di kecamatan X (Surabaya)", "domain": "reference", "id": 169},
    {"q": "Berapa total site per region dari reference territory?", "domain": "reference", "id": 170},
    {"q": "Super88 site list di East Java", "domain": "reference", "id": 171},
    {"q": "Holiday calendar: tanggal libur bulan ini", "domain": "reference", "id": 172},
    {"q": "Territory hierarchy: region > circle > branch > kabkota", "domain": "reference", "id": 173},
    {"q": "Berapa jumlah kelurahan per kabkota di Central Java?", "domain": "reference", "id": 174},
    {"q": "FWA master tracker: status semua FWA site", "domain": "reference", "id": 175},
    {"q": "Mapping kecamatan ke branch di Semarang", "domain": "reference", "id": 176},

    # ═══ MISC (4 questions) ═══
    {"q": "SND kecwise IS performance overview", "domain": "misc", "id": 177},
    {"q": "Territory kecamatan mapping dari tabel misc", "domain": "misc", "id": 178},
    {"q": "Data apa saja yang ada di tabel zz_territory_kecamatan?", "domain": "misc", "id": 179},
    {"q": "SND kecwise performance per region", "domain": "misc", "id": 180},

    # ═══ CROSS-DOMAIN / COMPLEX (20 questions) ═══
    {"q": "Korelasi antara 5G traffic dengan revenue per site", "domain": "cross", "id": 181},
    {"q": "Wilayah mana yang market share tinggi tapi revenue rendah?", "domain": "cross", "id": 182},
    {"q": "Bandingkan HVC churn dengan overall churn per region", "domain": "cross", "id": 183},
    {"q": "Apakah site dengan coverage 5G memiliki revenue lebih tinggi?", "domain": "cross", "id": 184},
    {"q": "Daerah mana yang perlu prioritas investasi berdasarkan forecast dan market share?", "domain": "cross", "id": 185},
    {"q": "Kecamatan dengan market share tinggi tapi FTTH penetrasi rendah", "domain": "cross", "id": 186},
    {"q": "Bagaimana performance outlet berkorelasi dengan market share?", "domain": "cross", "id": 187},
    {"q": "Region mana yang forecast-nya paling optimis vs pessimis?", "domain": "cross", "id": 188},
    {"q": "Bandingkan KPI summary dengan marketing KPI per region", "domain": "cross", "id": 189},
    {"q": "Site mana yang 5G traffic tinggi tapi subscriber rendah?", "domain": "cross", "id": 190},
    {"q": "Berikan executive summary seluruh Java: revenue, market share, 5G, churn", "domain": "cross", "id": 191},
    {"q": "Top 3 masalah utama yang terlihat dari data bulan ini", "domain": "cross", "id": 192},
    {"q": "Rekomendasi area untuk ekspansi berdasarkan forecast dan competitive data", "domain": "cross", "id": 193},
    {"q": "Perbandingan kinerja brand IM3 vs 3ID di semua aspek", "domain": "cross", "id": 194},
    {"q": "Berapa total revenue, subscriber, dan churn seluruh Java bulan ini?", "domain": "cross", "id": 195},
    {"q": "Analisis gap: area market share tinggi tapi 5G coverage rendah", "domain": "cross", "id": 196},
    {"q": "Branch mana yang paling butuh improvement di semua KPI?", "domain": "cross", "id": 197},
    {"q": "Summary data quality: berapa null/missing di kolom-kolom kunci?", "domain": "cross", "id": 198},
    {"q": "Ranking branch secara keseluruhan (composite score)", "domain": "cross", "id": 199},
    {"q": "Prediksi revenue kuartal depan berdasarkan trend 3 bulan terakhir", "domain": "cross", "id": 200},
]

def run_one(q_item, session_id):
    """Send one question via streaming, collect the full response."""
    payload = {"message": q_item["q"], "session_id": session_id}
    start = time.time()

    try:
        resp = requests.post(API, json=payload, stream=True, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        return {
            "id": q_item["id"],
            "question": q_item["q"],
            "expected_domain": q_item["domain"],
            "status": "CONNECTION_ERROR",
            "error": str(e),
            "elapsed_s": round(time.time() - start, 1),
            "routed_domain": "",
            "sql": "",
            "row_count": 0,
            "answer_preview": "",
            "has_chart": False,
            "has_table": False,
        }

    # Parse SSE stream
    full_data = {}
    raw_chunks = []
    answer_tokens = []
    try:
        for line in resp.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data: "):
                continue
            payload_str = line[6:]
            if payload_str == "[DONE]":
                break
            try:
                chunk = json.loads(payload_str)
                raw_chunks.append(chunk)
                # Collect answer tokens (streamed as {"t": "..."})
                if "t" in chunk:
                    answer_tokens.append(chunk["t"])
                # Collect result data
                elif "rows" in chunk:
                    full_data["preview"] = chunk
                elif "sql" in chunk and "attempt" in chunk:
                    full_data["sql"] = chunk.get("sql", "")
                    full_data["explanation"] = chunk.get("explanation", "")
                elif "domain" in chunk and "reason" in chunk:
                    full_data["domain"] = chunk.get("domain", "")
                elif "domain" in chunk and "reason" not in chunk:
                    # final done event
                    full_data.setdefault("domain", chunk.get("domain", ""))
                elif "error" in chunk:
                    full_data["error"] = chunk.get("error", "")
            except json.JSONDecodeError:
                pass
    except Exception as e:
        full_data["stream_error"] = str(e)

    elapsed = round(time.time() - start, 1)

    # Extract results
    sql = full_data.get("sql", "")
    answer = "".join(answer_tokens)
    error = full_data.get("error", "") or full_data.get("stream_error", "")
    domain = full_data.get("domain", "")
    preview = full_data.get("preview", {})
    row_count = preview.get("row_count", 0) if preview else 0
    has_chart = bool(preview and row_count > 0)
    has_table = row_count > 0

    # Determine status
    if error:
        status = "ERROR"
    elif not sql and not answer:
        status = "EMPTY"
    elif sql and row_count == 0 and not answer:
        status = "NO_ROWS"
    elif answer:
        status = "OK"
    else:
        status = "PARTIAL"

    return {
        "id": q_item["id"],
        "question": q_item["q"],
        "expected_domain": q_item["domain"],
        "routed_domain": domain,
        "status": status,
        "error": error[:200] if error else "",
        "elapsed_s": elapsed,
        "sql": sql[:500] if sql else "",
        "row_count": row_count,
        "answer_preview": answer[:300] if answer else "",
        "has_chart": has_chart,
        "has_table": has_table,
    }


def main():
    # Determine batch range from args
    start_id = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    end_id = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    batch_tag = f"batch_{start_id}_{end_id}"

    questions = [q for q in QUESTIONS if start_id <= q["id"] <= end_id]
    print(f"=== Running {len(questions)} questions (ID {start_id}-{end_id}) ===")

    results = []
    for i, q in enumerate(questions):
        session_id = f"test-{batch_tag}-{q['id']}-{uuid.uuid4().hex[:6]}"
        print(f"  [{i+1}/{len(questions)}] Q{q['id']}: {q['q'][:60]}...", flush=True)
        result = run_one(q, session_id)
        results.append(result)
        print(f"    → {result['status']} | domain={result['routed_domain']} | {result['elapsed_s']}s | rows={result['row_count']}")

        # Save incrementally
        csv_path = RESULTS_DIR / f"{batch_tag}.csv"
        with open(csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=results[0].keys())
            writer.writeheader()
            writer.writerows(results)

        # Pace: 2s between calls to avoid overwhelming
        if i < len(questions) - 1:
            time.sleep(2)

    # Summary
    ok = sum(1 for r in results if r["status"] == "OK")
    err = sum(1 for r in results if r["status"] == "ERROR")
    empty = sum(1 for r in results if r["status"] in ("EMPTY", "NO_ROWS"))
    partial = sum(1 for r in results if r["status"] == "PARTIAL")
    conn_err = sum(1 for r in results if r["status"] == "CONNECTION_ERROR")

    # Domain routing accuracy
    correct_route = sum(1 for r in results
                       if r["expected_domain"] == r["routed_domain"]
                       or r["expected_domain"] == "cross")
    total_routable = len([r for r in results if r["expected_domain"] != "cross"])

    print(f"\n{'='*60}")
    print(f"RESULTS: {ok} OK | {err} ERROR | {empty} EMPTY/NO_ROWS | {partial} PARTIAL | {conn_err} CONN_ERR")
    print(f"ROUTING: {correct_route}/{total_routable} correct ({100*correct_route/max(total_routable,1):.0f}%)")
    print(f"AVG TIME: {sum(r['elapsed_s'] for r in results)/max(len(results),1):.1f}s")
    print(f"CSV: {csv_path}")

    # Save full JSON too
    json_path = RESULTS_DIR / f"{batch_tag}.json"
    with open(json_path, "w") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"JSON: {json_path}")


if __name__ == "__main__":
    main()
