"""Network Benchmark Report — FB Network & Availability stats.

Retrieves data from rham_fb_network_territory_wly_wide and 
rham_avail_stat_territory_monthly to provide a competitive view over the last 3 months.
"""
from __future__ import annotations

from typing import Optional
from . import config
from .bigquery_tool import run_query
import datetime

_P = config.BQ_PROJECT
_D = config.BQ_DATASET

_FB_NET = f"`{_P}.{_D}.rham_fb_network_territory_wly_wide`"
_AVAIL = f"`{_P}.{_D}.rham_avail_stat_territory_monthly`"


def _esc(v: str) -> str:
    return (v or "").replace("'", "")


# XL and SF are one commercial operator, XLSMART. Merge them the same way
# reports_competitive._facebook_query does: weight each member by its own
# sample count, never a plain average of two averages.
_XLSMART_MEMBERS = ("xl", "sf")
_FB_MEASURES = ("dl_speed", "latency", "signal")


def _xlsmart_select() -> str:
    # IFNULL keeps one member with no data from nulling the whole pair, and the
    # denominator only counts samples for weeks where that member reported.
    parts = []
    for measure in _FB_MEASURES:
        numerator = " + ".join(
            f"IFNULL(SUM({measure}_{member}_4g * sample_{member}_4g), 0)"
            for member in _XLSMART_MEMBERS
        )
        denominator = " + ".join(
            f"IFNULL(SUM(IF({measure}_{member}_4g IS NULL, NULL, sample_{member}_4g)), 0)"
            for member in _XLSMART_MEMBERS
        )
        parts.append(
            f"SAFE_DIVIDE({numerator}, {denominator}) as {measure}_xlsmart_4g"
        )
    return ",\n            ".join(parts)


def build_network_benchmark(circle: str, filter_type: str = "all", filter_value: str = "") -> dict:
    """Builds the network benchmark payload for the last 3 available months."""
    c = _esc(circle)
    # Determine the territory level filter
    t_level = "circle"
    t_name = c
    if filter_type not in (None, "", "all") and filter_value:
        t_level = _esc(filter_type)
        t_name = _esc(filter_value)
    
    if t_level == 'microcluster': t_level = 'micro_cluster'
    if t_level == 'kabkota': t_level = 'kabkot'

    # --- FB Network Data (Weekly data, we will aggregate to monthly for the last 3 months) ---
    # First, find the latest wk_end_dt
    try:
        mx_res = run_query(f"SELECT MAX(wk_end_dt) mx FROM {_FB_NET}")
        max_dt_str = mx_res["rows"][0]["mx"] if mx_res["rows"] else None
    except Exception:
        max_dt_str = None
        
    fb_data = []
    if max_dt_str:
        # Get data for the last ~12 weeks (approx 3 months)
        sql_fb = f"""
        SELECT
            SUBSTR(CAST(wk_end_dt AS STRING), 1, 7) as month_prefix,
            AVG(dl_speed_im3_4g) as dl_speed_im3_4g, AVG(latency_im3_4g) as latency_im3_4g, AVG(signal_im3_4g) as signal_im3_4g,
            AVG(dl_speed_tri_4g) as dl_speed_tri_4g, AVG(latency_tri_4g) as latency_tri_4g, AVG(signal_tri_4g) as signal_tri_4g,
            AVG(dl_speed_tsel_4g) as dl_speed_tsel_4g, AVG(latency_tsel_4g) as latency_tsel_4g, AVG(signal_tsel_4g) as signal_tsel_4g,
            AVG(dl_speed_xl_4g) as dl_speed_xl_4g, AVG(latency_xl_4g) as latency_xl_4g, AVG(signal_xl_4g) as signal_xl_4g,
            AVG(dl_speed_sf_4g) as dl_speed_sf_4g, AVG(latency_sf_4g) as latency_sf_4g, AVG(signal_sf_4g) as signal_sf_4g,
            {_xlsmart_select()}
        FROM {_FB_NET}
        WHERE territory_level = '{t_level}' AND territory_name = '{t_name}'
          AND wk_end_dt >= DATE_SUB(CAST('{max_dt_str}' AS DATE), INTERVAL 90 DAY)
        GROUP BY month_prefix
        ORDER BY month_prefix DESC
        LIMIT 3
        """
        try:
            fb_rows = run_query(sql_fb, row_limit=10)["rows"]
            fb_data = fb_rows
        except Exception as e:
            pass

    # --- Network Availability (Monthly data, last 3 months) ---
    try:
        mx_avail_res = run_query(f"SELECT MAX(month_id) mx FROM {_AVAIL}")
        max_avail_mth = mx_avail_res["rows"][0]["mx"] if mx_avail_res["rows"] else None
    except Exception:
        max_avail_mth = None

    avail_data = []
    if max_avail_mth:
        sql_avail = f"""
        SELECT 
            month_id,
            mean_avg_avail_pct_2g, mean_avg_avail_pct_4g, mean_avg_avail_pct_5g,
            min_avail_pct_2g, min_avail_pct_4g, min_avail_pct_5g,
            sites_below_sla99_4g, sites_below_sla95_4g,
            total_down_day_events_4g, total_downtime_hrs_4g
        FROM {_AVAIL}
        WHERE territory_level = '{t_level}' AND territory_name = '{t_name}'
        ORDER BY month_id DESC
        LIMIT 3
        """
        try:
            avail_rows = run_query(sql_avail, row_limit=10)["rows"]
            avail_data = avail_rows
        except Exception as e:
            pass

    return {
        "scope": {"circle": circle, "filter_type": filter_type, "filter_value": filter_value, "level_used": t_level, "name_used": t_name},
        "fb_benchmark": fb_data,
        "availability": avail_data
    }
