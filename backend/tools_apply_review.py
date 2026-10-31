#!/usr/bin/env python3
"""Apply a reviewed decision file to table_governance.json, incrementally.

`--rebuild-governance` regenerates every record from the hardcoded rules and
resets every decision_history to a single entry, which erases the audit trail
and conflicts with the reversal policy. Onboarding therefore uses this instead:
it only touches the objects named in the review file, appends to history rather
than replacing it, and stamps the reviewed schema and physical hashes from the
live dataset so a later change shows up as drift.

    venv/bin/python tools_apply_review.py governance/review_2026_09_17.json --dry-run
    venv/bin/python tools_apply_review.py governance/review_2026_09_17.json --write
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app import config  # noqa: E402
from tools_knowledge_refresh import (  # noqa: E402
    _atomic_json,
    _object_class,
    _physical_hash,
    _schema_hash,
    load_inventory,
    validate_state,
)

POLICY_FOR = {
    "approved": "runtime_allowed",
    "candidate": "not_runtime_allowed",
    "quarantined": "hard_block",
    "rejected": "hard_block",
    "superseded": "hard_block",
}


def apply_review(
    governance: dict[str, Any],
    review: dict[str, Any],
    inventory: dict[str, Any],
) -> tuple[dict[str, Any], list[str]]:
    live = {item["name"]: item for item in inventory.get("tables", [])}
    objects = governance.setdefault("objects", {})
    changes: list[str] = []
    review_id = review["review_id"]

    for name, decision in review["decisions"].items():
        lifecycle = decision["lifecycle"]
        if lifecycle not in POLICY_FOR:
            raise SystemExit(f"{name}: unknown lifecycle {lifecycle}")
        item = live.get(name)
        record = objects.get(name)
        history = list(record.get("decision_history", [])) if record else []
        previous = record.get("lifecycle") if record else None

        entry = {
            "review_id": review_id,
            "decision": lifecycle,
            "reason": decision["reason"],
            "reviewed_at": review["reviewed_at"],
            "reviewer": review["reviewer"],
            "evidence": decision["evidence"],
        }
        # A blocked object may only come back through an explicit reviewed
        # override. Nothing in this review does that, but the flag has to be
        # carried so validate_state can tell a fresh approval from a reversal.
        was_blocked = any(
            h.get("decision") in {"rejected", "quarantined"} for h in history)
        if was_blocked and lifecycle == "approved":
            entry["override"] = True
        history.append(entry)

        objects[name] = {
            "lifecycle": lifecycle,
            "object_class": (_object_class(name, item) if item
                             else (record or {}).get("object_class", "aggregate")),
            "policy": POLICY_FOR[lifecycle],
            "domain": decision.get("domain"),
            "reason": decision["reason"],
            "review_id": review_id,
            # A missing table keeps its last reviewed hash: there is nothing live
            # to hash, and overwriting it would hide the deletion.
            "schema_hash": _schema_hash(item) if item else (record or {}).get("schema_hash"),
            "physical_hash": _physical_hash(item) if item else (record or {}).get("physical_hash"),
            "decision_history": history,
            "replacement_table": decision.get("replacement_table"),
        }
        changes.append(f"{name}: {previous or 'NEW'} -> {lifecycle}")

    governance["review_id"] = review_id
    return governance, changes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("review", type=Path)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    review = json.loads(args.review.read_text())
    governance = json.loads(config.TABLE_GOVERNANCE_PATH.read_text())
    inventory = load_inventory(args.inventory)
    kb = json.loads(config.KB_PATH.read_text())

    updated, changes = apply_review(governance, review, inventory)
    errors = validate_state(kb, updated)

    print(json.dumps({
        "review_id": review["review_id"],
        "objects_touched": len(changes),
        "governance_objects": len(updated["objects"]),
        "changes": changes,
        "validation_errors": errors,
        "written": False,
    }, indent=2))

    if errors:
        # The KB still holds tables this review just blocked. Promotion clears
        # them; refusing to write here would deadlock the two steps.
        print("\nNote: validation errors above are expected until "
              "--promote-reviewed rewrites the runtime KB.", file=sys.stderr)

    if args.write and not args.dry_run:
        backup = config.TABLE_GOVERNANCE_PATH.with_name(
            config.TABLE_GOVERNANCE_PATH.name + ".bak"
            + datetime.now().strftime("%Y%m%d%H%M%S"))
        shutil.copy2(config.TABLE_GOVERNANCE_PATH, backup)
        _atomic_json(config.TABLE_GOVERNANCE_PATH, updated)
        print(f"written: {config.TABLE_GOVERNANCE_PATH} (backup: {backup.name})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
