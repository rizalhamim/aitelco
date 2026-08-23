#!/usr/bin/env python3
"""Deterministic routing, governance, and prompt-size benchmark."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from app import knowledge


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
        if problems:
            failures.append({"case": case["name"], "problems": problems, "tables": tables})
        results.append({
            "case": case["name"],
            "confidence": selection.get("confidence"),
            "tables": tables,
            "schema_chars": len(schema),
            "ok": not problems,
        })

    print(json.dumps({
        "cases": len(cases),
        "passed": len(cases) - len(failures),
        "failed": failures,
        "results": results,
    }, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

