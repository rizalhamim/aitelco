"""Prepaid Data Revenue + Product Demand reports (reference Sections 6 & 7).

Both read the Kecamatan-level data-revenue family (filtered to kpi_group='REVENUE
DATA'); these tables carry circle/kabkota/kec_id directly (no territory join
needed). Brand model IOH = IM3 + 3ID as elsewhere.

Data Revenue (Section 6):
  - 3 chunks by atl_btl: Total / ATL / BTL.
  - Per chunk: headline (IOH/IM3/3ID) + per channel_group breakdown.
  - Price-slab group: 15 natural-order slabs with revenue + hit.

Product Demand (Section 7):
  - quota_data (GB) x validity (days) binned into a heatmap matrix (revenue),
    with MoM growth matrix, top-3 rank cells, and top products.
"""
from __future__ import annotations

from typing import Optional
from concurrent.futures import ThreadPoolExecutor

from . import config
from .bigquery_tool import run_query
from .territory import scope_column
from .reports_comprehensive import shift_month_id

_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET
_CHANNEL = f"`{_PROJECT}.{_DATASET}.rham_kec_data_rev_channel_mtd`"
_MTH = f"`{_PROJECT}.{_DATASET}.rham_kec_data_rev_channel_mth`"
_SLAB = f"`{_PROJECT}.{_DATASET}.rham_kec_data_rev_price_slab_mtd`"
_PRODUCT = f"`{_PROJECT}.{_DATASET}.rham_kec_data_rev_product_mtd`"

CIRCLES = ["JAVA", "KALISUMAPA", "JAKARTA RAYA", "SUMATERA"]

PRICE_SLAB_ORDER = [
    "0-10k", "10-20k", "20-30k", "30-40k", "40-50k", "50-60k", "60-70k",
    "70-80k", "80-90k", "90-100k", "100-150k", "150-200k", "200-500k",
    "500k-1Mn", "above 1Mn",
]

CHANNEL_GROUPS = ["ORGANIC", "DIGITAL DISTRIBUTION", "MOBO TRADE"]

# Quota (GB) bins — 9 visible (No Data Quota + Other collapsed per reference)
QUOTA_BINS = [
    ("0-1 GB", 0, 1), ("1-3 GB", 1, 3), ("3-5 GB", 3, 5), ("5-10 GB", 5, 10),
    ("10-15 GB", 10, 15), ("15-25 GB", 15, 25), ("25-50 GB", 25, 50), (">50 GB", 50, 1e9),
]
# Validity (days) bins — 7 visible
VALIDITY_BINS = [
    ("0-7D", 0, 7), ("8-14D", 7, 14), ("15-30D", 14, 30), ("31-60D", 30, 60),
    ("61-90D", 60, 90), ("91-180D", 90, 180), (">180D", 180, 1e9),
]


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


_TERR = f"`{_PROJECT}.{_DATASET}.rham_ref_territory`"


def _circle_clause(circle: str, alias: str = "") -> str:
    """circle filter (these tables carry their own `circle` column); ALL → 1=1."""
    col = f"{alias}.circle" if alias else "circle"
    if (circle or "").strip().upper() == "ALL":
        return "1=1"
    return f"{col}='{_esc(circle)}'"


def _scope_filter(filter_type: str, filter_value: str) -> tuple[str, str]:
    """Return (extra_join_sql, extra_where_sql) for a territory scope filter.
    kabkota/kecamatan are on the fact table directly; region/area/branch/etc
    require joining the territory dimension on kec_id."""
    if not filter_value or filter_type in (None, "", "all"):
        return "", ""
    fv = _esc(filter_value)
    if filter_type == "kabkota":
        return "", f" AND f.kabkota='{fv}'"
    if filter_type == "kecamatan":
        return "", f" AND f.kec_id='{fv}'"
    col = scope_column(filter_type)
    if not col:
        return "", ""
    join = f" JOIN {_TERR} t ON f.kec_id = t.kec_id"
    return join, f" AND {col}='{fv}'"


def _data_as_of() -> str:
    """Freshness marker (as_of_dt) of the data-revenue source tables."""
    try:
        r = run_query(f"SELECT MAX(as_of_dt) AS m FROM {_CHANNEL}", row_limit=2)
        v = r["rows"][0].get("m") if r["rows"] else None
        return str(v) if v is not None else ""
    except Exception:
        return ""


