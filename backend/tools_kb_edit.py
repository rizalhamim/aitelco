#!/usr/bin/env python3
"""Safe, auditable editor for backend/data/knowledge_base.json.

The runtime KB is the single source of agent knowledge, so edits must be atomic,
backed up, and verifiable. This tool adds or removes a domain key fact (or a global
data_facts entry) without hand-editing a 1.7 MB JSON file.

Usage (from backend/, with the venv):
    venv/bin/python tools_kb_edit.py list-facts --domain ftth
    venv/bin/python tools_kb_edit.py add-fact --domain ftth --text "..."
    venv/bin/python tools_kb_edit.py drop-fact --domain ftth --index 8

Every write leaves a timestamped .bak next to the file. A backend restart is required
afterwards because knowledge.load_kb() is lru_cached.
"""
from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path

KB_PATH = Path(__file__).resolve().parent / "data" / "knowledge_base.json"


def load() -> dict:
    return json.loads(KB_PATH.read_text())


def save(kb: dict) -> Path:
    stamp = time.strftime("%Y%m%d%H%M%S")
    backup = KB_PATH.with_suffix(KB_PATH.suffix + f".bak{stamp}")
    shutil.copy2(KB_PATH, backup)
    tmp = KB_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(kb, ensure_ascii=False, indent=1))
    tmp.replace(KB_PATH)
    return backup


def facts_list(kb: dict, domain: str) -> list:
    agent = kb["domains"][domain].setdefault("agent", {})
    facts = agent.setdefault("key_facts", [])
    if not isinstance(facts, list):
        raise SystemExit(f"domain '{domain}' key_facts is {type(facts).__name__}, not a list")
    return facts


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_list = sub.add_parser("list-facts")
    p_list.add_argument("--domain", required=True)

    p_add = sub.add_parser("add-fact")
    p_add.add_argument("--domain", required=True)
    p_add.add_argument("--text", required=True)

    p_drop = sub.add_parser("drop-fact")
    p_drop.add_argument("--domain", required=True)
    p_drop.add_argument("--index", type=int, required=True)

    args = parser.parse_args()
    kb = load()
    if args.domain not in kb["domains"]:
        raise SystemExit(f"unknown domain '{args.domain}'")

    facts = facts_list(kb, args.domain)

    if args.cmd == "list-facts":
        for i, f in enumerate(facts):
            print(f"[{i}] {f}")
        return 0

    if args.cmd == "add-fact":
        if args.text in facts:
            print("fact already present, nothing to do")
            return 0
        facts.append(args.text)
    elif args.cmd == "drop-fact":
        if not 0 <= args.index < len(facts):
            raise SystemExit(f"index out of range (0..{len(facts) - 1})")
        removed = facts.pop(args.index)
        print(f"removed: {removed[:100]}")

    backup = save(kb)
    print(f"written. backup: {backup.name}")
    print("restart the backend: sudo systemctl restart telco-backend")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
