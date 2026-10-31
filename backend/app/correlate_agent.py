"""Cross-domain CORRELATION agent.

Handles questions that need TWO different data domains joined on a common
territory key, e.g. "kabkota mana yang HVC ratio tinggi TAPI site congestion juga
tinggi" or "korelasikan kabkota yang VLR YoY decline dengan trend FB speed".

Flow (reuses the proven profile fan-out infra, NOT ad-hoc 2 calls in the router):
  1. plan_correlation() -> LLM splits the question into TWO sub-queries, each with
     its own domain + a SQL question that returns (join_key, metric) at the SAME
     territory grain.
  2. The caller runs both sub-queries in parallel (profile_engine.run_parallel_stream).
  3. correlate_join() merges the two result sets on the join key in Python.
  4. synthesize_correlation_stream() narrates the relationship (co-occurrence,
     direction, notable territories) over the merged table.
"""
from __future__ import annotations
import json

from . import llm, config, knowledge
from .orchestrator import IDENTITY


PLANNER_SYS = IDENTITY + """

You are the CROSS-DOMAIN CORRELATION PLANNER for the IOH Java telco AI. The user
wants to relate TWO different metrics that live in DIFFERENT data domains, joined
by a common TERRITORY key.

Available domains and what they hold:
{domains}

Your job: split the question into EXACTLY TWO sub-queries (A and B). Rules:
- Each sub-query targets ONE domain and asks for that domain's metric AGGREGATED
  PER TERRITORY at the SAME grain (default: per kabkota; use kecamatan/area/district/region
  only if the user said so). Both A and B MUST use the SAME grain and the SAME
  join key name.
- Choose `join_key`: 'kabkota' (default), 'kec_id' for kecamatan, or 'region'/'area'/'district'.
- Each sub-query's `question` MUST instruct the SQL agent to output: the join key
  column (named exactly = join_key), plus the metric column(s) for that domain, for
  the latest period (and a prior period if the user asked YoY/MoM/trend), filtered
  to any territory the user named.
- Pick the right domain for each side. Examples:
  * "HVC ratio" -> customer_hvc ; "site congestion / occupancy / availability" -> network.
  * "VLR / subscriber / revenue / churn" -> kpi_summary (or site_performance if per-site).
  * "FB speed / latency / congestion / OpenSignal experience" -> network_benchmark.
  * "market share" -> competitive ; "product/package revenue" -> product ;
    "outlet/URO/SSO/primary-secondary-tertiary" -> sales_distribution.
- `relation_hint`: a short phrase describing the expected relationship to test
  (e.g. "high HVC ratio vs high congestion", "VLR YoY decline vs FB speed trend").

Output ONLY compact JSON with this FLAT schema (no nested objects). All 8 keys are REQUIRED:
{{
 "territory_grain": "kabkota|kecamatan|region|area|district",
 "join_key": "kabkota|kec_id|region|area|district",
 "relation_hint": "<short phrase>",
 "language": "id|en",
 "domain_a": "<domain key for metric A>",
 "label_a": "<short label for metric A>",
 "question_a": "<SQL question: output join_key + metric A per territory>",
 "domain_b": "<domain key for metric B>",
 "label_b": "<short label for metric B>",
 "question_b": "<SQL question: output join_key + metric B per territory>"
}}
"""


def _normalise_plan(out: dict) -> dict:
    """Normalise the FLAT planner schema into the nested shape the caller expects."""
    if not isinstance(out, dict):
        return {}
    if "sub_a" not in out and out.get("domain_a"):
        out["sub_a"] = {"domain": out.get("domain_a"), "label": out.get("label_a", "Metric A"),
                        "question": out.get("question_a", "")}
    if "sub_b" not in out and out.get("domain_b"):
        out["sub_b"] = {"domain": out.get("domain_b"), "label": out.get("label_b", "Metric B"),
                        "question": out.get("question_b", "")}
    return out


def plan_is_valid(plan: dict) -> bool:
    """A usable correlation plan needs TWO DIFFERENT domains, each with a sub-question."""
    if not isinstance(plan, dict):
        return False
    a = plan.get("sub_a") or {}
    b = plan.get("sub_b") or {}
    da, db = (a.get("domain") or "").strip(), (b.get("domain") or "").strip()
    if not da or not db or da == db:
        return False
    return bool((a.get("question") or "").strip() and (b.get("question") or "").strip())


