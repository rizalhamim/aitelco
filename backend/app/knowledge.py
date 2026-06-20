"""Knowledge base loader and per-domain schema context builder."""
import json
from functools import lru_cache

from . import config


@lru_cache(maxsize=1)
def load_kb() -> dict:
    return json.loads(config.KB_PATH.read_text())


def domain_list() -> list[dict]:
    kb = load_kb()
    out = []
    for key, d in kb["domains"].items():
        out.append({
            "key": key,
            "label": d["label"],
            "description": d["description"],
            "table_count": d["table_count"],
            "tables": list(d["tables"].keys()),
        })
    return out


def domain_overview_text() -> str:
    """Compact routing context: domain -> label/desc/tables."""
    lines = []
    for d in domain_list():
        lines.append(f"- {d['key']} ({d['label']}): {d['description']}")
        lines.append(f"    tables: {', '.join(d['tables'])}")
    return "\n".join(lines)


def schema_for_domain(domain_key: str, max_cols_per_table: int = 60) -> str:
    """Full schema text for one domain's tables, for the SQL-writing agent.
    Includes per-column descriptions (`desc`) when present in the KB."""
    kb = load_kb()
    d = kb["domains"].get(domain_key)
    if not d:
        return ""
    proj, ds = kb["project"], kb["dataset"]
    parts = [f"Dataset: `{proj}.{ds}` (region {kb['region']})",
             f"Domain: {d['label']} — {d['description']}", ""]
    for tname, t in d["tables"].items():
        parts.append(f"TABLE `{proj}.{ds}.{tname}`  (~{t['rows']:,} rows)")
        cols = t["columns"][:max_cols_per_table]
        for c in cols:
            tag = " [PARTITION]" if c.get("partition") else ""
            desc = c.get("desc")
            if desc:
                parts.append(f"  - {c['name']} {c['type']}{tag} — {desc}")
            else:
                parts.append(f"  - {c['name']} {c['type']}{tag}")
        hidden = t["columns"][max_cols_per_table:]
        if hidden:
            # Show ALL column names so the LLM never hallucinates non-existent ones
            hidden_names = [c['name'] for c in hidden]
            parts.append(f"  ... (+{len(hidden)} more columns: {', '.join(hidden_names)})")
        parts.append("")
    return "\n".join(parts)


def agent_persona(domain_key: str) -> str:
    """Return the per-domain agent persona text, or '' if none defined."""
    kb = load_kb()
    d = kb["domains"].get(domain_key) or {}
    ag = d.get("agent")
    if not ag:
        return ""
    parts = [f"YOUR ROLE: You are the '{ag.get('name','Domain Analyst')}' agent."]
    if ag.get("persona"):
        parts.append(ag["persona"])
    if ag.get("key_facts"):
        parts.append("Key domain facts:")
        for f in ag["key_facts"]:
            parts.append(f"  - {f}")
    return "\n".join(parts)


def _find_table(kb, tname):
    for d in kb["domains"].values():
        if tname in d.get("tables", {}):
            return d["tables"][tname]
    return None


def schema_for_tables(table_names: list[str], max_cols_per_table: int = 40) -> str:
    """Schema text for a specific set of tables (across any domain)."""
    kb = load_kb()
    proj, ds = kb["project"], kb["dataset"]
    parts = []
    for tname in table_names:
        t = _find_table(kb, tname)
        if not t:
            continue
        parts.append(f"TABLE `{proj}.{ds}.{tname}`  (~{t['rows']:,} rows)")
        cols = t["columns"][:max_cols_per_table]
        for c in cols:
            tag = " [PARTITION]" if c.get("partition") else ""
            parts.append(f"  - {c['name']} {c['type']}{tag}")
        hidden = t["columns"][max_cols_per_table:]
        if hidden:
            hidden_names = [c['name'] for c in hidden]
            parts.append(f"  ... (+{len(hidden)} more columns: {', '.join(hidden_names)})")
        parts.append("")
    return "\n".join(parts)


# Site tables useful for map/coordinate queries (reference + cross-domain metrics)
MAP_SITE_TABLES = [
    "rham_site_wise_addr_java",   # coordinates + territory reference
    "rham_site_wise_monthly",     # revenue/subs/usage monthly
    "rham_site_wise_daily",       # revenue/subs/usage daily
    "rham_5g_site_monthly",       # 5G traffic/coverage
    "rham_site_fwa_daily",        # FWA
    "rham_avail_stat_site_monthly",  # availability 4G/5G
]


def map_site_schema() -> str:
    """Schema for the canonical site tables used in map/coordinate queries."""
    return schema_for_tables(MAP_SITE_TABLES)


def data_facts_text() -> str:
    kb = load_kb()
    return json.dumps(kb.get("data_facts", {}), indent=1)
