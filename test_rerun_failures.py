#!/usr/bin/env python3
"""Re-run only the failed questions from the 200-question batch test."""
import csv
import json
import sys
import time
import urllib.request
import urllib.error

API = "http://localhost:8000"

# Collect all failed question IDs
failed_ids = set()
failed_questions = {}

for csv_path in [
    'test_results/batch_1_20.csv',
    'test_results/batch_21_80.csv',
    'test_results/batch_81_200.csv',
]:
    try:
        with open(csv_path) as f:
            for row in csv.DictReader(f):
                if row['status'] in ('ERROR', 'CONNECTION_ERROR'):
                    qid = int(row['id'])
                    failed_ids.add(qid)
                    failed_questions[qid] = row['question']
    except FileNotFoundError:
        pass

# Load questions from JSON files too for fuller data
for json_path in [
    'test_results/batch_1_20.json',
    'test_results/batch_21_80.json',
    'test_results/batch_81_200.json',
]:
    try:
        with open(json_path) as f:
            for r in json.load(f):
                qid = int(r['id'])
                if qid in failed_ids and r.get('question'):
                    failed_questions[qid] = r['question']
    except (FileNotFoundError, json.JSONDecodeError):
        pass

print(f"Re-running {len(failed_questions)} failed questions...")
print("=" * 60)

results = []
ok = err = 0

for i, (qid, question) in enumerate(sorted(failed_questions.items()), 1):
    print(f"  [{i}/{len(failed_questions)}] Q{qid}: {question[:60]}...", flush=True)
    t0 = time.time()

    try:
        payload = json.dumps({
            "message": question,
            "session_id": f"retest_{qid}"
        }).encode()
        req = urllib.request.Request(
            f"{API}/api/chat",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        resp = urllib.request.urlopen(req, timeout=180)
        body = resp.read().decode()
        trace = json.loads(body)

        domain = trace.get("domain", "")
        error_msg = trace.get("error", "")
        result = trace.get("result", {})
        row_count = result.get("row_count", 0)
        sql = result.get("sql", "")
        final = trace.get("final", "")

        if error_msg:
            status = "ERROR"
        elif result:
            status = "OK"
        elif domain == "none":
            status = "OK"  # general/chat response
        else:
            status = "ERROR"
            error_msg = "no_result_no_error"

        elapsed = time.time() - t0
        results.append({
            "id": qid, "question": question, "status": status,
            "domain": domain, "duration_sec": round(elapsed, 1),
            "row_count": row_count, "sql": sql, "error": error_msg,
        })
        print(f"    → {status} | domain={domain} | {elapsed:.1f}s | rows={row_count}", flush=True)
        if status == "ERROR":
            err += 1
            print(f"    ERR: {error_msg[:120]}", flush=True)
        else:
            ok += 1

    except Exception as e:
        elapsed = time.time() - t0
        results.append({
            "id": qid, "question": question, "status": "CONNECTION_ERROR",
            "domain": "", "duration_sec": round(elapsed, 1),
            "row_count": 0, "sql": "", "error": str(e)[:300],
        })
        err += 1
        print(f"    → CONNECTION_ERROR: {str(e)[:100]}", flush=True)

    time.sleep(1)  # rate limit

print(f"\n{'='*60}")
print(f"RETEST RESULTS: {ok} OK | {err} ERROR out of {len(failed_questions)}")
if failed_questions:
    print(f"FIX RATE: {ok}/{len(failed_questions)} = {100*ok/len(failed_questions):.0f}% of previously-failed now pass")

# Save results
out_csv = "test_results/retest_failures.csv"
out_json = "test_results/retest_failures.json"

with open(out_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["id", "question", "status", "domain",
                                       "duration_sec", "row_count", "error"])
    w.writeheader()
    for r in results:
        w.writerow({k: r[k] for k in w.fieldnames})

with open(out_json, "w") as f:
    json.dump(results, f, indent=2, ensure_ascii=False)

print(f"\nCSV: {out_csv}")
print(f"JSON: {out_json}")
