"""Knowledge loader, bounded retrieval, and prompt context builder."""
from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from . import config, knowledge_graph


@lru_cache(maxsize=1)
def load_kb() -> dict:
    return json.loads(config.KB_PATH.read_text())


def domain_list() -> list[dict]:
    kb = load_kb()
    out = []
    for key, domain in kb["domains"].items():
        tables = domain.get("tables", {})
        out.append({
            "key": key,
            "label": domain["label"],
            "description": domain["description"],
            "table_count": len(tables),
            "tables": list(tables),
            "metric_families": sorted({
                metric
                for table in tables.values()
                for metric in (table.get("metric_families") or [])
            }),
        })
    return out


def table_index() -> dict[str, dict[str, Any]]:
    kb = load_kb()
    index: dict[str, dict[str, Any]] = {}
    for domain_key, domain in kb.get("domains", {}).items():
        for table_name, table in domain.get("tables", {}).items():
            index[table_name] = {**table, "domain": domain_key}
    return index


def approved_table_names() -> set[str]:
    return {
        name for name, table in table_index().items()
        if table.get("status", "approved") == "approved"
    }


def blocked_table_names() -> set[str]:
    blocked: set[str] = set()
    groups = load_kb().get("data_facts", {}).get("banned_tables", {})
    if isinstance(groups, dict):
        for entry in groups.values():
            if isinstance(entry, dict):
                blocked.update(str(name) for name in entry.get("tables", []))
    return blocked


def domain_overview_text(question: str | None = None) -> str:
    """Compact routing context without dumping every physical table name."""
    lines = []
    q_tokens = knowledge_graph.tokenize(question)
    for domain in domain_list():
        if domain["table_count"] == 0:
            continue
        metrics = domain.get("metric_families") or []
        if q_tokens:
            metrics = sorted(
                metrics,
                key=lambda metric: (
                    -len(q_tokens.intersection(knowledge_graph.tokenize(metric))), metric
                ),
            )
        metric_text = ", ".join(metrics[:12]) if metrics else "general domain metrics"
        lines.append(
            f"- {domain['key']} ({domain['label']}): {domain['description']} "
            f"Capabilities: {metric_text}."
        )
    return "\n".join(lines)


def selection_for_question(
    domain_key: str,
    question: str,
    max_tables: int | None = None,
    table_hints: list[str] | None = None,
) -> dict[str, Any]:
    return knowledge_graph.select_tables(
        load_kb(), domain_key, question, max_tables=max_tables, table_hints=table_hints
    )


def _format_contract(table: dict[str, Any]) -> str:
    values = []
    for label, key in (
        ("status", "status"),
        ("source", "source_kind"),
        ("grain", "grain"),
        ("period", "period_semantics"),
        ("aggregation", "aggregation_rule"),
        ("territory", "territory_vocabulary"),
        ("cost", "cost_tier"),
    ):
        value = table.get(key)
        if value:
            values.append(f"{label}={value}")
    return "; ".join(values)


def _schema_for_named_tables(
    table_names: list[str],
    question: str = "",
    max_cols_per_table: int = 48,
) -> str:
    kb = load_kb()
    index = table_index()
    project, dataset = kb["project"], kb["dataset"]
    parts = [f"Dataset: `{project}.{dataset}` (region {kb['region']})", ""]
    for table_name in table_names:
        table = index.get(table_name)
        if not table or table.get("status", "approved") != "approved":
            continue
        parts.append(
            f"TABLE `{project}.{dataset}.{table_name}` (~{int(table.get('rows') or 0):,} rows)"
        )
        if table.get("description"):
            parts.append(f"  Purpose: {table['description']}")
        contract = _format_contract(table)
        if contract:
            parts.append(f"  Contract: {contract}")
        if table.get("metric_families"):
            parts.append("  Metrics: " + ", ".join(table["metric_families"]))
        for constraint in table.get("use_constraints", []) or []:
            parts.append(f"  Constraint: {constraint}")
        selected, omitted = knowledge_graph.select_columns(
            table, question, max_columns=max_cols_per_table
        )
        for column in selected:
            tag = " [PARTITION]" if column.get("partition") else ""
            description = column.get("desc")
            if description:
                parts.append(
                    f"  - {column['name']} {column['type']}{tag}: {description}"
                )
            else:
                parts.append(f"  - {column['name']} {column['type']}{tag}")
        if omitted:
            parts.append(
                f"  Other valid columns not expanded ({len(omitted)}): "
                + ", ".join(omitted)
            )
        parts.append("")
    return "\n".join(parts)


