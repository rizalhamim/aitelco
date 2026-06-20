"""AI-powered chat summarizer using the Analyst LLM (Agent-Java-v02.3-Analys).

Takes the full on-screen chat transcript and produces a structured executive
summary: key points, findings, insights, key numbers, and action items.
"""
import json
import logging

from . import llm, config

log = logging.getLogger("chat_summary")

_SUMMARY_SYS = (
    "You are a senior telecom business analyst at Indosat Ooredoo Hutchison (IOH) Java. "
    "You are given a full chat transcript between a user and an AI data analyst (questions + "
    "data answers, including numbers and tables). Produce a concise, executive-grade SUMMARY "
    "of the ENTIRE conversation.\n\n"
    "Voice & tone: confident, numbers-up-front, no exclamation marks, no emoji, no marketing "
    "jargon. Use the user's language (Indonesian if the chat is Indonesian).\n\n"
    "Return ONLY a compact JSON object with EXACTLY these keys:\n"
    "{\n"
    '  "title": "<short title of the analysis session, max 80 chars>",\n'
    '  "overview": "<2-3 sentence executive overview>",\n'
    '  "key_points": ["<bullet>", ...],            // 3-6 main discussion points\n'
    '  "findings": ["<finding with the number>", ...], // 3-7 concrete findings, each anchored to a real number/metric from the chat\n'
    '  "insights": ["<insight>", ...],              // 2-5 business insights / what it means\n'
    '  "key_numbers": [{"label":"<metric>","value":"<value>","note":"<optional context>"}, ...], // 3-8 most important figures\n'
    '  "action_items": ["<actionable next step / key to-do>", ...] // 3-6 recommendations\n'
    "}\n"
    "MAIN TOPIC RULE: The LAST user question (marked === MAIN TOPIC ===) is the primary subject. "
    "The title and overview MUST center on that last topic; earlier turns are supporting context. "
    "Rules: NEVER invent numbers — only use figures that appear in the transcript (including the "
    "DATA tables provided). If the chat has no data, still summarize the discussion. Keep each "
    "bullet one sentence. Output JSON only."
)


def _rows_to_text(columns, rows, max_rows=12):
    if not columns or not rows:
        return ""
    out = [" | ".join(str(c) for c in columns)]
    for r in rows[:max_rows]:
        out.append(" | ".join("" if r.get(c) is None else str(r.get(c)) for c in columns))
    return "DATA:\n" + "\n".join(out)


def _build_transcript(messages: list[dict]) -> str:
    """messages: [{role, content, domain?, row_count?, result?, profile_sections?}].
    Includes the underlying data tables so the AI summary is grounded in numbers.
    The LAST user turn is flagged as the MAIN TOPIC."""
    # index of the last user message (main topic)
    last_user = None
    for i in range(len(messages) - 1, -1, -1):
        if messages[i].get("role") == "user" and (messages[i].get("content") or "").strip():
            last_user = i
            break
    lines = []
    for idx, m in enumerate(messages):
        role = "USER" if m.get("role") == "user" else "AI ANALYST"
        content = (m.get("content") or "").strip()
        extra = ""
        if m.get("domain"):
            extra += f" [domain: {m['domain']}]"
        if m.get("row_count"):
            extra += f" [rows: {m['row_count']}]"
        header = f"{role}{extra}:"
        if idx == last_user:
            header = "=== MAIN TOPIC ===\n" + header
        block = [header]
        if content:
            block.append(content)
        # include data tables
        res = m.get("result") or {}
        if isinstance(res, dict) and res.get("columns") and res.get("rows"):
            block.append(_rows_to_text(res["columns"], res["rows"]))
        for sec in (m.get("profile_sections") or []):
            if sec.get("columns") and sec.get("rows"):
                block.append(f"[{sec.get('section_title','')}] " + _rows_to_text(sec["columns"], sec["rows"], 8))
        if len(block) > 1 or content:
            lines.append("\n".join(block))
    return "\n\n".join(lines)


def summarize_chat(messages: list[dict], language: str = "id") -> dict:
    """Return a structured summary dict using the Analyst model."""
    transcript = _build_transcript(messages)
    if not transcript.strip():
        return {
            "title": "Chat Summary",
            "overview": "Tidak ada percakapan untuk diringkas.",
            "key_points": [], "findings": [], "insights": [],
            "key_numbers": [], "action_items": [],
        }
    # cap transcript size to keep prompt bounded
    if len(transcript) > 24000:
        transcript = transcript[:24000] + "\n\n[...transcript truncated...]"

    msgs = [
        {"role": "system", "content": _SUMMARY_SYS + f"\n\nReply language: {language}."},
        {"role": "user", "content": "Ringkas seluruh percakapan berikut:\n\n" + transcript},
    ]
    try:
        result = llm.chat_json(msgs, model=config.LLM_MODEL_ANALYST, max_tokens=2500)
    except Exception as e:
        log.error(f"summarize_chat failed: {e}")
        result = {}

    # normalize keys / defaults
    out = {
        "title": str(result.get("title") or "Chat Summary")[:120],
        "overview": str(result.get("overview") or ""),
        "key_points": result.get("key_points") or [],
        "findings": result.get("findings") or [],
        "insights": result.get("insights") or [],
        "key_numbers": result.get("key_numbers") or [],
        "action_items": result.get("action_items") or [],
    }
    # coerce list[str]
    for k in ("key_points", "findings", "insights", "action_items"):
        out[k] = [str(x) for x in out[k] if str(x).strip()][:8]
    # coerce key_numbers
    kn = []
    for item in out["key_numbers"][:10]:
        if isinstance(item, dict):
            kn.append({
                "label": str(item.get("label", "")),
                "value": str(item.get("value", "")),
                "note": str(item.get("note", "")),
            })
        else:
            kn.append({"label": "", "value": str(item), "note": ""})
    out["key_numbers"] = kn
    return out
