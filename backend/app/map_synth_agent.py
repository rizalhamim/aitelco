"""Map Synthesizer Agent.

The Map Query flow reuses the SAME domain reasoning as the chat AI agent
(analyst -> orchestrator route -> domain write_sql). The ONLY thing that differs
is the final step: instead of the generic business-narrative synthesizer, a
dedicated *map synthesizer* turns the query result into:

  1. a structured `map_spec` telling the frontend HOW to render the data
     (points vs choropleth, which columns are the id/lat/lon/metric, how to
     colour it, the legend label and a human title), and
  2. a short map-focused narrative (what the map shows, notable highs/lows).

This keeps a single brain (domain understanding) while giving map output its own
translator — symmetric with the normal synthesizer.
"""
from __future__ import annotations
import json
import re

from . import llm, config
from .orchestrator import IDENTITY


# ---- deterministic column detection (no LLM needed, robust) ----

_LAT_RE = re.compile(r"^(lat|latitude)$|_lat(itude)?$|^(addr_)?latitude$", re.I)
_LON_RE = re.compile(r"^(lon|long|longitude)$|_lon(g|gitude)?$|^(addr_)?longitude$", re.I)
_GROWTH_RE = re.compile(r"growth|pertumbuhan|change|delta|_pp$|_pct$|_pct_|trend|mom|yoy|qoq|naik|turun", re.I)
_EXCLUDE_METRIC_RE = re.compile(
    r"_id$|^provinsi$|^province$|^prov$|^kabupaten$|^kabkota$|^kabkot$|^kecamatan$|^kec$|"
    r"^region$|^area$|^branch$|^circle$|month|mth|periode?$|^dt_id|^site_id$|^outlet_id$|"
    r"^site_name$|^site_nm$|^outlet_name$|^nama",
    re.I,
)


def _first(cols, pred):
    for c in cols:
        if pred(c):
            return c
    return None


def detect_map_spec(columns: list[str], rows: list[dict]) -> dict:
    """Pure-Python classification of a result into a map render spec.
    Returns {mode: 'points'|'choropleth'|'none', ...}."""
    cols = list(columns or [])
    if not cols or not rows:
        return {"mode": "none", "reason": "empty_result"}

    lc = {c.lower(): c for c in cols}

    # --- choropleth: region key present ---
    # The map geometry is ALWAYS kecamatan-grain; higher levels (branch/region/
    # circle/area/kabupaten/province) are dissolved on the client by grouping the
    # kecamatan polygons on the requested `geo_level`. So the geometry join key is
    # kec_id (preferred); kabkot_id is supported for kabupaten-only results.
    kec_key = next((cols[i] for i, c in enumerate(cols) if c.lower() == "kec_id"), None)
    kab_key = next((cols[i] for i, c in enumerate(cols) if c.lower() == "kabkot_id"), None)
    region_key = kec_key or kab_key
    if region_key:
        # geo_level: prefer an explicit column from the agent; else infer.
        geo_level = None
        gl_col = lc.get("geo_level")
        if gl_col and rows and isinstance(rows[0].get(gl_col), str):
            geo_level = str(rows[0][gl_col]).strip().lower()
        if geo_level not in ("kecamatan", "kabupaten", "kabkota", "branch", "region", "circle", "area", "province"):
            geo_level = "kecamatan" if kec_key else "kabupaten"
        # readable label column for the level
        label_key = (
            lc.get(geo_level) or lc.get("territory_name") or lc.get("geo_name")
            or lc.get("branch") or lc.get("region") or lc.get("circle")
            or lc.get("area") or lc.get("kecamatan") or lc.get("kabupaten") or lc.get("kabkota")
            or lc.get("kabkot") or region_key
        )
        exclude = {region_key, label_key, gl_col} if gl_col else {region_key, label_key}
        metric_key = _pick_metric(cols, rows, exclude=exclude)
        if metric_key:
            signed = _is_signed_metric(metric_key, rows)
            return {
                "mode": "choropleth",
                "level": geo_level,                       # the dissolve level
                "geo_key": "kec_id" if kec_key else "kabkot_id",   # geometry join key
                "group_key": label_key,                   # value-by-territory grouping name
                "id_key": "kec_id" if kec_key else "kabkot_id",    # kept for back-compat
                "label_key": label_key,
                "metric_key": metric_key,
                "coloring": "sign" if signed else "range",
                "legend": _pretty(metric_key),
            }

    # --- points: lat/lon present ---
    lat_key = _first(cols, lambda c: bool(_LAT_RE.search(c)))
    lon_key = _first(cols, lambda c: bool(_LON_RE.search(c)))
    if lat_key and lon_key:
        label_key = (
            lc.get("site_name") or lc.get("site_nm") or lc.get("outlet_name")
            or _first(cols, lambda c: re.search(r"name|nama", c, re.I)) or cols[0]
        )
        metric_key = _pick_metric(cols, rows, exclude={lat_key, lon_key, label_key})
        return {
            "mode": "points",
            "lat_key": lat_key,
            "lon_key": lon_key,
            "label_key": label_key,
            "metric_key": metric_key,
            "coloring": "range",
            "legend": _pretty(metric_key) if metric_key else None,
        }

    # --- territory-level choropleth dissolved client-side via the territory ref ---
    # The agent naturally returns one row per territory (e.g. 12 regions). The map
    # dissolves kecamatan polygons by that level using zz_territory_kecamatan.
    # Supported levels map to a ref column the client loads.
    for lvl in ("kecamatan", "kabkota", "kabupaten", "branch", "region", "circle", "area", "province"):
        key = lc.get(lvl)
        if key:
            metric_key = _pick_metric(cols, rows, exclude={key})
            if metric_key:
                signed = _is_signed_metric(metric_key, rows)
                # normalise level name to the territory-ref column
                ref_level = {"kabupaten": "kabkota", "province": "province"}.get(lvl, lvl)
                return {
                    "mode": "choropleth",
                    "level": ref_level,
                    "dissolve_by": "name",     # join polygons by territory NAME via ref
                    "group_key": key,          # the territory-name column in the result
                    "metric_key": metric_key,
                    "coloring": "sign" if signed else "range",
                    "legend": _pretty(metric_key),
                }

    return {"mode": "none", "reason": "no_geo_columns"}


