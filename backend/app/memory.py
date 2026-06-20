"""SQLite-backed short-term conversation memory.

One table `turns`: every user/assistant exchange in a session.
- session_id : opaque uuid from the frontend (one per browser tab / user).
- role       : 'user' | 'assistant'
- content    : the user question OR the final assistant answer
- domain     : routed domain key for that turn (NULL for general)
- sql        : SQL executed (assistant turn, optional)
- result_preview : JSON string {columns, rows[:5], row_count}
- ts         : unix epoch

The orchestrator pulls the last N turns via `history_messages()` to build the
LLM message list, and the last result via `last_result()` so follow-ups like
"breakdown per region" know what data the previous answer was about.
"""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from threading import Lock
from typing import Any

from . import config

DB_PATH = Path(config.KB_PATH).parent / "sessions.db"
_LOCK = Lock()


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(DB_PATH, check_same_thread=False)
    c.execute("PRAGMA journal_mode=WAL")
    return c


def init() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _LOCK, _conn() as c:
        c.executescript(
            """
            CREATE TABLE IF NOT EXISTS turns (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id      TEXT NOT NULL,
                role            TEXT NOT NULL,
                content         TEXT NOT NULL,
                domain          TEXT,
                sql             TEXT,
                result_preview  TEXT,
                ts              REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_turns_session_ts
                ON turns(session_id, ts);

            CREATE TABLE IF NOT EXISTS analytics (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id       TEXT NOT NULL,
                question         TEXT NOT NULL,
                domain           TEXT,
                sql              TEXT,
                success          BOOLEAN NOT NULL DEFAULT 1,
                error_msg        TEXT,
                response_summary TEXT,
                row_count        INTEGER,
                latency_ms       INTEGER,
                ts               REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_analytics_session
                ON analytics(session_id);
            CREATE INDEX IF NOT EXISTS idx_analytics_ts
                ON analytics(ts);

            CREATE TABLE IF NOT EXISTS learning_notes (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id  TEXT,
                category    TEXT NOT NULL,
                content     TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_learning_category
                ON learning_notes(category);

            -- Latest structured analysis context per session (profile deck data,
            -- last query result table). Used by the Advisor flow to reason over
            -- existing data WITHOUT re-querying.
            CREATE TABLE IF NOT EXISTS session_context (
                session_id   TEXT PRIMARY KEY,
                kind         TEXT NOT NULL,   -- 'profile' | 'query'
                territory    TEXT,
                payload      TEXT NOT NULL,   -- JSON: profile sections or query result
                ts           REAL NOT NULL
            );
            """
        )


def append_user(session_id: str, content: str) -> None:
    if not session_id:
        return
    with _LOCK, _conn() as c:
        c.execute(
            "INSERT INTO turns(session_id, role, content, ts) VALUES (?,?,?,?)",
            (session_id, "user", content, time.time()),
        )


def append_assistant(
    session_id: str,
    content: str,
    domain: str | None = None,
    sql: str | None = None,
    result: dict | None = None,
) -> None:
    if not session_id:
        return
    preview = None
    if result is not None:
        preview = json.dumps(
            {
                "columns": result.get("columns"),
                "rows": result.get("rows", [])[:5],
                "row_count": result.get("row_count"),
            },
            ensure_ascii=False,
            default=str,
        )
    with _LOCK, _conn() as c:
        c.execute(
            """INSERT INTO turns(session_id, role, content, domain, sql, result_preview, ts)
                 VALUES (?,?,?,?,?,?,?)""",
            (session_id, "assistant", content, domain, sql, preview, time.time()),
        )


def history_messages(session_id: str, limit_turns: int = 6) -> list[dict[str, str]]:
    """Return last N user+assistant turns as plain chat messages for the LLM."""
    if not session_id:
        return []
    with _LOCK, _conn() as c:
        rows = c.execute(
            """SELECT role, content FROM turns
                 WHERE session_id = ?
                 ORDER BY id DESC LIMIT ?""",
            (session_id, limit_turns * 2),
        ).fetchall()
    rows.reverse()
    # cap each message size — protect token budget
    out: list[dict[str, str]] = []
    for role, content in rows:
        if not content:
            continue
        text = content if len(content) <= 1200 else content[:1200] + " …[truncated]"
        out.append({"role": role, "content": text})
    return out


def last_result(session_id: str) -> dict[str, Any] | None:
    """Most recent assistant turn that produced tabular data (for follow-up SQL)."""
    if not session_id:
        return None
    with _LOCK, _conn() as c:
        row = c.execute(
            """SELECT content, domain, sql, result_preview FROM turns
                 WHERE session_id = ? AND role='assistant' AND result_preview IS NOT NULL
                 ORDER BY id DESC LIMIT 1""",
            (session_id,),
        ).fetchone()
    if not row:
        return None
    content, domain, sql, preview = row
    try:
        preview_obj = json.loads(preview) if preview else None
    except Exception:
        preview_obj = None
    return {
        "answer": content,
        "domain": domain,
        "sql": sql,
        "preview": preview_obj,
    }