def schema_for_question(
    domain_key: str,
    question: str,
    max_cols_per_table: int = 48,
    max_tables: int | None = None,
    table_hints: list[str] | None = None,
) -> tuple[str, dict[str, Any]]:
    kb = load_kb()
    domain = kb["domains"].get(domain_key)
    if not domain:
        return "", {"tables": [], "confidence": 0.0}
    selection = selection_for_question(
        domain_key, question, max_tables=max_tables, table_hints=table_hints
    )
    question_tokens = knowledge_graph.tokenize(question)
    territory_columns = {
        "area": {"branch", "branch_im3"},
        "branch": {"branch"},
        "district": {"im3_mc", "micro_cluster_im3", "micro_cluster", "mc"},
        "circle": {"circle", "region_circle"},
        "kabkota": {"kabkota", "kabkot", "kabkot_nm", "city"},
        "kabkot": {"kabkota", "kabkot", "kabkot_nm", "city"},
        "kabupaten": {"kabkota", "kabkot", "kabkot_nm", "city"},
        "kecamatan": {"kec_id", "unik_kec", "kecamatan", "kecamatan_nm"},
        "kota": {"kabkota", "kabkot", "kabkot_nm", "city"},
        "province": {"province", "provinsi"},
        "provinsi": {"province", "provinsi"},
        "region": {"region", "sales_region"},
    }
    requested_columns = set().union(*(
        territory_columns[token]
        for token in question_tokens
        if token in territory_columns
    )) if question_tokens.intersection(territory_columns) else set()
    index = table_index()
    # A secondary source can require a territory join even when the first
    # retrieved table already has a native geography column.
    needs_reference = bool(requested_columns and any(
        not requested_columns.intersection({
            str(column.get("name", "")).lower()
            for column in index.get(name, {}).get("columns", [])
        })
        for name in selection["tables"]
    ))
    if needs_reference:
        reference = "zz_territory_kecamatan"
        if reference in approved_table_names() and reference not in selection["tables"]:
            selection["tables"].append(reference)
            selection.setdefault("reasons", {})[reference] = ["canonical_territory_reference"]
    header = (
        f"Domain: {domain['label']} - {domain['description']}\n"
        f"Retrieved tables: {', '.join(selection['tables']) or '(none)'}\n"
        f"Retrieval confidence: {selection.get('confidence', 0):.3f}\n\n"
    )
    return header + _schema_for_named_tables(
        selection["tables"], question, max_cols_per_table
    ), selection


def schema_for_domain(
    domain_key: str,
    max_cols_per_table: int = 48,
    question: str = "",
) -> str:
    """Compatibility wrapper using bounded retrieval, never a full-domain dump."""
    schema, _ = schema_for_question(
        domain_key,
        question or load_kb()["domains"].get(domain_key, {}).get("description", domain_key),
        max_cols_per_table=max_cols_per_table,
    )
    return schema


def agent_persona(domain_key: str) -> str:
    kb = load_kb()
    domain = kb["domains"].get(domain_key) or {}
    agent = domain.get("agent")
    if not agent:
        return ""
    if isinstance(agent, str):
        return f"YOUR ROLE: You are the '{agent}' agent."
    parts = [f"YOUR ROLE: You are the '{agent.get('name', 'Domain Analyst')}' agent."]
    if agent.get("persona"):
        parts.append(agent["persona"])
    if agent.get("key_facts"):
        parts.append("Key domain facts:")
        parts.extend(f"  - {fact}" for fact in agent["key_facts"])
    return "\n".join(parts)


