"""Multi-domain profile engine v2.

Enhanced profile generation with:
- Clarification flow (deck vs ringkas)
- 15+ comprehensive sections covering all KPIs
- Revenue by channel/ATL-BTL/slab/trade
- FWA profile
- 5G penetration & funnel
- Site metrics
- Competitive SOGA profile
"""
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

from . import llm, knowledge, config
from .bigquery_tool import run_query, QueryError


# ── Profile Clarification Detection ──

def needs_clarification(question: str) -> bool:
    """Check if profile question needs clarification about depth."""
    q = question.lower()
    profile_keywords = ['profile', 'profil', 'deck', 'comprehensive', 'overview lengkap', 
                        'analisa lengkap', 'tampilkan semua', 'rangkuman lengkap', 
                        'dashboard', 'semua kpi']
    # If already specifies depth, no clarification needed
    depth_keywords = ['ringkas', 'singkat', 'simple', 'lengkap', 'detail', 'komprehensif',
                      'deck', 'full', 'complete']
    
    is_profile = any(k in q for k in profile_keywords)
    has_depth = any(k in q for k in depth_keywords)
    
    return is_profile and not has_depth


CLARIFY_PROMPT = """Anda ingin melihat profile {territory}. Pilih format:

1️⃣ **Ringkas** — KPI utama saja (revenue, subs, market share). ~30 detik.
2️⃣ **Deck Lengkap** — Analisa komprehensif dengan 15+ sections:
   • Revenue by channel (ATL/BTL, MOBO Trade, Organic, Digital)
   • Revenue by price slab (0-10k, 10-20k, ..., >1Mn)
   • Trade profile (Voucher, SP Inject, Rebuy Inject trend)
   • Base Revenue vs Acquisition Revenue
   • Site profile (total, addressable, new, avg rev/site)
   • FWA (revenue, subs, gross add, churn, net add)
   • 5G penetration & device funnel
   • Market Share & SOGA by operator
   • HVC profile
   • Gross Add by channel
   • Territory info (jumlah kec, outlet)
   ~2-3 menit.

Mau yang mana?"""


# ── Comprehensive Profile Sections ──

PROFILE_SECTIONS_FULL = [
    # ── REVENUE 360 ──
    {"section_title": "Revenue Overview (Trend 360)", "domain": "kpi_summary",
     "question_template": "Revenue overview {territory}: rev_prepaid, rev_vsd, rev_data, rev_voice, rev_sms with MoM, monthly trend, YoY, and quarterly.",
     "table_hint": "rham_mkt_highlevel_mth"},
    {"section_title": "Revenue Decomposition (VSD Breakdown)", "domain": "kpi_summary",
     "question_template": "Revenue {territory} decomposition rev_data organic/mobo_trade/mobo_non_trade.",
     "table_hint": "rham_mkt_highlevel_mth"},
    {"section_title": "Base vs Acquisition Revenue", "domain": "kpi_summary",
     "question_template": "Revenue {territory} rev_base vs rev_acquisition_m0.",
     "table_hint": "rham_mkt_highlevel_mth"},
    {"section_title": "Revenue by Channel (ATL vs BTL)", "domain": "revenue",
     "question_template": "Revenue {territory} by atl_btl & channel_group.",
     "table_hint": "rham_site_data_rev_channel_mtd"},
    {"section_title": "Revenue by Channel Detail", "domain": "revenue",
     "question_template": "Revenue {territory} by channel_detail.",
     "table_hint": "rham_site_data_rev_channel_mtd"},
    {"section_title": "MOBO Trade Revenue Trend", "domain": "revenue",
     "question_template": "Revenue {territory} MOBO TRADE channel detail trend.",
     "table_hint": "rham_site_data_rev_channel_mtd"},
    {"section_title": "Revenue by Price Slab", "domain": "revenue",
     "question_template": "Revenue {territory} by price_slab + hit.",
     "table_hint": "rham_site_data_rev_price_slab_mtd"},
    # ── PRODUCT ──
    {"section_title": "Product Mix (Family & Stream)", "domain": "product",
     "question_template": "Revenue {territory} product mix: top 10 family_group by revenue (Mn) with contribution %, plus kpi_group data-vs-non-data split and MTD vs LMTD growth.",
     "table_hint": "rham_site_data_rev_product_mtd"},
    # ── SUBSCRIBER & CHURN 360 ──
    {"section_title": "Subscriber & RGU (Trend 360)", "domain": "kpi_summary",
     "question_template": "Subscriber {territory}: rgu_90d, rgu_30d, pack_subs, avg_vlr_daily, subs_pau with MoM/monthly/YoY/quarterly.",
     "table_hint": "rham_mkt_highlevel_mth"},
    {"section_title": "Gross Add & Net Add (Trend 360)", "domain": "kpi_summary",
     "question_template": "Gross add & net add {territory}: gross_add, net_add_90d, net_add_30d trend.",
     "table_hint": "rham_mkt_highlevel_mth"},
    {"section_title": "Churn Analysis (Trend 360)", "domain": "kpi_summary",
     "question_template": "Churn {territory}: gross_churn_90d, churn_back_90d, net_churn_90d trend.",
     "table_hint": "rham_mkt_highlevel_mth"},
    # ── ACQUISITION ──
    {"section_title": "Acquisition by Channel", "domain": "kpi_summary",
     "question_template": "Gross add {territory} by channel: ga_modern/ola/online/fwa/gerai/bank/h2h/traditional/dsf + biometric + M1S/M2S survival.",
     "table_hint": "rham_mkt_highlevel_mth"},
    # ── SITE ──
    {"section_title": "Site Infrastructure Profile", "domain": "kpi_summary",
     "question_template": "Site metrics {territory}: total_site, addr_site, base_site, new_site, site_addr_rev.",
     "table_hint": "rham_mkt_highlevel_mth"},
    # ── FWA ──
    {"section_title": "FWA Business Profile", "domain": "kpi_summary",
     "question_template": "FWA {territory}: rev_fwa_total/pack/sim/regular, fwa_rgu90, fwa_net_add, churn, vlr aging.",
     "table_hint": "rham_mkt_highlevel_mth"},
    # ── FTTH ──
    {"section_title": "FTTH / HBB Funnel", "domain": "ftth",
     "question_template": "FTTH {territory}: funnel SO (Sales Order, pasang baru) -> SA (Service Active, terinstalasi) -> PA (Permanent Active, bayar & aktif) trend bulanan + conversion rate.",
     "table_hint": "rham_ftth_so_detail"},
    # ── 5G ──
    {"section_title": "5G Penetration & Device Funnel", "domain": "5g",
     "question_template": "5G funnel {territory}: Data UU all -> Data UU with 5G device -> 5G device with 5G traffic, conversion %, penetration trend.",
     "table_hint": "rham_5g_territory_monthly"},
    # ── NETWORK QUALITY (CONDITION) ──
    {"section_title": "Network Condition (Availability & SLA)", "domain": "network",
     "question_template": "Network condition {territory}: avg_avail_pct_2g/4g/5g, downtime hours, sites below SLA, congestion/PRB utilization — describe the network HEALTH/condition with trend.",
     "table_hint": "rham_avail_stat_territory_monthly"},
    # ── NETWORK COMPETITION (vs competitor) — MANDATORY ──
    {"section_title": "Network Competition — FB Speed & Congestion", "domain": "network_benchmark",
     "question_template": "Network competition {territory} from Facebook network insight: download SPEED and CONGESTION (and latency/RTT if available) for IOH/IM3 vs Telkomsel/XL/SF, split 4G/5G. Compare IOH position vs competitors and state gap.",
     "table_hint": "rham_fb_network_kabkot_wly_wide"},
    {"section_title": "Network Competition — OpenSignal Experience", "domain": "network_benchmark",
     "question_template": "OpenSignal experience {territory} (latest week_id): video_indosat/voice_indosat/games_indosat/download_indosat vs *_tsel/*_xl/*_sf for a COMPLETE experience picture. Rank IOH (Indosat) vs each competitor per experience metric and call out where IOH leads or lags.",
     "table_hint": "rham_opensignal_territory_wly_wide"},
    # ── COMPETITIVE ──
    {"section_title": "Market Share (Trend 360)", "domain": "competitive",
     "question_template": "Market share {territory}: ms_ioh/im3/3id/tsel/xl/sf trend.",
     "table_hint": "rham_report_fb_ms_kabkota"},
    {"section_title": "SOGA (Share of Gross Add)", "domain": "competitive",
     "question_template": "SOGA {territory}: soga per operator trend.",
     "table_hint": "rham_report_fb_ms_kabkota"},
    {"section_title": "Churn Share (vs Competitor)", "domain": "competitive",
     "question_template": "Churn share {territory}: churn per operator trend.",
     "table_hint": "rham_report_fb_ms_kabkota"},
    # ── HVC ──
    {"section_title": "HVC (High Value Customer) Profile", "domain": "kpi_summary",
     "question_template": "HVC {territory}: subs_hvc flow + hvc_rev_total trend.",
     "table_hint": "rham_mkt_highlevel_mth"},
    # ── SALES & DISTRIBUTION ──
    {"section_title": "Sales & Distribution KPI", "domain": "sales_distribution",
     "question_template": "SND {territory}: total_outlet, uro, sso, qsso, q_uro, trade_supply, trade_demand trend.",
     "table_hint": "rham_snd_kpi_highlevel_dly"},
    # ── CHANNEL TRADE: PRIMARY / SECONDARY / TERTIARY (MANDATORY) ──
    {"section_title": "Channel Trade — Primary / Secondary / Tertiary & Ratio", "domain": "sales_distribution",
     "question_template": "Channel trade flow {territory}: SUM(primary), SUM(secondary), SUM(tertiary) (and tertiary_inner vs tertiary_outer) for the latest period with trend. COMPUTE the key trade business ratios: secondary/primary (sell-through from distributor to retailer) and tertiary/secondary (sell-out from retailer to end customer), plus tertiary_inner vs tertiary_outer split. Interpret the ratios: a healthy channel has secondary and tertiary tracking primary (low stock pile-up); flag if primary >> secondary (overstock at distributor) or secondary >> tertiary (overstock at retailer / weak sell-out).",
     "table_hint": "rham_snd_kpi_highlevel_dly"},
    # ── TERRITORY INFO ──
    {"section_title": "Territory Info", "domain": "kpi_summary",
     "question_template": "Territory info {territory}: jumlah kecamatan, jumlah kabkota, total outlet.",
     "table_hint": "rham_mkt_highlevel_mth"},
]