def clear(session_id: str) -> int:
    if not session_id:
        return 0
    with _LOCK, _conn() as c:
        cur = c.execute("DELETE FROM turns WHERE session_id = ?", (session_id,))
        c.execute("DELETE FROM session_context WHERE session_id = ?", (session_id,))
        return cur.rowcount


# ---- Structured analysis context (for Advisor reuse, no re-query) ----

def store_context(session_id: str, kind: str, payload: dict, territory: str | None = None) -> None:
    """Persist the latest structured analysis (profile deck or query result) so a
    follow-up recommendation can reason over it WITHOUT re-querying BigQuery.

    payload is trimmed to keep it bounded (rows capped per section/table)."""
    if not session_id:
        return
    try:
        text = json.dumps(payload, ensure_ascii=False, default=str)
        if len(text) > 200_000:  # hard cap to protect the DB / token budget
            text = text[:200_000]
        with _LOCK, _conn() as c:
            c.execute(
                """INSERT INTO session_context(session_id, kind, territory, payload, ts)
                     VALUES (?,?,?,?,?)
                   ON CONFLICT(session_id) DO UPDATE SET
                     kind=excluded.kind, territory=excluded.territory,
                     payload=excluded.payload, ts=excluded.ts""",
                (session_id, kind, territory, text, time.time()),
            )
    except Exception:
        pass


def last_context(session_id: str) -> dict[str, Any] | None:
    """Return the latest stored analysis context {kind, territory, payload} or None."""
    if not session_id:
        return None
    with _LOCK, _conn() as c:
        row = c.execute(
            "SELECT kind, territory, payload, ts FROM session_context WHERE session_id = ?",
            (session_id,),
        ).fetchone()
    if not row:
        return None
    kind, territory, payload, ts = row
    try:
        payload_obj = json.loads(payload) if payload else None
    except Exception:
        payload_obj = None
    return {"kind": kind, "territory": territory, "payload": payload_obj, "ts": ts}


# ---- Analytics & Learning ----

def log_analytics(
    session_id: str,
    question: str,
    domain: str | None = None,
    sql: str | None = None,
    success: bool = True,
    error_msg: str | None = None,
    response_summary: str | None = None,
    row_count: int | None = None,
    latency_ms: int | None = None,
) -> None:
    with _LOCK, _conn() as c:
        c.execute(
            """INSERT INTO analytics
               (session_id, question, domain, sql, success, error_msg,
                response_summary, row_count, latency_ms, ts)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (session_id, question, domain, sql, success, error_msg,
             response_summary, row_count, latency_ms, time.time()),
        )


def get_analytics(limit: int = 100) -> list[dict]:
    with _LOCK, _conn() as c:
        rows = c.execute(
            """SELECT session_id, question, domain, sql, success,
                      error_msg, response_summary, row_count, latency_ms, ts
               FROM analytics ORDER BY id DESC LIMIT ?""",
            (limit,),
        ).fetchall()
    cols = ["session_id", "question", "domain", "sql", "success",
            "error_msg", "response_summary", "row_count", "latency_ms", "ts"]
    return [dict(zip(cols, r)) for r in rows]


def get_session_summary(session_id: str) -> dict:
    with _LOCK, _conn() as c:
        total = c.execute(
            "SELECT COUNT(*) FROM analytics WHERE session_id = ?", (session_id,)
        ).fetchone()[0]
        success = c.execute(
            "SELECT COUNT(*) FROM analytics WHERE session_id = ? AND success = 1",
            (session_id,),
        ).fetchone()[0]
        domains = c.execute(
            "SELECT DISTINCT domain FROM analytics WHERE session_id = ? AND domain IS NOT NULL",
            (session_id,),
        ).fetchall()
    return {
        "session_id": session_id,
        "total_questions": total,
        "successful": success,
        "failed": total - success,
        "success_rate": round(success / total * 100, 1) if total else 0,
        "domains_used": [d[0] for d in domains],
    }


def add_learning(session_id: str | None, category: str, content: str) -> None:
    with _LOCK, _conn() as c:
        c.execute(
            "INSERT INTO learning_notes(session_id, category, content, created_at) VALUES (?,?,?,?)",
            (session_id, category, content, time.time()),
        )


def get_learnings(category: str | None = None, limit: int = 50) -> list[dict]:
    with _LOCK, _conn() as c:
        if category:
            rows = c.execute(
                "SELECT session_id, category, content, created_at FROM learning_notes WHERE category = ? ORDER BY id DESC LIMIT ?",
                (category, limit),
            ).fetchall()
        else:
            rows = c.execute(
                "SELECT session_id, category, content, created_at FROM learning_notes ORDER BY id DESC LIMIT ?",
                (limit,),
            ).fetchall()
    cols = ["session_id", "category", "content", "created_at"]
    return [dict(zip(cols, r)) for r in rows]


# initialise lazily on import
init()
