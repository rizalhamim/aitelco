"""Analyst Agent — sits between user and orchestrator.

Responsibilities:
1. Validate & rephrase the user's question into a clear data query
2. Detect export intent (download/excel/pdf keywords)
3. Add context hints (date ranges, aggregation level)
4. Determine language
5. Gate: is this a data question or general chat?
"""
from . import llm, config
from .orchestrator import IDENTITY

ANALYST_SYS = IDENTITY + """

You are the ANALYST AGENT — the first stage in the pipeline. Your job is to
receive a raw user question and prepare it for the downstream orchestrator.

Tasks:
1. **Validate**: Is this a data/analytics question about the IOH Java telco dataset,
   or general conversation (greeting, capability question, chit-chat)?
2. **Rephrase**: If it's a data question, rephrase it into a clear, precise data need.
   - Add specificity: if user says "bulan lalu" → clarify to "latest month_id in the dataset"
   - If vague like "gimana performanya?" but there's conversation history, infer what
     "performance" refers to (revenue, traffic, market share, etc.)
3. **Export detection**: Check if user is asking to download/export data.
   Keywords: 'download', 'export', 'excel', 'xlsx', 'pdf', 'kirim file', 'buat laporan',
   'bikin report', 'simpan', 'unduh'.
   If export is detected AND there is no new data question (just "export hasil tadi"),
   set is_data_query=false and export_requested=true.
4. **Language**: Detect the user's language (id/en/etc.)
5. **Hints**: Suggest helpful context for the SQL agent (e.g. "use monthly table",
   "aggregate by region", "include competitor columns").

Respond ONLY as compact JSON:
{{
  "validated_query": "<rephrased clear question>",
  "is_data_query": true,
  "export_requested": false,
  "export_format": null,
  "hints": "<brief hints for SQL agent or empty string>",
  "language": "id"
}}

export_format values: "xlsx", "pdf", or null.
If user asks for "laporan" or "report" → pdf. If "excel" or "spreadsheet" → xlsx.
If just "download" or "export" without format → "xlsx" (default).
"""


def analyze(question: str, history: list | None = None) -> dict:
    """Analyze the user's question before routing."""
    msgs = [{"role": "system", "content": ANALYST_SYS}]
    if history:
        for h in history[-4:]:
            msgs.append(h)
    msgs.append({"role": "user", "content": question})
    try:
        result = llm.chat_json(msgs, model=config.LLM_MODEL_FAST, max_tokens=500)
        # ensure required keys exist
        result.setdefault("validated_query", question)
        result.setdefault("is_data_query", True)
        result.setdefault("export_requested", False)
        result.setdefault("export_format", None)
        result.setdefault("hints", "")
        result.setdefault("language", "id")
        return result
    except Exception as e:
        # fallback — don't block the pipeline
        return {
            "validated_query": question,
            "is_data_query": True,
            "export_requested": False,
            "export_format": None,
            "hints": "",
            "language": "id",
            "analyst_error": str(e),
        }