PROFILE_SECTIONS_SIMPLE = [
    PROFILE_SECTIONS_FULL[0],   # Revenue Overview
    PROFILE_SECTIONS_FULL[7],   # Subscriber & RGU
    PROFILE_SECTIONS_FULL[17],  # Market Share
    PROFILE_SECTIONS_FULL[11],  # Site Profile
]


# ── Profile Planner ──

PLANNER_SYS = """You are a profile query planner for Indosat (IOH) telco analytics.
Given a territory profile request, generate focused SQL sub-queries for each section.

IMPORTANT RULES:
1. Each sub-query must be self-contained and specific.
2. Use the correct filter based on territory_type:
   - kabkota: WHERE kabkot = '<territory_name>' (or kabkota for some tables)
   - kecamatan: WHERE kec_id = '<kec_id>' OR kecamatan = '<territory_name>'
   - region: WHERE region = '<territory_name>'
   - circle: WHERE circle = '<territory_name>'
   - branch: WHERE branch = '<territory_name>'
   - province: WHERE province = '<territory_name>'
3. For 5G table (rham_5g_territory_monthly), use: territory_level = '<territory_type>' AND territory_name = '<territory_name>'
4. Always compare latest 2-3 months for trend.
5. Generate the exact question that will be sent to the SQL agent.

SECTIONS TO GENERATE:
__SECTIONS__

Output JSON:
{
  "territory_type": "kabkota|kecamatan|region|circle|branch|province",
  "territory_name": "<exact territory name>",
  "sub_queries": [
    {"domain": "<domain>", "section_title": "<title>", "question": "<specific question with territory filter>"},
    ...
  ]
}"""


_TERRITORY_SYS = (
    "Extract the territory from an Indonesian telco profile request. "
    "Return ONLY compact JSON: {\"territory_type\":\"kabkota|kecamatan|region|circle|branch|province\","
    "\"territory_name\":\"<name as written, without the prefix word>\"}. "
    "Rules: 'kota X' or 'kabupaten X' -> kabkota; 'kecamatan X' -> kecamatan; "
    "'region X' -> region; 'circle X' -> circle; 'branch X' -> branch. "
    "If only a place name is given (e.g. 'profile Surabaya'), default territory_type=kabkota. "
    "Output JSON only, no prose."
)


