"""Profile Analysis API Endpoint (formerly City Profile).
Wraps comprehensive data into the Profile Analysis scoring engine.
"""
from __future__ import annotations
import json
import os
from typing import Optional

from . import config
from . import reports_comprehensive
from . import reports_cache
from .profile_analysis_engine import computeProfile

_P = config.BQ_PROJECT
_D = config.BQ_DATASET

def load_config():
    path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "profile_analysis_config.json")
    with open(path, "r") as f:
        return json.load(f)

def load_mapping():
    path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "field_mapping.json")
    with open(path, "r") as f:
        return json.load(f)

def _find_metric(sections, code):
    """Find a metric by code across all grid sections. Returns IOH brand values."""
    for sec in sections:
        if sec.get("layout") == "grid":
            for m in sec.get("metrics", []):
                if m.get("code") == code:
                    return m.get("ioh", {})
    return None

def _find_m2m_row(sections, prefix, actor):
    """Find an actor's row in a flat M2M section."""
    for sec in sections:
        if sec.get("layout") == "flat" and sec.get("title", "").startswith(prefix):
            for row in sec.get("rows", []):
                if row.get("actor") == actor:
                    return row.get("cells", [])
    return None

def _find_m2m_rows(sections, prefix):
    """Get all rows from an M2M section."""
    for sec in sections:
        if sec.get("layout") == "flat" and sec.get("title", "").startswith(prefix):
            return sec.get("rows", [])
    return []

def _extract_metrics_from_comp(comp_data: dict, mapping: dict) -> dict:
    """Extracts all needed metrics with full period data from the comprehensive response."""
    sections = comp_data.get("sections", [])
    metrics_out = {}

    # Build a fast lookup: code -> IOH values dict
    code_map = {}
    for sec in sections:
        if sec.get("layout") == "grid":
            for m in sec.get("metrics", []):
                code_map[m.get("code", "")] = m.get("ioh", {})

    for out_key, m_def in mapping.items():
        src = m_def.get("source")

        if src == "m2m":
            # Market share / SoGA from flat M2M sections
            prefix = m_def.get("section_prefix", "")
            actor = m_def.get("actor", "IOH")
            col_idx = m_def.get("col_idx", 0)
            cells = _find_m2m_row(sections, prefix, actor)
            mtd = (cells[col_idx] if cells and len(cells) > col_idx else None)

            # For lmtd: M2M rows don't have lmtd data natively.
            # We only have the share% for the latest closed month.
            # So lmtd is None (engine treats None as 50).
            metrics_out[out_key] = {"mtd": mtd, "lmtd": None, "ytd": None, "lytd": None,
                                    "yoy": None, "mom": None}
            continue

        if src == "m2m_rank":
            rows = _find_m2m_rows(sections, "FB Market Share")
            ranked = sorted(
                [r for r in rows if r.get("actor") not in ("Industry",) and r.get("cells") and r["cells"][0] is not None],
                key=lambda x: x["cells"][0], reverse=True
            )
            mtd = None
            for idx, r in enumerate(ranked):
                if r["actor"] == "IM3":  # IOH proxy (M2M data only queried with IM3 brand)
                    mtd = idx + 1
                    break
            metrics_out[out_key] = {"mtd": mtd, "lmtd": None, "ytd": None, "lytd": None,
                                    "yoy": None, "mom": None}
            continue

        if src == "ratio":
            # Computed ratio from two comprehensive metric codes
            num_code = m_def.get("num_code")
            den_code = m_def.get("den_code")
            num_m = code_map.get(num_code, {})
            den_m = code_map.get(den_code, {})

            def safe_div(n, d):
                return (n / d * 100) if d and d != 0 else None

            mtd_v = safe_div(num_m.get("mtd"), den_m.get("mtd"))
            lmtd_v = safe_div(num_m.get("lmtd"), den_m.get("lmtd"))
            ytd_v = safe_div(num_m.get("ytd"), den_m.get("ytd"))
            lytd_v = safe_div(num_m.get("lytd"), num_m.get("lytd") is not None and den_m.get("lytd"))

            metrics_out[out_key] = {
                "mtd": mtd_v, "lmtd": lmtd_v, "ytd": ytd_v, "lytd": lytd_v,
                "yoy": safe_div(num_m.get("ytd"), den_m.get("lytd")) if den_m.get("lytd") else None,
                "mom": safe_div(num_m.get("mtd"), den_m.get("lmtd")) if den_m.get("lmtd") else None,
            }
            continue

        # Standard metric: lookup by comprehensive code
        comp_code = m_def.get("code", out_key)
        m_obj = code_map.get(comp_code)
        if m_obj is None:
            metrics_out[out_key] = {"mtd": None, "lmtd": None, "ytd": None, "lytd": None,
                                    "yoy": None, "mom": None}
            continue

        metrics_out[out_key] = {
            "mtd": m_obj.get("mtd"),
            "lmtd": m_obj.get("lmtd"),
            "ytd": m_obj.get("ytd"),
            "lytd": m_obj.get("lytd"),
            "yoy": m_obj.get("growth_yoy_pct"),
            "mom": m_obj.get("growth_mom_pct"),
        }

    return metrics_out


def get_geo_metrics(circle: str, geo_level: str, geo_value: str, month_id: Optional[int] = None) -> dict:
    comp_data = reports_comprehensive.build_comprehensive(circle, month_id, geo_level, geo_value)
    mapping = load_mapping()
    metrics = _extract_metrics_from_comp(comp_data, mapping)
    return {
        "geo_id": f"{geo_level}_{geo_value}".lower(),
        "geo_name": geo_value or circle,
        "level": geo_level,
        "parent_id": None,
        "as_of": comp_data["scope"].get("data_as_of"),
        "partial_month": True,
        "metrics": metrics,
    }

def get_peer_metrics(circle: str, geo_level: str, geo_value: str, month_id: Optional[int] = None) -> list:
    """Peers are expensive (N comprehensive queries). Skip for now."""
    return []

def build_profile_analysis(circle: str, geo_level: str, geo_value: str, month_id: Optional[int], lens: str, period: str) -> dict:
    cfg = load_config()
    target_data = get_geo_metrics(circle, geo_level, geo_value, month_id)
    peer_data = get_peer_metrics(circle, geo_level, geo_value, month_id)
    options = {"lens": lens, "period": period}
    profile = computeProfile(target_data, peer_data, cfg, options)
    return {"geo": target_data, "profile": profile}
