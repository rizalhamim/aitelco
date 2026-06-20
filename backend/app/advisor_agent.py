"""Advisor / Recommendation agent (sequential multi-agent swarm).

Used for FOLLOW-UP analytical questions like:
  "apa yang perlu diimprove untuk menaikkan revenue kota Surabaya?"

Flow (sequential, agents pass context to each other — no parallel re-query):
  1. PLAN  — Advisor (Analyst LLM) reads the data ALREADY on screen (profile deck
     or last query result from session memory). It decides if that data is enough
     to answer, or which 1-3 SUPPORTING queries it still needs (per domain).
  2. FETCH — for each requested supporting query, the SQL agent writes & runs it
     ONE BY ONE (sequential), and the new data is appended to the working context.
  3. ADVISE — Advisor synthesizes the final business recommendation grounded in
     all the gathered data (existing + supporting), with concrete action items.

This avoids re-running the whole expensive pipeline and prevents the timeout /
"network error" that happened when a follow-up triggered a full re-query.
"""
import json
import logging

from . import llm, config, knowledge, orchestrator
from .bigquery_tool import run_query

log = logging.getLogger("advisor_agent")

# Heuristic: is this an advisory / recommendation / "why / what-to-improve" question?
_ADVISORY_KEYWORDS = [
    "improve", "diimprove", "tingkatkan", "menaikkan", "naikkan", "rekomendasi",
    "recommend", "saran", "strategi", "strategy", "apa yang perlu", "bagaimana cara",
    "how to", "what should", "actionable", "perbaiki", "optimalkan", "optimize",
    "kenapa", "mengapa", "why", "penyebab", "root cause", "akar masalah",
    "insight", "analisa lebih", "analisis lebih", "deep dive", "deepdive",
    "kesimpulan", "summary", "ringkas", "to do", "todo", "langkah",
]


def is_advisory(question: str) -> bool:
    q = (question or "").lower()
    return any(k in q for k in _ADVISORY_KEYWORDS)


def _context_digest(ctx: dict, max_chars: int = 16000) -> str:
    """Turn the stored analysis context into a compact text the LLM can reason on."""
    if not ctx:
        return ""
    kind = ctx.get("kind")
    payload = ctx.get("payload") or {}
    parts = []
    if kind == "profile":
        parts.append(f"EXISTING PROFILE DATA for {ctx.get('territory','')}:")
        for sec in payload.get("sections", []):
            title = sec.get("section_title", "")
            if sec.get("error"):
                continue
            cols = sec.get("columns", [])
            rows = sec.get("rows", [])[:8]
            parts.append(f"\n## {title}\ncolumns: {cols}")
            for r in rows:
                parts.append(json.dumps(r, ensure_ascii=False, default=str))
    elif kind == "query":
        parts.append(f"EXISTING QUERY RESULT for {ctx.get('territory','')}:")
        parts.append(f"columns: {payload.get('columns', [])}")
        for r in (payload.get("rows") or [])[:25]:
            parts.append(json.dumps(r, ensure_ascii=False, default=str))
    text = "\n".join(parts)
    return text[:max_chars]


_PLAN_SYS = (
    "You are the ADVISOR agent — a senior IOH Java telecom business strategist. "
    "A user asked a follow-up ANALYTICAL/RECOMMENDATION question. You already have "
    "the data from the previous analysis on screen (provided below). "
    "Decide whether that data is ENOUGH to give a solid, number-grounded recommendation, "
    "or whether you need a FEW supporting data points first.\n\n"
    "Available data domains you can request from (for supporting queries):\n{domains}\n\n"
    "Return ONLY compact JSON:\n"
    "{{\n"
    '  "have_enough": true|false,\n'
    '  "reasoning": "<1-2 sentences>",\n'
    '  "supporting_queries": [\n'
    '     {{"domain": "<domain_key>", "question": "<specific data question to fetch>"}}\n'
    "  ]  // 0-3 items; empty if have_enough=true. Only request what truly adds value.\n"
    "}}\n"
    "Be frugal: prefer 0-2 supporting queries. Never request the same data already shown."
)


