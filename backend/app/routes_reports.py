"""Daily Reports API - recreates the daily reporting views (live dashboards,
KPI tiles, brand-banded drill-down tables, slab distribution) outside of the
email/PDF/Excel pipeline.

Implements the Daily Snapshot report (single, switchable metric) per the
Bizplan Java Daily Reports engineering reference:
  - Brand model: IOH = IM3 + 3ID (no IOH rows; summed across brands).
  - Territory hierarchy: circle > region > area_im3 > branch_im3 > kabkot > kec_id.
  - Time windows: MTD (MAX month_id), LMTD (-1), LLMTD (-2) from the _mtd table.
  - Var (MoM abs) = mtd - lmtd ; Growth% = (mtd-lmtd)/lmtd*100.
  - Worst-first sort: every multi-row table ordered by Var IOH ascending.
  - Slab distribution: 8-bucket growth_pct histogram for health bars.

All queries hit rham_mkt_highlevel_mtd JOIN rham_ref_territory, capped by the
shared run_query byte/row guards.
"""
from __future__ import annotations

import math
from typing import Optional

from fastapi import APIRouter, Query
from pydantic import BaseModel

from . import config
from .bigquery_tool import run_query, QueryError
from . import reports_comprehensive
from . import reports_data
from . import reports_network
from . import reports_competitive
from . import reports_internal
from . import reports_fwa
from . import reports_market_insight
from . import reports_ftth
from . import reports_ftth_summary
from . import reports_city_profile as reports_profile_analysis
from . import reports_cache

router = APIRouter(prefix="/api/reports", tags=["reports"])

_PROJECT = config.BQ_PROJECT
_DATASET = config.BQ_DATASET
_MTD = f"`{_PROJECT}.{_DATASET}.rham_mkt_highlevel_mtd`"
_TERR = f"`{_PROJECT}.{_DATASET}.rham_ref_territory`"

CIRCLES = ["JAVA", "KALISUMAPA", "JAKARTA RAYA", "SUMATERA"]

# ── Metric catalog ──────────────────────────────────────────────────────────
# Each metric: code, name, unit, expr (raw SQL fragment, columns are unqualified
# from the highlevel table aliased `x`), category. `expr` may be a sum of cols.
METRICS: list[dict] = [
    # Revenue
    {"code": "rev_prepaid", "name": "Revenue Prepaid", "unit": "IDR", "expr": "x.rev_prepaid", "category": "Revenue"},
    {"code": "rev_data", "name": "Revenue Data", "unit": "IDR", "expr": "x.rev_data", "category": "Revenue"},
    {"code": "rev_voice", "name": "Revenue Voice", "unit": "IDR", "expr": "x.rev_voice", "category": "Revenue"},
    {"code": "rev_sms", "name": "Revenue SMS", "unit": "IDR", "expr": "x.rev_sms", "category": "Revenue"},
    {"code": "rev_base", "name": "Revenue Base", "unit": "IDR", "expr": "x.rev_base", "category": "Revenue"},
    {"code": "rev_acquisition_m0", "name": "Revenue Acquisition M0", "unit": "IDR", "expr": "x.rev_acquisition_m0", "category": "Revenue"},
    # Revenue ATL/BTL (rev_atl raw is empty → derive from gift+ori+renewal)
    {"code": "rev_atl", "name": "Revenue ATL", "unit": "IDR", "expr": "(x.rev_atl_gift + x.rev_atl_ori + x.rev_atl_renewal)", "category": "Revenue ATL/BTL"},
    {"code": "rev_atl_gift", "name": "Revenue ATL Gift", "unit": "IDR", "expr": "x.rev_atl_gift", "category": "Revenue ATL/BTL"},
    {"code": "rev_atl_ori", "name": "Revenue ATL Original", "unit": "IDR", "expr": "x.rev_atl_ori", "category": "Revenue ATL/BTL"},
    {"code": "rev_atl_renewal", "name": "Revenue ATL Renewal", "unit": "IDR", "expr": "x.rev_atl_renewal", "category": "Revenue ATL/BTL"},
    {"code": "rev_btl", "name": "Revenue BTL", "unit": "IDR", "expr": "x.rev_btl", "category": "Revenue ATL/BTL"},
    # Acquisition
    {"code": "gross_add", "name": "Gross Add", "unit": "Subs", "expr": "x.gross_add", "category": "Acquisition"},
    {"code": "ga_total", "name": "Gross Add Total", "unit": "Subs", "expr": "x.ga_total", "category": "Acquisition"},
    {"code": "ga_traditional", "name": "GA Trade (Traditional)", "unit": "Subs", "expr": "x.ga_traditional", "category": "Acquisition"},
    {"code": "ga_usage_100mb_plus", "name": "GA Usage 100MB+", "unit": "Subs", "expr": "x.ga_usage_100mb_plus", "category": "Acquisition"},
    {"code": "ga_usage_500mb_plus", "name": "GA Usage 500MB+", "unit": "Subs", "expr": "x.ga_usage_500mb_plus", "category": "Acquisition"},
    # Churn & Net Add
    {"code": "net_add_90d", "name": "Net Add 90D", "unit": "Subs", "expr": "x.net_add_90d", "category": "Churn & Net Add"},
    {"code": "gross_churn_90d", "name": "Gross Churn 90D", "unit": "Subs", "expr": "x.gross_churn_90d", "category": "Churn & Net Add"},
    {"code": "net_churn_90d", "name": "Net Churn 90D", "unit": "Subs", "expr": "x.net_churn_90d", "category": "Churn & Net Add"},
    # Subscriber
    {"code": "rgu_90d", "name": "RGU 90D", "unit": "Subs", "expr": "x.rgu_90d", "category": "Subscriber"},
    {"code": "rgu_30d", "name": "RGU 30D", "unit": "Subs", "expr": "x.rgu_30d", "category": "Subscriber"},
    {"code": "avg_vlr_daily", "name": "VLR Daily", "unit": "Subs", "expr": "x.avg_vlr_daily", "category": "Subscriber"},
    {"code": "pack_subs", "name": "Pack Subs", "unit": "Subs", "expr": "x.pack_subs", "category": "Subscriber"},
    {"code": "data_uu_30", "name": "Data Users 30D", "unit": "Subs", "expr": "x.data_uu_30", "category": "Subscriber"},
    # HVC
    {"code": "subs_hvc", "name": "Subscriber HVC", "unit": "Subs", "expr": "x.subs_hvc", "category": "HVC"},
    {"code": "subs_hvc_stay", "name": "HVC Stay", "unit": "Subs", "expr": "x.subs_hvc_stay", "category": "HVC"},
    {"code": "hvc_rev_total", "name": "Revenue HVC Total", "unit": "IDR", "expr": "x.hvc_rev_total", "category": "HVC"},
    {"code": "hvc_rev_organic", "name": "Revenue HVC Organic", "unit": "IDR", "expr": "x.hvc_rev_organic", "category": "HVC"},
    # Usage
    {"code": "usg_data_gb", "name": "Usage Data", "unit": "GB", "expr": "x.usg_data_gb", "category": "Usage"},
    {"code": "usg_og_voice_min", "name": "Usage Voice", "unit": "Min", "expr": "x.usg_og_voice_min", "category": "Usage"},
    {"code": "usg_og_sms_hit", "name": "Usage SMS", "unit": "Hits", "expr": "x.usg_og_sms_hit", "category": "Usage"},
    # Site (network-level; not brand-split meaningfully but kept simple)
    {"code": "total_site", "name": "Total Site", "unit": "Sites", "expr": "x.total_site", "category": "Site"},
    {"code": "addr_site", "name": "Addressable Site", "unit": "Sites", "expr": "x.addr_site", "category": "Site"},
    # FWA
    {"code": "fwa_rgu90", "name": "FWA RGU 90D", "unit": "Subs", "expr": "x.fwa_rgu90", "category": "FWA"},
    {"code": "rev_fwa_total", "name": "Revenue FWA Total", "unit": "IDR", "expr": "x.rev_fwa_total", "category": "FWA"},
    # Trade
    {"code": "num_outlet", "name": "Number of Outlets", "unit": "Outlets", "expr": "x.num_outlet", "category": "Trade"},
    {"code": "trade_demand", "name": "Trade Demand", "unit": "Subs", "expr": "x.trade_demand", "category": "Trade"},
]