def _pick_metric(cols, rows, exclude: set[str]):
    cands = [
        c for c in cols
        if c not in exclude and not _EXCLUDE_METRIC_RE.search(c)
        and any(isinstance(r.get(c), (int, float)) for r in rows[:50])
    ]
    if not cands:
        return None
    # prefer a growth/change metric for colouring
    return next((c for c in cands if _GROWTH_RE.search(c)), cands[0])


def _is_signed_metric(metric_key: str, rows) -> bool:
    """A metric should be coloured by sign (green +, red −) when it is a
    growth/change metric OR when its values span both negative and positive."""
    if _GROWTH_RE.search(metric_key):
        return True
    has_neg = any(isinstance(r.get(metric_key), (int, float)) and r[metric_key] < 0 for r in rows[:200])
    has_pos = any(isinstance(r.get(metric_key), (int, float)) and r[metric_key] > 0 for r in rows[:200])
    return has_neg and has_pos


def _pretty(name) -> str:
    if not name:
        return ""
    return str(name).replace("_", " ").strip()


# ---- styling intent (AI-driven point colours + label) ----

_STYLE_SYS = (
    "You translate a user's MAP styling request into a small JSON styling spec. "
    "The data is being plotted on a map. Given the user's question and the available "
    "columns, output ONLY compact JSON describing how to style POINT markers and labels. "
    "Schema (all fields optional, omit if not requested):\n"
    "{\n"
    '  "point_rules": [   // ordered; first matching rule wins per row\n'
    '     {"rank_by": "<column>", "order": "asc|desc", "top": <N>, "color": "red|yellow|green|teal|pink|magenta|<hex>"},\n'
    '     {"where": "<column>", "op": "<|<=|>|>=|==", "value": <num>, "color": "..."},\n'
    '     {"default": true, "color": "..."}\n'
    "  ],\n"
    '  "label": {"column": "<column>", "format": "short|mn|bn|full|raw", "show": true}\n'
    "}\n"
    "Rules:\n"
    "- 'rank_by' picks the N extreme rows (e.g. '5 outlet terdekat' -> rank_by the distance column, order asc, top 5).\n"
    "- Use the column names EXACTLY as given. 'terdekat'/'nearest' -> the distance_km column if present.\n"
    "- Colour words map: merah=red, kuning=yellow, hijau=green, biru/teal=teal, pink, magenta.\n"
    "- For a value label like 'revenue dalam Mn' -> label.column=<the revenue column>, format='mn'. "
    "'dalam Bn'->'bn'; unspecified magnitude->'short'.\n"
    "- 'tambahkan/tampilkan <metric> di tooltip/label/node' OR 'tooltip <metric>' -> set "
    "label.column to the matching column (e.g. revenue, distance_km, subs, traffic) and show=true. "
    "Match the metric the user named to the closest available column name.\n"
    "- If the user gave NO styling/label request, output {}.\n"
    "Output JSON only, no prose."
)


