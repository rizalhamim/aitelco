#!/usr/bin/env python3
"""Re-run a specific subset of question IDs from training-questions-100.txt.

Usage:
  python3 rerun_subset.py <output.json> <id1> <id2> ...

Loads questions from training-questions-100.txt, filters by ID, then runs them
through the same /api/chat/stream pipeline as run_training_corpus.py.
"""
import sys
from pathlib import Path

# reuse the runner's machinery
sys.path.insert(0, str(Path(__file__).parent))
from run_training_corpus import parse_corpus, run_one, summarize
import json
import time
import uuid

CORPUS = Path("/home/ubuntu/telco-ai/training-questions-100.txt")
PACE = 3.0  # seconds between calls — give upstream LLM time to breathe


def main():
    out_path = Path(sys.argv[1])
    wanted = set(sys.argv[2:])
    all_items = parse_corpus(CORPUS)
    items = [i for i in all_items if i["id"] in wanted]
    missing = wanted - {i["id"] for i in items}
    if missing:
        print(f"Warning: not found in corpus: {sorted(missing)}", file=sys.stderr)
    print(f"=== Re-running {len(items)} questions ===")
    results = []
    tag = uuid.uuid4().hex[:6]
    for i, item in enumerate(items):
        sid = f"rerun-{tag}-{item['id']}"
        print(f"  [{i+1}/{len(items)}] {item['id']}: {item['q'][:60]}...", flush=True)
        r = run_one(item, sid)
        results.append(r)
        print(f"    → {r['status']} | routed={r['routed_domain']} | {r['elapsed_s']}s | rows={r['row_count']}")
        out_path.write_text(json.dumps(results, indent=2, ensure_ascii=False))
        if i < len(items) - 1 and PACE:
            time.sleep(PACE)
    summarize(results)
    print(f"\nJSON: {out_path}")


if __name__ == "__main__":
    main()
