"""Closed-loop learning from real failures, with a curated vocabulary.

`analytics` already records every failed turn, but nothing ever read it back, so the
agent repeated the same mistake forever. This module closes that loop WITHOUT feeding
user or model text into a prompt: a failure is classified into one of a fixed set of
buckets, and only the hand-written remediation sentence for that bucket is injected.
The database decides WHICH lesson applies, never WHAT it says, so a malicious question
or a hallucinated error string cannot become an instruction.

A lesson is injected only after the same bucket has failed `MIN_COUNT` times in the
same domain inside the lookback window, so one-off upstream blips stay out.
"""
from __future__ import annotations

import sqlite3
import time
from collections import Counter

from . import config

# Error signature -> (bucket, remediation injected into the SQL prompt).
# The remediation text is a constant authored here. Never interpolate error text.
CLASSES: list[tuple[str, tuple[str, ...], str]] = [
    ("sql_syntax", ("syntax error", 'expected ")"', "unexpected keyword"),
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

ACTIONS = {bucket: action for bucket, _, action in CLASSES}
ACTIONS["silent_or_empty"] = (
    "Turn failed with no error text: usually an empty or all-NULL result. Verify the "
    "empty-result rescue fired and the answer was honest about what it checked.")
ACTIONS["other"] = "Unclassified. Read a sample before deciding."

# What the SQL writer is told when a bucket keeps failing in this domain. Written for
# the model, unlike ACTIONS which is written for a human reviewer.
PROMPT_LESSONS: dict[str, str] = {
    "sql_syntax": (
        "Recent queries in this domain failed with BigQuery syntax errors. Before "
        "returning, re-read your SQL once and confirm every parenthesis, CTE, and "
        "string literal is closed and that it is ONE statement."),
    "truncated_sql": (
        "Recent queries in this domain were cut off mid-statement. Write the SHORTEST "
        "query that answers the question: merge CTEs, use SAFE_DIVIDE instead of extra "
        "self-joins, and select only the columns you actually output."),
    "bad_identifier": (
        "Recent queries in this domain referenced columns that do not exist. Use ONLY "
        "column names copied verbatim from the schema above, and check the exact "
        "kabkot/kabkota and kecamatan/kec_id spelling for each table you touch."),
    "scan_cap": (
        "Recent queries in this domain exceeded the scan cap. Filter the partition "
        "column to LITERAL values (month_id IN ('202605','202606'), not a subquery or "
        "a join to MAX()), and never SELECT *."),
    "correlate": (
        "Recent cross-domain questions in this domain failed to join. Give each table "
        "its own CTE with its own MAX(month_id), then join on the territory key."),
    "silent_or_empty": (
        "Recent queries in this domain returned zero or all-NULL rows. Do not invent an "
        "absolute threshold: rank with ORDER BY plus LIMIT, or derive the cut-off from "
        "the data, and verify the period you filter on actually exists in that table."),
}

_MAX_CHARS = 700
_cache: dict[str, tuple[float, list[str]]] = {}

def classify(error: str | None) -> str:
    text = (error or "").lower()
    if not text.strip():
        return "silent_or_empty"
    for bucket, needles, _ in CLASSES:
        if any(n in text for n in needles):
            return bucket
    return "other"

def failure_buckets(domain_key: str, days: int | None = None) -> Counter:
    """Count recent failure classes for one domain. Never raises."""
    from .memory import DB_PATH

    days = days or config.LESSON_DAYS
    since = time.time() - days * 86400
    try:
        with sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True) as con:
            rows = con.execute(
                "SELECT error_msg FROM analytics "
                "WHERE domain = ? AND success = 0 AND ts >= ?",
                (domain_key, since),
            ).fetchall()
    except (sqlite3.Error, OSError):
        return Counter()
    return Counter(classify(r[0]) for r in rows)

def domain_lessons(domain_key: str) -> list[str]:
    """Curated remediation lines for the failure classes that keep recurring."""
    if not config.LESSONS_ENABLED or not domain_key:
        return []
    hit = _cache.get(domain_key)
    now = time.time()
    if hit and now - hit[0] < config.LESSON_CACHE_TTL_S:
        return hit[1]
    counts = failure_buckets(domain_key)
    picked = [
        PROMPT_LESSONS[bucket]
        for bucket, n in counts.most_common()
        if n >= config.LESSON_MIN_COUNT and bucket in PROMPT_LESSONS
    ][: config.LESSON_MAX]
    _cache[domain_key] = (now, picked)
    return picked

def lessons_text(domain_key: str) -> str:
    """Prompt block, or empty string. Capped so it can never crowd out the schema."""
    picked = domain_lessons(domain_key)
    if not picked:
        return ""
    body = "\n".join(f"- {line}" for line in picked)[:_MAX_CHARS]
    return ("\n\nRECURRING FAILURES IN THIS DOMAIN (learned from real runs, fix these "
            "proactively):\n" + body)

def reset_cache() -> None:
    _cache.clear()