def detect_style(question: str, spec: dict, columns: list[str]) -> dict:
    """Use the LLM to translate a styling request in the question into a styling
    spec (point colour rules + label config). Returns {} when nothing requested.
    Only meaningful for point maps; choropleth colour is metric-driven."""
    if spec.get("mode") != "points":
        return {}
    q = (question or "").lower()
    # cheap gate: only call the LLM when the user hints at styling/labels.
    # Broadened to catch tooltip/label phrasings (tooltip, tambahkan <metric>,
    # info, keterangan, di node/marker/titik, etc.).
    if not re.search(
        r"warna|warnai|merah|kuning|hijau|biru|label|tooltip|tool tip|"
        r"tampilkan\s+(nilai|revenue|angka|rev|metric)|tambah\w*\s+\w*\s*(revenue|rev|nilai|angka|info|kolom|param|metric|tooltip)|"
        r"di\s*(tooltip|label|node|marker|titik|popup)|info\b|keterangan|"
        r"satuan|dalam\s*(mn|bn|juta|miliar)|juta|miliar|color|highlight|tandai|beri\s+warna",
        q,
    ):
        return {}
    try:
        payload = {"question": question, "columns": columns,
                   "metric_key": spec.get("metric_key"), "label_key": spec.get("label_key")}
        msgs = [
            {"role": "system", "content": _STYLE_SYS},
            {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
        ]
        out = llm.chat_json(msgs, model=config.LLM_MODEL_FAST, max_tokens=500)
        return out if isinstance(out, dict) else {}
    except Exception:
        return {}


# ---- map-focused narrative (streamed) ----

MAP_SYNTH_SYS = IDENTITY + """

You are the MAP SYNTHESIZER agent of the IOH Java telco analytics AI. The data
shown to the user is being drawn on an interactive map (markers for sites/outlets,
or coloured regions for a choropleth). Write a SHORT narrative (reply in {language})
that helps the user read the MAP — not a generic table summary.

Rules:
- Lead with what the map shows (e.g. "Peta menampilkan 5 kecamatan di Kota Surabaya & Malang, diwarnai berdasarkan pertumbuhan revenue MTD vs LMTD").
- Call out the notable extremes that the colours encode: which region/site is highest (e.g. growth tertinggi / hijau paling pekat) and which is lowest (penurunan terdalam / merah paling pekat), with their numbers.
- If the metric is a growth/change: state how many grew vs declined.
- 3-5 short sentences max. No raw column names. Do NOT invent values not in the data.
- If the result is empty, say no data matched and suggest the likely filter cause.
"""


def synthesize_map_stream(question: str, result: dict, language: str,
                          explanation: str, map_spec: dict):
    """Yield narrative tokens for a map result. Mirrors orchestrator.synthesize
    but map-aware (knows the render mode + which column is coloured)."""
    preview = result["rows"][:60]
    payload = {
        "question": question,
        "what_it_computes": explanation,
        "map_render": {
            "mode": map_spec.get("mode"),
            "level": map_spec.get("level"),
            "metric": map_spec.get("metric_key"),
            "coloring": map_spec.get("coloring"),
        },
        "columns": result["columns"],
        "row_count": result["row_count"],
        "rows_preview": preview,
    }
    msgs = [
        {"role": "system", "content": MAP_SYNTH_SYS.format(language=language)},
        {"role": "user", "content": json.dumps(payload, ensure_ascii=False, default=str)},
    ]
    for tok in llm.chat_stream_complete(msgs, model=config.LLM_MODEL_CODER, max_tokens=1400):
        yield tok