def plan_correlation(question: str, history: list | None = None) -> dict:
    """Plan a 2-domain correlation. Retries once when the planner collapses both sides
    onto the SAME domain, then gives up so the caller can fall back to single-domain
    routing instead of running an invalid A == B plan."""
    sys = PLANNER_SYS.format(domains=knowledge.domain_overview_text(question))
    base_msgs = [{"role": "system", "content": sys}]
    if history:
        for h in history[-4:]:
            base_msgs.append(h)
    base_msgs.append({"role": "user", "content": question})

    # ANALYST model is more reliable for this structured 2-domain split than FAST.
    out = _normalise_plan(llm.chat_json(base_msgs, model=config.LLM_MODEL_ANALYST,
                                        max_tokens=900))
    if plan_is_valid(out):
        return out

    same = ((out.get("sub_a") or {}).get("domain") or "").strip()
    retry_msgs = list(base_msgs)
    retry_msgs.append({
        "role": "user",
        "content": (
            "Your previous plan was REJECTED: it put both metrics in the same domain"
            + (f" ('{same}')" if same else "")
            + ". `domain_a` and `domain_b` MUST be TWO DIFFERENT domain keys, each owning "
              "one of the two metrics. Re-read the domain list and map each metric to the "
              "domain whose tables actually hold it. If both metrics genuinely live in ONE "
              "domain, reply exactly {\"single_domain\": \"<domain key>\"} instead."
        ),
    })
    retry = _normalise_plan(llm.chat_json(retry_msgs, model=config.LLM_MODEL_ANALYST,
                                          max_tokens=900))
    if plan_is_valid(retry):
        return retry
    if isinstance(retry, dict) and retry.get("single_domain"):
        return {"invalid": "single_domain", "single_domain": retry["single_domain"]}
    fallback = same or ((retry.get("sub_a") or {}).get("domain") if isinstance(retry, dict) else "")
    return {"invalid": "same_domain", "single_domain": fallback or ""}


def _find_key_col(columns: list[str], join_key: str) -> str | None:
    jk = join_key.lower()
    for c in columns:
        if c.lower() == jk:
            return c
    # fallbacks
    for cand in (jk, "kabkota", "kabkot", "kec_id", "kecamatan", "region", "area", "district", "branch"):
        for c in columns:
            if c.lower() == cand:
                return c
    return None


def correlate_join(join_key: str, res_a: dict, res_b: dict,
                   label_a: str, label_b: str) -> dict:
    """Inner-join two per-territory result sets on the join key. Returns a merged
    table {columns, rows} plus simple stats for the synthesizer."""
    ca = res_a.get("columns", []) or []
    cb = res_b.get("columns", []) or []
    ka = _find_key_col(ca, join_key)
    kb_ = _find_key_col(cb, join_key)
    if not ka or not kb_:
        return {"error": "join key not found in one side",
                "columns": [], "rows": [], "row_count": 0}

    # metric columns = everything that is not the key (and not an obvious id/name dup)
    def metric_cols(cols, key):
        return [c for c in cols if c != key]

    ma = metric_cols(ca, ka)
    mb = metric_cols(cb, kb_)

    # index B by key
    bmap = {}
    for r in res_b.get("rows", []):
        k = str(r.get(kb_, "")).strip().upper()
        if k:
            bmap[k] = r

    merged_rows = []
    for r in res_a.get("rows", []):
        k = str(r.get(ka, "")).strip().upper()
        if not k or k not in bmap:
            continue
        rb = bmap[k]
        row = {"territory": r.get(ka)}
        for c in ma:
            row[f"A_{c}"] = r.get(c)
        for c in mb:
            row[f"B_{c}"] = rb.get(c)
        merged_rows.append(row)

    cols = ["territory"] + [f"A_{c}" for c in ma] + [f"B_{c}" for c in mb]
    return {
        "columns": cols,
        "rows": merged_rows,
        "row_count": len(merged_rows),
        "metric_a_cols": [f"A_{c}" for c in ma],
        "metric_b_cols": [f"B_{c}" for c in mb],
        "label_a": label_a,
        "label_b": label_b,
        "matched": len(merged_rows),
        "n_a": res_a.get("row_count", 0),
        "n_b": res_b.get("row_count", 0),
    }


SYNTH_SYS = IDENTITY + """

You are the CROSS-DOMAIN CORRELATION ANALYST for IOH Java. You are given a MERGED
table that joins two metrics (A and B) from two different domains, per territory.
Analyse and explain the RELATIONSHIP (reply in {language}):
- State what A and B are (use the provided labels) and how many territories matched.
- Identify territories where BOTH conditions hold (the co-occurrence the user asked
  about, e.g. high A AND high B) and name the top ones with their numbers.
- Describe the direction of the relationship qualitatively: do high-A territories
  tend to have high (or low) B? If the data clearly trends, say so; if it's mixed,
  say it's weak/no clear correlation. Do NOT fabricate a precise correlation
  coefficient unless it is obvious from the data.
- Give 2-3 actionable takeaways tied to the territories.
- Be concise, numbers-led, use a short ranked table of the most relevant territories.
- NEVER invent values not present in the merged data.
"""


def synthesize_correlation_stream(question: str, merged: dict, relation_hint: str,
                                   language: str):
    payload = {
        "question": question,
        "relation_hint": relation_hint,
        "label_a": merged.get("label_a"),
        "label_b": merged.get("label_b"),
        "metric_a_cols": merged.get("metric_a_cols"),
        "metric_b_cols": merged.get("metric_b_cols"),
        "matched_territories": merged.get("matched"),
        "columns": merged.get("columns"),
        "rows": merged.get("rows", [])[:120],
    }
    msgs = [
        {"role": "system", "content": SYNTH_SYS.format(language=language)},
        {"role": "user", "content": json.dumps(payload, ensure_ascii=False, default=str)},
    ]
    yield from llm.chat_stream_complete(msgs, model=config.LLM_MODEL_CODER, max_tokens=2500)
