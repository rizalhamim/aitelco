#!/usr/bin/env python3
"""Re-run only failed questions (CONNECTION_ERROR or ERROR) from batch CSVs."""
import csv
import json
import sys
import time
import requests
import uuid

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

API = "http://localhost:8000/api/chat/stream"
TIMEOUT = 180

# Load all test questions
test_questions = json.loads(open("test_batch.py").read().split("QUESTIONS = ")[1].split("\n]\n")[0] + "\n]") if False else None

# Actually load from test_batch module
import importlib.util
spec = importlib.util.spec_from_file_location("test_batch", "test_batch.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
QUESTIONS = mod.QUESTIONS

def run_question(q):
    sid = f"rerun-{uuid.uuid4().hex[:8]}"
    start = time.time()
    try:
        resp = requests.post(API, json={"message": q["question"], "session_id": sid},
                             stream=True, timeout=TIMEOUT)
        resp.raise_for_status()
    except Exception as e:
        return {"status": "CONNECTION_ERROR", "error": str(e), "elapsed_s": round(time.time()-start, 1),
                "routed_domain": "", "sql": "", "row_count": 0, "answer_preview": "", "has_chart": False, "has_table": False}

    full_data = {}
    answer_tokens = []
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

    elapsed = round(time.time() - start, 1)
    answer = "".join(answer_tokens)
    preview = full_data.get("preview", {})
    row_count = preview.get("row_count", 0) if preview else 0

    status = "ERROR" if full_data.get("error") else ("OK" if answer else "PARTIAL")
    return {
        "status": status,
        "routed_domain": full_data.get("domain", ""),
        "sql": full_data.get("sql", ""),
        "row_count": row_count,
        "answer_preview": answer[:200],
        "error": full_data.get("error", ""),
        "elapsed_s": elapsed,
        "has_chart": bool(preview and row_count > 0),
        "has_table": row_count > 0,
    }


def rerun_failures(csv_files):
    """Collect failed IDs from CSVs, rerun them, write combined results."""
    failed = []
    all_results = {}
    
    for csv_file in csv_files:
        with open(csv_file) as f:
            rows = list(csv.DictReader(f))
            for row in rows:
                qid = int(row["id"])
                if row["status"] in ("CONNECTION_ERROR", "ERROR"):
                    failed.append(qid)
                else:
                    all_results[qid] = row
    
    print(f"Found {len(failed)} failed questions to rerun")
    
    for i, qid in enumerate(sorted(failed)):
        q = QUESTIONS[qid - 1]  # 1-indexed
        question_text = q.get('question') or q.get('q', '')
        expected = q.get('expected_domain') or q.get('domain', '')
        print(f"  [{i+1}/{len(failed)}] Q{qid}: {question_text[:60]}...")
        result = run_question({"question": question_text})
        result["id"] = str(qid)
        result["question"] = question_text
        result["expected_domain"] = expected
        all_results[qid] = result
        print(f"    → {result['status']} | domain={result['routed_domain']} | {result['elapsed_s']}s | rows={result['row_count']}")
    
    # Write combined output
    out_path = "test_results/rerun_results.csv"
    fieldnames = ["id", "question", "expected_domain", "routed_domain", "status", "error",
                  "elapsed_s", "sql", "row_count", "answer_preview", "has_chart", "has_table"]
    with open(out_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for qid in sorted(all_results.keys()):
            row = all_results[qid]
            w.writerow({k: row.get(k, "") for k in fieldnames})
    
    # Summary
    results = list(all_results.values())
    ok = sum(1 for x in results if x.get("status") == "OK")
    err = sum(1 for x in results if x.get("status") in ("ERROR", "CONNECTION_ERROR"))
    print(f"\n{'='*60}")
    print(f"RERUN RESULTS: {ok} OK | {err} ERROR | Total: {len(results)}")
    print(f"CSV: {out_path}")


if __name__ == "__main__":
    csv_files = sys.argv[1:] or [
        "test_results/batch_1_20.csv",
        "test_results/batch_21_80.csv",
        "test_results/batch_81_200.csv",
    ]
    rerun_failures([f for f in csv_files if __import__("os").path.exists(f)])