_METRIC_BY_CODE = {m["code"]: m for m in METRICS}

# Territory drill levels: api level -> (grain column, parent label column)
LEVELS: dict[str, dict] = {
    "circle": {"col": "t.circle", "label": "circle", "parent": None},
    "region": {"col": "t.region", "label": "region", "parent": "t.circle"},
    "area": {"col": "t.area_im3", "label": "area", "parent": "t.region"},
    "branch": {"col": "t.branch_im3", "label": "branch", "parent": "t.area_im3"},
    "kabkota": {"col": "t.kabkot", "label": "kabkota", "parent": "t.branch_im3"},
    "kecamatan": {"col": "t.kec_id", "label": "kecamatan", "parent": "t.kabkot"},
    "microcluster": {"col": "t.micro_cluster_im3", "label": "microcluster", "parent": "t.branch_im3"},
    "supergtm": {"col": "t.super_gtm", "label": "supergtm", "parent": "t.region"},
}

# Parent filter column for drilling INTO a level (filter on the parent value)
DRILL_PARENT_COL = {
    "region": "t.circle",
    "area": "t.region",
    "branch": "t.area_im3",
    "kabkota": "t.branch_im3",
    "kecamatan": "t.kabkot",
}


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


def _is_all(circle: str) -> bool:
    return (circle or "").strip().upper() == "ALL"


def _circle_clause(circle: str, col: str = "t.circle") -> str:
    """WHERE fragment for the circle filter. 'ALL' → no restriction (1=1)."""
    if _is_all(circle):
        return "1=1"
    return f"{col} = '{_esc(circle)}'"


def _latest_month() -> int:
    r = run_query(f"SELECT MAX(month_id) AS m FROM {_MTD}")
    return int(r["rows"][0]["m"])


