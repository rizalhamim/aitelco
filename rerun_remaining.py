#!/usr/bin/env python3
"""Rerun specific question IDs that failed and weren't retested."""

import json
import csv
import time
import urllib.request
import urllib.error
import sys

# Load questions from test_batch
sys.path.insert(0, '/home/ubuntu/telco-ai')
from test_batch import QUESTIONS

# IDs to rerun
REMAINING_IDS = [26, 27, 28, 29, 31, 32, 34, 90, 91, 92, 93, 102, 125, 130, 131, 132, 
                 146, 148, 170, 177, 181, 183, 184, 185, 186, 187, 189, 191, 192, 193, 
                 196, 197, 198, 199, 200]

API_URL = "http://localhost:8000/api/chat"


def run_question(qid: int) -> dict:
    """Run a single question and return result."""
    q = QUESTIONS[qid - 1]
    question_text = q.get('question') or q.get('q', '')
    expected = q.get('expected_domain') or q.get('domain', '')
    
    start = time.time()
    try:
        payload = json.dumps({"message": question_text, "session_id": f"rerun_{qid}"}).encode()
        req = urllib.request.Request(API_URL, data=payload, 
                                      headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode())
        
        elapsed = time.time() - start
        has_error = bool(data.get("error"))
        has_rows = data.get("result", {}).get("row_count", 0) > 0
        status = "ERROR" if has_error else "OK"
        return {
            "id": str(qid),
            "question": question_text,
            "expected_domain": expected,
            "routed_domain": data.get("domain", ""),
            "status": status,
            "row_count": data.get("result", {}).get("row_count", 0),
            "elapsed_s": f"{elapsed:.1f}",
            "error": (data.get("error", "") or "")[:200]
        }
    except Exception as e:
        elapsed = time.time() - start
        return {
            "id": str(qid),
            "question": question_text,
            "expected_domain": expected,
            "routed_domain": "",
            "status": "CONNECTION_ERROR",
            "row_count": 0,
            "elapsed_s": f"{elapsed:.1f}",
            "error": str(e)[:200]
        }


def main():
    print(f"Rerunning {len(REMAINING_IDS)} remaining questions...")
    results = []
    
    for i, qid in enumerate(REMAINING_IDS):
        q = QUESTIONS[qid - 1]
        question_text = q.get('question') or q.get('q', '')[:60]
        print(f"  [{i+1}/{len(REMAINING_IDS)}] Q{qid}: {question_text[:55]}...")
        
        result = run_question(qid)
        results.append(result)
        print(f"    → {result['status']} | domain={result['routed_domain']} | {result['elapsed_s']}s | rows={result['row_count']}")
        sys.stdout.flush()
    
    # Summary
    ok = sum(1 for r in results if r['status'] == 'OK')
    err = sum(1 for r in results if r['status'] == 'ERROR')
    conn = sum(1 for r in results if r['status'] == 'CONNECTION_ERROR')
    
    print("\n" + "=" * 60)
    print(f"RESULTS: {ok} OK | {err} ERROR | {conn} CONN_ERR out of {len(REMAINING_IDS)}")
    
    # Save
    with open('test_results/rerun_remaining.csv', 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=results[0].keys())
        w.writeheader()
        w.writerows(results)
    
    with open('test_results/rerun_remaining.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"CSV: test_results/rerun_remaining.csv")
    print(f"JSON: test_results/rerun_remaining.json")


if __name__ == "__main__":
    main()