def _brand_clause(brand: str, alias: str = "") -> str:
    """SQL filter for the selected brand. 'ioh' = both brands (no filter)."""
    col = f"{alias}.brand" if alias else "brand"
    b = (brand or "ioh").lower()
    if b == "im3":
        return f" AND {col}='IM3'"
    if b in ("3id", "id3"):
        return f" AND {col}='3ID'"
    return ""


def _latest_month(table: str) -> int:
    # month_id is stored as STRING in these tables; CAST for MAX.
    r = run_query(f"SELECT MAX(CAST(month_id AS INT64)) AS m FROM {table}")
    return int(r["rows"][0]["m"])


def _quota_case() -> str:
    parts = []
    for lbl, lo, hi in QUOTA_BINS:
        parts.append(f"WHEN quota_data > {lo} AND quota_data <= {hi} THEN '{lbl}'")
    return "CASE " + " ".join(parts) + " ELSE 'Other' END"


def _validity_case() -> str:
    parts = []
    for lbl, lo, hi in VALIDITY_BINS:
        parts.append(f"WHEN validity > {lo} AND validity <= {hi} THEN '{lbl}'")
    return "CASE " + " ".join(parts) + " ELSE 'Other' END"


# ── Data Revenue ─────────────────────────────────────────────────────────────

def _ytd_lytd_months(mid: int) -> tuple[list[int], list[int]]:
    year, mm = mid // 100, mid % 100
    ytd = [year * 100 + i for i in range(1, mm + 1)]
    lytd = [(year - 1) * 100 + i for i in range(1, mm + 1)]
    return ytd, lytd


def _fnum(r, k):
    return float((r or {}).get(k) or 0)


def _node(ioh, im3, id3, lm, llm, ytd, lytd, contrib_base=None):
    """Build a full brand-banded record with MoM + YoY for a revenue node."""
    rec = {
        "ioh": ioh, "im3": im3, "3id": id3,
        "lmtd": lm, "llmtd": llm,
        "var_mom": ioh - lm,
        "growth_mom_pct": ((ioh - lm) / lm * 100) if lm else None,
        "ytd": ytd, "lytd": lytd,
        "var_yoy": ytd - lytd,
        "growth_yoy_pct": ((ytd - lytd) / lytd * 100) if lytd else None,
    }
    if contrib_base is not None:
        rec["contrib_pct"] = (ioh / contrib_base * 100) if contrib_base else None
    return rec


def _sum_product_months(query, table, months):
    """Bound additive product scans without dropping requested YTD months.

    Product history is unclustered and a whole-year detail scan can exceed the
    shared job budget. Two-month literal batches preserve every SUM bucket.
    Ratios and rankings are computed only after combining all batches.
    """
    batches = [months[i:i + 2] for i in range(0, len(months), 2)]
    if not batches:
        return {}
    def fetch(batch):
        return query(table, "f.month_id IN (" + ",".join(f"'{m}'" for m in batch) + ")")
    with ThreadPoolExecutor(max_workers=min(3, len(batches))) as pool:
        results = list(pool.map(fetch, batches))
    merged = {}
    for result in results:
        for key, row in result.items():
            if key not in merged:
                merged[key] = dict(row)
                continue
            for column in ("ioh", "im3", "id3", "hit"):
                if column not in row:
                    continue
                a, b = merged[key].get(column), row.get(column)
                merged[key][column] = None if a is None and b is None else (a or 0) + (b or 0)
    return merged