def _shift_month(month_id: int, delta: int) -> int:
    """Shift YYYYMM using calendar arithmetic, including January boundaries."""
    year, month = divmod(int(month_id), 100)
    absolute = year * 12 + month - 1 + delta
    return (absolute // 12) * 100 + absolute % 12 + 1


def _brand_split(expr: str, prefix: str) -> str:
    """Emit IOH/IM3/3ID columns for a value expression at one timeframe."""
    return (
        f"COALESCE(SUM({expr}),0) AS {prefix}_ioh, "
        f"COALESCE(SUM(CASE WHEN x.brand='IM3' THEN {expr} END),0) AS {prefix}_im3, "
        f"COALESCE(SUM(CASE WHEN x.brand='3ID' THEN {expr} END),0) AS {prefix}_3id"
    )


def _territory_filter(filter_type: str, filter_value: str) -> str:
    """Optional scope filter clause (ANDed)."""
    if not filter_value:
        return ""
    col = {
        "region": "t.region",
        "area": "t.area_im3",
        "branch": "t.branch_im3",
        "kabkota": "t.kabkot",
        "microcluster": "t.micro_cluster_im3",
        "supergtm": "t.super_gtm",
        "island": "t.island",
    }.get(filter_type)
    if not col:
        return ""
    return f" AND {col} = '{_esc(filter_value)}'"


def _level_summary(metric: dict, level: str, circle: str, month_id: int,
                   filter_clause: str, order: str = "var",
                   limit: Optional[int] = None) -> dict:
    """One brand-banded table for a territory level with LLMTD/LMTD/MTD x IOH/IM3/3ID
    plus abs_growth (Var IOH) and growth_pct."""
    lv = LEVELS[level]
    grain = lv["col"]
    parent = lv["parent"]
    expr = metric["expr"]
    lmtd = _shift_month(month_id, -1)
    llmtd = _shift_month(month_id, -2)

    parent_sel = f"MIN({parent}) AS parent," if parent else ""

    def block(alias: str, mid: int) -> str:
        return f"""{alias} AS (
  SELECT {grain} AS grain,
    {_brand_split(expr, 'v')}
  FROM {_MTD} x
  LEFT JOIN {_TERR} t ON x.kec_id = t.kec_id
  WHERE {_circle_clause(circle)}{filter_clause} AND x.month_id={mid} AND {grain} IS NOT NULL
  GROUP BY grain
)"""

    if order == "var":
        order_by = "ORDER BY abs_growth_ioh ASC"  # worst-first
    elif order == "mtd_desc":
        order_by = "ORDER BY mtd_ioh DESC"
    else:
        order_by = "ORDER BY abs_growth_ioh ASC"
    lim = f"\nLIMIT {limit}" if limit else ""

    # parent label must come from the MTD block; re-derive via a join to territory
    parent_join = ""
    parent_col = "CAST(NULL AS STRING) AS parent"
    if parent:
        parent_join = f"""LEFT JOIN (
  SELECT {grain} AS grain, MIN({parent}) AS parent
  FROM {_TERR} t
  WHERE {_circle_clause(circle)}{filter_clause} AND {grain} IS NOT NULL
  GROUP BY grain
) p ON m.grain = p.grain"""
        parent_col = "p.parent AS parent"

    sql = f"""
WITH
{block('mtd', month_id)},
{block('lmtd', lmtd)},
{block('llmtd', llmtd)}
SELECT
  m.grain AS name,
  {parent_col},
  COALESCE(l2.v_ioh,0) AS llmtd_ioh, COALESCE(l1.v_ioh,0) AS lmtd_ioh, m.v_ioh AS mtd_ioh,
  (m.v_ioh - COALESCE(l1.v_ioh,0)) AS abs_growth_ioh,
  SAFE_DIVIDE(m.v_ioh - COALESCE(l1.v_ioh,0), NULLIF(ABS(l1.v_ioh),0)) * 100 AS growth_pct,
  COALESCE(l2.v_im3,0) AS llmtd_im3, COALESCE(l1.v_im3,0) AS lmtd_im3, m.v_im3 AS mtd_im3,
  (m.v_im3 - COALESCE(l1.v_im3,0)) AS abs_growth_im3,
  SAFE_DIVIDE(m.v_im3 - COALESCE(l1.v_im3,0), NULLIF(ABS(l1.v_im3),0)) * 100 AS growth_pct_im3,
  COALESCE(l2.v_3id,0) AS llmtd_3id, COALESCE(l1.v_3id,0) AS lmtd_3id, m.v_3id AS mtd_3id,
  (m.v_3id - COALESCE(l1.v_3id,0)) AS abs_growth_3id,
  SAFE_DIVIDE(m.v_3id - COALESCE(l1.v_3id,0), NULLIF(ABS(l1.v_3id),0)) * 100 AS growth_pct_3id
FROM mtd m
LEFT JOIN lmtd l1 ON m.grain = l1.grain
LEFT JOIN llmtd l2 ON m.grain = l2.grain
{parent_join}
{order_by}{lim}
"""
    res = run_query(sql, row_limit=5000)
    return res


def _compute_slabs(rows: list[dict]) -> dict:
    """8-bucket growth_pct distribution (worst→best) for health bars."""
    out = {"total": 0, "declining": 0, "growing": 0,
           "decline_gt5": 0, "decline_3_5": 0, "decline_1_3": 0, "decline_0_1": 0,
           "growth_0_1": 0, "growth_1_3": 0, "growth_3_5": 0, "growth_gt5": 0}
    for r in rows:
        p = r.get("growth_pct")
        if p is None or (isinstance(p, float) and math.isnan(p)):
            continue
        out["total"] += 1
        if p < 0:
            out["declining"] += 1
            if p <= -5:
                out["decline_gt5"] += 1
            elif p <= -3:
                out["decline_3_5"] += 1
            elif p <= -1:
                out["decline_1_3"] += 1
            else:
                out["decline_0_1"] += 1
        else:
            out["growing"] += 1
            if p >= 5:
                out["growth_gt5"] += 1
            elif p >= 3:
                out["growth_3_5"] += 1
            elif p >= 1:
                out["growth_1_3"] += 1
            else:
                out["growth_0_1"] += 1
    return out


def _scale(peak: float, unit: str) -> dict:
    if unit == "GB" and peak >= 100_000:
        return {"divisor": 1_000, "unit": "K GB"}
    if peak >= 100_000_000:
        return {"divisor": 1_000_000, "unit": f"Mn {unit}"}
    if peak >= 100_000:
        return {"divisor": 1_000, "unit": f"K {unit}"}
    return {"divisor": 1, "unit": unit}


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/metrics")
def list_metrics():
    """Metric catalog for the Daily Snapshot picker, grouped by category."""
    cats: dict[str, list] = {}
    for m in METRICS:
        cats.setdefault(m["category"], []).append(
            {"code": m["code"], "name": m["name"], "unit": m["unit"]}
        )
    return {
        "metrics": [{"code": m["code"], "name": m["name"], "unit": m["unit"],
                     "category": m["category"]} for m in METRICS],
        "categories": [{"name": k, "metrics": v} for k, v in cats.items()],
        "circles": CIRCLES,
    }


@router.get("/latest-month")
def latest_month():
    try:
        return {"month_id": _latest_month()}
    except Exception as e:
        return {"error": str(e)[:300]}


@router.get("/territory-tree")
def territory_tree(circle: str = "JAVA"):
    """Region → Area → Branch tree for the scope picker."""
    try:
        sql = f"""
SELECT t.region, t.area_im3 AS area, t.branch_im3 AS branch
FROM {_TERR} t
WHERE {_circle_clause(circle)} AND t.region IS NOT NULL
GROUP BY t.region, t.area_im3, t.branch_im3
ORDER BY t.region, area, branch
"""
        res = run_query(sql, row_limit=5000)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}

    tree: dict = {}
    for r in res["rows"]:
        reg = r.get("region") or "N/A"
        area = r.get("area") or "N/A"
        br = r.get("branch")
        tree.setdefault(reg, {})
        tree[reg].setdefault(area, [])
        if br and br not in tree[reg][area]:
            tree[reg][area].append(br)
    return {
        "circle": circle,
        "tree": [
            {"region": reg,
             "areas": [{"area": a, "branches": brs} for a, brs in areas.items()]}
            for reg, areas in tree.items()
        ],
    }


