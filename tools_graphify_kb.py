"""Generate a safe, deterministic Graphify corpus from the runtime knowledge base.

The runtime JSON remains authoritative. This tool exports only schema metadata,
approved data facts, and domain key facts. It never imports backend configuration,
loads environment variables, or reads live data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
DEFAULT_SOURCE = ROOT / "backend" / "data" / "knowledge_base.json"
DEFAULT_OUTPUT = ROOT / "graphify-knowledge"
DEFAULT_GOVERNANCE = ROOT / "backend" / "governance" / "table_governance.json"
SOURCE_LABEL = "backend/data/knowledge_base.json"

ALLOWED_DATA_FACTS = {
    "banned_tables",
    "brands",
    "causal_analysis_flow",
    "circle_region_mapping",
    "competitive_tables",
    "customer_demand_tables",
    "date_columns",
    "date_ranges",
    "follow_up_handling",
    "forecast_tables",
    "ftth_tables",
    "hvc_source_status",
    "geography",
    "metric_prefixes",
    "month_id_arithmetic",
    "month_id_casting",
    "knowledge_governance",
    "operators_for_competitive",
    "partial_period_warning",
    "query_guidance",
    "query_cost_policy",
    "source_grain_migration",
    "territory_hierarchy",
    "read_only",
    "revenue_defaults",
    "runtime_graph",
    "site_kec_id_mapping",
    "table_grains",
    "table_routing_constraints",
    "window_filter_examples",
}


def clean(value: Any) -> str:
    """Return single-line Markdown-safe text without em dash characters."""
    text = str(value).replace("\u2014", " - ").replace("\r", " ").replace("\n", " ")
    return re.sub(r"\s+", " ", text).strip()


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def yaml_text(value: Any) -> str:
    return json.dumps(clean(value), ensure_ascii=False)


def scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return clean(value)


def flatten(value: Any, prefix: str = "value") -> list[tuple[str, str]]:
    """Flatten nested facts into explicit property paths for semantic extraction."""
    rows: list[tuple[str, str]] = []
    if isinstance(value, dict):
        for key in sorted(value):
            next_prefix = f"{prefix}.{key}" if prefix else str(key)
            rows.extend(flatten(value[key], next_prefix))
    elif isinstance(value, list):
        if all(not isinstance(item, (dict, list)) for item in value):
            rows.append((prefix, ", ".join(scalar(item) for item in value)))
        else:
            for index, item in enumerate(value):
                rows.extend(flatten(item, f"{prefix}[{index}]"))
    else:
        rows.append((prefix, scalar(value)))
    return rows


def load_and_validate(source: Path) -> tuple[dict[str, Any], bytes, list[str]]:
    raw = source.read_bytes()
    try:
        kb = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {source}: {exc}") from exc

    errors: list[str] = []
    warnings: list[str] = []
    for key in ("project", "dataset", "region", "domains", "data_facts"):
        if key not in kb:
            errors.append(f"missing top-level key: {key}")

    domains = kb.get("domains")
    if not isinstance(domains, dict):
        errors.append("domains must be an object")
        domains = {}

    table_owners: dict[str, str] = {}
    for domain_key, domain in domains.items():
        if not isinstance(domain, dict):
            errors.append(f"domains.{domain_key} must be an object")
            continue
        for required in ("label", "description", "tables"):
            if required not in domain:
                errors.append(f"domains.{domain_key} missing {required}")
        tables = domain.get("tables")
        if not isinstance(tables, dict):
            errors.append(f"domains.{domain_key}.tables must be an object")
            continue
        declared_count = domain.get("table_count")
        if declared_count != len(tables):
            errors.append(
                f"domains.{domain_key}.table_count is {declared_count}, expected {len(tables)}"
            )
        agent = domain.get("agent")
        if agent is not None and not isinstance(agent, (dict, str)):
            errors.append(f"domains.{domain_key}.agent must be an object or string")
        if isinstance(agent, str):
            warnings.append(
                f"domains.{domain_key}.agent is a legacy string; runtime agent_persona expects an object"
            )
        for table_name, table in tables.items():
            previous_owner = table_owners.get(table_name)
            if previous_owner:
                errors.append(
                    f"table {table_name} belongs to both {previous_owner} and {domain_key}"
                )
            table_owners[table_name] = domain_key
            if not isinstance(table, dict):
                errors.append(f"table {table_name} must be an object")
                continue
            columns = table.get("columns")
            if not isinstance(columns, list):
                errors.append(f"table {table_name}.columns must be an array")
                continue
            seen_columns: set[str] = set()
            for index, column in enumerate(columns):
                path = f"table {table_name}.columns[{index}]"
                if not isinstance(column, dict):
                    errors.append(f"{path} must be an object")
                    continue
                name = column.get("name")
                data_type = column.get("type")
                if not isinstance(name, str) or not name:
                    errors.append(f"{path}.name must be a non-empty string")
                elif name in seen_columns:
                    errors.append(f"table {table_name} has duplicate column {name}")
                else:
                    seen_columns.add(name)
                if not isinstance(data_type, str) or not data_type:
                    errors.append(f"{path}.type must be a non-empty string")
            status = table.get("status", "approved")
            if status != "approved":
                errors.append(f"table {table_name}.status must be approved in the runtime KB")
            if table.get("source_kind") not in {
                "observed", "proxy", "modelled", "recommendation"
            }:
                errors.append(f"table {table_name}.source_kind is invalid or missing")
            for required_contract in (
                "grain", "period_semantics", "aggregation_rule", "priority",
                "cost_tier", "metric_families", "schema_hash",
            ):
                if not table.get(required_contract):
                    errors.append(f"table {table_name} missing contract {required_contract}")

    data_facts = kb.get("data_facts")
    if not isinstance(data_facts, dict):
        errors.append("data_facts must be an object")
    else:
        unexpected = sorted(set(data_facts) - ALLOWED_DATA_FACTS)
        if unexpected:
            errors.append(
                "data_facts contains keys that are not allowlisted: " + ", ".join(unexpected)
            )

    if errors:
        raise ValueError("Knowledge base validation failed:\n- " + "\n- ".join(errors))
    return kb, raw, warnings


def domain_document(domain_key: str, domain: dict[str, Any], digest: str) -> str:
    agent = domain.get("agent")
    if isinstance(agent, dict):
        key_facts = agent.get("key_facts") or []
        agent_name = agent.get("name")
    else:
        key_facts = []
        agent_name = agent if isinstance(agent, str) else None

    lines = [
        "---",
        f"title: {yaml_text('Runtime KB domain: ' + domain_key)}",
        "type: generated-knowledge",
        f"domain: {yaml_text(domain_key)}",
        f"source_sha256: {yaml_text(digest)}",
        "---",
        "",
        f"# Runtime KB domain: `{clean(domain_key)}`",
        "",
        "> [!warning] Generated file",
        f"> Source: `{SOURCE_LABEL}`. Do not edit this file by hand.",
        "",
        f"- **Label:** {clean(domain.get('label', domain_key))}",
        f"- **Description:** {clean(domain.get('description', ''))}",
        f"- **Tables:** {len(domain.get('tables', {}))}",
    ]
    if agent_name:
        lines.append(f"- **Agent identifier:** `{clean(agent_name)}`")

    lines.extend(["", "## Domain to table relationships", ""])
    for table_name in sorted(domain.get("tables", {})):
        lines.append(f"- Domain `{clean(domain_key)}` contains table `{clean(table_name)}`.")

    lines.extend(["", "## Table schemas", ""])
    for table_name in sorted(domain.get("tables", {})):
        table = domain["tables"][table_name]
        columns = table.get("columns", [])
        partitions = [clean(c["name"]) for c in columns if c.get("partition")]
        lines.extend(
            [
                f"### `{clean(table_name)}`",
                "",
                f"- Relationship: domain `{clean(domain_key)}` contains table `{clean(table_name)}`.",
                f"- Column count: {len(columns)}.",
                f"- Partition columns: {', '.join(f'`{name}`' for name in partitions) if partitions else 'none declared'}.",
                f"- Source kind: `{clean(table.get('source_kind', ''))}`.",
                f"- Grain: `{clean(table.get('grain', ''))}`.",
                f"- Period semantics: `{clean(table.get('period_semantics', ''))}`.",
                f"- Aggregation rule: `{clean(table.get('aggregation_rule', ''))}`.",
                f"- Priority: `{clean(table.get('priority', ''))}`.",
                f"- Relative cost tier: `{clean(table.get('cost_tier', ''))}`.",
                f"- Metric families: {', '.join(f'`{clean(metric)}`' for metric in table.get('metric_families', []))}.",
                "- Columns:",
            ]
        )
        for column in columns:
            tags = []
            if column.get("partition"):
                tags.append("partition")
            if column.get("nullable") is False:
                tags.append("required")
            suffix = f" ({', '.join(tags)})" if tags else ""
            lines.append(
                f"  - `{clean(column.get('name', ''))}`: `{clean(column.get('type', ''))}`{suffix}"
            )
        lines.append("")

    lines.extend(["## Approved agent key facts", ""])
    if key_facts:
        for fact in key_facts:
            lines.append(f"- {clean(fact)}")
    else:
        lines.append("- No object-based key facts are declared for this domain.")

    lines.extend(
        [
            "",
            "## Related",
            "",
            "- [Knowledge catalog](../README.md)",
            "- [Vault knowledge base note](../../vault/30-data/knowledge-base-json.md)",
            "",
        ]
    )
    return "\n".join(lines)


def fact_document(fact_key: str, value: Any, digest: str) -> str:
    lines = [
        "---",
        f"title: {yaml_text('Runtime KB data fact: ' + fact_key)}",
        "type: generated-knowledge",
        f"data_fact: {yaml_text(fact_key)}",
        f"source_sha256: {yaml_text(digest)}",
        "---",
        "",
        f"# Runtime KB data fact: `{clean(fact_key)}`",
        "",
        "> [!warning] Generated file",
        f"> Source: `{SOURCE_LABEL}`. Do not edit this file by hand.",
        "",
        "## Flattened fact paths",
        "",
    ]
    for path, item in flatten(value, fact_key):
        lines.append(f"- **`{clean(path)}`:** {clean(item)}")
    lines.extend(
        [
            "",
            "## Related",
            "",
            "- [Knowledge catalog](../README.md)",
            "- [Vault knowledge base note](../../vault/30-data/knowledge-base-json.md)",
            "",
        ]
    )
    return "\n".join(lines)


def governance_document(governance: dict[str, Any], digest: str) -> str:
    objects = governance.get("objects", {})
    lines = [
        "---",
        f"title: {yaml_text('java_precalc table governance')}",
        "type: generated-knowledge-governance",
        f"source_sha256: {yaml_text(digest)}",
        "---",
        "",
        "# java_precalc table governance",
        "",
        "> [!warning] Generated file",
        "> Source: `backend/governance/table_governance.json`. Do not edit this file by hand.",
        "",
        "Lifecycle and object class are separate. Only `approved` objects can be used by runtime SQL.",
        "",
    ]
    for lifecycle in ("approved", "candidate", "quarantined", "rejected", "superseded"):
        names = sorted(
            name for name, item in objects.items() if item.get("lifecycle") == lifecycle
        )
        lines.extend([f"## {lifecycle.title()} ({len(names)})", ""])
        for name in names:
            item = objects[name]
            domain = f", domain `{clean(item.get('domain'))}`" if item.get("domain") else ""
            replacement = (
                f", replacement `{clean(item.get('replacement_table'))}`"
                if item.get("replacement_table") else ""
            )
            lines.append(
                f"- `{clean(name)}`: class `{clean(item.get('object_class'))}`{domain}{replacement}. "
                f"{clean(item.get('reason', ''))}"
            )
        lines.append("")
    return "\n".join(lines)


def build_outputs(kb: dict[str, Any], digest: str) -> dict[Path, str]:
    domains = kb["domains"]
    facts = kb["data_facts"]
    table_count = sum(len(domain["tables"]) for domain in domains.values())
    column_count = sum(
        len(table["columns"])
        for domain in domains.values()
        for table in domain["tables"].values()
    )
    key_fact_count = sum(
        len(domain.get("agent", {}).get("key_facts", []))
        for domain in domains.values()
        if isinstance(domain.get("agent"), dict)
    )

    readme = [
        "---",
        "title: Runtime knowledge projection for Graphify",
        "type: generated-knowledge-index",
        f"source_sha256: {yaml_text(digest)}",
        "---",
        "",
        "# Runtime knowledge projection for Graphify",
        "",
        "This directory is a deterministic, development-only projection of",
        f"`{SOURCE_LABEL}`. The JSON remains the runtime source of truth.",
        "",
        "> [!warning] Generated corpus",
        "> Do not edit these files. Run `backend/venv/bin/python tools_graphify_kb.py`.",
        "",
        "## Coverage",
        "",
        f"- Source SHA-256: `{digest}`",
        f"- Project: `{clean(kb['project'])}`",
        f"- Dataset: `{clean(kb['dataset'])}`",
        f"- Region: `{clean(kb['region'])}`",
        f"- Domains: {len(domains)}",
        f"- Tables: {table_count}",
        f"- Columns: {column_count}",
        f"- Approved domain key facts: {key_fact_count}",
        f"- Approved global data fact groups: {len(facts)}",
        "",
        "## Security and ownership boundary",
        "",
        "Included: domain labels, descriptions, domain-to-table relationships, column names and",
        "types, partition flags, approved domain key facts, and allowlisted global data facts.",
        "",
        "Excluded: agent personas, prompt templates, credentials, environment values, row samples,",
        "customer data, SQLite content, and live KPI values. Graphify must not be used as a source",
        "for production business metrics or chat answers.",
        "",
        "## Domains",
        "",
    ]
    for domain_key in sorted(domains):
        domain = domains[domain_key]
        readme.append(
            f"- [`{clean(domain_key)}`](domains/{slug(domain_key)}.md): "
            f"{len(domain['tables'])} tables, {clean(domain.get('label', domain_key))}"
        )
    readme.extend(["", "## Global data facts", ""])
    for fact_key in sorted(facts):
        readme.append(f"- [`{clean(fact_key)}`](data-facts/{slug(fact_key)}.md)")
    readme.extend([
        "",
        "## Governance",
        "",
        "- [Full java_precalc lifecycle registry](table-governance.md)",
    ])
    readme.extend(
        [
            "",
            "## Refresh workflow",
            "",
            "1. Edit the authoritative runtime KB.",
            "2. Run `backend/venv/bin/python tools_graphify_kb.py`.",
            "3. Run the semantic Graphify update workflow because Markdown changed.",
            "4. Verify with `backend/venv/bin/python tools_graphify_kb.py --check` and smoke queries.",
            "",
            "See `vault/40-decisions/graphify-development-index.md` for the architecture boundary.",
            "",
        ]
    )

    outputs = {Path("README.md"): "\n".join(readme)}
    for domain_key in sorted(domains):
        outputs[Path("domains") / f"{slug(domain_key)}.md"] = domain_document(
            domain_key, domains[domain_key], digest
        )
    for fact_key in sorted(facts):
        outputs[Path("data-facts") / f"{slug(fact_key)}.md"] = fact_document(
            fact_key, facts[fact_key], digest
        )
    if DEFAULT_GOVERNANCE.exists():
        governance = json.loads(DEFAULT_GOVERNANCE.read_text())
        governance_digest = hashlib.sha256(DEFAULT_GOVERNANCE.read_bytes()).hexdigest()
        outputs[Path("table-governance.md")] = governance_document(
            governance, governance_digest
        )
    return outputs


def compare_outputs(output_dir: Path, outputs: dict[Path, str]) -> list[str]:
    drift: list[str] = []
    expected = set(outputs)
    for relative, content in outputs.items():
        target = output_dir / relative
        if not target.exists():
            drift.append(f"missing: {target}")
        elif target.read_text(encoding="utf-8") != content:
            drift.append(f"changed: {target}")
    for owned_dir in (output_dir / "domains", output_dir / "data-facts"):
        if owned_dir.exists():
            for target in owned_dir.glob("*.md"):
                relative = target.relative_to(output_dir)
                if relative not in expected:
                    drift.append(f"stale: {target}")
    return sorted(drift)


def write_outputs(output_dir: Path, outputs: dict[Path, str]) -> None:
    for relative, content in outputs.items():
        target = output_dir / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(target.suffix + ".tmp")
        temporary.write_text(content, encoding="utf-8")
        temporary.replace(target)
    expected = set(outputs)
    for owned_dir in (output_dir / "domains", output_dir / "data-facts"):
        if owned_dir.exists():
            for target in owned_dir.glob("*.md"):
                if target.relative_to(output_dir) not in expected:
                    target.unlink()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="fail if generated files drift")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        kb, raw, warnings = load_and_validate(args.source)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    digest = hashlib.sha256(raw).hexdigest()
    outputs = build_outputs(kb, digest)
    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)

    if args.check:
        drift = compare_outputs(args.output, outputs)
        if drift:
            print("Graphify knowledge projection is stale:", file=sys.stderr)
            for item in drift:
                print(f"- {item}", file=sys.stderr)
            return 1
        print(f"Graphify knowledge projection is current ({len(outputs)} files, {digest[:12]}).")
        return 0

    write_outputs(args.output, outputs)
    print(f"Generated {len(outputs)} Graphify knowledge files from {digest[:12]}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