def build_data_revenue(circle: str, month_id: Optional[int], brand: str = "ioh",
                       filter_type: str = "all", filter_value: str = "") -> dict:
    mid = int(month_id) if month_id else _latest_month(_CHANNEL)
    lmtd, llmtd = shift_month_id(mid, -1), shift_month_id(mid, -2)
    bc = _brand_clause(brand, alias="f")
    cc = _circle_clause(circle, alias="f")
    sj, sw = _scope_filter(filter_type, filter_value)  # scope join + where
    ytd_months, lytd_months = _ytd_lytd_months(mid)

    def _grp_query(table: str, month_filter: str) -> dict:
        """SUM(revenue) grouped by atl_btl+channel_group+channel_detail (IOH +
        IM3 + 3ID) for the given month filter. Returns {(ab,cg,cd): row}."""
        sql = f"""
SELECT f.atl_btl AS atl_btl, f.channel_group AS channel_group, f.channel_detail AS channel_detail,
  COALESCE(SUM(f.revenue),0) AS ioh,
  COALESCE(SUM(CASE WHEN f.brand='IM3' THEN f.revenue END),0) AS im3,
  COALESCE(SUM(CASE WHEN f.brand='3ID' THEN f.revenue END),0) AS id3
FROM {table} f{sj}
WHERE {cc} AND f.kpi_group='REVENUE DATA'{bc}{sw} AND {month_filter}
GROUP BY atl_btl, channel_group, channel_detail
"""
        r = run_query(sql, row_limit=8000)
        return {(x.get("atl_btl"), x.get("channel_group"), x.get("channel_detail")): x
                for x in r["rows"]}

    def _f(r, k):
        return float((r or {}).get(k) or 0)

    mid_ly = mid - 100  # same month, previous year
    prior = [x for x in ytd_months if x != mid]           # Jan..mid-1 (this year)
    prior_ly = [x for x in lytd_months if x != mid_ly]    # Jan..mid-1 (last year)

    m_mtd = _grp_query(_CHANNEL, f"f.month_id='{mid}'")
    m_lmtd = _grp_query(_CHANNEL, f"f.month_id='{lmtd}'")
    m_llmtd = _grp_query(_CHANNEL, f"f.month_id='{llmtd}'")
    # Apple-to-apple YTD vs LYTD: both = prior FULL months (_mth) + PARTIAL current
    # month from the cutoff-capped MTD table (_channel). The current month last
    # year (mid_ly) must come from _channel (MTD), NOT _mth (full month).
    m_ytd_prior = _grp_query(_MTH, "f.month_id IN (" + ",".join(f"'{x}'" for x in prior) + ")") if prior else {}
    m_lytd_prior = _grp_query(_MTH, "f.month_id IN (" + ",".join(f"'{x}'" for x in prior_ly) + ")") if prior_ly else {}
    m_lytd_cur = _grp_query(_CHANNEL, f"f.month_id='{mid_ly}'")

    keys = set(m_mtd) | set(m_lmtd) | set(m_llmtd) | set(m_ytd_prior) | set(m_lytd_prior) | set(m_lytd_cur)

    def chunk(name: str, predicate) -> dict:
        ksel = [k for k in keys if predicate(k)]
        def sums(mp, br):
            return sum(_fnum(mp.get(k), br) for k in ksel)
        # headline
        h_ioh = sums(m_mtd, "ioh")
        h = _node(h_ioh, sums(m_mtd, "im3"), sums(m_mtd, "id3"),
                  sums(m_lmtd, "ioh"), sums(m_llmtd, "ioh"),
                  sums(m_ytd_prior, "ioh") + h_ioh, sums(m_lytd_prior, "ioh") + sums(m_lytd_cur, "ioh"))
        channels = []
        for cg in CHANNEL_GROUPS:
            ck = [k for k in ksel if k[1] == cg]
            def csum(mp, br):
                return sum(_f(mp.get(k), br) for k in ck)
            c_ioh = csum(m_mtd, "ioh")
            cnode = _node(c_ioh, csum(m_mtd, "im3"), csum(m_mtd, "id3"),
                          csum(m_lmtd, "ioh"), csum(m_llmtd, "ioh"),
                          csum(m_ytd_prior, "ioh") + c_ioh, csum(m_lytd_prior, "ioh") + csum(m_lytd_cur, "ioh"),
                          contrib_base=h_ioh)
            # channel_detail — merge by detail across atl_btl
            dnames = {k[2] for k in ck}
            details = []
            for dn in dnames:
                dk = [k for k in ck if k[2] == dn]
                def dsum(mp, br):
                    return sum(_f(mp.get(k), br) for k in dk)
                d_ioh = dsum(m_mtd, "ioh")
                details.append({"detail": dn or "—", **_node(
                    d_ioh, dsum(m_mtd, "im3"), dsum(m_mtd, "id3"),
                    dsum(m_lmtd, "ioh"), dsum(m_llmtd, "ioh"),
                    dsum(m_ytd_prior, "ioh") + d_ioh, dsum(m_lytd_prior, "ioh") + dsum(m_lytd_cur, "ioh"),
                    contrib_base=c_ioh)})
            details.sort(key=lambda x: x["ioh"], reverse=True)
            channels.append({"channel": cg, **cnode, "details": details})
        return {"name": name, "headline": h, "channels": channels}

    chunks = [
        chunk("Total Channel", lambda k: True),
        chunk("ATL (Non CVM)", lambda k: k[0] == "ATL"),
        chunk("BTL (CVM)", lambda k: k[0] == "BTL"),
    ]

    # ATL vs BTL ratios (share of total + ratio)
    total_ioh = chunks[0]["headline"]["ioh"]
    atl_ioh = chunks[1]["headline"]["ioh"]
    btl_ioh = chunks[2]["headline"]["ioh"]
    ratios = {
        "atl_pct": (atl_ioh / total_ioh * 100) if total_ioh else None,
        "btl_pct": (btl_ioh / total_ioh * 100) if total_ioh else None,
        "atl_vs_btl": (atl_ioh / btl_ioh) if btl_ioh else None,
        # channel contribution % of total channel revenue
        "channel_pct": {c["channel"]: ((c["ioh"] / total_ioh * 100) if total_ioh else None)
                        for c in chunks[0]["channels"]},
    }

    # Price-slab tables — now broken down by channel_group + channel_detail
    # (these columns DO exist on the price_slab table). Each timeframe query is
    # keyed by (channel_group, channel_detail, price_slab).
    def _slab_query(table: str, month_filter: str) -> dict:
        sql = f"""
SELECT f.channel_group AS channel_group, f.channel_detail AS channel_detail, f.price_slab AS price_slab,
  COALESCE(SUM(f.revenue),0) AS ioh,
  COALESCE(SUM(CASE WHEN f.brand='IM3' THEN f.revenue END),0) AS im3,
  COALESCE(SUM(CASE WHEN f.brand='3ID' THEN f.revenue END),0) AS id3,
  COALESCE(SUM(f.hit),0) AS hit
FROM {table} f{sj}
WHERE {cc}{bc}{sw} AND {month_filter}
GROUP BY channel_group, channel_detail, price_slab
"""
        r = run_query(sql, row_limit=8000)
        return {(x.get("channel_group"), x.get("channel_detail"), x.get("price_slab")): x
                for x in r["rows"]}

    _SLAB_MTH = _SLAB.replace("_mtd", "_mth")
    ps_mtd = _slab_query(_SLAB, f"f.month_id='{mid}'")
    ps_lmtd = _slab_query(_SLAB, f"f.month_id='{lmtd}'")
    ps_llmtd = _slab_query(_SLAB, f"f.month_id='{llmtd}'")
    ps_ytd_prior = _slab_query(_SLAB_MTH, "f.month_id IN (" + ",".join(f"'{x}'" for x in prior) + ")") if prior else {}
    ps_lytd_prior = _slab_query(_SLAB_MTH, "f.month_id IN (" + ",".join(f"'{x}'" for x in prior_ly) + ")") if prior_ly else {}
    ps_lytd_cur = _slab_query(_SLAB, f"f.month_id='{mid_ly}'")

    all_keys = set(ps_mtd) | set(ps_lmtd) | set(ps_llmtd) | set(ps_ytd_prior) | set(ps_lytd_prior) | set(ps_lytd_cur)

    def _slab_rows(predicate) -> list:
        """Build the 15 ordered slab rows (full timeframe) for keys matching
        `predicate(channel_group, channel_detail)`."""
        rows = []
        for s in PRICE_SLAB_ORDER:
            ksel = [k for k in all_keys if k[2] == s and predicate(k[0], k[1])]
            def ssum(mp, br):
                return sum(_fnum(mp.get(k), br) for k in ksel)
            ioh = ssum(ps_mtd, "ioh")
            node = _node(ioh, ssum(ps_mtd, "im3"), ssum(ps_mtd, "id3"),
                         ssum(ps_lmtd, "ioh"), ssum(ps_llmtd, "ioh"),
                         ssum(ps_ytd_prior, "ioh") + ioh, ssum(ps_lytd_prior, "ioh") + ssum(ps_lytd_cur, "ioh"))
            node["slab"] = s
            node["hit"] = ssum(ps_mtd, "hit")
            rows.append(node)
        return rows

    # Build scope tabs: total + each channel group, with channel_detail sub-tabs.
    slab_scopes = {"total": {"label": "Total", "slabs": _slab_rows(lambda g, d: True), "details": {}}}
    for cg in CHANNEL_GROUPS:
        key = cg.lower().split()[0]  # organic / digital / mobo
        if key == "mobo":
            key = "trade"
        dnames = sorted({k[1] for k in all_keys if k[0] == cg and k[1]})
        details = {dn: _slab_rows(lambda g, d, _cg=cg, _dn=dn: g == _cg and d == _dn) for dn in dnames}
        slab_scopes[key] = {"label": cg.title(), "channel_group": cg,
                            "slabs": _slab_rows(lambda g, d, _cg=cg: g == _cg),
                            "details": details}

    return {
        "scope": {"circle": circle, "month_id": mid, "brand": brand, "data_as_of": _data_as_of()},
        "unit": "IDR",
        "chunks": chunks,
        "ratios": ratios,
        "price_slabs": slab_scopes["total"]["slabs"],  # backward-compat
        "price_slab_scopes": slab_scopes,
    }