# Map an api filter level to its territory column.
_SCOPE_COL = {
    "region": "t.region", "area": "t.area_im3", "branch": "t.branch_im3",
    "kabkota": "t.kabkot", "kecamatan": "t.kec_id",
    "microcluster": "t.micro_cluster_im3", "supergtm": "t.super_gtm",
}


@router.get("/scope-options")
def scope_options(
    circle: str = Query("JAVA"), 
    level: str = Query("region"),
    parent_type: str = Query(""),
    parent_value: str = Query("")
):
    """Distinct scope values for a territory level within a circle, optionally filtered by a parent."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    col = _SCOPE_COL.get(level)
    if not col:
        return {"error": f"unknown level '{level}'", "kind": "validation"}
    
    parent_filter = ""
    if parent_type and parent_value:
        pcol = _SCOPE_COL.get(parent_type)
        if pcol:
            parent_filter = f" AND {pcol} = '{_esc(parent_value)}'"
            
    try:
        sql = f"""
SELECT DISTINCT {col} AS value
FROM {_TERR} t
WHERE {_circle_clause(circle)} AND {col} IS NOT NULL {parent_filter}
ORDER BY value
"""
        res = run_query(sql, row_limit=10000)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
    return {"circle": circle, "level": level,
            "values": [r["value"] for r in res["rows"] if r.get("value")]}


class SnapshotResp(BaseModel):
    metric: dict
    scope: dict
    display: dict
    totals: dict
    best: Optional[dict] = None
    worst: Optional[dict] = None


@router.get("/snapshot")
def snapshot(
    metric: str = Query("rev_prepaid"),
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    month_id: Optional[int] = Query(None),
    refresh: bool = Query(False, description="bypass cache and rebuild"),
):
    """Daily Snapshot for one metric (cached, auto-refreshed when BQ dt_id_snapshot changes)."""
    if not _METRIC_BY_CODE.get(metric):
        return {"error": f"unknown metric '{metric}'", "kind": "validation"}
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{metric}|{circle}|{filter_type}|{filter_value}|{month_id}"
    return reports_cache.get_or_build(
        "snapshot", key,
        lambda: _snapshot_build(metric, circle, filter_type, filter_value, month_id),
        force=refresh)


@router.get("/map-explore")
def map_explore(
    metric: str = Query("rev_prepaid"),
    circle: str = Query("JAVA"),
    level: str = Query("kecamatan"),
    brand: str = Query("ioh"),
    value_mode: str = Query("growth", description="value|delta|growth"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    month_id: Optional[int] = Query(None),
):
    """Deterministic map exploration contract for the mobile Map Query page.

    This endpoint complements, but does not replace, the AI and nearest-site
    modes. It returns the complete selected territory grain without truncating
    top or bottom rows.
    """
    selected_metric = _METRIC_BY_CODE.get(metric)
    if not selected_metric:
        return {"error": f"unknown metric '{metric}'", "kind": "validation"}
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    if level not in LEVELS:
        return {"error": f"unknown level '{level}'", "kind": "validation"}
    if brand not in {"ioh", "im3", "3id"}:
        return {"error": f"unknown brand '{brand}'", "kind": "validation"}
    if value_mode not in {"value", "delta", "growth"}:
        return {"error": f"unknown value_mode '{value_mode}'", "kind": "validation"}

    try:
        mid = int(month_id) if month_id else _latest_month()
        result = _level_summary(
            selected_metric,
            level,
            circle,
            mid,
            _territory_filter(filter_type, filter_value),
            order="mtd_desc",
        )
    except QueryError as exc:
        return {"error": str(exc), "kind": "validation"}
    except Exception as exc:
        return {"error": str(exc)[:400], "kind": "execution"}

    suffix = "ioh" if brand == "ioh" else brand
    mtd_key = f"mtd_{suffix}"
    lmtd_key = f"lmtd_{suffix}"
    delta_key = f"abs_growth_{suffix}"
    growth_key = "growth_pct" if brand == "ioh" else f"growth_pct_{suffix}"
    inverse = any(
        token in metric.lower()
        for token in ("churn", "days_down", "downtime", "latency")
    )
    rows = []
    for raw in result.get("rows", []):
        current = raw.get(mtd_key)
        previous = raw.get(lmtd_key)
        delta = raw.get(delta_key)
        growth = raw.get(growth_key)
        value = {"value": current, "delta": delta, "growth": growth}[value_mode]
        favorable = None
        if value_mode != "value" and value is not None and float(value) != 0:
            favorable = float(value) < 0 if inverse else float(value) > 0
        rows.append({
            **raw,
            "geo_key": raw.get("name"),
            "territory_name": raw.get("name"),
            "value": value,
            "metric_value": current,
            "comparison_value": previous,
            "delta": delta,
            "growth": growth,
            "favorable": favorable,
        })

    available = [row for row in rows if row.get("value") is not None]
    descending = not inverse
    ranked = sorted(
        available,
        key=lambda row: (
            -float(row["value"]) if descending else float(row["value"]),
            str(row.get("territory_name") or ""),
        ),
    )
    rank_by_name: dict[str, int] = {}
    prior_value: float | None = None
    prior_rank = 0
    for index, row in enumerate(ranked, start=1):
        row_value = float(row["value"])
        if prior_value is None or row_value != prior_value:
            prior_rank = index
            prior_value = row_value
        rank_by_name[str(row.get("territory_name"))] = prior_rank
    for row in rows:
        row["rank"] = rank_by_name.get(str(row.get("territory_name")))

    present_values = [float(row["value"]) for row in available]
    id_geometry = level == "kecamatan"
    return {
        "schema_version": "map-explore.v1",
        "metric": {
            "code": selected_metric["code"],
            "name": selected_metric["name"],
            "unit": selected_metric["unit"],
            "category": selected_metric["category"],
            "inverse_polarity": inverse,
        },
        "scope": {
            "circle": circle,
            "level": level,
            "brand": brand,
            "month_id": mid,
            "comparison_month_id": _shift_month(mid, -1),
            "filter_type": filter_type,
            "filter_value": filter_value,
        },
        "value_mode": value_mode,
        "columns": list(rows[0].keys()) if rows else [],
        "rows": rows,
        "map_spec": {
            "mode": "choropleth",
            "level": level,
            "dissolve_by": "id" if id_geometry else "name",
            "geo_key": "geo_key",
            "group_key": "territory_name",
            "label_key": "territory_name",
            "metric_key": "value",
            "legend": f"{selected_metric['name']} · {value_mode}",
            "coloring": (
                "favorable_sign" if value_mode != "value" else "range"
            ),
        },
        "summary": {
            "territory_count": len(rows),
            "covered_count": len(available),
            "missing_count": len(rows) - len(available),
            "min": min(present_values) if present_values else None,
            "max": max(present_values) if present_values else None,
            "average": (
                sum(present_values) / len(present_values)
                if present_values else None
            ),
        },
        "meta": {
            "complete_grain": True,
            "bytes_processed": result.get("bytes_processed", 0),
            "source": "rham_mkt_highlevel_mtd",
        },
    }


def _snapshot_build(metric, circle, filter_type, filter_value, month_id):
    m = _METRIC_BY_CODE.get(metric)
    fc = _territory_filter(filter_type, filter_value)
    try:
        mid = int(month_id) if month_id else _latest_month()

        # 1. circle-level rows. When circle=ALL this returns one row per circle;
        #    KPI totals below sum across them.
        circ = _level_summary(m, "circle", circle, mid, fc, order="mtd_desc")
        crow = circ["rows"][0] if circ["rows"] else {}

        # 2. region summary (full table, MTD desc).
        region = _level_summary(m, "region", circle, mid, fc, order="mtd_desc")

        # 3. branch table for best/worst chips + slabs + deck.
        branch = _level_summary(m, "branch", circle, mid, fc, order="var")

        # 4. kecamatan table for the health distribution slabs.
        kec = _level_summary(m, "kecamatan", circle, mid, fc, order="var")

        # 5. full deck: top/bottom rankings (ref §4.3). Level summaries are
        #    ordered Var IOH ASC (worst-first): decline = head, growth = tail rev.
        mc = _level_summary(m, "microcluster", circle, mid, fc, order="var")
        kab = _level_summary(m, "kabkota", circle, mid, fc, order="var")
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:400], "kind": "execution"}

    brows = branch["rows"]
    # best/worst by Var IOH
    worst = brows[0] if brows else None
    best = brows[-1] if brows else None

    def _rankings(res: dict, n: int = 10) -> dict:
        """Top-10 decline (most negative Var) + top-10 growth (most positive),
        keeping full brand-banded rows so the UI renders them like the branch
        table."""
        rows = res["rows"]
        ranked = [r for r in rows if r.get("abs_growth_ioh") is not None]
        decline = ranked[:n]
        growth = list(reversed(ranked[-n:])) if ranked else []
        return {"columns": res["columns"], "decline": decline, "growth": growth}

    # KPI totals = sum across all circle rows (1 row for a single circle, N for ALL).
    def _sumk(rows, k):
        return sum(float(r.get(k) or 0) for r in rows)
    crows = circ["rows"]
    mtd_ioh = _sumk(crows, "mtd_ioh")
    lmtd_ioh = _sumk(crows, "lmtd_ioh")
    llmtd_ioh = _sumk(crows, "llmtd_ioh")
    mtd_im3 = _sumk(crows, "mtd_im3")
    mtd_3id = _sumk(crows, "mtd_3id")
    abs_change = mtd_ioh - lmtd_ioh
    pct_change = (abs_change / lmtd_ioh * 100) if lmtd_ioh else None

    # display scaling from peak across rendered tables
    peak = 0.0
    for r in [crow] + brows + kec["rows"]:
        for k in ("llmtd_ioh", "lmtd_ioh", "mtd_ioh"):
            peak = max(peak, abs(float(r.get(k) or 0)))
    disp = _scale(peak, m["unit"])

    kec_slabs = _compute_slabs(kec["rows"])
    branch_slabs = _compute_slabs(brows)

    deck = {
        "circle": {"columns": circ["columns"], "rows": circ["rows"]},
        "region": {"columns": region["columns"], "rows": region["rows"]},
        "branch": {"columns": branch["columns"], "rows": brows},
        "microcluster": _rankings(mc),
        "kabkota": _rankings(kab),
        "kecamatan": _rankings(kec),
        "counts": {
            "circle": len(circ["rows"]),
            "region": len(region["rows"]),
            "microcluster": len(mc["rows"]),
            "kabkota": len(kab["rows"]),
            "kecamatan": len(kec["rows"]),
            "branch": len(brows),
        },
    }

    return {
        "metric": {"code": m["code"], "name": m["name"], "unit": m["unit"], "category": m["category"]},
        "scope": {"circle": circle, "filter_type": filter_type,
                  "filter_value": filter_value, "month_id": mid,
                  "data_as_of": reports_cache.data_marker("highlevel")},
        "display": disp,
        "totals": {
            "mtd": mtd_ioh, "lmtd": lmtd_ioh, "llmtd": llmtd_ioh,
            "mtd_im3": mtd_im3, "mtd_3id": mtd_3id,
            "abs_change": abs_change, "pct_change": pct_change,
            "trend": "up" if abs_change >= 0 else "down",
        },
        "best": {"name": best.get("name"), "var": best.get("abs_growth_ioh"),
                 "pct": best.get("growth_pct")} if best else None,
        "worst": {"name": worst.get("name"), "var": worst.get("abs_growth_ioh"),
                  "pct": worst.get("growth_pct")} if worst else None,
        "branch": {"columns": branch["columns"], "rows": brows},
        "slabs": {"kecamatan": kec_slabs, "branch": branch_slabs},
        "deck": deck,
        "meta": {"bytes_processed": (circ.get("bytes_processed", 0)
                                     + branch.get("bytes_processed", 0)
                                     + kec.get("bytes_processed", 0))},
    }


def _guarded(builder):
    """Run a builder with the standard error envelope."""
    try:
        return builder()
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:400], "kind": "execution"}


@router.get("/comprehensive")
def comprehensive(
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    month_id: Optional[int] = Query(None),
    refresh: bool = Query(False),
):
    """Comprehensive multi-metric P&L brief (cached, auto-refreshed on dt_id_snapshot change)."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{filter_type}|{filter_value}|{month_id}"
    return reports_cache.get_or_build(
        "comprehensive", key,
        lambda: _guarded(lambda: reports_comprehensive.build_comprehensive(
            circle, month_id, filter_type, filter_value)),
        force=refresh)