def plan(question: str, ctx: dict, language: str = "id") -> dict:
    digest = _context_digest(ctx)
    domains = knowledge.domain_overview_text()
    sys = _PLAN_SYS.format(domains=domains)
    msgs = [
        {"role": "system", "content": sys},
        {"role": "user", "content": (
            f"USER FOLLOW-UP QUESTION: {question}\n\n"
            f"--- DATA ALREADY AVAILABLE ---\n{digest if digest else '(none)'}\n\n"
            "Decide have_enough and any supporting_queries. JSON only.")},
    ]
    try:
        out = llm.chat_json(msgs, model=config.LLM_MODEL_ANALYST, max_tokens=900)
    except Exception as e:
        log.error(f"advisor.plan failed: {e}")
        out = {}
    sq = out.get("supporting_queries") or []
    clean = []
    kb = knowledge.load_kb()
    for item in sq[:3]:
        if isinstance(item, dict) and item.get("domain") in kb["domains"] and item.get("question"):
            clean.append({"domain": item["domain"], "question": str(item["question"])})
    return {
        "have_enough": bool(out.get("have_enough", True)) if not clean else False,
        "reasoning": str(out.get("reasoning", "")),
        "supporting_queries": clean,
    }


def fetch_supporting(domain: str, question: str) -> dict:
    """Run ONE supporting query via the SQL agent. Returns a compact result dict."""
    try:
        gen = orchestrator.write_sql(domain, question)
        sql = gen.get("sql", "")
        if not sql:
            return {"domain": domain, "question": question, "error": "no_sql"}
        res = run_query(sql)
        return {
            "domain": domain, "question": question, "sql": sql,
            "columns": res.get("columns", []),
            "rows": res.get("rows", [])[:15],
            "row_count": res.get("row_count", 0),
        }
    except Exception as e:
        log.warning(f"advisor.fetch_supporting failed ({domain}): {e}")
        return {"domain": domain, "question": question, "error": str(e)[:200]}


_ADVISE_SYS = (
    "You are the ADVISOR agent — a senior IOH Java telecom business strategist. "
    "Using ALL the data provided (the existing analysis + any supporting data), "
    "answer the user's follow-up question with a concrete, number-grounded business "
    "recommendation. Voice: confident, numbers up front, no exclamation marks, no emoji.\n\n"
    "Structure the answer in markdown:\n"
    "## Ringkasan Situasi  (2-3 kalimat, anchored to the key numbers)\n"
    "## Temuan Utama  (3-5 bullets, each with the supporting number)\n"
    "## Rekomendasi  (3-6 prioritized, actionable items — what to do, where, expected impact)\n"
    "## Langkah Berikutnya / Key To-Do  (short checklist)\n"
    "Reply in {language}. NEVER invent numbers — only use figures present in the data. "
    "If data is insufficient for a point, say so briefly."
)


def advise_stream(question: str, ctx: dict, supporting: list[dict], language: str = "id"):
    """Stream the final recommendation (Coder model for good narrative)."""
    digest = _context_digest(ctx)
    sup_text = ""
    for s in supporting:
        if s.get("error"):
            continue
        sup_text += f"\n## SUPPORTING: {s.get('question','')}\ncolumns: {s.get('columns',[])}\n"
        for r in (s.get("rows") or [])[:12]:
            sup_text += json.dumps(r, ensure_ascii=False, default=str) + "\n"
    sys = _ADVISE_SYS.format(language=language)
    user = (
        f"USER FOLLOW-UP QUESTION: {question}\n\n"
        f"--- EXISTING ANALYSIS DATA ---\n{digest if digest else '(none)'}\n\n"
        f"--- SUPPORTING DATA FETCHED ---\n{sup_text if sup_text else '(none)'}\n\n"
        "Write the recommendation now."
    )
    msgs = [{"role": "system", "content": sys}, {"role": "user", "content": user}]
    yield from llm.chat_stream_complete(msgs, model=config.LLM_MODEL_CODER, max_tokens=2200)
