"""Safe runtime knowledge graph compiled from the approved runtime KB.

This module never reads ``graphify-out``. The runtime graph uses a small,
Graphify-compatible node and edge representation compiled from
``knowledge_base.json``. Question history can only adjust weights on existing
approved edges. It cannot create tables, columns, formulas, or business facts.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
import sqlite3
from collections import defaultdict
from pathlib import Path
from typing import Any

from . import config


GRAPH_SCHEMA_VERSION = "1.0"
COMPILER_VERSION = "1.1"

_TOKEN_RE = re.compile(r"[a-z0-9_]+", re.IGNORECASE)
_TABLE_REF_RE = re.compile(
    r"`(?:(?P<project>[a-zA-Z0-9_-]+)\.)?"
    r"(?:(?P<dataset>[a-zA-Z0-9_-]+)\.)?"
    r"(?P<table>[a-zA-Z_][a-zA-Z0-9_]*)`"
)
_STOPWORDS = {
    "a", "ada", "adalah", "agar", "ai", "akan", "apa", "apakah", "atau",
    "bagaimana", "berapa", "buat", "dalam", "dan", "dari", "data", "dengan",
    "di", "dong", "for", "ini", "itu", "java", "ke", "latest", "mana",
    "mohon", "of", "pada", "paling", "per", "please", "saat", "saya",
    "secara", "sekarang", "terbaru", "the", "this", "to", "tolong", "untuk",
    "yang",
}
_GRAIN_TERMS = {
    "site": {"site", "bts", "cell", "site_id"},
    "outlet": {"outlet", "dealer", "nbs", "pjp"},
    "kecamatan": {"kecamatan", "kec", "kec_id"},
    "kabkota": {"kabkota", "kabkot", "kabupaten", "kota"},
    "branch": {"branch"},
    "region": {"region"},
    "circle": {"circle"},
    "subscriber_segment": {"subscriber", "subs", "segment", "cohort"},
}
_PERIOD_TERMS = {
    "daily": {"daily", "harian", "hari", "tanggal", "dt_id"},
    "mtd": {"mtd", "bulan_ini", "month_to_date"},
    "monthly": {"monthly", "mth", "bulanan", "bulan", "mom", "yoy"},
    "snapshot": {"snapshot", "stock", "eom"},
}
_HIGH_RISK_TERMS = {
    "akurasi", "bandingkan", "benchmark", "bottom", "correlate", "correlation",
    "forecast", "kenapa", "korelasi", "lytd", "model", "opportunity", "prediksi",
    "proxy", "ranking", "rekomendasi", "root", "terendah", "tertinggi", "top",
    "versus", "vs", "why", "ytd",
}
_STRUCTURAL_TABLE_TOKENS = {
    "area", "branch", "daily", "java", "kabkot", "kec", "mtd", "mth",
    "monthly", "outlet", "rham", "site", "territory", "wise",
}


def _canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def kb_sha256(kb: dict[str, Any]) -> str:
    return hashlib.sha256(_canonical_bytes(kb)).hexdigest()


def tokenize(text: str | None) -> set[str]:
    raw = {token.lower() for token in _TOKEN_RE.findall(text or "")}
    raw.update(
        part
        for token in list(raw)
        for part in token.split("_")
        if part
    )
    tokens = {token for token in raw if len(token) > 1 and token not in _STOPWORDS}
    # Common phrases are normalized into stable graph vocabulary.
    lower = (text or "").lower()
    phrases = {
        "market share": "market_share",
        "gross add": "gross_add",
        "home pass": "homepass",
        "home broadband": "ftth",
        "fixed wireless": "fwa",
        "month to date": "mtd",
        "last year to date": "lytd",
        "year to date": "ytd",
        "data traffic": "traffic",
        "network experience": "network_experience",
    }
    for phrase, normalized in phrases.items():
        if phrase in lower:
            tokens.add(normalized)
    return tokens


def _stable_id(kind: str, key: str) -> str:
    return f"{kind}:{key}"


def _blocked_policy(kb: dict[str, Any]) -> dict[str, dict[str, Any]]:
    blocked: dict[str, dict[str, Any]] = {}
    banned = kb.get("data_facts", {}).get("banned_tables", {})
    if isinstance(banned, dict):
        for group, entry in banned.items():
            if not isinstance(entry, dict):
                continue
            for name in entry.get("tables", []):
                blocked[str(name)] = {
                    "policy": "hard_block",
                    "group": group,
                    "reason": entry.get("reason", "Rejected by table governance"),
                    "replacement": entry.get("replacement_table"),
                }
    return blocked


def build_graph(kb: dict[str, Any]) -> dict[str, Any]:
    """Compile deterministic executable nodes from approved KB content."""
    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    vocabulary: set[str] = set()

    for domain_key in sorted(kb.get("domains", {})):
        domain = kb["domains"][domain_key]
        domain_id = _stable_id("domain", domain_key)
        domain_text = " ".join(
            [domain_key, str(domain.get("label", "")), str(domain.get("description", ""))]
        )
        domain_tokens = sorted(tokenize(domain_text))
        vocabulary.update(domain_tokens)
        nodes.append({
            "id": domain_id,
            "kind": "domain",
            "key": domain_key,
            "label": domain.get("label", domain_key),
            "tokens": domain_tokens,
        })

        for table_name in sorted(domain.get("tables", {})):
            table = domain["tables"][table_name]
            table_id = _stable_id("table", table_name)
            contract_text = " ".join(
                [
                    table_name,
                    str(table.get("description", "")),
                    " ".join(table.get("aliases", []) or []),
                    " ".join(table.get("metric_families", []) or []),
                    str(table.get("grain", "")),
                    str(table.get("period_semantics", "")),
                ]
            )
            table_tokens = set(tokenize(contract_text))
            for column in table.get("columns", []):
                table_tokens.update(tokenize(column.get("name", "")))
                table_tokens.update(tokenize(column.get("desc", "")))
            vocabulary.update(table_tokens)
            nodes.append({
                "id": table_id,
                "kind": "table",
                "key": table_name,
                "domain": domain_key,
                "tokens": sorted(table_tokens),
                "contract": {
                    key: table.get(key)
                    for key in (
                        "status", "source_kind", "grain", "period_semantics",
                        "aggregation_rule", "territory_vocabulary", "priority",
                        "cost_tier", "metric_families", "use_constraints",
                        "warning_columns", "schema_hash",
                    )
                    if table.get(key) is not None
                },
            })
            edges.append({
                "source": domain_id,
                "target": table_id,
                "type": "HAS_TABLE",
                "weight": 1.0,
            })

            for column in table.get("columns", []):
                column_name = str(column.get("name", ""))
                if not column_name:
                    continue
                column_id = _stable_id("column", f"{table_name}.{column_name}")
                column_tokens = sorted(tokenize(
                    column_name + " " + str(column.get("desc", ""))
                ))
                vocabulary.update(column_tokens)
                nodes.append({
                    "id": column_id,
                    "kind": "column",
                    "key": column_name,
                    "table": table_name,
                    "data_type": column.get("type"),
                    "partition": bool(column.get("partition")),
                    "tokens": column_tokens,
                })
                edges.append({
                    "source": table_id,
                    "target": column_id,
                    "type": "HAS_COLUMN",
                    "weight": 1.0,
                })

    return {
        "schema_version": GRAPH_SCHEMA_VERSION,
        "compiler_version": COMPILER_VERSION,
        "source_kb_sha256": kb_sha256(kb),
        "project": kb.get("project"),
        "dataset": kb.get("dataset"),
        "nodes": nodes,
        "edges": edges,
        "negative_policy": _blocked_policy(kb),
        "vocabulary": sorted(vocabulary),
    }


def write_graph_atomic(kb: dict[str, Any], path: Path | None = None) -> dict[str, Any]:
    path = path or config.RUNTIME_GRAPH_PATH
    graph = build_graph(kb)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    temp_path.write_text(json.dumps(graph, ensure_ascii=False, indent=2) + "\n")
    temp_path.replace(path)

    graph_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    manifest = {
        "schema_version": GRAPH_SCHEMA_VERSION,
        "compiler_version": COMPILER_VERSION,
        "kb_sha256": graph["source_kb_sha256"],
        "graph_sha256": graph_hash,
        "graph_path": path.name,
    }
    manifest_path = config.RUNTIME_KNOWLEDGE_MANIFEST_PATH
    manifest_tmp = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    manifest_tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    manifest_tmp.replace(manifest_path)
    return graph


def load_graph(kb: dict[str, Any]) -> tuple[dict[str, Any], str]:
    """Load a matching graph, otherwise return a safe in-memory compilation."""
    expected = kb_sha256(kb)
    try:
        graph = json.loads(config.RUNTIME_GRAPH_PATH.read_text())
        if (
            graph.get("source_kb_sha256") == expected
            and graph.get("compiler_version") == COMPILER_VERSION
            and graph.get("schema_version") == GRAPH_SCHEMA_VERSION
        ):
            return graph, "artifact"
    except Exception:
        pass
    return build_graph(kb), "fallback"


def _priority_score(value: Any) -> float:
    return {
        "primary": 8.0,
        "high": 6.0,
        "standard": 3.0,
        "supporting": 1.0,
        "low": 0.0,
    }.get(str(value or "standard").lower(), 3.0)


def _routing_weights(domain_key: str, tokens: set[str]) -> dict[str, float]:
    """Read only promoted routing evidence from SQLite.

    Evidence is bounded to existing terms and approved table edges. It never
    changes the compiled graph structure.
    """
    if not tokens:
        return {}
    db_path = Path(config.KB_PATH).parent / "sessions.db"
    if not db_path.exists():
        return {}
    try:
        placeholders = ",".join("?" for _ in tokens)
        with sqlite3.connect(db_path) as conn:
            rows = conn.execute(
                f"""SELECT table_name, SUM(success_count) AS successes
                      FROM knowledge_route_edges
                     WHERE domain = ? AND state = 'active'
                       AND term IN ({placeholders})
                     GROUP BY table_name""",
                (domain_key, *sorted(tokens)),
            ).fetchall()
        return {
            table: min(3.0, math.log2(max(1, successes)))
            for table, successes in rows
        }
    except (sqlite3.Error, OSError):
        return {}


def _table_search_text(table_name: str, table: dict[str, Any]) -> str:
    chunks = [
        table_name,
        str(table.get("description", "")),
        " ".join(table.get("aliases", []) or []),
        " ".join(table.get("metric_families", []) or []),
        str(table.get("grain", "")),
        str(table.get("period_semantics", "")),
    ]
    for column in table.get("columns", []):
        chunks.extend([column.get("name", ""), column.get("desc", "")])
    return " ".join(str(chunk) for chunk in chunks)


def select_tables(
    kb: dict[str, Any],
    domain_key: str,
    question: str,
    max_tables: int | None = None,
    table_hints: list[str] | None = None,
) -> dict[str, Any]:
    """Return a bounded, explainable table selection for one question."""
    domain = kb.get("domains", {}).get(domain_key) or {}
    tables = domain.get("tables", {})
    if not tables:
        return {"tables": [], "confidence": 0.0, "scores": {}, "reason": "no tables"}

    limit = max(1, max_tables or config.KNOWLEDGE_TABLE_LIMIT)
    limit = min(limit, config.KNOWLEDGE_TABLE_MAX_EXPANSION)
    q_tokens = tokenize(question)
    hints = {
        hint for hint in (table_hints or [])
        if hint in tables and tables[hint].get("status", "approved") == "approved"
    }
    routing = _routing_weights(domain_key, q_tokens)
    scores: dict[str, float] = {}
    score_reasons: dict[str, list[str]] = defaultdict(list)

    requested_grains = {
        grain for grain, terms in _GRAIN_TERMS.items() if q_tokens.intersection(terms)
    }
    requested_periods = {
        period for period, terms in _PERIOD_TERMS.items() if q_tokens.intersection(terms)
    }

    for table_name, table in tables.items():
        if table.get("status", "approved") != "approved":
            continue
        searchable_tokens = tokenize(_table_search_text(table_name, table))
        overlap = q_tokens.intersection(searchable_tokens)
        score = _priority_score(table.get("priority"))
        if overlap:
            score += min(18.0, 2.5 * len(overlap))
            score_reasons[table_name].append("terms=" + ",".join(sorted(overlap)[:8]))
        name_tokens = tokenize(table_name.replace("rham_", ""))
        name_overlap = q_tokens.intersection(name_tokens)
        if name_overlap:
            semantic_name_overlap = name_overlap - _STRUCTURAL_TABLE_TOKENS
            structural_name_overlap = name_overlap.intersection(_STRUCTURAL_TABLE_TOKENS)
            score += 8.0 * len(semantic_name_overlap)
            score += 1.0 * len(structural_name_overlap)
            score_reasons[table_name].append("name=" + ",".join(sorted(name_overlap)))
        if table_name in hints:
            score += 50.0
            score_reasons[table_name].append("validated_hint")
        grain = str(table.get("grain", "")).lower()
        if requested_grains and any(value in grain for value in requested_grains):
            score += 6.0
            score_reasons[table_name].append("grain")
        elif requested_grains and grain not in {"", "declared_dimensions"}:
            score -= 4.0
        period = str(table.get("period_semantics", "")).lower()
        if requested_periods and any(value in period for value in requested_periods):
            score += 5.0
            score_reasons[table_name].append("period")
        elif requested_periods:
            score -= 3.0
        score += routing.get(table_name, 0.0)
        if routing.get(table_name):
            score_reasons[table_name].append("verified_usage")
        scores[table_name] = score

    ranked = sorted(scores, key=lambda name: (-scores[name], name))
    selected = ranked[:limit]

    # Region and cross-territory questions often need the canonical reference.
    ref_name = "zz_territory_kecamatan"
    needs_ref = bool(q_tokens.intersection({
        "area", "branch", "circle", "kabkota", "kabkot", "kecamatan",
        "province", "provinsi", "region", "territory", "wilayah",
    }))
    if needs_ref and ref_name in tables and ref_name not in selected:
        if len(selected) >= limit:
            selected[-1] = ref_name
        else:
            selected.append(ref_name)
        score_reasons[ref_name].append("territory_reference")

    best = scores.get(selected[0], 0.0) if selected else 0.0
    second = scores.get(selected[1], 0.0) if len(selected) > 1 else 0.0
    separation = max(0.0, best - second)
    confidence = min(0.99, 0.35 + best / 40.0 + separation / 80.0)
    return {
        "tables": selected,
        "confidence": round(confidence, 3),
        "scores": {name: round(scores.get(name, 0.0), 2) for name in selected},
        "reasons": {name: score_reasons.get(name, []) for name in selected},
        "question_tokens": sorted(q_tokens),
    }


def select_columns(
    table: dict[str, Any], question: str, max_columns: int = 48
) -> tuple[list[dict[str, Any]], list[str]]:
    """Select relevant columns while retaining names of every omitted column."""
    columns = table.get("columns", [])
    if len(columns) <= max_columns:
        return list(columns), []
    q_tokens = tokenize(question)
    essential = {
        "area", "brand", "branch", "circle", "city", "dt_id", "kec_id",
        "kecamatan", "kabkot", "kabkot_nm", "month_id", "mth_dt", "province",
        "provinsi", "region", "site_id", "site_name",
    }
    scored: list[tuple[float, int, dict[str, Any]]] = []
    for index, column in enumerate(columns):
        name = str(column.get("name", ""))
        tokens = tokenize(name + " " + str(column.get("desc", "")))
        score = 0.0
        if column.get("partition"):
            score += 100.0
        if name.lower() in essential:
            score += 50.0
        overlap = q_tokens.intersection(tokens)
        score += 12.0 * len(overlap)
        if any(q in name.lower() for q in q_tokens if len(q) >= 3):
            score += 5.0
        scored.append((score, -index, column))
    chosen = sorted(scored, key=lambda item: (-item[0], -item[1]))[:max_columns]
    selected_names = {item[2].get("name") for item in chosen}
    selected = [column for column in columns if column.get("name") in selected_names]
    omitted = [
        str(column.get("name")) for column in columns
        if column.get("name") not in selected_names
    ]
    return selected, omitted


def known_terms(kb: dict[str, Any], question: str) -> list[str]:
    """Return only non-sensitive terms already present in the approved graph."""
    graph, _ = load_graph(kb)
    vocabulary = set(graph.get("vocabulary", []))
    return sorted(tokenize(question).intersection(vocabulary))[:20]


def extract_sql_tables(sql: str) -> set[str]:
    tables: set[str] = set()
    for match in _TABLE_REF_RE.finditer(sql or ""):
        table = match.group("table")
        project = match.group("project")
        dataset = match.group("dataset")
        if project and dataset:
            tables.add(table)
    return tables


def question_is_high_risk(question: str) -> bool:
    return bool(tokenize(question).intersection(_HIGH_RISK_TERMS))


def graph_health(kb: dict[str, Any]) -> dict[str, Any]:
    graph, source = load_graph(kb)
    return {
        "status": "ok" if source == "artifact" else "fallback",
        "source": source,
        "schema_version": graph.get("schema_version"),
        "kb_sha256": graph.get("source_kb_sha256"),
        "nodes": len(graph.get("nodes", [])),
        "edges": len(graph.get("edges", [])),
        "blocked_tables": len(graph.get("negative_policy", {})),
    }
