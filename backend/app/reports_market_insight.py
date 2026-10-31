"""Market Insight Report — Monthly trends and MoM Growth for FB MS & SoGA."""
from __future__ import annotations

from typing import Optional
from . import config
from .bigquery_tool import run_query
from .territory import scope_column

_P = config.BQ_PROJECT
_D = config.BQ_DATASET

_MTH = f"`{_P}.{_D}.rham_mkt_highlevel_mth`"
_TERR = f"`{_P}.{_D}.rham_ref_territory`"

M2M_SECTIONS: list[dict] = [
    {"title": "FB Market Share", "prefix": "fb_ms",
     "actors": [("Industry", "industry"), ("IM3", "im3"), ("3ID", "3id"),
                ("TSEL", "tsel"), ("XL", "xl"), ("SF", "sf")]},
    {"title": "FB SoGA", "prefix": "fb_soga",
     "actors": [("Industry", "industry"), ("IM3", "im3"), ("3ID", "3id"),
                ("TSEL", "tsel"), ("XL", "xl"), ("SF", "sf")]},
]


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


def _circle_clause(circle: str) -> str:
    if (circle or "").strip().upper() == "ALL":
        return "1=1"
    return f"t.circle='{_esc(circle)}'"


def _terr_filter(filter_type: str, filter_value: str) -> str:
    if not filter_value:
        return ""
    col = scope_column(filter_type)
    return f" AND {col} = '{_esc(filter_value)}'" if col else ""


def build_market_insight(circle: str, filter_type: str = "all", filter_value: str = "", months: int = 6) -> dict:
    fc = _terr_filter(filter_type, filter_value)
    
    cols = []
    for sec in M2M_SECTIONS:
        for _label, key in sec["actors"]:
            c = f"{sec['prefix']}_{key}"
            cols.append(f"SUM(CASE WHEN m.brand='IM3' THEN m.{c} END) AS {c}")
    
    # also add churn for SoGA
    for key in ("im3", "3id", "tsel", "xl", "sf"):
        c = f"fb_churn_{key}"
        cols.append(f"SUM(CASE WHEN m.brand='IM3' THEN m.{c} END) AS {c}")
    
    sel = ",\n  ".join(cols)
    
    # We need the last `months` closed months.
    sql = f"""
WITH lastfull AS (
  SELECT MAX(m.month_id) m FROM {_MTH} m
  LEFT JOIN {_TERR} t ON m.kec_id = t.kec_id
  WHERE {_circle_clause(circle)}{fc} AND m.brand='IM3' AND m.fb_ms_industry IS NOT NULL
)
SELECT m.month_id,
  {sel}
FROM {_MTH} m
LEFT JOIN {_TERR} t ON m.kec_id = t.kec_id, lastfull
WHERE {_circle_clause(circle)}{fc} AND m.brand='IM3'
  AND CAST(m.month_id AS INT64) <= CAST(lastfull.m AS INT64)
  AND CAST(m.month_id AS INT64) > CAST(lastfull.m AS INT64) - {int(months) + 1}
GROUP BY m.month_id
ORDER BY m.month_id DESC
"""
    try:
        rows = run_query(sql, row_limit=int(months) + 2)["rows"]
    except Exception:
        rows = []
        
    def num(d, k):
        v = d.get(k)
        return float(v) if v is not None else 0.0

    # IOH is not a source column. It is the sum of its two brands, so every
    # actor lookup routes through here and the synthetic key is handled once.
    def actor_num(d, prefix, key):
        if key == "ioh":
            return num(d, f"{prefix}_im3") + num(d, f"{prefix}_3id")
        return num(d, f"{prefix}_{key}")

    # Display order: Industry, then the IOH group total, then its parts.
    panel_actors = [("Industry", "industry"), ("IOH", "ioh")] + [
        item for item in M2M_SECTIONS[0]["actors"] if item[1] != "industry"
    ]

    # New requirement: X=Month, Y=Operator. We will return data structured
    # as panels, where each panel represents a metric (e.g. MS %, MS Abs),
    # and contains operators -> values per month.
    
    # Pre-calculate metrics for all months (excluding the extra one used for growth calc)
    metrics_panels = []
    
    if len(rows) > 0:
        months_list = [str(r["month_id"]) for r in rows[:-1]] # exclude the last one used for growth
        
        def build_panel(title, kind, calc_func):
            actors_data = []
            for label, key in panel_actors:
                history = []
                for i in range(len(rows) - 1):
                    r = rows[i]
                    r_prev = rows[i+1]
                    val = calc_func(r, key)
                    val_prev = calc_func(r_prev, key)
                    growth = None
                    if val is not None and val_prev is not None and val_prev != 0:
                        if kind in ("pct_ms", "pct_soga"):
                            growth = val - val_prev # percentage point difference
                        else:
                            growth = (val - val_prev) / abs(val_prev) * 100
                    history.append({"value": val, "growth": growth})
                # Industry has no churn source, so it has no churn or net add
                # row either. Emit no row rather than a column of nulls.
                if all(point["value"] is None for point in history):
                    continue
                actors_data.append({
                    "actor": label,
                    "aggregate": key == "ioh",
                    "history": history,
                })
            return {"title": title, "kind": kind, "months": months_list, "actors": actors_data}
        
        # 1. FB MS %
        metrics_panels.append(build_panel("FB Market Share (%)", "pct_ms", 
            lambda r, k: (actor_num(r, "fb_ms", k) / num(r, "fb_ms_industry") * 100) if num(r, "fb_ms_industry") else None))
        
        # 2. FB MS Abs
        metrics_panels.append(build_panel("FB Market Share (Absolute)", "abs", 
            lambda r, k: actor_num(r, "fb_ms", k)))
            
        # 3. FB SoGA %
        metrics_panels.append(build_panel("FB Share of Gross Add (SoGA %)", "pct_soga", 
            lambda r, k: (actor_num(r, "fb_soga", k) / num(r, "fb_soga_industry") * 100) if num(r, "fb_soga_industry") else None))
            
        # 4. FB GA Abs
        metrics_panels.append(build_panel("FB Gross Add (Absolute)", "abs", 
            lambda r, k: actor_num(r, "fb_soga", k)))
            
        # 5. FB Churn Abs
        metrics_panels.append(build_panel("FB Churn (Absolute)", "abs", 
            lambda r, k: None if k == "industry" else actor_num(r, "fb_churn", k)))
            
        # 6. FB Net Add
        metrics_panels.append(build_panel("FB Net Add", "abs", 
            lambda r, k: None if k == "industry"
                else actor_num(r, "fb_soga", k) - actor_num(r, "fb_churn", k)))
            

    # determine data_as_of
    try:
        max_dt = run_query(f"SELECT MAX(dt_id_snapshot) m FROM {_MTH}", row_limit=2)["rows"][0]["m"]
    except Exception:
        max_dt = ""

    return {
        "scope": {"circle": circle, "filter_type": filter_type, "filter_value": filter_value, "data_as_of": max_dt},
        "panels": metrics_panels
    }
