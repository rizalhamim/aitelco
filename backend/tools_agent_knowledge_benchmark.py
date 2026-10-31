#!/usr/bin/env python3
"""Deterministic routing, governance, and prompt-size benchmark."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from app import config, knowledge


ROOT = Path(__file__).resolve().parent
DEFAULT_CASES = ROOT / "benchmarks" / "agent_knowledge_cases.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--max-schema-chars", type=int, default=50000)
    args = parser.parse_args()

    cases = json.loads(args.cases.read_text())
    failures = []
    results = []
    blocked = knowledge.blocked_table_names()
    governed = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())["objects"]
    contracts = knowledge.table_contracts()
    for case in cases:
        selection = knowledge.selection_for_question(
            case["domain"], case["question"], max_tables=4
        )
        tables = selection.get("tables", [])
        schema, _ = knowledge.schema_for_question(case["domain"], case["question"])
        required = set(case.get("required_any", []))
        forbidden = set(case.get("forbidden", [])).union(blocked)
        problems = []
        if required and not required.intersection(tables):
            problems.append("none of the required tables was retrieved")
        if forbidden.intersection(tables):
            problems.append("forbidden table was retrieved")
        if len(schema) > args.max_schema_chars:
            problems.append(f"schema prompt is {len(schema)} chars")
        # Retrieval alone is not enough: a table can be selected while carrying no
        # governance approval or no reviewed contract, and the SQL writer would
        # then work from a name and a column list only.
        warnings = []
        for table in tables:
            decision = governed.get(table)
            if decision is None:
                problems.append(f"{table} has no governance decision")
                continue
            if decision.get("lifecycle") != "approved":
                problems.append(f"{table} is {decision.get('lifecycle')}, not approved")
            if decision.get("domain") != case["domain"]:
                problems.append(
                    f"{table} is owned by {decision.get('domain')}, not {case['domain']}")
            contract = contracts.get(table) or {}
            for field in ("grain", "period_semantics", "aggregation_rule"):
                if not contract.get(field):
                    problems.append(f"{table} has no {field}")
            # Reported, not failed. A large number of pre-existing tables carry an
            # empty description; that is a real retrieval weakness but it predates
            # this benchmark, and failing on it here would hide genuine regressions.
            if not contract.get("description"):
                warnings.append(f"{table} has no description")
        if problems:
            failures.append({"case": case["name"], "problems": problems, "tables": tables})
        results.append({
            "case": case["name"],
            "confidence": selection.get("confidence"),
            "tables": tables,
            "schema_chars": len(schema),
            "warnings": warnings,
            "ok": not problems,
        })

    missing_description = sorted({
        w.split(" ")[0] for r in results for w in r["warnings"]})
    print(json.dumps({
        "cases": len(cases),
        "passed": len(cases) - len(failures),
        "failed": failures,
        "tables_without_description": missing_description,
        "results": results,
    }, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

