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
