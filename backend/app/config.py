"""Configuration loaded from environment."""
import os
from pathlib import Path

# Load .env if present (simple parser, no extra deps)
ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
if ENV_PATH.exists():
    for line in ENV_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())

# ---- LLM (9Router / OpenAI-compatible) ----
LLM_BASE = os.environ.get("LLM_BASE", "http://43.129.52.9:20128/v1")
LLM_KEY = os.environ.get("LLM_KEY", "")
LLM_MODEL = os.environ.get("LLM_MODEL", "Agent-Java-v02.3")
LLM_MODEL_FAST = os.environ.get("LLM_MODEL_FAST", "Agent-Java-v02.3-Flash")
LLM_MODEL_SQL = os.environ.get("LLM_MODEL_SQL", "Agent-Java-v02.3-SQL")
LLM_MODEL_CODER = os.environ.get("LLM_MODEL_CODER", "Agent-Java-v02.3-Coder")
LLM_MODEL_ANALYST = os.environ.get("LLM_MODEL_ANALYST", "Agent-Java-v02.3-Analyst")
LLM_OMIT_TEMPERATURE = os.environ.get("LLM_OMIT_TEMPERATURE", "true").lower() == "true"

# ---- BigQuery ----
BQ_PROJECT = os.environ.get("BQ_PROJECT", "data-java-prd-97b9")
BQ_DATASET = os.environ.get("BQ_DATASET", "java_precalc")
BQ_LOCATION = os.environ.get("BQ_LOCATION", "asia-southeast2")
BQ_ADC = os.environ.get(
    "BQ_ADC",
    "/home/ubuntu/.config/gcloud/legacy_credentials/90086171@ioh.co.id/adc.json",
)

# ---- Query safety ----
MAX_BYTES_BILLED = int(os.environ.get("MAX_BYTES_BILLED", str(50 * 1024**3)))  # 50 GB cap
DEFAULT_ROW_LIMIT = int(os.environ.get("DEFAULT_ROW_LIMIT", "1000"))
QUERY_TIMEOUT_S = int(os.environ.get("QUERY_TIMEOUT_S", "120"))

# ---- Paths ----
DATA_DIR = Path(__file__).resolve().parent.parent / "data"
KB_PATH = DATA_DIR / "knowledge_base.json"
RUNTIME_GRAPH_PATH = DATA_DIR / "runtime_knowledge_graph.json"
RUNTIME_KNOWLEDGE_MANIFEST_PATH = DATA_DIR / "runtime_knowledge_manifest.json"
TABLE_CATALOG_PATH = DATA_DIR / "table_catalog.json"
TABLE_GOVERNANCE_PATH = Path(__file__).resolve().parent.parent / "governance" / "table_governance.json"

# Runtime knowledge retrieval is deliberately bounded. PROFILE and CORRELATE
# can request a wider budget explicitly, but normal chat stays compact.
KNOWLEDGE_TABLE_LIMIT = int(os.environ.get("KNOWLEDGE_TABLE_LIMIT", "4"))
KNOWLEDGE_TABLE_MAX_EXPANSION = int(os.environ.get("KNOWLEDGE_TABLE_MAX_EXPANSION", "6"))
KNOWLEDGE_FAST_PATH = os.environ.get("KNOWLEDGE_FAST_PATH", "true").lower() == "true"
# Deterministic assist that tells the router which two domains a contrast-pair
# question ("X tinggi TAPI Y rendah") actually retrieves against. Advisory only.
ROUTER_CONTRAST_HINT = os.environ.get("ROUTER_CONTRAST_HINT", "true").lower() == "true"

# SQL generation budgets. The retry budget applies only after a TRUNCATED generation:
# reusing the budget that just overflowed tends to overflow again, so the retry gets
# both more room and an instruction to write a simpler query.
SQL_MAX_TOKENS = int(os.environ.get("SQL_MAX_TOKENS", "8000"))
SQL_MAX_TOKENS_TRUNCATED = int(os.environ.get("SQL_MAX_TOKENS_TRUNCATED", "12000"))