# ── Product Demand ───────────────────────────────────────────────────────────

def build_product_demand(circle: str, month_id: Optional[int], scope: str = "total",
                         brand: str = "ioh", filter_type: str = "all", filter_value: str = "") -> dict:
    mid = int(month_id) if month_id else _latest_month(_PRODUCT)
    lmtd, llmtd = shift_month_id(mid, -1), shift_month_id(mid, -2)
    cir = _esc(circle)
    bc = _brand_clause(brand, alias="f")
    cc = _circle_clause(circle, alias="f")
    sj, sw = _scope_filter(filter_type, filter_value)

    scope_filter = {
        "total": "",
        "organic": " AND f.channel_group='ORGANIC'",
        "digital": " AND f.channel_group='DIGITAL DISTRIBUTION'",
        "trade": " AND f.channel_group='MOBO TRADE'",
    }.get(scope, "")

    qcase = _quota_case()
    vcase = _validity_case()
    base = (f"FROM {_PRODUCT} f{sj} WHERE {cc} AND f.kpi_group='REVENUE DATA'"
            f"{scope_filter}{bc}{sw}")

    # heatmap matrix: quota x validity revenue (mtd) + prev (lmtd) for growth
    sql = f"""
WITH cur AS (
  SELECT {qcase} AS quota_slab, {vcase} AS validity_slab,
    COALESCE(SUM(f.revenue),0) AS rev
  {base} AND f.month_id='{mid}'
  GROUP BY quota_slab, validity_slab
),
prev AS (
  SELECT {qcase} AS quota_slab, {vcase} AS validity_slab,
    COALESCE(SUM(f.revenue),0) AS rev_prev
  {base} AND f.month_id='{lmtd}'
  GROUP BY quota_slab, validity_slab
)
SELECT c.quota_slab, c.validity_slab, c.rev, COALESCE(p.rev_prev,0) AS rev_prev
FROM cur c LEFT JOIN prev p USING(quota_slab, validity_slab)
"""
    res = run_query(sql, row_limit=2000)
    cell = {(r["quota_slab"], r["validity_slab"]): r for r in res["rows"]}

    q_labels = [b[0] for b in QUOTA_BINS]
    v_labels = [b[0] for b in VALIDITY_BINS]
    rev_matrix, growth_matrix = [], []
    flat = []
    for q in q_labels:
        rev_row, gr_row = [], []
        for v in v_labels:
            r = cell.get((q, v), {})
            rev = float(r.get("rev") or 0)
            prev = float(r.get("rev_prev") or 0)
            growth = ((rev - prev) / prev * 100) if prev else None
            rev_row.append(rev)
            gr_row.append(growth)
            flat.append((q, v, rev))
        rev_matrix.append(rev_row)
        growth_matrix.append(gr_row)

    flat.sort(key=lambda x: x[2], reverse=True)
    top3 = [{"rank": i + 1, "quota": q, "validity": v, "value": rev}
            for i, (q, v, rev) in enumerate(flat[:3]) if rev > 0]

    # Top products
    prod_sql = f"""
SELECT product_group, family_group,
  COALESCE(SUM(revenue),0) AS rev,
  COALESCE(SUM(hit),0) AS hit
{base} AND f.month_id='{mid}' AND f.product_group IS NOT NULL
GROUP BY product_group, family_group
ORDER BY rev DESC
LIMIT 10
"""
    prod_res = run_query(prod_sql, row_limit=50)
    top_products = [{
        "product": r.get("product_group"), "family": r.get("family_group"),
        "rev": float(r.get("rev") or 0), "hit": float(r.get("hit") or 0),
    } for r in prod_res["rows"]]

    # ── Slab tables (Data-Revenue-style) per channel scope + full timeframe ──
    # Grouped once by channel_group + quota_slab + validity_slab; aggregated in
    # Python into quota-slab and validity-slab tables for each scope.
    cc = _circle_clause(circle, alias="f")
    pmth = _PRODUCT.replace("_mtd", "_mth")
    ytd_months, lytd_months = _ytd_lytd_months(mid)
    mid_ly = mid - 100
    prior = [x for x in ytd_months if x != mid]          # Jan..mid-1 (this year)
    prior_ly = [x for x in lytd_months if x != mid_ly]   # Jan..mid-1 (last year)

    # Slab queries grouped by channel_group + channel_detail + quota + validity.
    def _slabq(table, month_filter):
        sql = f"""
SELECT f.channel_group AS channel_group, f.channel_detail AS channel_detail, {qcase} AS quota_slab, {vcase} AS validity_slab,
  COALESCE(SUM(f.revenue),0) AS ioh,
  COALESCE(SUM(CASE WHEN f.brand='IM3' THEN f.revenue END),0) AS im3,
  COALESCE(SUM(CASE WHEN f.brand='3ID' THEN f.revenue END),0) AS id3
FROM {table} f{sj} WHERE {cc} AND f.kpi_group='REVENUE DATA'{bc}{sw} AND {month_filter}
GROUP BY channel_group, channel_detail, quota_slab, validity_slab
"""
        r = run_query(sql, row_limit=40000)
        return {(x.get("channel_group"), x.get("channel_detail"), x.get("quota_slab"), x.get("validity_slab")): x
                for x in r["rows"]}

    pq_mtd = _slabq(_PRODUCT, f"f.month_id='{mid}'")
    pq_lmtd = _slabq(_PRODUCT, f"f.month_id='{lmtd}'")
    pq_llmtd = _slabq(_PRODUCT, f"f.month_id='{llmtd}'")
    pq_ytd_prior = _sum_product_months(_slabq, pmth, prior)
    # LYTD = prior full months last year (_mth) + current month last year MTD (_mtd, cutoff-capped)
    pq_lytd_prior = _sum_product_months(_slabq, pmth, prior_ly)
    pq_lytd_cur = _slabq(_PRODUCT, f"f.month_id='{mid_ly}'")
    pkeys = set(pq_mtd) | set(pq_lmtd) | set(pq_llmtd) | set(pq_ytd_prior) | set(pq_lytd_prior) | set(pq_lytd_cur)

    SCOPE_CG = {"total": None, "organic": "ORGANIC", "digital": "DIGITAL DISTRIBUTION", "trade": "MOBO TRADE"}

    def _dim_rows(predicate, dim_idx, labels):
        """dim_idx: 2=quota_slab, 3=validity_slab. Sum keys matching predicate(cg,cd)."""
        rows = []
        for lab in labels:
            ksel = [k for k in pkeys if k[dim_idx] == lab and predicate(k[0], k[1])]
            def s(mp, br):
                return sum(_fnum(mp.get(k), br) for k in ksel)
            ioh = s(pq_mtd, "ioh")
            node = _node(ioh, s(pq_mtd, "im3"), s(pq_mtd, "id3"),
                         s(pq_lmtd, "ioh"), s(pq_llmtd, "ioh"),
                         s(pq_ytd_prior, "ioh") + ioh, s(pq_lytd_prior, "ioh") + s(pq_lytd_cur, "ioh"))
            node["slab"] = lab
            rows.append(node)
        return rows

    def _tables(predicate):
        return {"quota": _dim_rows(predicate, 2, q_labels),
                "validity": _dim_rows(predicate, 3, v_labels)}

    slab_scopes = {}
    for sk, cg in SCOPE_CG.items():
        label = "Total" if sk == "total" else (cg or sk).title()
        pred = (lambda g, d: True) if cg is None else (lambda g, d, _cg=cg: g == _cg)
        entry = {"label": label, **_tables(pred), "details": {}}
        if cg is not None:
            dnames = sorted({k[1] for k in pkeys if k[0] == cg and k[1]})
            entry["details"] = {dn: _tables(lambda g, d, _cg=cg, _dn=dn: g == _cg and d == _dn)
                                for dn in dnames}
        slab_scopes[sk] = entry

    # ── Top products per scope (full timeframe) ──
    def _prodq(table, month_filter):
        sql = f"""
SELECT f.channel_group AS channel_group, f.channel_detail AS channel_detail, f.product_group AS product_group, f.family_group AS family_group,
  COALESCE(SUM(f.revenue),0) AS ioh,
  COALESCE(SUM(CASE WHEN f.brand='IM3' THEN f.revenue END),0) AS im3,
  COALESCE(SUM(CASE WHEN f.brand='3ID' THEN f.revenue END),0) AS id3,
  COALESCE(SUM(f.hit),0) AS hit
FROM {table} f{sj} WHERE {cc} AND f.kpi_group='REVENUE DATA'{bc}{sw} AND {month_filter} AND f.product_group IS NOT NULL
GROUP BY channel_group, channel_detail, product_group, family_group
"""
        r = run_query(sql, row_limit=40000)
        return {(x.get("channel_group"), x.get("channel_detail"), x.get("product_group"), x.get("family_group")): x for x in r["rows"]}

    tp_mtd = _prodq(_PRODUCT, f"f.month_id='{mid}'")
    tp_lmtd = _prodq(_PRODUCT, f"f.month_id='{lmtd}'")
    tp_llmtd = _prodq(_PRODUCT, f"f.month_id='{llmtd}'")
    tp_ytd_prior = _sum_product_months(_prodq, pmth, prior)
    tp_lytd_prior = _sum_product_months(_prodq, pmth, prior_ly)
    tp_lytd_cur = _prodq(_PRODUCT, f"f.month_id='{mid_ly}'")
    tp_keys = set(tp_mtd) | set(tp_lmtd) | set(tp_llmtd) | set(tp_ytd_prior) | set(tp_lytd_prior) | set(tp_lytd_cur)

    def _top_products(cg, cd=None, n=10):
        prods = {}
        for k in tp_keys:
            if cg is not None and k[0] != cg:
                continue
            if cd is not None and k[1] != cd:
                continue
            pk = (k[2], k[3])
            prods.setdefault(pk, [])
            prods[pk].append(k)
        rows = []
        for (pg, fg), keys in prods.items():
            def s(mp, br):
                return sum(_fnum(mp.get(k), br) for k in keys)
            ioh = s(tp_mtd, "ioh")
            node = _node(ioh, s(tp_mtd, "im3"), s(tp_mtd, "id3"),
                         s(tp_lmtd, "ioh"), s(tp_llmtd, "ioh"),
                         s(tp_ytd_prior, "ioh") + ioh, s(tp_lytd_prior, "ioh") + s(tp_lytd_cur, "ioh"))
            node["product"] = pg
            node["family"] = fg
            node["hit"] = s(tp_mtd, "hit")
            rows.append(node)
        rows.sort(key=lambda x: x["ioh"], reverse=True)
        return rows[:n]

    for sk, cg in SCOPE_CG.items():
        slab_scopes[sk]["top_products"] = _top_products(cg)
        if cg is not None:
            for dn in slab_scopes[sk]["details"]:
                slab_scopes[sk]["details"][dn]["top_products"] = _top_products(cg, dn)

    return {
        "scope": {"circle": circle, "month_id": mid, "channel_scope": scope, "brand": brand,
                  "filter_type": filter_type, "filter_value": filter_value, "data_as_of": _data_as_of()},
        "unit": "IDR",
        "quota_labels": q_labels,
        "validity_labels": v_labels,
        "revenue_matrix": rev_matrix,
        "growth_matrix": growth_matrix,
        "top_3": top3,
        "top_products": top_products,
        "slab_scopes": slab_scopes,
    }
