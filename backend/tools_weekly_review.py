#!/usr/bin/env python3
"""Weekly agent-quality review from real chat traffic. REPORT ONLY.

Reads the last N days of `analytics` from backend/data/sessions.db, buckets the
failures by domain and error class, and writes a compact markdown report to
backend/data/training/weekly/. It never edits the knowledge base, never touches
prompts, and never feeds chat text back into the agent: every finding is meant to
become a REVIEWED knowledge-base fact, a benchmark case, or a code fix.

    venv/bin/python tools_weekly_review.py               # last 7 days
    venv/bin/python tools_weekly_review.py --days 30
    venv/bin/python tools_weekly_review.py --stdout      # print, do not write
"""
from __future__ import annotations

import argparse
import sqlite3
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "sessions.db"
OUT_DIR = ROOT / "data" / "training" / "weekly"

# Error signature -> (bucket, what to do about it). The action text is the point of
# the report: a bucket without a next step just becomes noise.
CLASSES: list[tuple[str, tuple[str, ...], str]] = [
    ("sql_syntax", ("syntax error", "expected \")\"", "unexpected keyword"),
     "SQL writer produced invalid SQL. Check for truncation first (unbalanced parens "
     "means the generation was cut off, so the fix is a SIMPLER query, not a patch)."),
    ("truncated_sql", ("structurally invalid", "looks cut off", "dangling keyword"),
     "Generation ran out of room. Consider a worked example in the domain SQL prompt "
     "for this question shape."),
    ("bad_identifier", ("unrecognized name", "not found inside", "does not exist",
                        "did you mean"),
     "Model invented a column or table. Fix the domain schema facts in "
     "knowledge_base.json so the right column is obvious."),
    ("scan_cap", ("exceeding the", "would scan", "quota"),
     "Query too wide. Add or sharpen a partition-filter key fact for this domain."),
    ("timeout", ("timeout", "timed out", "deadline"),
     "Latency problem, not a knowledge problem. Check upstream LLM health first."),
    ("upstream_llm", ("http 429", "http 400", "http 500", "long_context_beta",
                      "sql_gen_failed"),
     "Upstream proxy or model error. See docs/9router-haiku-long-context-bug.md."),
    ("correlate", ("no overlapping", "two domains", "planning was incomplete"),
     "Correlation planning or join failed. Check domain ownership of both metrics."),
    ("out_of_scope", ("di luar territory", "tidak memiliki kolom", "does not cover"),
     "Scope gate rejected the question. Confirm this is genuinely out of scope, not a "
     "missing table."),
]


def classify(error: str | None) -> str:
    text = (error or "").lower()
    if not text.strip():
        return "silent_or_empty"
    for bucket, needles, _ in CLASSES:
        if any(n in text for n in needles):
            return bucket
    return "other"


ACTIONS = {bucket: action for bucket, _, action in CLASSES}
ACTIONS["silent_or_empty"] = (
    "Turn failed with no error text: usually an empty or all-NULL result. Verify the "
    "empty-result rescue fired and the answer was honest about what it checked.")
ACTIONS["other"] = "Unclassified. Read a sample before deciding."


def build_report(days: int) -> str:
    since = int(time.time()) - days * 86400
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "SELECT question, domain, error_msg, success FROM analytics "
            "WHERE ts >= ? ORDER BY ts DESC", (since,)).fetchall()
    finally:
        con.close()

    total = len(rows)
    failures = [r for r in rows if not r[3]]
    by_class: dict[str, list[tuple[str, str, str]]] = defaultdict(list)
    for question, domain, error, _ in failures:
        by_class[classify(error)].append((domain or "?", question or "", error or ""))
    by_domain = Counter((r[1] or "?") for r in failures)

    today = time.strftime("%Y-%m-%d")
    rate = (len(failures) / total * 100) if total else 0.0
    out = [
        f"# Weekly agent review {today} (last {days} days)",
        "",
        "Report only. Every finding must become a reviewed knowledge_base.json fact, a",
        "benchmark case in data/training/, or a code fix. Nothing here is fed back into",
        "the agent automatically.",
        "",
        f"- Turns: {total}",
        f"- Failures: {len(failures)} ({rate:.1f}%)",
        "",
        "## Failures by class",
        "",
    ]
    if not failures:
        out.append("No failures in the window.")
    for bucket, items in sorted(by_class.items(), key=lambda kv: -len(kv[1])):
        out.append(f"### {bucket} ({len(items)})")
        out.append("")
        out.append(f"Action: {ACTIONS.get(bucket, '')}")
        out.append("")
        seen: set[str] = set()
        for domain, question, error in items:
            key = question[:80]
            if key in seen:
                continue
            seen.add(key)
            out.append(f"- `{domain}` {question[:110]}")
            if error.strip():
                out.append(f"  - {error.strip()[:150]}")
            if len(seen) >= 5:
                break
        out.append("")

    out.append("## Failures by domain")
    out.append("")
    for domain, n in by_domain.most_common(10):
        out.append(f"- {domain}: {n}")
    out.append("")
    out.append("## Next actions")
    out.append("")
    out.append("For each class above, record the decision taken in the phase log of")
    out.append("`docs/agent-improvement-plan.md`.")
    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--stdout", action="store_true")
    args = parser.parse_args()

    if not DB.exists():
        raise SystemExit(f"sessions.db not found at {DB}")

    report = build_report(args.days)
    if args.stdout:
        print(report)
        return 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"review-{time.strftime('%Y-%m-%d')}.md"
    path.write_text(report)
    print(f"written: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