def plan_profile(question: str, history: list | None = None,
                 full_deck: bool = True) -> dict:
    """Plan profile sub-queries. full_deck=True for comprehensive, False for simple.

    Sub-queries are generated from hardcoded templates for reliability, so the
    planner ONLY needs territory_type + territory_name. We resolve those with a
    fast regex first and fall back to a tiny FAST-model call only if needed —
    this avoids a slow ~40s heavy-model planner call.
    """
    sections = PROFILE_SECTIONS_FULL if full_deck else PROFILE_SECTIONS_SIMPLE

    territory_type, territory_name = _resolve_territory(question)

    # Only call the LLM if regex failed to find a name.
    if not territory_name:
        try:
            msgs = [{"role": "system", "content": _TERRITORY_SYS},
                    {"role": "user", "content": question}]
            res = llm.chat_json(msgs, model=config.LLM_MODEL_FAST, max_tokens=120)
            territory_type = res.get("territory_type") or territory_type
            territory_name = res.get("territory_name") or territory_name
        except Exception:
            pass

    territory_label = f"{territory_type} {territory_name}".strip()

    return {
        "territory_type": territory_type,
        "territory_name": territory_name,
        "sub_queries": [
            {
                "domain": s["domain"],
                "section_title": s["section_title"],
                "question": s["question_template"].format(territory=territory_label),
            }
            for s in sections
        ],
    }


_STOP_WORDS = {
    "lengkap", "ringkas", "detail", "deck", "profile", "profil", "bulan", "tahun",
    "dari", "sampai", "yang", "mencakup", "seluruh", "semua", "kpi", "marketing",
    "dan", "dengan", "untuk", "data", "trend", "tren", "tampilkan", "buatkan",
    "berikan", "analisa", "analisis", "overview", "komprehensif", "vs", "per",
}


def _clean_name(raw: str) -> str:
    """Keep only the leading place-name tokens, stop at the first filler word."""
    import re
    toks = re.findall(r"[A-Za-z][A-Za-z.\-]*", raw or "")
    out = []
    for tk in toks:
        if tk.lower() in _STOP_WORDS:
            break
        out.append(tk)
        if len(out) >= 3:  # place names are rarely >3 words
            break
    return " ".join(out).strip().title()


def _resolve_territory(question: str):
    """Fast regex territory resolver -> (territory_type, territory_name)."""
    import re
    q = question or ""
    patterns = [
        (r'\bkecamatan\s+([A-Za-z][A-Za-z .\-]*)', "kecamatan"),
        (r'\b(?:kota|kabupaten|kabkota|kab\.?)\s+([A-Za-z][A-Za-z .\-]*)', "kabkota"),
        (r'\bregion\s+([A-Za-z][A-Za-z .\-]*)', "region"),
        (r'\bcircle\s+([A-Za-z][A-Za-z .\-]*)', "circle"),
        (r'\bbranch\s+([A-Za-z][A-Za-z .\-]*)', "branch"),
        (r'\bprovinsi\s+([A-Za-z][A-Za-z .\-]*)', "province"),
    ]
    for pat, ttype in patterns:
        m = re.search(pat, q, re.IGNORECASE)
        if m:
            name = _clean_name(m.group(1))
            if name:
                return ttype, name
    # No explicit prefix: take the place name after profile/profil keyword
    m = re.search(r'\bprofil?e?\s+(?:lengkap\s+|ringkas\s+)?([A-Za-z][A-Za-z .\-]*)', q, re.IGNORECASE)
    if m:
        name = _clean_name(m.group(1))
        if name:
            return "kabkota", name
    return "kabkota", _clean_name(_extract_territory(question))


def _extract_territory(question: str) -> str:
    """Best-effort territory name extraction from question."""
    import re
    q = question.lower()
    # Common patterns
    for pattern in [r'kota\s+(\w+)', r'kabkota\s+(\w+)', r'kabupaten\s+(\w+)',
                    r'kecamatan\s+(\w+)', r'region\s+(\w+)', r'circle\s+(\w+)']:
        m = re.search(pattern, q)
        if m:
            return m.group(1).title()
    # Fallback: last capitalized word
    words = question.split()
    for w in reversed(words):
        if w[0].isupper() and len(w) > 2:
            return w
    return ""


# ── Parallel Execution ──

# Pre-built SQL templates for sections that reliably fail via LLM
# These use site-level tables which need explicit aggregation
_PROJECT = "data-java-prd-97b9"
_DATASET = "java_precalc"