def schema_for_tables(
    table_names: list[str], max_cols_per_table: int = 40, question: str = ""
) -> str:
    approved = approved_table_names()
    safe_names = [name for name in table_names if name in approved]
    return _schema_for_named_tables(safe_names, question, max_cols_per_table)


MAP_SITE_TABLES = [
    "rham_site_wise_addr_java",
    "rham_site_wise_monthly",
    "rham_site_wise_daily",
    "rham_5g_site_monthly",
    "rham_fwa_site_wise_daily",
    "rham_avail_stat_site_monthly",
]


def map_site_schema(question: str = "") -> str:
    return schema_for_tables(MAP_SITE_TABLES, question=question)


# Canonical territory reference. Most fact tables carry kabkota/kecamatan but NOT
# province, region, or branch, so a question like "kecamatan di Jawa Timur" can only
# be answered by joining this reference. It lives in the territory_reference domain,
# which means the policy gate rejects it for every other domain unless it is offered
# explicitly. Both objects are governance-approved.
TERRITORY_REF_TABLES = [
    "zz_territory_kecamatan",
    "rham_ref_territory",
]

_TERRITORY_REF_TERMS = (
    "province", "provinsi", "jawa timur", "jawa tengah", "jawa barat", "jatim",
    "jateng", "jabar", "region", "branch", "circle", "micro cluster", "microcluster",
    "wilayah", "area",
)


def question_needs_territory_ref(question: str) -> bool:
    lower = (question or "").lower()
    return any(term in lower for term in _TERRITORY_REF_TERMS)


def approved_territory_ref_tables() -> list[str]:
    """The reference tables that governance currently allows at runtime.

    Callers widen the SQL writer's allowed-table set with this, so it must go through
    the same approval filter the schema text does. A table that is quarantined or
    rejected later must silently drop out of both, not just out of the schema.
    """
    approved = approved_table_names()
    return [name for name in TERRITORY_REF_TABLES if name in approved]


def territory_ref_schema(question: str = "") -> str:
    return schema_for_tables(TERRITORY_REF_TABLES, question=question)


def _fact_score(key: str, value: Any, tokens: set[str], domain_key: str | None) -> int:
    text = key + " " + json.dumps(value, ensure_ascii=False, default=str)
    score = len(tokens.intersection(knowledge_graph.tokenize(text)))
    if key in {"territory_hierarchy", "source_grain_migration", "query_cost_policy"}:
        score += 30
    if key in {"banned_tables", "read_only", "query_guidance", "table_routing_constraints"}:
        score += 20
    if key in {"date_columns", "month_id_arithmetic", "month_id_casting", "partial_period_warning"}:
        score += 6
    if domain_key and domain_key in text.lower():
        score += 4
    return score


def data_facts_text(
    domain_key: str | None = None,
    question: str = "",
    max_chars: int = 12000,
) -> str:
    """Render only relevant global facts, while always keeping safety rules."""
    facts = load_kb().get("data_facts", {})
    tokens = knowledge_graph.tokenize(question)
    ranked = sorted(
        facts,
        key=lambda key: (-_fact_score(key, facts[key], tokens, domain_key), key),
    )
    selected: dict[str, Any] = {}
    for key in ranked:
        candidate = {**selected, key: facts[key]}
        rendered = json.dumps(candidate, ensure_ascii=False, indent=1)
        if len(rendered) > max_chars and selected:
            continue
        selected[key] = facts[key]
    return json.dumps(selected, ensure_ascii=False, indent=1)


def graph_health() -> dict[str, Any]:
    return knowledge_graph.graph_health(load_kb())


def table_contracts(table_names: list[str] | None = None) -> dict[str, dict[str, Any]]:
    index = table_index()
    names = table_names or list(index)
    return {name: index[name] for name in names if name in index}
