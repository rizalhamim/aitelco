"""Runs the real /api/chat/stream generator end to end with the model, BigQuery and
storage stubbed. The generator is one long function that no other unit test executes,
so scoping mistakes there used to surface only on the live server (see vault
agent-quality-gates). This pins the 2026-11 rework: tidy step labels, the timeline and
elapsed time on `done`, a chronological trend, the chart brief and key facts handed
to the writer, and the speculative Analyst and SQL being used, not recomputed."""
import json
import os
import tempfile

os.environ.setdefault("TELCO_AI_DB", os.path.join(tempfile.mkdtemp(), "t.db"))

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import main, orchestrator, llm, knowledge, memory  # noqa: E402

KB = {"domains": {"revenue": {"label": "Revenue"}}}


def _events(body: str):
    out = []
    for block in body.strip().split("\n\n"):
        ev, data = None, ""
        for line in block.split("\n"):
            if line.startswith("event:"):
                ev = line[6:].strip()
            elif line.startswith("data:"):
                data += line[5:].strip()
        if ev:
            out.append((ev, json.loads(data)))
    return out


@pytest.fixture
def stubbed(monkeypatch):
    calls = {"analyst": 0, "write_sql": 0, "route": 0, "synth_payload": None, "critique": 0}

    monkeypatch.setattr(knowledge, "load_kb", lambda: KB)
    monkeypatch.setattr(knowledge, "table_contracts", lambda: {})
    for name in ("append_user", "append_assistant", "log_analytics", "add_learning", "store_context"):
        monkeypatch.setattr(memory, name, lambda *a, **k: None)
    monkeypatch.setattr(memory, "history_messages", lambda *a, **k: [])
    monkeypatch.setattr(memory, "last_result", lambda *a, **k: None)
    monkeypatch.setattr(memory, "last_context", lambda *a, **k: None)
    monkeypatch.setattr(main, "_save_chat_to_db", lambda *a, **k: None)

    def route(q, h=None, avoid_domains=None):
        calls["route"] += 1
        return {"domain": "revenue", "reason": "revenue question", "language": "id",
                "rephrased": "revenue per bulan enam bulan terakhir"}

    def analyst(q, h=None):
        calls["analyst"] += 1
        return {"is_data_query": True, "validated_query": "revenue per bulan enam bulan terakhir",
                "language": "id", "export_requested": False, "export_format": None}

    def write_sql(domain, question, *a, **k):
        calls["write_sql"] += 1
        return {"sql": "SELECT month_id, revenue FROM t ORDER BY month_id DESC",
                "explanation": "revenue per month", "_allowed_tables": ["t"]}

    rows = [{"month_id": 202609 - i, "revenue": 100e9 - i * 5e9} for i in range(6)]

    def run_query(sql, allowed_tables=None):
        return {"columns": ["month_id", "revenue"], "rows": [dict(r) for r in rows],
                "row_count": len(rows), "sql": sql, "bytes_processed": 1}

    def stream(msgs, model=None, max_tokens=0, **k):
        calls["synth_payload"] = json.loads(msgs[-1]["content"])
        yield "**Revenue naik** \u2014 stabil"

    def critique(*a, **k):
        calls["critique"] += 1
        return {"verdict": "ok"}

    monkeypatch.setattr(orchestrator, "route", route)
    monkeypatch.setattr(main, "analyst_analyze", analyst)
    monkeypatch.setattr(orchestrator, "write_sql", write_sql)
    monkeypatch.setattr(orchestrator, "assess_domain_fit",
                        lambda *a, **k: {"verdict": "answerable", "confidence": 0.9, "reason": "ok"})
    monkeypatch.setattr(orchestrator, "critique_result", critique)
    monkeypatch.setattr(main, "run_query", run_query)
    monkeypatch.setattr(llm, "chat_stream_complete", stream)
    return calls


def test_stream_flow_end_to_end(stubbed, monkeypatch):
    monkeypatch.setattr(orchestrator, "fast_path_intent", lambda d, q: {"safe": False, "reason": "test"})
    res = TestClient(main.app).post("/api/chat/stream", json={
        "message": "revenue per bulan enam bulan terakhir", "session_id": "t1"})
    ev = _events(res.text)
    names = [e for e, _ in ev]
    assert names[-1] == "done" and "error" not in names

    labels = [d["label"] for e, d in ev if e == "step_start"]
    assert labels[0] == "Memahami pertanyaan"
    assert "Menyusun query" in labels and "Menyusun jawaban" in labels
    assert all(l in main.STEP_LABELS.values() for l in labels)

    done = ev[-1][1]
    assert isinstance(done["elapsed_ms"], int)
    assert [t["label"] for t in done["timeline"]] == labels

    result = next(d for e, d in ev if e == "result")
    assert [r["month_id"] for r in result["rows"]] == sorted(r["month_id"] for r in result["rows"])
    assert result["chart"]["type"] == "area" and result["chart"]["caption"].startswith("6 periode")

    payload = stubbed["synth_payload"]
    assert payload["chart_spec"]["type"] == "area"
    assert payload["key_facts"]["measures"][0]["latest"].startswith("Rp 100,0 M (September 2026")

    text = "".join(d["t"] for e, d in ev if e == "token")
    assert "\u2014" not in text

    # Speculation: the Analyst ran once (in parallel with the router), the router did
    # not run again for a cosmetic rewrite, and the SQL written during the scope gate
    # was the one executed.
    assert stubbed["analyst"] == 1 and stubbed["route"] == 1 and stubbed["write_sql"] == 1


def test_fast_path_skips_the_analyst_result_and_the_grain_critique(stubbed, monkeypatch):
    monkeypatch.setattr(orchestrator, "fast_path_intent", lambda d, q: {"safe": True, "reason": "test"})
    res = TestClient(main.app).post("/api/chat/stream", json={
        "message": "revenue per bulan enam bulan terakhir", "session_id": "t2"})
    ev = _events(res.text)
    assert ev[-1][0] == "done"
    reflect = [d for e, d in ev if e == "reflect"]
    # "per bulan" answered with a month column: verified without a critique call.
    assert reflect and reflect[-1]["verdict"] == "ok" and stubbed["critique"] == 0
    assert stubbed["write_sql"] == 1
