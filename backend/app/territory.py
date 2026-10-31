"""Public territory vocabulary after the 2026-10 hierarchy migration.

Warehouse column names still use branch and micro-cluster. The former area
is empty and must never be used as the new operational Area.
"""
import re

HIERARCHY_VERSION = "2026-10"
LEVEL_ALIASES = {"branch": "area", "microcluster": "district", "micro_cluster": "district", "mc": "district"}
LABELS = {"circle": "Circle", "region": "Region", "area": "Area", "district": "District",
          "kabkota": "Kab/Kota", "kecamatan": "Kecamatan", "supergtm": "Super GTM"}
REFERENCE_COLUMNS = {
    "circle": "circle", "region": "region", "area": "branch_im3",
    "district": "micro_cluster_im3", "kabkota": "kabkot", "kecamatan": "kec_id",
    "supergtm": "super_gtm", "island": "island",
}


def normalize_level(level: str) -> str:
    return LEVEL_ALIASES.get(level, level)


def preserve_requested_grain(original: str, rewritten: str) -> str:
    """A clarification/rephrase cannot silently change an explicit grouping."""
    pattern = r"\b(?:per|by|tiap|setiap|berdasarkan)\s+(micro\s+cluster|microcluster|district|area|branch|mc|kecamatan|kabupaten|kabkota|region|circle|site)\b"
    def grain(text):
        match = re.search(pattern, text or "", re.IGNORECASE)
        if not match:
            return None
        level = match.group(1).lower().replace(" ", "")
        return normalize_level(level)
    requested = grain(original)
    return original if requested and grain(rewritten) != requested else rewritten or original


def scope_column(level: str, alias: str = "t") -> str | None:
    column = REFERENCE_COLUMNS.get(normalize_level(level))
    return f"{alias}.{column}" if column else None


def public_territory(row: dict) -> dict:
    """Expose current labels while keeping physical column names separate."""
    return {
        "circle": row.get("circle"), "region": row.get("region"),
        "area": row.get("branch_im3") or row.get("branch"),
        "district": row.get("micro_cluster_im3") or row.get("im3_mc") or row.get("micro_cluster"),
        "kabkota": row.get("kabkot") or row.get("kabkota") or row.get("kabupaten"),
        "province": row.get("province") or row.get("provinsi"),
        "kecamatan": row.get("kecamatan"),
    }