@router.get("/data-revenue")
def data_revenue(
    circle: str = Query("JAVA"),
    month_id: Optional[int] = Query(None),
    brand: str = Query("ioh", description="ioh|im3|3id"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    refresh: bool = Query(False),
):
    """Prepaid Data Revenue (cached, auto-refreshed on as_of_dt change)."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{brand}|{month_id}|{filter_type}|{filter_value}"
    return reports_cache.get_or_build(
        "data-revenue", key,
        lambda: _guarded(lambda: reports_data.build_data_revenue(circle, month_id, brand, filter_type, filter_value)),
        force=refresh)


@router.get("/product-demand")
def product_demand(
    circle: str = Query("JAVA"),
    month_id: Optional[int] = Query(None),
    scope: str = Query("total", description="total|organic|digital|trade"),
    brand: str = Query("ioh", description="ioh|im3|3id"),
    refresh: bool = Query(False),
):
    """Product Demand (cached, auto-refreshed on as_of_dt change)."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{scope}|{brand}|{month_id}"
    return reports_cache.get_or_build(
        "product-demand", key,
        lambda: _guarded(lambda: reports_data.build_product_demand(circle, month_id, scope, brand)),
        force=refresh)


@router.get("/locate")
def locate(lat: float = Query(...), lon: float = Query(...)):
    """Lightweight: map a GPS point to its territory hierarchy (no reports).
    Used by My Coordinate to populate the level picker before loading a report."""
    from . import geo_locate
    loc = geo_locate.locate_kecamatan(lat, lon)
    if not loc or not loc.get("kec_id"):
        return {"error": "Koordinat tidak termasuk dalam wilayah yang dipetakan.", "kind": "not_found"}
    kid = str(loc["kec_id"]).replace("'", "")
    try:
        terr = run_query(
            f"SELECT circle, region, area_im3, branch_im3, micro_cluster_im3, kabkot, kecamatan "
            f"FROM {_TERR} WHERE kec_id='{kid}' LIMIT 1", row_limit=2)
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
    if not terr["rows"]:
        return {"error": "Kecamatan tidak ditemukan.", "kind": "not_found"}
    t = terr["rows"][0]
    return {
        "kec_id": kid, "circle": t.get("circle") or "JAVA",
        "levels": [
            {"level": "kecamatan", "label": "Kecamatan", "name": t.get("kecamatan"), "value": kid},
            {"level": "kabkota", "label": "Kab/Kota", "name": t.get("kabkot"), "value": t.get("kabkot")},
            {"level": "microcluster", "label": "Micro Cluster", "name": t.get("micro_cluster_im3"), "value": t.get("micro_cluster_im3")},
            {"level": "branch", "label": "Branch", "name": t.get("branch_im3"), "value": t.get("branch_im3")},
            {"level": "area", "label": "Area", "name": t.get("area_im3"), "value": t.get("area_im3")},
            {"level": "region", "label": "Region", "name": t.get("region"), "value": t.get("region")},
        ],
    }


@router.get("/my-coordinate")
def my_coordinate(
    lat: float = Query(...),
    lon: float = Query(...),
    month_id: Optional[int] = Query(None),
    refresh: bool = Query(False),
):
    """My Coordinate: locate the GPS point to a kecamatan via the SHP, resolve
    its full territory hierarchy, then return a Comprehensive payload for each
    level (kecamatan / kabkota / microcluster / branch / area / region) - same
    structure & UI as the Comprehensive report, scoped automatically."""
    from . import geo_locate
    loc = geo_locate.locate_kecamatan(lat, lon)
    if not loc or not loc.get("kec_id"):
        return {"error": "Koordinat tidak termasuk dalam wilayah Java yang dipetakan.",
                "kind": "not_found"}
    kid = str(loc["kec_id"]).replace("'", "")
    try:
        terr = run_query(
            f"SELECT circle, region, area_im3, branch_im3, micro_cluster_im3, kabkot, kecamatan "
            f"FROM {_TERR} WHERE kec_id='{kid}' LIMIT 1", row_limit=2)
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
    if not terr["rows"]:
        return {"error": "Kecamatan tidak ditemukan di tabel territory.", "kind": "not_found"}
    t = terr["rows"][0]
    circle = t.get("circle") or "JAVA"
    if circle not in CIRCLES:
        circle = "JAVA"

    # ordered levels (most specific → broadest)
    levels = [
        ("kecamatan", "Kecamatan", t.get("kecamatan"), kid),
        ("kabkota", "Kab/Kota", t.get("kabkot"), t.get("kabkot")),
        ("microcluster", "Micro Cluster", t.get("micro_cluster_im3"), t.get("micro_cluster_im3")),
        ("branch", "Branch", t.get("branch_im3"), t.get("branch_im3")),
        ("area", "Area", t.get("area_im3"), t.get("area_im3")),
        ("region", "Region", t.get("region"), t.get("region")),
    ]

    out_levels = []
    for ftype, label, name, fvalue in levels:
        if not fvalue:
            continue
        key = f"mycoord|{circle}|{ftype}|{fvalue}|{month_id}"
        payload = reports_cache.get_or_build(
            "comprehensive", key,
            lambda ft=ftype, fv=fvalue: _guarded(lambda: reports_comprehensive.build_comprehensive(
                circle, month_id, ft, fv)),
            force=refresh)
        out_levels.append({"level": ftype, "label": label, "name": name, "report": payload})

    return {
        "located": {"kec_id": kid, "kecamatan": t.get("kecamatan"), "kabkota": t.get("kabkot"),
                    "microcluster": t.get("micro_cluster_im3"), "branch": t.get("branch_im3"),
                    "area": t.get("area_im3"), "region": t.get("region"), "circle": circle,
                    "lat": lat, "lon": lon},
        "levels": out_levels,
    }


@router.get("/network-benchmark")
def network_benchmark(
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    refresh: bool = Query(False),
):
    """Network Benchmark (cached, auto-refreshed)."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{filter_type}|{filter_value}"

    def build_network_payload():
        legacy = reports_network.build_network_benchmark(
            circle, filter_type, filter_value)
        if filter_type not in {"all", "", "region", "kabkota", "kecamatan"}:
            catalog = reports_competitive.competitive_catalog()
            page = {
                "sections": catalog["sections"],
                "metrics": [
                    {
                        **metric,
                        "_served_availability": "unsupported",
                        "_served_source": None,
                        "_unavailable_reason": (
                            "Requested territory grain is not available for "
                            "Competitive."
                        ),
                    }
                    for metric in catalog["metrics"]
                ],
            }
            competitive = {
                **catalog,
                "report": "competitive",
                "available": False,
                "unavailable_reason": (
                    "Competitive supports circle, region, kabkota, and "
                    "metric-dependent kecamatan grain."
                ),
                "requested_filter_type": filter_type,
                "brands": ["IOH", "TSEL", "XLSMART"],
                "periods": [],
                "sections": reports_internal._sections_payload(
                    page, {}, [], None, ("IOH", "TSEL", "XLSMART")),
            }
        else:
            competitive = reports_competitive.build_competitive(
                circle, filter_type, filter_value)
        return {
            **legacy,
            "schema_version": "network-benchmark.v2",
            "competitive": competitive,
            "legacy": legacy,
        }

    return reports_cache.get_or_build(
        "network-benchmark", key,
        lambda: _guarded(build_network_payload),
        force=refresh)


@router.get("/fwa")
def fwa(
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    month_id: Optional[int] = Query(None),
    basis: str = Query("mtd", description="mtd|monthly"),
    refresh: bool = Query(False),
):
    """Complete 64-metric FWA Performance Outlook report."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{filter_type}|{filter_value}|{month_id}|{basis}"
    return reports_cache.get_or_build(
        "fwa",
        key,
        lambda: _guarded(lambda: reports_fwa.build_fwa(
            circle, month_id, filter_type, filter_value, basis)),
        force=refresh,
    )


@router.get("/internal-performance")
def internal_performance(
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    refresh: bool = Query(False),
):
    """Complete 229-metric Internal Net Performance report."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    if filter_type not in {"all", "", "region", "kabkota", "kecamatan"}:
        catalog = reports_internal.internal_catalog()
        page = {
            "sections": catalog["sections"],
            "metrics": [
                {
                    **metric,
                    "_served_availability": "unsupported",
                    "_served_source": None,
                    "_unavailable_reason": (
                        "Requested territory grain is not available for "
                        "Internal Net Performance."
                    ),
                }
                for metric in catalog["metrics"]
            ],
        }
        return {
            **catalog,
            "report": "internal",
            "available": False,
            "unavailable_reason": (
                "Internal Net Performance supports circle, region, kabkota, "
                "and kecamatan grain."
            ),
            "requested_filter_type": filter_type,
            "brands": ["IOH"],
            "periods": [],
            "sections": reports_internal._sections_payload(
                page, {}, [], None, ("IOH",)),
        }
    key = f"{circle}|{filter_type}|{filter_value}"
    return reports_cache.get_or_build(
        "internal-performance",
        key,
        lambda: _guarded(lambda: reports_internal.build_internal(
            circle, filter_type, filter_value)),
        force=refresh,
    )


@router.get("/market-insight")
def market_insight(
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    refresh: bool = Query(False),
):
    """Market Insight (cached, auto-refreshed)."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{filter_type}|{filter_value}"
    return reports_cache.get_or_build(
        "market-insight", key,
        lambda: _guarded(lambda: reports_market_insight.build_market_insight(circle, filter_type, filter_value)),
        force=refresh)

@router.get("/ftth")
def ftth(
    circle: str = Query("JAVA"),
    filter_type: str = Query("all"),
    filter_value: str = Query(""),
    refresh: bool = Query(False),
):
    """FTTH Performance Report (cached, auto-refreshed)."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    key = f"{circle}|{filter_type}|{filter_value}"

    def build_ftth_payload():
        legacy = reports_ftth.build_ftth(circle, filter_type, filter_value)
        if filter_type == "ftth_province" and filter_value:
            executive = {
                "schema_version": "ftth-summary.v1",
                "available": False,
                "unavailable_reason": (
                    "The FTTH kecamatan summary source has no province column. "
                    "The legacy FTTH report remains filtered by province."
                ),
                "catalog": reports_ftth_summary.catalog_payload("ftth"),
                "sections": [],
            }
        else:
            executive = reports_ftth_summary.build_ftth_summary(
                circle, None, filter_type, filter_value)
            executive["available"] = True
        return {
            **legacy,
            "schema_version": "ftth-report.v2",
            "executive_summary": executive,
            "legacy": legacy,
        }

    return reports_cache.get_or_build(
        "ftth", key,
        lambda: _guarded(build_ftth_payload),
        force=refresh)

_FTTH_SITEWISE = f"`{_PROJECT}.{_DATASET}.rham_ftth_sitewise_monthly`"
_FTTH_SCOPE_COL = {
    "ftth_region": "region_25",
    "ftth_province": "provinsi",
    "ftth_kabkota": "city",
    "ftth_kecamatan": "kecamatan",
}


@router.get("/ftth/scope-options")
def ftth_scope_options(
    circle: str = Query("JAVA"),
    level: str = Query("ftth_region"),
):
    """Distinct FTTH-native territory values for a level within a circle. FTTH
    uses its own vocabulary (region_25 / provinsi / city / kecamatan), not the
    IM3 ref_territory hierarchy, so options come straight from the sitewise table."""
    if not _is_all(circle) and circle not in CIRCLES:
        return {"error": f"unknown circle '{circle}'", "kind": "validation"}
    col = _FTTH_SCOPE_COL.get(level)
    if not col:
        return {"error": f"unknown level '{level}'", "kind": "validation"}
    provs = reports_ftth._circle_provinces(circle)
    prov_filter = "1=1" if _is_all(circle) else (
        "UPPER(provinsi) IN (" + ",".join(f"'{p}'" for p in provs) + ")")
    try:
        sql = f"""
SELECT DISTINCT {col} AS value
FROM {_FTTH_SITEWISE}
WHERE {prov_filter} AND {col} IS NOT NULL AND {col} != ''
ORDER BY value
"""
        res = run_query(sql, row_limit=10000)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}
    return {"circle": circle, "level": level,
            "values": [r["value"] for r in res["rows"] if r.get("value")]}


@router.get("/data-version")
def data_version():
    """Current data freshness markers (dt_id_snapshot / as_of_dt)."""
    return reports_cache.version()


@router.post("/cache/clear")
def cache_clear():
    n = reports_cache.clear()
    return {"cleared": n}
