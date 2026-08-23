#!/usr/bin/env python3
"""Recompile backend/data/runtime_knowledge_graph.json from the runtime KB.

The production graph artifact is keyed by a SHA-256 of knowledge_base.json. Any KB
edit invalidates it, and the backend then falls back to an in-memory compilation and
reports a health warning. Run this after every KB edit, before restarting the backend:

    venv/bin/python tools_runtime_graph.py            # rebuild
    venv/bin/python tools_runtime_graph.py --check    # verify only, non-zero on drift
"""
from __future__ import annotations

import argparse

from app import knowledge
from app.knowledge_graph import write_graph_atomic, graph_health


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="report drift without rewriting the artifact")
    args = parser.parse_args()

    knowledge.load_kb.cache_clear()
    kb = knowledge.load_kb()

    if args.check:
        health = graph_health(kb)
        print(health)
        return 0 if health.get("status") == "ok" else 1

    graph = write_graph_atomic(kb)
    knowledge.load_kb.cache_clear()
    health = graph_health(knowledge.load_kb())
    print(f"rebuilt: nodes={len(graph.get('nodes', []))} "
          f"edges={len(graph.get('edges', []))} kb_sha256={graph.get('source_kb_sha256', '')[:12]}")
    print("health:", health)
    print("now restart the backend: sudo systemctl restart telco-backend")
    return 0 if health.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
