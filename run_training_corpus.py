#!/usr/bin/env python3
"""Run training-questions-100.txt against the backend and write results in the
same JSON schema as test_batch.py's batch_*.json files.

Usage:
  python3 run_training_corpus.py <corpus.txt> <output.json> [--start N] [--end N]

Reads lines like `B01|kpi_summary|question text` and treats `B`/`M`/`H`
prefixes as Basic/Medium/Hard categories.
"""

import argparse
import csv
import json
import re
import sys
import time
import uuid
from pathlib import Path

import requests

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

API = "http://localhost:8000/api/chat/stream"
TIMEOUT = 300  # 5 min — fallback path adds per-call latency when specialized models are upstream-broken
LINE_RE = re.compile(r"^([BMH]\d+)\|([^|]+)\|(.+)$")


def parse_corpus(path: Path):
    items = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        qid, domain, question = m.group(1), m.group(2).strip(), m.group(3).strip()
        category = {"B": "basic", "M": "medium", "H": "hard"}[qid[0]]
        items.append({"id": qid, "category": category, "domain": domain, "q": question})
    return items


def run_one(item, session_id):
    payload = {"message": item["q"], "session_id": session_id}
    start = time.time()
    try:
        resp = requests.post(API, json=payload, stream=True, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        return {
            "id": item["id"],
            "category": item["category"],
            "question": item["q"],
            "expected_domain": item["domain"],
            "status": "CONNECTION_ERROR",
            "error": str(e)[:200],
            "elapsed_s": round(time.time() - start, 1),
            "routed_domain": "",
            "sql": "",
            "row_count": 0,
            "answer_preview": "",
            "has_chart": False,
            "has_table": False,
        }

    full_data = {}
    answer_tokens = []
    try:
        for line in resp.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data: "):
                continue
            payload_str = line[6:]
            if payload_str == "[DONE]":
                break
            try:
                chunk = json.loads(payload_str)
                if "t" in chunk:
                    answer_tokens.append(chunk["t"])
                elif "rows" in chunk:
                    full_data["preview"] = chunk
                elif "sql" in chunk and "attempt" in chunk:
                    full_data["sql"] = chunk.get("sql", "")
                elif "domain" in chunk and "reason" in chunk:
                    full_data["domain"] = chunk.get("domain", "")
                elif "domain" in chunk:
                    full_data.setdefault("domain", chunk.get("domain", ""))
                elif "error" in chunk:
                    full_data["error"] = chunk.get("error", "")
            except json.JSONDecodeError:
                pass
    except Exception as e:
        full_data["stream_error"] = str(e)

    elapsed = round(time.time() - start, 1)
    sql = full_data.get("sql", "")
    answer = "".join(answer_tokens)
    error = full_data.get("error", "") or full_data.get("stream_error", "")
    domain = full_data.get("domain", "")
    preview = full_data.get("preview", {})
    row_count = preview.get("row_count", 0) if preview else 0

    if error:
        status = "ERROR"
    elif not sql and not answer:
        status = "EMPTY"
    elif sql and row_count == 0 and not answer:
        status = "NO_ROWS"
    elif answer:
        status = "OK"
    else:
        status = "PARTIAL"

    return {
        "id": item["id"],
        "category": item["category"],
        "question": item["q"],
        "expected_domain": item["domain"],
        "routed_domain": domain,
        "status": status,
        "error": error[:200] if error else "",
        "elapsed_s": elapsed,
        "sql": sql[:500] if sql else "",
        "row_count": row_count,
        "answer_preview": answer[:300] if answer else "",
        "has_chart": bool(preview and row_count > 0),
        "has_table": row_count > 0,
    }


def summarize(results):
    n = len(results)
    by_status = {}
    for r in results:
        by_status[r["status"]] = by_status.get(r["status"], 0) + 1
    ok = by_status.get("OK", 0)

    by_cat = {}
    by_dom = {}
    routed_correct = 0
    for r in results:
        cat = r["category"]
        by_cat.setdefault(cat, {"total": 0, "ok": 0})
        by_cat[cat]["total"] += 1
        if r["status"] == "OK":
            by_cat[cat]["ok"] += 1
        dom = r["expected_domain"]
        by_dom.setdefault(dom, {"total": 0, "ok": 0})
        by_dom[dom]["total"] += 1
        if r["status"] == "OK":
            by_dom[dom]["ok"] += 1
        if r["routed_domain"] == r["expected_domain"]:
            routed_correct += 1

    print(f"\n{'='*70}")
    print(f"TOTAL: {ok}/{n} OK ({100*ok/max(n,1):.1f}%) | statuses: {by_status}")
    print(f"ROUTING accuracy: {routed_correct}/{n} ({100*routed_correct/max(n,1):.1f}%)")
    print(f"\nBy category:")
    for cat in ("basic", "medium", "hard"):
        if cat in by_cat:
            c = by_cat[cat]
            print(f"  {cat:<8} {c['ok']:>3}/{c['total']:<3}  ({100*c['ok']/c['total']:.0f}%)")
    print(f"\nBy domain:")
    for dom in sorted(by_dom):
        d = by_dom[dom]
        print(f"  {dom:<22} {d['ok']:>3}/{d['total']:<3}  ({100*d['ok']/d['total']:.0f}%)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--start", type=int, default=0, help="0-indexed start (inclusive)")
    ap.add_argument("--end", type=int, default=None, help="0-indexed end (exclusive)")
    ap.add_argument("--pace", type=float, default=1.0, help="seconds between calls")
    args = ap.parse_args()

    items = parse_corpus(args.corpus)
    if args.end is None:
        args.end = len(items)
    items = items[args.start : args.end]
    print(f"=== Running {len(items)} questions from {args.corpus} ===")

    results = []
    tag = uuid.uuid4().hex[:6]
    for i, item in enumerate(items):
        sid = f"corpus-{tag}-{item['id']}"
        print(f"  [{i+1}/{len(items)}] {item['id']}: {item['q'][:60]}...", flush=True)
        r = run_one(item, sid)
        results.append(r)
        print(f"    → {r['status']} | routed={r['routed_domain']} | {r['elapsed_s']}s | rows={r['row_count']}")
        # Save incrementally so partial runs are recoverable
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(results, indent=2, ensure_ascii=False))
        if i < len(items) - 1 and args.pace:
            time.sleep(args.pace)

    summarize(results)
    print(f"\nJSON: {args.output}")


if __name__ == "__main__":
    main()