def _direct_sql_templates(territory_type: str, territory_name: str) -> dict:
    """Return section_title -> SQL for sections with predictable queries.

    Every section computes 4 trend views in ONE query via a monthly aggregate
    that the compiler reads: latest month, prev month (MoM), same month last
    year (YoY), and the last ~15 months (for monthly + quarterly rollup).
    """
    # ── territory filters per table family ──
    # Normalize territory name for case-insensitive LIKE matching (e.g. "Surabaya"
    # must match "KOTA SURABAYA"). Strip common prefixes the user might omit.
    tn = (territory_name or "").upper().strip()
    for pfx in ("KOTA ", "KABUPATEN ", "KAB ", "KAB. ", "KEC ", "KEC. ", "KECAMATAN "):
        if tn.startswith(pfx):
            tn = tn[len(pfx):]
    tn = tn.replace("'", "")
    if territory_type == "kabkota":
        f_mkt = f"UPPER(kabkot) LIKE '%{tn}%'"
        f_chan = f"UPPER(kabkota) LIKE '%{tn}%'"
        f_5g = f"territory_level = 'kabkot' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_report = f"UPPER(kabkota) LIKE '%{tn}%'"
        f_avail = f"territory_level = 'kabkot' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_nb = f"UPPER(kabkot) LIKE '%{tn}%'"
        f_ftth = f"UPPER(city) LIKE '%{tn}%'"
        f_snd = f"kec_unik IN (SELECT kec_id FROM `{_PROJECT}.{_DATASET}.zz_territory_kecamatan` WHERE UPPER(kabkota) LIKE '%{tn}%')"
    elif territory_type == "kecamatan":
        f_mkt = f"UPPER(kecamatan) LIKE '%{tn}%'"
        f_chan = f"UPPER(kecamatan) LIKE '%{tn}%'"
        f_5g = f"territory_level = 'kecamatan' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_report = f"UPPER(kecamatan) LIKE '%{tn}%'"
        f_avail = f"territory_level = 'kecamatan' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_nb = f"UPPER(kecamatan) LIKE '%{tn}%'"
        f_ftth = f"UPPER(shp_kecamatan) LIKE '%{tn}%'"
        f_snd = f"UPPER(kec_unik) LIKE '%{tn}%'"
    elif territory_type in ("region", "circle", "branch", "province", "area"):
        col = {"region": "region", "circle": "circle", "branch": "branch",
               "province": "province", "area": "area"}[territory_type]
        # These tables are kecamatan-grain; resolve the higher-level territory by
        # joining to the territory reference on kec_id (canonical names live there).
        kec_sub = (f"kec_id IN (SELECT kec_id FROM "
                   f"`{_PROJECT}.{_DATASET}.zz_territory_kecamatan` "
                   f"WHERE UPPER({col}) LIKE '%{tn}%')")
        f_mkt = kec_sub          # rham_mkt_highlevel_* has kec_id
        f_chan = kec_sub         # rev channel/slab have kec_id... fallback below
        f_5g = f"territory_level = '{territory_type}' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_report = kec_sub       # rham_report_fb_ms_kecamatan has kec_id
        f_avail = f"territory_level = '{territory_type}' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_nb = kec_sub
        f_ftth = None
        f_snd = kec_sub
        _territory_grain = territory_type  # used to switch report table to kecamatan
    else:
        f_mkt = f"UPPER(kabkot) LIKE '%{tn}%'"; f_chan = f"UPPER(kabkota) LIKE '%{tn}%'"
        f_5g = f"territory_level = 'kabkot' AND UPPER(territory_name) LIKE '%{tn}%'"
        f_report = f"UPPER(kabkota) LIKE '%{tn}%'"; f_avail = f_5g
        f_nb = f"UPPER(kabkot) LIKE '%{tn}%'"; f_ftth = None; f_snd = None

    t = f"`{_PROJECT}.{_DATASET}"
    out = {}

    # For higher-level territories (circle/region/etc.) the competitive market
    # share table must be the KECAMATAN one (it has kec_id); for kabkota/kecamatan
    # we use the kabkota table. SND keys on kec_unik; network benchmark on kabkot.
    _is_high = territory_type in ("region", "circle", "branch", "province", "area")
    # kecamatan-grain report table when the territory is kecamatan OR a higher
    # level (those filter via kec_id); kabkota table only for a kabkota profile.
    report_table = ("rham_report_fb_ms_kabkota" if territory_type == "kabkota"
                    else "rham_report_fb_ms_kecamatan")
    # network-benchmark table: kabkot-grain for a kabkota profile, else kecamatan-grain
    nb_table = ("rham_fb_network_kabkot_wly_wide" if territory_type == "kabkota"
                else "rham_fb_network_kec_wly_wide")
    if _is_high:
        _col = {"region": "region", "circle": "circle", "branch": "branch",
                "province": "province", "area": "area"}[territory_type]
        # SND keys by kec_unik -> map via territory ref (its kec_id == kec_unik)
        f_snd = (f"kec_unik IN (SELECT kec_id FROM "
                 f"`{_PROJECT}.{_DATASET}.zz_territory_kecamatan` "
                 f"WHERE UPPER({_col}) LIKE '%{tn}%')")
        # network benchmark keyed by kabkot -> map kabkot list via territory ref
        f_nb = (f"kec_id IN (SELECT kec_id FROM "
                f"`{_PROJECT}.{_DATASET}.zz_territory_kecamatan` "
                f"WHERE UPPER({_col}) LIKE '%{tn}%')")

    # The current month is often PARTIAL (data only through day N). Comparing a
    # partial month vs a full prior month understates flow metrics (revenue,
    # gross add, churn, usage). To keep MoM/YoY/quarterly apples-to-apples we use
    # the MTD tables for kpi_summary flow metrics — MTD snapshots are taken at the
    # SAME day-of-month every month, so the comparison is always fair. We tag the
    # output with a 'basis' column ('MTD') so the compiler labels it correctly.
    KPI_TABLE = "rham_mkt_highlevel_mtd"  # MTD = fair comparison even mid-month

    # ── helper: build a 360 trend query over a monthly/MTD table ──
    # metrics_sql: comma-separated SUM(...) AS alias expressions
    def trend_mth(table, mid_col, mthdt_col, where, metrics_sql, extra_group="", basis=None):
        gb = f"{mid_col}{(', ' + extra_group) if extra_group else ''}"
        sel_extra = (extra_group + ", ") if extra_group else ""
        # auto-tag MTD basis so the compiler labels comparisons correctly
        if basis is None and table.endswith("_mtd"):
            basis = "MTD"
        basis_sel = f"'{basis}' AS basis, " if basis else ""
        return f"""
WITH mx AS (SELECT MAX({mthdt_col}) AS m FROM {t}.{table}`)
SELECT {mid_col} AS period, {basis_sel}{sel_extra}{metrics_sql}
FROM {t}.{table}`, mx
WHERE {where}
  AND {mthdt_col} >= DATE_SUB(mx.m, INTERVAL 15 MONTH)
GROUP BY {gb}
ORDER BY period DESC{(', ' + extra_group) if extra_group else ''}""".strip()

    # ===== REVENUE (kpi_summary) =====
    if f_mkt:
        out["Revenue Overview (Trend 360)"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(rev_prepaid) AS rev_prepaid, SUM(rev_vsd) AS rev_vsd, SUM(rev_data) AS rev_data, "
            "SUM(rev_voice) AS rev_voice, SUM(rev_sms) AS rev_sms")
        out["Revenue Decomposition (VSD Breakdown)"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(rev_data_organic) AS rev_data_organic, SUM(rev_data_mobo_trade) AS rev_data_mobo_trade, "
            "SUM(rev_data_mobo_non_trade) AS rev_data_mobo_non_trade, SUM(rev_voice) AS rev_voice, SUM(rev_sms) AS rev_sms")
        out["Base vs Acquisition Revenue"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(rev_base) AS rev_base, SUM(rev_acquisition_m0) AS rev_acquisition_m0, SUM(rev_prepaid) AS rev_prepaid")
        out["Subscriber & RGU (Trend 360)"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(rgu_90d) AS rgu_90d, SUM(rgu_30d) AS rgu_30d, SUM(pack_subs) AS pack_subs, "
            "SUM(avg_vlr_daily) AS avg_vlr_daily")
        out["Gross Add & Net Add (Trend 360)"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(gross_add) AS gross_add, SUM(net_add_90d) AS net_add_90d, SUM(net_add_30d) AS net_add_30d")
        out["Churn Analysis (Trend 360)"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(gross_churn_90d) AS gross_churn_90d, SUM(churn_back_90d) AS churn_back_90d, "
            "SUM(net_churn_90d) AS net_churn_90d")
        out["Acquisition by Channel"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(ga_modern) AS ga_modern, SUM(ga_ola) AS ga_ola, SUM(ga_online) AS ga_online, "
            "SUM(ga_fwa) AS ga_fwa, SUM(ga_gerai) AS ga_gerai, SUM(ga_bank) AS ga_bank, "
            "SUM(ga_h2h) AS ga_h2h, SUM(ga_traditional) AS ga_traditional, SUM(ga_dsf) AS ga_dsf, "
            "SUM(ga_total) AS ga_total")
        out["Site Infrastructure Profile"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(total_site) AS total_site, SUM(addr_site) AS addr_site, SUM(base_site) AS base_site, "
            "SUM(new_site) AS new_site, SUM(site_addr_rev) AS site_addr_rev")
        out["FWA Business Profile"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(rev_fwa_total) AS rev_fwa_total, SUM(rev_fwa_pack) AS rev_fwa_pack, "
            "SUM(fwa_rgu90) AS fwa_rgu90, SUM(fwa_net_add) AS fwa_net_add, "
            "SUM(fwa_grosschurn90) AS fwa_grosschurn90")
        out["HVC (High Value Customer) Profile"] = trend_mth(
            KPI_TABLE, "month_id", "mth_dt", f_mkt,
            "SUM(subs_hvc) AS subs_hvc, SUM(subs_hvc_in) AS subs_hvc_in, SUM(subs_hvc_out) AS subs_hvc_out, "
            "SUM(hvc_rev_total) AS hvc_rev_total")
        out["Territory Info"] = f"""
WITH mx AS (SELECT MAX(mth_dt) AS m FROM {t}.{KPI_TABLE}`)
SELECT COUNT(DISTINCT kec_id) AS jumlah_kecamatan, COUNT(DISTINCT kabkot) AS jumlah_kabkota,
       SUM(num_outlet) AS total_outlet
FROM {t}.{KPI_TABLE}`, mx
WHERE {f_mkt} AND mth_dt = mx.m""".strip()

    # ===== REVENUE channel/slab =====
    if f_chan:
        out["Revenue by Channel (ATL vs BTL)"] = trend_mth(
            "rham_site_data_rev_channel_mtd", "month_id", "mth_dt", f_chan,
            "SUM(revenue) AS revenue", extra_group="atl_btl")
        out["Revenue by Channel Detail"] = f"""
WITH mx AS (SELECT MAX(month_id) AS m FROM {t}.rham_site_data_rev_channel_mtd`)
SELECT month_id AS period, channel_group, channel_detail, SUM(revenue) AS revenue
FROM {t}.rham_site_data_rev_channel_mtd`, mx
WHERE {f_chan} AND month_id = mx.m
GROUP BY period, channel_group, channel_detail
ORDER BY revenue DESC LIMIT 30""".strip()
        out["MOBO Trade Revenue Trend"] = f"""
WITH mx AS (SELECT MAX(mth_dt) AS m FROM {t}.rham_site_data_rev_channel_mtd`)
SELECT month_id AS period, channel_detail, SUM(revenue) AS revenue
FROM {t}.rham_site_data_rev_channel_mtd`, mx
WHERE {f_chan} AND channel_group = 'MOBO TRADE'
  AND mth_dt >= DATE_SUB(mx.m, INTERVAL 15 MONTH)
GROUP BY period, channel_detail
ORDER BY period DESC, revenue DESC""".strip()
        out["Revenue by Price Slab"] = f"""
WITH mx AS (SELECT MAX(month_id) AS m FROM {t}.rham_site_data_rev_price_slab_mtd`)
SELECT month_id AS period, price_slab, SUM(revenue) AS revenue, SUM(hit) AS hit
FROM {t}.rham_site_data_rev_price_slab_mtd`, mx
WHERE {f_chan} AND month_id = mx.m
GROUP BY period, price_slab
ORDER BY revenue DESC""".strip()

    # ===== 5G FUNNEL =====
    # Funnel: total data UU -> data UU with 5G device -> 5G device with 5G traffic.
    # Includes step conversion rates + traffic split for context.
    out["5G Penetration & Device Funnel"] = f"""
WITH mx AS (SELECT MAX(mth_dt) AS m FROM {t}.rham_5g_territory_monthly`)
SELECT mth_id AS period,
       SUM(site_count) AS site_count,
       SUM(data_uu30_all) AS uu_data_all,
       SUM(data_uu30_dev_5g) AS uu_data_5g_device,
       SUM(dev5g_with_traffic) AS uu_5g_device_with_5g_traffic,
       SAFE_DIVIDE(SUM(data_uu30_dev_5g), SUM(data_uu30_all)) AS conv_5g_device_pct,
       SAFE_DIVIDE(SUM(dev5g_with_traffic), SUM(data_uu30_dev_5g)) AS conv_5g_traffic_pct,
       SAFE_DIVIDE(SUM(dev5g_with_traffic), SUM(dev5g_total)) AS penetration_5g,
       SUM(dev5g_total) AS dev5g_total,
       SUM(dev5g_no_traffic) AS dev5g_no_traffic,
       SUM(traffic_5g) AS traffic_5g, SUM(traffic_4g) AS traffic_4g
FROM {t}.rham_5g_territory_monthly`, mx
WHERE {f_5g} AND mth_dt >= DATE_SUB(mx.m, INTERVAL 15 MONTH)
GROUP BY period ORDER BY period DESC""".strip()

    # ===== Network availability =====
    out["Network Availability & SLA"] = f"""
WITH mx AS (SELECT MAX(month_start) AS m FROM {t}.rham_avail_stat_territory_monthly`)
SELECT month_id AS period, mean_avg_avail_pct_2g, mean_avg_avail_pct_4g, mean_avg_avail_pct_5g,
       total_downtime_hrs_4g, sites_below_sla99_4g, sites_below_sla95_4g, total_sites
FROM {t}.rham_avail_stat_territory_monthly`, mx
WHERE {f_avail} AND month_start >= DATE_SUB(mx.m, INTERVAL 15 MONTH)
ORDER BY period DESC""".strip()

    # ===== Network benchmark (competitor) =====
    if f_nb:
        out["Network Benchmark (vs Competitor)"] = f"""
WITH mx AS (SELECT MAX(wk_end_dt) AS m FROM {t}.{nb_table}`)
SELECT wk_end_dt AS period,
       AVG(dl_speed_im3_4g) AS dl_im3_4g, AVG(dl_speed_tri_4g) AS dl_tri_4g,
       AVG(dl_speed_tsel_4g) AS dl_tsel_4g, AVG(dl_speed_xl_4g) AS dl_xl_4g, AVG(dl_speed_sf_4g) AS dl_sf_4g,
       AVG(dl_speed_im3_5g) AS dl_im3_5g, AVG(dl_speed_tsel_5g) AS dl_tsel_5g
FROM {t}.{nb_table}`, mx
WHERE {f_nb} AND wk_end_dt = mx.m
GROUP BY period""".strip()

    # ===== Competitive MS / SOGA / Churn =====
    if f_report:
        out["Market Share (Trend 360)"] = trend_mth(
            report_table, "month_id", "dt_id", f_report,
            "AVG(ms_ioh) AS ms_ioh, AVG(ms_im3) AS ms_im3, AVG(ms_3id) AS ms_3id, "
            "AVG(ms_tsel) AS ms_tsel, AVG(ms_xl) AS ms_xl, AVG(ms_sf) AS ms_sf")
        out["SOGA (Share of Gross Add)"] = trend_mth(
            report_table, "month_id", "dt_id", f_report,
            "AVG(soga_ioh) AS soga_ioh, AVG(soga_im3) AS soga_im3, AVG(soga_3id) AS soga_3id, "
            "AVG(soga_tsel) AS soga_tsel, AVG(soga_xl) AS soga_xl, AVG(soga_sf) AS soga_sf")
        out["Churn Share (vs Competitor)"] = trend_mth(
            report_table, "month_id", "dt_id", f_report,
            "AVG(churn_ioh) AS churn_ioh, AVG(churn_im3) AS churn_im3, AVG(churn_3id) AS churn_3id, "
            "AVG(churn_tsel) AS churn_tsel, AVG(churn_xl) AS churn_xl, AVG(churn_sf) AS churn_sf")

    # ===== FTTH funnel =====
    if f_ftth:
        out["FTTH / HBB Funnel"] = f"""
SELECT '1. SO (Sales Order - pasang baru)' AS funnel_stage, year_month AS period, COUNT(DISTINCT bill_acc) AS accounts
FROM {t}.rham_ftth_so_detail` WHERE {f_ftth} GROUP BY period
UNION ALL
SELECT '2. SA (Service Active - terinstalasi)', year_month, COUNT(DISTINCT bill_acc)
FROM {t}.rham_ftth_sa_detail` WHERE {f_ftth} GROUP BY year_month
UNION ALL
SELECT '3. PA (Permanent Active - bayar & aktif)', year_month, COUNT(DISTINCT bill_acc)
FROM {t}.rham_ftth_pa_detail` WHERE {f_ftth} GROUP BY year_month
ORDER BY period DESC, funnel_stage""".strip()

    # ===== Sales & Distribution =====
    if f_snd:
        out["Sales & Distribution KPI"] = f"""
WITH mx AS (SELECT MAX(dt_id) AS m FROM {t}.rham_snd_kpi_highlevel_dly`)
SELECT month_id AS period, SUM(total_outlet) AS total_outlet, SUM(uro) AS uro, SUM(sso) AS sso,
       SUM(qsso_m0) AS qsso, SUM(q_uro) AS q_uro, SUM(trade_supply) AS trade_supply,
       SUM(trade_demand) AS trade_demand, SUM(`primary`) AS primary_sales, SUM(secondary) AS secondary,
       SUM(tertiary) AS tertiary
FROM {t}.rham_snd_kpi_highlevel_dly`, mx
WHERE {f_snd} AND dt_id >= DATE_SUB(mx.m, INTERVAL 12 MONTH)
GROUP BY period ORDER BY period DESC""".strip()

    return out


def _run_direct_sql(section_title: str, sql: str) -> dict:
    """Execute a pre-built SQL directly (no LLM)."""
    result_entry = {
        "domain": "direct_sql",
        "section_title": section_title,
        "question": f"[Direct SQL] {section_title}",
        "sql": sql.strip(),
        "rows": [],
        "columns": [],
        "row_count": 0,
        "error": None,
        "explanation": "Pre-built SQL template for reliable territory aggregation",
    }
    try:
        qr = run_query(sql.strip())
        result_entry["rows"] = qr["rows"][:50]
        result_entry["columns"] = qr["columns"]
        result_entry["row_count"] = qr["row_count"]
    except Exception as e:
        result_entry["error"] = str(e)[:400]
    return result_entry


def _run_one_domain(domain_key: str, question: str, section_title: str) -> dict:
    """Execute a single domain query."""
    from . import orchestrator

    result_entry = {
        "domain": domain_key,
        "section_title": section_title,
        "question": question,
        "sql": None,
        "rows": [],
        "columns": [],
        "row_count": 0,
        "error": None,
        "explanation": "",
    }

    kb = knowledge.load_kb()
    if domain_key not in kb["domains"]:
        result_entry["error"] = f"Unknown domain: {domain_key}"
        return result_entry

    prior_error = prior_sql = None
    for attempt in range(3):
        try:
            gen = orchestrator.write_sql(domain_key, question, prior_error, prior_sql)
            sql = gen.get("sql", "")
            explanation = gen.get("explanation", "")
            result_entry["sql"] = sql
            result_entry["explanation"] = explanation
        except Exception as e:
            result_entry["error"] = f"SQL generation failed: {str(e)[:200]}"
            continue

        try:
            qr = run_query(sql)
            result_entry["rows"] = qr["rows"][:50]
            result_entry["columns"] = qr["columns"]
            result_entry["row_count"] = qr["row_count"]
            result_entry["error"] = None
            return result_entry
        except Exception as e:
            prior_error = str(e)[:400]
            prior_sql = sql
            result_entry["error"] = prior_error

    return result_entry


def run_parallel(sub_queries: list[dict], max_workers: int = 5,
                 territory_type: str = "kabkota",
                 territory_name: str = "") -> list[dict]:
    """Fan-out sub-queries in parallel. Uses direct SQL for predictable sections."""
    import logging
    log = logging.getLogger("profile_engine")
    
    # Get direct SQL templates if available
    direct_sqls = _direct_sql_templates(territory_type, territory_name)
    
    results = []
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {}
        for sq in sub_queries:
            title = sq.get("section_title", sq["domain"])
            if title in direct_sqls:
                # Use direct SQL instead of LLM
                f = pool.submit(_run_direct_sql, title, direct_sqls[title])
                log.info(f"[DIRECT SQL] {title}")
            else:
                f = pool.submit(
                    _run_one_domain,
                    sq["domain"],
                    sq["question"],
                    title,
                )
                log.info(f"[LLM SQL] {title} -> {sq['domain']}")
            futures[f] = sq

        # Wait with per-future timeout to avoid hanging on slow LLM calls
        for f in as_completed(futures, timeout=180):
            try:
                results.append(f.result(timeout=10))
            except Exception as e:
                sq = futures[f]
                log.warning(f"[FAILED] {sq.get('section_title', '?')}: {e}")
                results.append({
                    "domain": sq["domain"],
                    "section_title": sq.get("section_title", sq["domain"]),
                    "question": sq["question"],
                    "error": str(e)[:300],
                    "rows": [], "columns": [], "row_count": 0,
                })

    # Re-order to match original sub_queries order
    order = {sq["section_title"]: i for i, sq in enumerate(sub_queries)}
    results.sort(key=lambda r: order.get(r["section_title"], 99))
    return results


# ── Profile Compiler ──

COMPILER_SYS = """You are a senior telco business analyst for Indosat (IOH) Java region.
Compile a COMPREHENSIVE TERRITORY PROFILE DECK from multi-domain query results.

Territory: {territory_type} = {territory_name}

This is a 360° profile. Most sections provide a MONTHLY time-series in column
'period' (YYYYMM) with ~15 months of history. From this single series you MUST
derive and present ALL FOUR trend views for the key metrics:
  • MoM growth = latest period vs previous period (%).
  • Monthly trend = last 6 periods (mini trend line / table).
  • YoY = latest period vs the same month 12 periods earlier (%).
  • Quarterly = roll the months into quarters (Q = 3 consecutive months) and
    show the last 3-4 quarters and QoQ change.
Compute these yourself from the 'period' rows — never invent numbers.

MTD BASIS (IMPORTANT): Sections that include a 'basis' column = 'MTD' use Month-To-Date
figures (data through the same day-of-month each period), because the latest month is
still PARTIAL. For these sections, comparisons are already apples-to-apples — clearly
LABEL them as "MTD" (e.g. "Revenue MTD: ... (MoM MTD +X%)"). Do NOT compare a partial
full-month against a complete prior month. When 'basis'='MTD', state that the current
month figure is month-to-date so the reader knows it is not the full month.

FORMAT RULES:
1. Start with **EXECUTIVE SUMMARY** (6-8 bullets: revenue, subs, market share, network, key risks).
2. Use markdown sections (## major, ### sub). Present data in tables.
3. For EACH major KPI section, include a compact block: MoM | YoY | QoQ | 6-month trend.
4. Trend arrows: ↑ increase, ↓ decrease, → stable. Flag 🔴 concern, 🟢 strength.
5. Revenue sections: show absolute (Rp) + percentage composition.
6. Competitive sections: compare IOH vs Telkomsel/XL/SF clearly with gap.
7. Calculate derived metrics (avg rev/site, 5G penetration %, ARPU proxy, SLA breach).
8. End with **STRATEGIC RECOMMENDATIONS** (5-7 actionable items tied to the data).
9. Reply in {language}. NEVER invent numbers. If a section errored/empty, note briefly & continue.

SECTION ORDER (group logically):
A. Executive Summary
B. REVENUE: Overview (MoM/YoY/QoQ) → Decomposition → Base vs Acquisition → Channel (ATL/BTL) → Channel Detail → MOBO Trade → Price Slab
C. CUSTOMER: Subscriber & RGU → Gross/Net Add → Churn → Acquisition by Channel → HVC
D. INFRASTRUCTURE: Site Profile → FWA → FTTH/HBB Funnel
   - FTTH funnel: show SO (Sales Order) → SA (Service Active) → PA (Permanent Active) with stage-to-stage conversion % (SA/SO, PA/SA).
E. NETWORK: 5G Funnel → Network Availability & SLA → Network Benchmark (vs competitor)
   - 5G funnel: show Data UU all → Data UU with 5G device → 5G device with 5G traffic, with conversion % at each step (conv_5g_device_pct, conv_5g_traffic_pct).
F. COMPETITIVE: Market Share → SOGA → Churn Share
G. DISTRIBUTION: Sales & Distribution KPI
H. Territory Info
I. Strategic Recommendations
"""


def compile_profile(territory_type: str, territory_name: str,
                    domain_results: list[dict], language: str = "id") -> str:
    """Synthesize all domain results into comprehensive deck."""
    sys = COMPILER_SYS.format(
        territory_type=territory_type,
        territory_name=territory_name,
        language=language,
    )

    sections = []
    for dr in domain_results:
        section = {
            "section_title": dr["section_title"],
            "domain": dr["domain"],
            "question": dr["question"],
            "explanation": dr.get("explanation", ""),
        }
        if dr.get("error"):
            section["status"] = "error"
            section["error"] = dr["error"]
        else:
            section["status"] = "ok"
            section["columns"] = dr["columns"]
            section["row_count"] = dr["row_count"]
            section["rows"] = dr["rows"][:30]
        sections.append(section)

    payload = {
        "territory": f"{territory_type}: {territory_name}",
        "sections": sections,
    }

    msgs = [
        {"role": "system", "content": sys},
        {"role": "user", "content": json.dumps(payload, ensure_ascii=False, default=str)},
    ]
    return llm.chat(msgs, model=config.LLM_MODEL_CODER, max_tokens=6000)


def _section_payload(dr: dict) -> dict:
    section = {"section_title": dr["section_title"], "domain": dr["domain"]}
    if dr.get("error"):
        section["status"] = "error"
        section["error"] = (dr.get("error") or "")[:120]
    else:
        section["status"] = "ok"
        section["columns"] = dr["columns"]
        section["row_count"] = dr["row_count"]
        section["rows"] = dr["rows"][:16]
    return section


# Logical grouping of sections into compile CHUNKS so a long deck is never
# truncated by a single generation's max_tokens. Matched by case-insensitive
# substring on section_title; anything unmatched falls into the last business chunk.
_CHUNK_DEFS = [
    ("BUSINESS",   ["revenue", "product", "subscriber", "rgu", "gross add", "net add",
                     "churn", "acquisition", "hvc", "base vs"]),
    ("INFRA_NET",  ["site", "fwa", "ftth", "hbb", "5g", "network", "availability",
                     "sla", "condition", "opensignal", "benchmark", "speed", "congestion"]),
    ("MARKET_DIST", ["market share", "soga", "churn share", "competition", "competitive",
                     "sales", "distribution", "channel trade", "primary", "secondary",
                     "tertiary", "territory info"]),
]


def _group_sections(domain_results: list[dict]) -> list[tuple[str, list[dict]]]:
    used = set()
    groups = []
    for name, keys in _CHUNK_DEFS:
        bucket = []
        for i, dr in enumerate(domain_results):
            if i in used:
                continue
            title = (dr.get("section_title") or "").lower()
            if any(k in title for k in keys):
                bucket.append(dr)
                used.add(i)
        if bucket:
            groups.append((name, bucket))
    # leftovers -> append to the first/business group (or make their own)
    leftovers = [dr for i, dr in enumerate(domain_results) if i not in used]
    if leftovers:
        if groups:
            groups[0] = (groups[0][0], groups[0][1] + leftovers)
        else:
            groups.append(("BUSINESS", leftovers))
    return groups


def compile_profile_stream(territory_type: str, territory_name: str,
                           domain_results: list[dict], language: str = "id"):
    """Streaming, CHUNKED profile compiler. To avoid the deck being cut off
    mid-sentence (the 26-section deck overflows a single generation), we compile
    in ordered passes: (1) Executive Summary, (2) Business, (3) Infra & Network,
    (4) Market & Distribution, (5) Strategic Recommendations. Each pass streams
    its own tokens, so total output length is effectively unbounded."""
    sys = COMPILER_SYS.format(
        territory_type=territory_type,
        territory_name=territory_name,
        language=language,
    )
    territory = f"{territory_type}: {territory_name}"
    all_sections = [_section_payload(dr) for dr in domain_results]
    groups = _group_sections(domain_results)

    def _run(part_name: str, instruction: str, sections: list[dict], max_tokens: int):
        payload = {"territory": territory, "part": part_name,
                   "instruction": instruction, "sections": sections}
        msgs = [
            {"role": "system", "content": sys},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False, default=str)},
        ]
        yield from llm.chat_stream_complete(msgs, model=config.LLM_MODEL_CODER, max_tokens=max_tokens)

    # Compile in 3 passes (fewer round-trips = lower latency, no truncation):
    #  Pass 1: Executive Summary + Business chunk
    #  Pass 2: Infrastructure & Network chunk
    #  Pass 3: Market & Distribution chunk + Strategic Recommendations
    part_titles = {
        "BUSINESS": "## Business — Revenue, Product, Subscriber, Acquisition, HVC",
        "INFRA_NET": "## Infrastructure & Network — Sites, FWA, FTTH, 5G, Network Condition & Competition",
        "MARKET_DIST": "## Market & Distribution — Market Share, SOGA, Churn Share, Channel Trade (Primary/Secondary/Tertiary)",
    }
    gmap = {name: bucket for name, bucket in groups}

    # Pass 1 — Exec Summary (compact view of all) + Business detail.
    biz = gmap.get("BUSINESS", [])
    yield from _run(
        "EXEC_AND_BUSINESS",
        "Write, in order: (1) '# Ringkasan Eksekutif' with 6-8 bullet key takeaways across "
        "revenue/product, subscriber, market share, network condition & competition, channel "
        "trade, and the top risks; then (2) the heading '"
        + part_titles["BUSINESS"] + "' with its detailed sections (data table + MoM/YoY/QoQ/6-month "
        "trend, arrows, 🔴/🟢). Finish every sentence.",
        biz, 5500)
    yield "\n\n"

    # Pass 2 — Infrastructure & Network.
    infra = gmap.get("INFRA_NET", [])
    if infra:
        yield from _run(
            "INFRA_NET",
            "Write the detailed sections under '" + part_titles["INFRA_NET"] + "'. For each: data "
            "table + trend (MoM/YoY/QoQ), arrows, 🔴/🟢. Include BOTH network condition (availability/"
            "SLA/congestion) AND network competition (FB speed/congestion + OpenSignal vs Telkomsel/XL/SF). "
            "Finish every sentence. Do NOT repeat earlier parts.",
            infra, 5000)
        yield "\n\n"

    # Pass 3 — Market & Distribution + Strategic Recommendations.
    mkt = gmap.get("MARKET_DIST", [])
    compact = [{"section_title": s["section_title"], "status": s.get("status"),
                "row_count": s.get("row_count", 0)} for s in all_sections]
    yield from _run(
        "MARKET_DIST_AND_RECO",
        "Write, in order: (1) the detailed sections under '" + part_titles["MARKET_DIST"] + "' "
        "(market share/SOGA/churn share vs Telkomsel/XL/SF, and channel trade Primary/Secondary/"
        "Tertiary with the secondary/primary & tertiary/secondary ratios); then (2) '# Rekomendasi "
        "Strategis' with 6-8 actionable, data-tied recommendations spanning revenue/product, network "
        "(condition & competitive gap), channel trade health, and competitive position. Finish every "
        "sentence. Do NOT repeat earlier parts.",
        mkt if mkt else compact, 5500)


def run_parallel_stream(sub_queries: list[dict], max_workers: int = 5,
                        territory_type: str = "kabkota",
                        territory_name: str = ""):
    """Generator variant of run_parallel: YIELDS each section result as soon as it
    completes. This keeps the SSE connection active (no long silent gap that can
    trip proxy/idle timeouts) for big profiles like circle-level."""
    import logging
    log = logging.getLogger("profile_engine")
    direct_sqls = _direct_sql_templates(territory_type, territory_name)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = {}
        for sq in sub_queries:
            title = sq.get("section_title", sq["domain"])
            if title in direct_sqls:
                f = pool.submit(_run_direct_sql, title, direct_sqls[title])
            else:
                f = pool.submit(_run_one_domain, sq["domain"], sq["question"], title)
            futures[f] = sq

        try:
            for f in as_completed(futures, timeout=180):
                sq = futures[f]
                try:
                    yield f.result(timeout=10)
                except Exception as e:
                    log.warning(f"[FAILED] {sq.get('section_title', '?')}: {e}")
                    yield {
                        "domain": sq["domain"],
                        "section_title": sq.get("section_title", sq["domain"]),
                        "question": sq["question"],
                        "error": str(e)[:300],
                        "rows": [], "columns": [], "row_count": 0,
                    }
        except Exception as e:
            log.warning(f"[run_parallel_stream timeout] {e}")
