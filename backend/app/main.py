"""FastAPI app exposing the orchestrator over REST + SSE."""
import io
import json
import time as _time
import uuid

from fastapi import FastAPI, Query, Depends, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, Response
from pydantic import BaseModel

from . import knowledge, orchestrator, llm, memory, config
from .bigquery_tool import run_query, QueryError
from .export_agent import export_xlsx, export_pdf
from .analyst_agent import analyze as analyst_analyze
from . import profile_engine
from . import advisor_agent
from . import geo_locate
from . import site_perf
from . import map_synth_agent
from . import correlate_agent
from . import chart_spec
from . import telemetry
from starlette.concurrency import run_in_threadpool
from .database import init_db, get_db, ChatSession, ChatMessage, UsageLog, utcnow
from .auth import get_current_user_optional
from .routes_auth import router as auth_router, admin_router, history_router
from .app_update import router as app_update_router
from .routes_reports import router as reports_router
from .routes_stats import router as stats_router
from sqlalchemy.orm import Session

app = FastAPI(title="Telco AI Orchestrator", version="1.0")

# Comma-separated list, e.g. "https://agent.bizplan-java.com". Defaults to "*"
# so existing deployments keep working; set it in production.
_cors_origins = [o.strip() for o in config.CORS_ORIGINS.split(",") if o.strip()] or ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=True,
)

@app.middleware("http")
async def _client_telemetry(request: Request, call_next):
    # Records app version / device for clients that send X-Client-Platform.
    response = await call_next(request)
    if request.headers.get("x-client-platform"):
        await run_in_threadpool(telemetry.record_client, request.headers)
    return response


# Register auth/admin/history routes
app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(history_router)
app.include_router(app_update_router)
app.include_router(reports_router)
app.include_router(stats_router)

# Init database on startup
@app.on_event("startup")
def startup():
    init_db()


def _backfill_coords(result: dict) -> dict:
    """Safety net for map queries: if the result has site_id but is missing
    latitude/longitude columns, look them up from rham_site_wise_addr_java and
    merge them in. Guarantees the frontend map can always render."""
    try:
        cols = [c.lower() for c in result.get("columns", [])]
        if "latitude" in cols and "longitude" in cols:
            return result  # already has coords
        orig_cols = result.get("columns", [])
        site_col = next((c for c in orig_cols if c.lower() in ("site_id", "siteid")), None)
        rows = result.get("rows", [])
        if not site_col or not rows:
            return result
        site_ids = [str(r.get(site_col)) for r in rows if r.get(site_col) is not None]
        if not site_ids:
            return result
        from . import config as _cfg
        id_list = ",".join("'" + s.replace("'", "") + "'" for s in site_ids[:1000])
        lookup_sql = (
            "SELECT site_id, "
            "SAFE_CAST(latitude AS FLOAT64) AS latitude, "
            "SAFE_CAST(longitude AS FLOAT64) AS longitude "
            f"FROM `{_cfg.BQ_PROJECT}.{_cfg.BQ_DATASET}.rham_site_wise_addr_java` "
            f"WHERE month_id = (SELECT MAX(month_id) FROM `{_cfg.BQ_PROJECT}.{_cfg.BQ_DATASET}.rham_site_wise_addr_java`) "
            f"AND site_id IN ({id_list})"
        )
        coord = run_query(lookup_sql)
        cmap = {str(r["site_id"]): (r.get("latitude"), r.get("longitude")) for r in coord.get("rows", [])}
        if not cmap:
            return result
        for r in rows:
            lat, lon = cmap.get(str(r.get(site_col)), (None, None))
            r["latitude"] = lat
            r["longitude"] = lon
        new_cols = list(orig_cols)
        if "latitude" not in new_cols:
            new_cols.append("latitude")
        if "longitude" not in new_cols:
            new_cols.append("longitude")
        result["columns"] = new_cols
        result["rows"] = rows
    except Exception:
        pass  # never break the main flow
    return result


def _save_chat_to_db(session_id: str, user_msg: str, assistant_msg: str,
                     domain: str | None = None, sql_query: str | None = None,
                     row_count: int | None = None, latency_ms: int | None = None,
                     user_id: int | None = None, source: str | None = None):
    """Save a chat exchange to the database."""
    try:
        db = next(get_db())
        # Find or create session
        chat_session = db.query(ChatSession).filter(
            ChatSession.session_id == session_id
        ).first()
        if not chat_session:
            chat_session = ChatSession(
                session_id=session_id,
                user_id=user_id or 0,
                title=user_msg[:100] if user_msg else "New Chat",
                message_count=0,
            )
            db.add(chat_session)
            db.flush()
        elif user_id and (not chat_session.user_id or chat_session.user_id == 0):
            # backfill ownership if the session was created before the user was known
            chat_session.user_id = user_id

        # Save user message
        db.add(ChatMessage(
            session_id=chat_session.id,
            role="user",
            content=user_msg,
        ))
        # Save assistant message
        db.add(ChatMessage(
            session_id=chat_session.id,
            role="assistant",
            content=assistant_msg,
            domain=domain,
            sql_query=sql_query,
            row_count=row_count,
            latency_ms=latency_ms,
            metadata_json=json.dumps({"source": source}) if source else None,
        ))
        chat_session.message_count = (chat_session.message_count or 0) + 2
        chat_session.updated_at = utcnow()
        db.commit()

        # Log usage
        if user_id:
            db.add(UsageLog(
                user_id=user_id,
                action="query",
                domain=domain,
                detail=user_msg[:200],
            ))
            db.commit()
        db.close()
    except Exception as e:
        import logging
        logging.getLogger("main").warning(f"Failed to save chat: {e}")


def _save_failed_turn(session_id: str, user_msg: str, error: str,
                      domain: str | None, user_id: int | None,
                      latency_ms: int | None = None):
    """Persist a turn that failed before producing an answer (planning/exec
    errors). Failed turns are highly valuable for training & fixing question
    logic, so we record them in chat_messages with source='error'."""
    if not session_id:
        return
    try:
        memory.log_analytics(
            session_id, question=user_msg, domain=domain,
            success=False, error_msg=str(error)[:500],
            latency_ms=latency_ms,
        )
    except Exception:
        pass
    _save_chat_to_db(
        session_id=session_id, user_msg=user_msg,
        assistant_msg=f"[ERROR] {error}", domain=domain,
        latency_ms=latency_ms, user_id=user_id, source="error",
    )

# In-memory store for last export per session (cleared on next query)
_export_cache: dict[str, tuple[bytes, str, str]] = {}  # session -> (data, media_type, filename)


class ChatReq(BaseModel):
    message: str
    history: list | None = None
    session_id: str | None = None
    language: str | None = None   # 'id' | 'en' user preference (overrides auto-detect)
    map_context: bool | None = None   # True when the question comes from the Map Query page


@app.get("/api/health")
def health():
    return {"ok": True}


class GeoLocateReq(BaseModel):
    lat: float
    lon: float


@app.post("/api/geo/locate")
def geo_locate_endpoint(req: GeoLocateReq):
    """Resolve a GPS coordinate to kecamatan (via SHP), then return the nearest
    10 sites and 10 outlets. Used by the 'Share Location' button."""
    try:
        loc = geo_locate.locate_kecamatan(req.lat, req.lon)
    except Exception as e:
        return {"ok": False, "error": f"locate failed: {e}"}
    out = {"ok": True, "lat": req.lat, "lon": req.lon, "kecamatan": loc}
    if loc and loc.get("kec_id"):
        try:
            prof = geo_locate.kec_profile(loc["kec_id"])
            out["kec_profile"] = prof["rows"][0] if prof.get("rows") else None
        except Exception as e:
            out["kec_profile_error"] = str(e)[:200]
    try:
        sites = geo_locate.nearest_sites(req.lat, req.lon, 10)
        out["sites"] = {"columns": sites["columns"], "rows": sites["rows"]}
    except Exception as e:
        out["sites_error"] = str(e)[:200]
    try:
        outlets = geo_locate.nearest_outlets(req.lat, req.lon, 10)
        out["outlets"] = {"columns": outlets["columns"], "rows": outlets["rows"]}
    except Exception as e:
        out["outlets_error"] = str(e)[:200]
    return out


@app.get("/api/site/search")
def site_search(q: str):
    """Site Performance — search sites by id or name."""
    if not q or len(q.strip()) < 2:
        return {"sites": []}
    try:
        return site_perf.search_sites(q.strip(), n=15)
    except Exception as e:
        return {"error": str(e)[:300], "sites": []}


@app.post("/api/site/nearest")
def site_nearest(req: GeoLocateReq):
    """Site Performance — 10 nearest sites to a coordinate."""
    try:
        return site_perf.nearest_sites(req.lat, req.lon, n=10)
    except Exception as e:
        return {"error": str(e)[:300], "sites": []}


@app.get("/api/site/detail")
def site_detail_endpoint(site_id: str, brand: str = "ioh"):
    """Site Performance — full per-site profile + LMTD/MTD/growth (perf table) +
    full-month history + GA-by-channel + channel/subs/usage/top-products/slab/funnel."""
    try:
        return site_perf.site_detail(site_id, brand=brand)
    except Exception as e:
        return {"error": str(e)[:300], "kind": "execution"}


@app.post("/api/geo/nearest-sites")
def geo_nearest_sites(req: GeoLocateReq):
    """Fix mode: up to 100 nearest sites with full attributes + latest-month
    performance + per-site monthly history (for rich map tooltips)."""
    try:
        data = geo_locate.nearest_sites_perf(req.lat, req.lon, n=100, months=6)
        return {"ok": True, "lat": req.lat, "lon": req.lon, **data}
    except Exception as e:
        return {"ok": False, "error": str(e)[:300]}


import os as _os

_GEO_DIR = _os.path.join(_os.path.dirname(_os.path.dirname(__file__)), "data", "geo")


@app.get("/api/geo/shapes/{level}")
def geo_shapes(level: str, request: Request):
    """Serve the pre-built simplified GeoJSON polygons for choropleth.
    level = 'kecamatan' (key: kec_id) or 'kabupaten' (key: kabkot_id).

    Honors the client's Accept-Encoding: returns gzip ONLY when the client
    advertises gzip support (and proxies preserve it); otherwise returns plain
    decompressed JSON. This avoids a class of proxy bugs (e.g. the Next.js
    rewrite) where a Content-Encoding: gzip body is forwarded to a client that
    didn't ask for it, breaking res.json()."""
    import gzip as _gzip
    if level not in ("kecamatan", "kabupaten"):
        return Response(content='{"error":"invalid level"}', media_type="application/json", status_code=400)
    gz = _os.path.join(_GEO_DIR, f"{level}.geojson.gz")
    plain = _os.path.join(_GEO_DIR, f"{level}.geojson")
    if not _os.path.exists(gz) and not _os.path.exists(plain):
        return Response(content='{"error":"geojson not built"}', media_type="application/json", status_code=404)

    accepts_gzip = "gzip" in (request.headers.get("accept-encoding") or "").lower()
    base_headers = {"Cache-Control": "public, max-age=604800", "X-Geo-Level": level}

    if accepts_gzip and _os.path.exists(gz):
        with open(gz, "rb") as f:
            data = f.read()
        return Response(content=data, media_type="application/json",
                        headers={**base_headers, "Content-Encoding": "gzip"})

    # Plain JSON fallback (decompress on the fly if only the .gz exists)
    if _os.path.exists(plain):
        with open(plain, "rb") as f:
            data = f.read()
    else:
        with open(gz, "rb") as f:
            data = _gzip.decompress(f.read())
    return Response(content=data, media_type="application/json", headers=base_headers)


@app.get("/api/geo/territory-map")
def geo_territory_map(request: Request):
    """Serve the kecamatan -> territory mapping (kabkota/province/region/circle/
    area/branch) sourced from zz_territory_kecamatan. The Map Query frontend uses
    this to DISSOLVE kecamatan polygons to whatever level the AI agent answered at
    (per branch/region/circle/etc.) — fully dynamic, driven by the territory ref."""
    import gzip as _gzip
    gz = _os.path.join(_GEO_DIR, "territory_map.json.gz")
    plain = _os.path.join(_GEO_DIR, "territory_map.json")
    if not _os.path.exists(gz) and not _os.path.exists(plain):
        return Response(content='{"error":"territory map not built"}', media_type="application/json", status_code=404)
    accepts_gzip = "gzip" in (request.headers.get("accept-encoding") or "").lower()
    base_headers = {"Cache-Control": "public, max-age=604800"}
    if accepts_gzip and _os.path.exists(gz):
        with open(gz, "rb") as f:
            data = f.read()
        return Response(content=data, media_type="application/json",
                        headers={**base_headers, "Content-Encoding": "gzip"})
    if _os.path.exists(plain):
        with open(plain, "rb") as f:
            data = f.read()
    else:
        with open(gz, "rb") as f:
            data = _gzip.decompress(f.read())
    return Response(content=data, media_type="application/json", headers=base_headers)


@app.get("/api/domains")
def domains():
    return {"domains": knowledge.domain_list()}


@app.get("/api/memory/{session_id}")
def get_memory(session_id: str):
    """Inspect what's stored in short-term memory for a session."""
    return {
        "session_id": session_id,
        "history": memory.history_messages(session_id, limit_turns=20),
        "last_result": memory.last_result(session_id),
    }


@app.delete("/api/memory/{session_id}")
def clear_memory(session_id: str):
    n = memory.clear(session_id)
    return {"session_id": session_id, "deleted": n}


@app.get("/api/analytics")
def get_analytics(limit: int = 100):
    return {"analytics": memory.get_analytics(limit)}


@app.get("/api/analytics/{session_id}")
def get_session_analytics(session_id: str):
    return memory.get_session_summary(session_id)


@app.get("/api/learnings")
def get_learnings(category: str | None = None, limit: int = 50):
    return {"learnings": memory.get_learnings(category, limit)}


@app.post("/api/chat")
def chat(req: ChatReq):
    """Non-streaming full pipeline; returns the whole trace."""
    return orchestrator.answer(req.message, req.history, req.session_id)


@app.post("/api/chat/stream")
def chat_stream(req: ChatReq, request: Request):
    """Server-Sent Events: emits step events, then streams the final answer tokens."""
    # Extract user from JWT if present (optional auth).
    # If no token OR token is expired/invalid → treat as anonymous (chat still
    # works; history simply won't attach to a user).  This matches the behaviour
    # of every other endpoint and prevents the web SSE stream from 401-ing when
    # the browser's stored JWT expires mid-session.
    _user_id = None
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        from .auth import decode_token
        token = auth_header[7:].strip()
        try:
            payload = decode_token(token)
        except Exception:
            # expired/invalid → anonymous, don't block the stream
            payload = {}
        sub = payload.get("sub")
        if sub:
            # JWT 'sub' is always the username (see create_access_token).
            # Resolve to the real user PK — NEVER int(sub), because numeric
            # usernames (e.g. "90086171") would be mistaken for a user id and
            # sessions would be saved under an id that no user owns, making
            # the chat history invisible to the user.
            from .database import SessionLocal, User
            db = SessionLocal()
            try:
                u = db.query(User).filter(User.username == str(sub)).first()
                if u:
                    _user_id = u.id
            finally:
                db.close()

    def gen():
        def sse(event, data):
            return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False, default=str)}\n\n"

        t0 = _time.time()
        llm.reset_usage()
        # explicit user language preference ('id'/'en') overrides auto-detection
        pref_lang = (req.language or "").lower().strip()
        pref_lang = pref_lang if pref_lang in ("id", "en") else None

        # merge persisted history with whatever the client passed.
        # ALWAYS ensure a session_id so EVERY conversation is persisted (for
        # training / question-logic improvement) — even raw API callers that
        # forget to send one. Auto-generated ids are prefixed "auto_".
        session_id = req.session_id or f"auto_{int(_time.time()*1000)}_{uuid.uuid4().hex[:6]}"
        merged_history = list(req.history or [])
        if session_id and not merged_history:
            merged_history = memory.history_messages(session_id, limit_turns=6)
        last_res = memory.last_result(session_id) if session_id else None
        prior_ctx = memory.last_context(session_id) if session_id else None
        if session_id:
            memory.append_user(session_id, req.message)

        # ──── ADVISORY / RECOMMENDATION FOLLOW-UP (sequential swarm) ────
        # If the user asks an analytical/recommendation follow-up AND we already
        # have data on screen (profile deck or last query), reason over the
        # EXISTING data instead of re-querying everything. The Advisor may pull a
        # few supporting queries one-by-one (not parallel) to complete the picture.
        if (prior_ctx and prior_ctx.get("payload")
                and advisor_agent.is_advisory(req.message)):
            try:
                lang = pref_lang or (last_res or {}).get("language") or "id"
                yield sse("step_start", {"step": "analyst", "label": "Advisor",
                                          "desc": "Menganalisis data yang sudah ada"})
                plan = advisor_agent.plan(req.message, prior_ctx, lang)
                yield sse("advisor_plan", {
                    "have_enough": plan["have_enough"],
                    "reasoning": plan["reasoning"],
                    "supporting": [sq["domain"] for sq in plan["supporting_queries"]],
                    "_usage": llm.get_last_usage(),
                })

                supporting = []
                for sq in plan["supporting_queries"]:
                    label = knowledge.load_kb()["domains"].get(sq["domain"], {}).get("label", sq["domain"])
                    yield sse("step_start", {"step": "bq_exec", "label": f"Data: {label}",
                                              "desc": sq["question"][:80]})
                    s = advisor_agent.fetch_supporting(sq["domain"], sq["question"])
                    supporting.append(s)
                    yield sse("advisor_support", {
                        "domain": sq["domain"], "question": sq["question"],
                        "rows": s.get("row_count", 0), "error": s.get("error"),
                    })

                yield sse("step_start", {"step": "synth", "label": "Advisor",
                                          "desc": "Menyusun rekomendasi bisnis"})
                buf = []
                for tok in advisor_agent.advise_stream(req.message, prior_ctx, supporting, lang):
                    buf.append(tok)
                    yield sse("token", {"t": tok})
                answer_text = "".join(buf)

                if session_id:
                    memory.append_assistant(session_id, answer_text, domain="ADVISORY")
                    memory.log_analytics(
                        session_id, question=req.message, domain="ADVISORY",
                        success=True, response_summary=answer_text[:200],
                        latency_ms=int((_time.time() - t0) * 1000),
                    )
                    _save_chat_to_db(
                        session_id=session_id, user_msg=req.message,
                        assistant_msg=answer_text, domain="ADVISORY",
                        latency_ms=int((_time.time() - t0) * 1000), user_id=_user_id,
                    )
                yield sse("done", {"_usage": llm.get_last_usage(), "domain": "advisory"})
                return
            except Exception as e:
                import logging as _lg
                _lg.getLogger("main").warning(f"advisory flow failed, falling back: {e}")
                # fall through to the normal pipeline

        # ──── 0. FAST PATH: Router first ────
        # Route first to detect domain. If none → reply immediately (skip Analyst).
        # If data query → Analyst validates → SQL pipeline.
        yield sse("step_start", {"step": "router", "label": "Orchestrator", "desc": "Menganalisis pertanyaan"})
        r = orchestrator.route(req.message, merged_history)
        domain = r.get("domain", "none")
        language = pref_lang or r.get("language", "id")
        r["_usage"] = llm.get_last_usage()
        yield sse("route", r)

        kb = knowledge.load_kb()

        # ──── General / non-data → reply immediately (NO Analyst needed) ────
        if domain == "none" or (domain not in kb["domains"] and domain not in ("PROFILE", "CORRELATE")):
            yield sse("step_start", {"step": "synth", "label": "Synthesizer", "desc": "Menyusun jawaban"})
            msgs = [
                {"role": "system", "content": orchestrator.IDENTITY +
                    "\n\nYou are the orchestrator of a telco analytics AI for Indosat (IOH) Java. "
                    "Help briefly. Domains you cover: site performance, network, competitive "
                    "market share, forecast, HVC, marketing, sales & distribution, fixed "
                    f"broadband, geography, KPI, reports. Reply in language: {language}."},
            ]
            for h in merged_history[-6:]:
                msgs.append(h)
            msgs.append({"role": "user", "content": req.message})
            buf = []
            for tok in llm.chat_stream_complete(msgs, model=config.LLM_MODEL_FAST, max_tokens=1200):
                buf.append(tok)
                yield sse("token", {"t": tok})
            _general_answer = "".join(buf)
            if session_id:
                memory.append_assistant(session_id, _general_answer, domain=None)
                memory.log_analytics(
                    session_id, question=req.message, domain=None,
                    success=True, response_summary="general",
                    latency_ms=int((_time.time() - t0) * 1000),
                )
                _save_chat_to_db(
                    session_id, req.message, _general_answer,
                    domain=None,
                    latency_ms=int((_time.time() - t0) * 1000),
                    user_id=_user_id,
                )
            yield sse("done", {"_usage": llm.get_last_usage(), "domain": "none"})
            return

        # ──── Data query detected → Analyst validates & enriches ────
        yield sse("step_start", {"step": "analyst", "label": "Analyst", "desc": "Memvalidasi & memperkaya pertanyaan"})
        analysis = analyst_analyze(req.message, merged_history)
        analysis["_usage"] = llm.get_last_usage()
        yield sse("analyst", analysis)

        language = pref_lang or analysis.get("language", language)
        export_requested = analysis.get("export_requested", False)
        export_format = analysis.get("export_format", "xlsx") or "xlsx"
        validated_query = analysis.get("validated_query", req.message)

        # ──── Export branch: user wants to export last result ────
        if export_requested and not analysis.get("is_data_query", True) and last_res:
            yield sse("step_start", {"step": "export", "label": "Export Agent", "desc": "Membuat file export"})
            _do_export(session_id, export_format, last_res, language)
            yield sse("export_ready", {
                "format": export_format,
                "download_url": f"/api/export/last/{session_id}",
            })
            fmt_label = "Excel" if export_format == "xlsx" else "PDF"
            reply = f"File {fmt_label} sudah siap. Klik tombol download di bawah."
            for ch in reply:
                yield sse("token", {"t": ch})
            if session_id:
                memory.append_assistant(session_id, reply, domain=None)
                memory.log_analytics(
                    session_id, question=req.message, domain=None,
                    success=True, response_summary="export",
                    latency_ms=int((_time.time() - t0) * 1000),
                )
                _save_chat_to_db(
                    session_id, req.message, reply, domain=None,
                    latency_ms=int((_time.time() - t0) * 1000),
                    user_id=_user_id,
                )
            yield sse("done", {"_usage": llm.get_last_usage(), "domain": "export"})
            return

        # Re-route with validated query if analyst changed it significantly
        if validated_query and validated_query != req.message:
            r2 = orchestrator.route(validated_query, merged_history)
            new_domain = r2.get("domain", "none")
            if new_domain != "none" and (new_domain in kb["domains"] or new_domain in ("PROFILE", "CORRELATE")):
                domain = new_domain
                r = r2

        # ──── CORRELATE MODE: cross-domain correlation (2 domains, joined) ────
        if domain == "CORRELATE":
            yield sse("step_start", {"step": "sql_write", "label": "Correlation Planner", "desc": "Memetakan 2 domain"})
            try:
                plan = correlate_agent.plan_correlation(req.message, merged_history)
            except Exception as e:
                _save_failed_turn(session_id, req.message, f"Correlation planning failed: {e}",
                                  "CORRELATE", _user_id, int((_time.time() - t0) * 1000))
                yield sse("error", {"error": f"Correlation planning failed: {e}"})
                return
            sub_a = plan.get("sub_a") or {}
            sub_b = plan.get("sub_b") or {}
            join_key = plan.get("join_key", "kabkota")
            relation_hint = plan.get("relation_hint", "")
            language = pref_lang or plan.get("language", language)
            if not sub_a.get("domain") or not sub_b.get("domain"):
                _save_failed_turn(session_id, req.message, "Correlation needs two domains but planning was incomplete.",
                                  "CORRELATE", _user_id, int((_time.time() - t0) * 1000))
                yield sse("error", {"error": "Correlation needs two domains but planning was incomplete."})
                return

            yield sse("correlate_plan", {
                "join_key": join_key, "relation_hint": relation_hint,
                "sub_a": {"domain": sub_a.get("domain"), "label": sub_a.get("label"), "question": sub_a.get("question")},
                "sub_b": {"domain": sub_b.get("domain"), "label": sub_b.get("label"), "question": sub_b.get("question")},
            })

            # Run both sides in parallel (reuse the profile fan-out runner).
            yield sse("step_start", {"step": "bq_exec", "label": "Parallel Data", "desc": "Mengambil data dari 2 domain"})
            subs = [
                {"domain": sub_a["domain"], "section_title": "A", "question": sub_a["question"]},
                {"domain": sub_b["domain"], "section_title": "B", "question": sub_b["question"]},
            ]
            by_tag = {}
            for dr in profile_engine.run_parallel_stream(subs, max_workers=2):
                by_tag[dr["section_title"]] = dr
                yield sse("correlate_side", {
                    "tag": dr["section_title"], "domain": dr["domain"],
                    "row_count": dr.get("row_count", 0), "error": dr.get("error"),
                    "columns": dr.get("columns", []), "rows": dr.get("rows", []),
                    "sql": dr.get("sql"),
                })
            res_a, res_b = by_tag.get("A", {}), by_tag.get("B", {})
            if res_a.get("error") or res_b.get("error"):
                _save_failed_turn(session_id, req.message,
                                  f"One side failed. A: {res_a.get('error')}; B: {res_b.get('error')}",
                                  "CORRELATE", _user_id, int((_time.time() - t0) * 1000))
                yield sse("error", {"error": f"One side failed. A: {res_a.get('error')}; B: {res_b.get('error')}"})
                return

            merged = correlate_agent.correlate_join(
                join_key, res_a, res_b,
                sub_a.get("label", "Metric A"), sub_b.get("label", "Metric B"))
            if merged.get("error") or merged.get("row_count", 0) == 0:
                _save_failed_turn(session_id, req.message,
                                  f"No overlapping territories to correlate (A={merged.get('n_a')}, B={merged.get('n_b')}).",
                                  "CORRELATE", _user_id, int((_time.time() - t0) * 1000))
                yield sse("error", {"error": f"No overlapping territories to correlate (A={merged.get('n_a')}, B={merged.get('n_b')})."})
                return

            # Emit the merged table as a normal `result` so the UI can table/chart it.
            yield sse("result", {
                "columns": merged["columns"], "rows": merged["rows"],
                "row_count": merged["row_count"], "sql": None, "bytes_processed": 0,
                "chart": chart_spec.suggest(merged["columns"], merged["rows"], "korelasi " + req.message),
            })

            yield sse("step_start", {"step": "synth", "label": "Correlation Analyst", "desc": "Menganalisis hubungan 2 metrik"})
            buf = []
            for tok in correlate_agent.synthesize_correlation_stream(
                    req.message, merged, relation_hint, language):
                buf.append(tok)
                yield sse("token", {"t": tok})
            answer_text = "".join(buf)
            if session_id:
                memory.append_assistant(session_id, answer_text, domain="CORRELATE")
                memory.log_analytics(
                    session_id, question=req.message, domain="CORRELATE",
                    success=True, response_summary=answer_text[:200],
                    row_count=merged["row_count"],
                    latency_ms=int((_time.time() - t0) * 1000))
                _save_chat_to_db(
                    session_id=session_id, user_msg=req.message, assistant_msg=answer_text,
                    domain="CORRELATE", row_count=merged["row_count"],
                    latency_ms=int((_time.time() - t0) * 1000), user_id=_user_id)
            yield sse("done", {"_usage": llm.get_last_usage(), "domain": "CORRELATE"})
            return

        # ──── PROFILE MODE: multi-domain parallel ────
        if domain == "PROFILE":
            # Determine deck depth
            q_lower = req.message.lower()
            # Check if user already specified depth
            wants_full = any(k in q_lower for k in [
                'deck', 'lengkap', 'detail', 'komprehensif', 'comprehensive',
                'full', 'complete', 'semua', 'all',
            ])
            wants_simple = any(k in q_lower for k in [
                'ringkas', 'singkat', 'simple', 'brief', 'quick',
            ])

            # Default to the FULL deck when depth is unspecified (no clarify gate);
            # only build the simple deck if the user explicitly asked for "ringkas".
            full_deck = not wants_simple

            yield sse("step_start", {"step": "sql_write", "label": "Profile Planner", "desc": "Merencanakan query multi-domain"})

            # 1. Plan sub-queries — use the ORIGINAL user message for territory
            # extraction (the rephrased query is often verbose/English and breaks
            # the fast regex resolver).
            try:
                plan = profile_engine.plan_profile(
                    req.message, merged_history, full_deck=full_deck)
            except Exception as e:
                _save_failed_turn(session_id, req.message, f"Profile planning failed: {e}",
                                  "PROFILE", _user_id, int((_time.time() - t0) * 1000))
                yield sse("error", {"error": f"Profile planning failed: {e}"})
                return

            territory_type = plan.get("territory_type", "kabkota")
            territory_name = plan.get("territory_name", "")
            sub_queries = plan.get("sub_queries", [])

            yield sse("profile_plan", {
                "territory_type": territory_type,
                "territory_name": territory_name,
                "deck_type": "full" if full_deck else "simple",
                "sub_queries": [{"domain": sq["domain"],
                                 "section_title": sq.get("section_title", ""),
                                 "question": sq["question"]}
                                for sq in sub_queries],
            })

            if not sub_queries:
                _save_failed_turn(session_id, req.message, "No sub-queries planned",
                                  "PROFILE", _user_id, int((_time.time() - t0) * 1000))
                yield sse("error", {"error": "No sub-queries planned"})
                return

            # 2. Fan-out parallel queries — STREAM each result as it completes so
            # the SSE connection never goes silent for long (avoids proxy/idle
            # timeouts a.k.a. "network error" on big circle/region profiles).
            yield sse("step_start", {"step": "bq_exec", "label": "Parallel Data", "desc": f"Mengambil data dari {len(sub_queries)} sumber"})

            domain_results = []
            for dr in profile_engine.run_parallel_stream(
                    sub_queries, max_workers=5,
                    territory_type=territory_type,
                    territory_name=territory_name):
                domain_results.append(dr)
                status = "ok" if not dr.get("error") else "error"
                yield sse("profile_domain_result", {
                    "domain": dr["domain"],
                    "section_title": dr["section_title"],
                    "status": status,
                    "row_count": dr.get("row_count", 0),
                    "error": dr.get("error"),
                    "columns": dr.get("columns", []),
                    "rows": dr.get("rows", []),
                    "sql": dr.get("sql"),
                    "explanation": dr.get("explanation", ""),
                    "chart": chart_spec.suggest(dr.get("columns", []), dr.get("rows", []),
                                                dr.get("section_title", "")),
                })

            # re-order results to the planned section order for a coherent deck
            _order = {sq.get("section_title"): i for i, sq in enumerate(sub_queries)}
            domain_results.sort(key=lambda r: _order.get(r.get("section_title"), 99))

            # 3. Compile profile deck (streaming)
            yield sse("step_start", {"step": "synth", "label": "Profile Compiler", "desc": "Merangkum hasil semua domain"})
            buf = []
            for tok in profile_engine.compile_profile_stream(
                    territory_type, territory_name,
                    domain_results, language):
                buf.append(tok)
                yield sse("token", {"t": tok})

            answer_text = "".join(buf)
            if session_id:
                memory.append_assistant(
                    session_id, answer_text, domain="PROFILE",
                )
                # store the full deck data so a follow-up recommendation can
                # reason over it WITHOUT re-querying everything
                try:
                    memory.store_context(
                        session_id, "profile",
                        {"sections": [
                            {"section_title": dr.get("section_title"),
                             "columns": dr.get("columns", []),
                             "rows": dr.get("rows", [])[:10],
                             "error": dr.get("error")}
                            for dr in domain_results
                        ]},
                        territory=f"{territory_type}: {territory_name}",
                    )
                except Exception:
                    pass
                memory.log_analytics(
                    session_id, question=req.message, domain="PROFILE",
                    success=True, response_summary=answer_text[:200],
                    row_count=sum(dr.get("row_count", 0) for dr in domain_results),
                    latency_ms=int((_time.time() - t0) * 1000),
                )
                _save_chat_to_db(
                    session_id=session_id,
                    user_msg=req.message,
                    assistant_msg=answer_text,
                    domain="PROFILE",
                    latency_ms=int((_time.time() - t0) * 1000),
                    row_count=sum(dr.get("row_count", 0) for dr in domain_results),
                    user_id=_user_id,
                )

            yield sse("done", {"_usage": llm.get_last_usage(), 
                "domain": "PROFILE",
                "deck_type": "full" if full_deck else "simple",
                "territory": f"{territory_type}: {territory_name}",
                "domains_queried": [dr["domain"] for dr in domain_results],
                "domains_success": [dr["domain"] for dr in domain_results if not dr.get("error")],
            })
            return

        # ──── 1b. DOMAIN SCOPE GATE: does the chosen domain own this question? ────
        # Each domain self-assesses against its OWN knowledge basis. If it does not
        # have the data, bounce back to the orchestrator to re-route to a better
        # domain. If the question is ambiguous, ask the user to confirm before we
        # execute (avoids guessing & wrong answers). Skipped for map_context (the
        # map flow widens the schema and has its own logic).
        if not req.map_context:
            _tried_domains: list[str] = []
            for _gate_round in range(3):
                yield sse("step_start", {"step": "scope", "label": "Domain Check",
                                         "desc": f"Memastikan domain '{kb['domains'][domain]['label']}' tepat"})
                fit = orchestrator.assess_domain_fit(
                    domain, r.get("rephrased") or validated_query, merged_history)
                verdict = fit.get("verdict", "answerable")
                yield sse("scope", {
                    "domain": domain, "verdict": verdict,
                    "confidence": fit.get("confidence"),
                    "reason": fit.get("reason", ""),
                    "round": _gate_round,
                })

                if verdict == "answerable":
                    break

                if verdict == "clarify":
                    # Ask the user to confirm before executing — terminal turn.
                    clarify_q = (fit.get("clarify_question") or "").strip() or (
                        "Bisa diperjelas sedikit maksud pertanyaannya agar saya bisa "
                        "memberikan jawaban yang paling tepat?")
                    yield sse("clarify", {"question": clarify_q, "domain": domain})
                    yield sse("step_start", {"step": "synth", "label": "Klarifikasi",
                                             "desc": "Meminta konfirmasi sebelum eksekusi"})
                    for _ch in clarify_q:
                        yield sse("token", {"t": _ch})
                    if session_id:
                        memory.append_assistant(session_id, clarify_q, domain=domain)
                        memory.log_analytics(
                            session_id, question=req.message, domain=domain,
                            success=True, response_summary="clarify: " + clarify_q[:160],
                            latency_ms=int((_time.time() - t0) * 1000))
                        _save_chat_to_db(
                            session_id=session_id, user_msg=req.message,
                            assistant_msg=clarify_q, domain=domain,
                            latency_ms=int((_time.time() - t0) * 1000),
                            user_id=_user_id, source="clarify")
                    yield sse("done", {"_usage": llm.get_last_usage(),
                                       "domain": domain, "clarify": True})
                    return

                # verdict == "reroute": ask orchestrator for the next best domain.
                _tried_domains.append(domain)
                suggested = (fit.get("suggested_domain") or "").strip()
                next_domain = None
                if suggested and suggested in kb["domains"] and suggested not in _tried_domains:
                    next_domain = suggested
                else:
                    rr = orchestrator.route(
                        r.get("rephrased") or validated_query, merged_history,
                        avoid_domains=_tried_domains)
                    cand = rr.get("domain", "none")
                    if cand in kb["domains"] and cand not in _tried_domains:
                        next_domain = cand
                        r = rr

                yield sse("reroute", {
                    "from": domain, "to": next_domain,
                    "reason": fit.get("reason", ""),
                    "suggested": suggested,
                })

                if not next_domain:
                    # No other domain owns this → honest "no answer in our data".
                    msg = ("Maaf, pertanyaan ini sepertinya di luar cakupan data yang "
                           "tersedia di sistem kami saat ini. " + (fit.get("reason") or ""))
                    yield sse("step_start", {"step": "synth", "label": "Synthesizer",
                                             "desc": "Menyusun jawaban"})
                    for _ch in msg:
                        yield sse("token", {"t": _ch})
                    if session_id:
                        memory.append_assistant(session_id, msg, domain=domain)
                        memory.log_analytics(
                            session_id, question=req.message, domain=domain,
                            success=False, response_summary="out_of_scope",
                            error_msg=(fit.get("reason") or "")[:200],
                            latency_ms=int((_time.time() - t0) * 1000))
                        _save_chat_to_db(
                            session_id=session_id, user_msg=req.message,
                            assistant_msg=msg, domain=domain,
                            latency_ms=int((_time.time() - t0) * 1000),
                            user_id=_user_id, source="out_of_scope")
                    yield sse("done", {"_usage": llm.get_last_usage(),
                                       "domain": "none", "out_of_scope": True})
                    return

                domain = next_domain
                # loop again: assess the NEW domain (bounded by range(3))

        label = kb["domains"][domain]["label"]
        yield sse("step_start", {"step": "sql_write", "label": "Query Builder", "desc": f"Menyusun query untuk {label}"})

        # ──── 2. SQL agent + self-check reasoning loop ────
        # Two nested behaviours:
        #  (a) ERROR-retry: if a query fails to RUN, fix the SQL (existing logic).
        #  (b) RELEVANCE-refine: if a query RUNS but a QA critique judges the RESULT
        #      as not answering the question (empty / wrong grain / wrong territory /
        #      wrong metric), re-query with a concrete refinement hint — best effort
        #      to find the most relevant answer instead of just "data tidak ada".
        prior_error = prior_sql = None
        result = explanation = None
        refine_hint = None            # carried between relevance-refine rounds
        prior_attempt_sql = None      # last successfully-run SQL we are improving on
        best_effort = None            # critique's note when we give up gracefully
        alt_suggestion = None         # closest askable data to suggest to the user
        MAX_REFINE_ROUNDS = 2         # extra re-queries after the first good run
        refine_round = 0
        is_map = bool(req.map_context) or orchestrator._is_map_query(req.message)

        while True:
            # ---- inner error-retry loop: get a query that RUNS ----
            prior_error = prior_sql = None
            result = None
            for attempt in range(3):
                try:
                    gen_sql = orchestrator.write_sql(
                        domain, r.get("rephrased") or validated_query,
                        prior_error, prior_sql, merged_history, last_res,
                        map_context=bool(req.map_context),
                        refine_hint=refine_hint, prior_attempt_sql=prior_attempt_sql)
                except Exception as e:
                    yield sse("retry", {"error": f"sql_gen_failed: {e}", "attempt": attempt + 1})
                    prior_error = f"sql_gen_failed: {e}"
                    prior_sql = None
                    result = None
                    if attempt == 2 and session_id:
                        memory.log_analytics(
                            session_id, question=req.message, domain=domain,
                            success=False, error_msg=str(e)[:300],
                            latency_ms=int((_time.time() - t0) * 1000),
                        )
                        memory.add_learning(session_id, "error_pattern",
                                            f"SQL gen failed for domain={domain}: {str(e)[:200]}")
                    continue
                sql = gen_sql.get("sql", "")
                explanation = gen_sql.get("explanation", "")
                yield sse("sql", {"sql": sql, "attempt": attempt + 1,
                                  "refine_round": refine_round,
                                  "explanation": explanation,
                                  "_usage": llm.get_last_usage()})
                try:
                    yield sse("step_start", {"step": "bq_exec", "label": "Data Engine", "desc": "Mengambil data dari database"})
                    result = run_query(sql)
                    if is_map:
                        result = _backfill_coords(result)
                    yield sse("result", {
                        "columns": result["columns"], "rows": result["rows"],
                        "row_count": result["row_count"], "sql": result["sql"],
                        "bytes_processed": result["bytes_processed"],
                        "refine_round": refine_round,
                        "chart": chart_spec.suggest(result["columns"], result["rows"], req.message),
                    })
                    break
                except Exception as e:
                    prior_error = str(e)[:600]
                    prior_sql = sql
                    yield sse("retry", {"error": prior_error, "attempt": attempt + 1})
                    result = None

            if result is None:
                break  # could not get a runnable query → fall through to error handling

            # ---- self-check critique (skip for map mode: it has its own spec agent) ----
            if req.map_context:
                # Map mode keeps its dedicated render-spec + style agents.
                try:
                    _map_spec = map_synth_agent.detect_map_spec(
                        result["columns"], result["rows"])
                    try:
                        _style = map_synth_agent.detect_style(
                            req.message, _map_spec, result["columns"])
                        if _style:
                            _map_spec["style"] = _style
                    except Exception:
                        pass
                    yield sse("map_spec", _map_spec)
                except Exception as _e:
                    yield sse("map_spec", {"mode": "none", "reason": f"spec_failed: {_e}"})
                break

            if refine_round >= MAX_REFINE_ROUNDS:
                break  # exhausted refinement budget → deliver best result so far

            yield sse("step_start", {"step": "reflect", "label": "Quality Check",
                                     "desc": "Memeriksa apakah jawaban sudah relevan"})
            crit = orchestrator.critique_result(
                req.message, result.get("sql", ""), result, attempt=refine_round + 1)
            verdict = crit.get("verdict", "ok")
            yield sse("reflect", {
                "verdict": verdict,
                "confidence": crit.get("confidence"),
                "reason": crit.get("reason", ""),
                "round": refine_round,
            })

            if verdict == "ok":
                break  # the result genuinely answers the question

            if verdict == "empty_truly":
                # Answerable in principle but data legitimately absent → stop and
                # let the synthesizer explain + suggest the closest alternative.
                best_effort = crit.get("reason", "")
                alt_suggestion = crit.get("alternative", "")
                break

            # verdict == "refine": re-query with a concrete correction hint.
            refine_round += 1
            refine_hint = crit.get("refinement_hint") or crit.get("reason") or ""
            prior_attempt_sql = result.get("sql", "")
            yield sse("step_start", {"step": "refine", "label": "Refining",
                                     "desc": f"Mencari jawaban yang lebih relevan (putaran {refine_round})"})
            if session_id:
                memory.add_learning(
                    session_id, "refine",
                    f"round={refine_round} domain={domain}: {refine_hint[:200]}")
            # If this was the last allowed round, keep whatever this re-query yields.
            # Loop continues → generates an improved query.

        if result is None:
            err_msg = ("Maaf, query gagal setelah 2 percobaan. "
                       f"Error terakhir: {prior_error}")
            if session_id:
                memory.append_assistant(session_id, err_msg, domain=domain)
                memory.log_analytics(
                    session_id, question=req.message, domain=domain,
                    sql=prior_sql, success=False, error_msg=prior_error,
                    latency_ms=int((_time.time() - t0) * 1000),
                )
                memory.add_learning(session_id, "error_pattern",
                                    f"SQL exec failed domain={domain}: {prior_error[:200]}")
                # Persist failed turns too — these are the most valuable for
                # training / improving question-to-SQL logic.
                _save_chat_to_db(
                    session_id=session_id, user_msg=req.message,
                    assistant_msg=err_msg, domain=domain,
                    sql_query=prior_sql,
                    latency_ms=int((_time.time() - t0) * 1000),
                    user_id=_user_id, source="error",
                )
            yield sse("error", {"error": prior_error or "unknown"})
            return

        # ──── 3. Synthesize final answer ────
        buf = []
        if req.map_context:
            # Dedicated MAP synthesizer: narrates the map (render mode aware).
            yield sse("step_start", {"step": "synth", "label": "Map Synthesizer", "desc": "Merangkai narasi peta dari data"})
            try:
                _spec = map_synth_agent.detect_map_spec(result["columns"], result["rows"])
            except Exception:
                _spec = {"mode": "none"}
            for tok in map_synth_agent.synthesize_map_stream(
                    req.message, result, language, explanation, _spec):
                buf.append(tok)
                yield sse("token", {"t": tok})
        else:
            yield sse("step_start", {"step": "synth", "label": "Synthesizer", "desc": "Merangkai jawaban dari data"})
            preview = result["rows"][:50]
            payload = {
                "question": req.message, "what_it_computes": explanation,
                "columns": result["columns"], "row_count": result["row_count"],
                "rows_preview": preview,
            }
            # When the self-check concluded the data is legitimately absent, give the
            # synthesizer the reason + closest alternative so it explains + suggests
            # instead of a bare "data tidak ada".
            if best_effort:
                payload["best_effort_note"] = best_effort
            if alt_suggestion:
                payload["alternative_suggestion"] = alt_suggestion
            msgs = [
                {"role": "system", "content":
                    orchestrator.SYNTH_SYS.format(language=language)},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False, default=str)},
            ]
            for tok in llm.chat_stream_complete(msgs, model=config.LLM_MODEL_CODER, max_tokens=2200):
                buf.append(tok)
                yield sse("token", {"t": tok})
        answer_text = "".join(buf)
        if session_id:
            memory.append_assistant(
                session_id, answer_text, domain=domain,
                sql=result["sql"], result=result,
            )
            # store result data for follow-up advisory reasoning (no re-query)
            try:
                memory.store_context(
                    session_id, "query",
                    {"question": req.message, "domain": domain,
                     "columns": result.get("columns", []),
                     "rows": result.get("rows", [])[:40]},
                    territory=domain,
                )
            except Exception:
                pass
            memory.log_analytics(
                session_id, question=req.message, domain=domain,
                sql=result["sql"], success=True,
                response_summary=answer_text[:200],
                row_count=result["row_count"],
                latency_ms=int((_time.time() - t0) * 1000),
            )
            # Save to DB
            _save_chat_to_db(
                session_id=session_id,
                user_msg=req.message,
                assistant_msg=answer_text,
                domain=domain,
                sql_query=result.get("sql"),
                row_count=result.get("row_count"),
                latency_ms=int((_time.time() - t0) * 1000),
                user_id=_user_id,
                source="map_query" if req.map_context else None,
            )

        # ──── 4. Export if analyst detected export intent alongside data query ────
        if export_requested:
            yield sse("step_start", {"step": "export", "label": "Export Agent", "desc": "Membuat file branded"})
            _do_export_from_result(session_id, export_format, result,
                                   answer_text, domain, label, explanation)
            yield sse("export_ready", {
                "format": export_format,
                "download_url": f"/api/export/last/{session_id}",
            })

        yield sse("done", {"_usage": llm.get_last_usage(), "domain": domain})

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache",
                                      "X-Accel-Buffering": "no"})


def _do_export(session_id: str, fmt: str, last_res: dict, language: str):
    """Generate export from last_result stored in memory."""
    preview = last_res.get("preview") or {}
    columns = preview.get("columns", [])
    rows = preview.get("rows", [])
    domain = last_res.get("domain", "")
    answer = last_res.get("answer", "")
    sql = last_res.get("sql", "")

    if fmt == "pdf":
        data = export_pdf(columns=columns, rows=rows, title=domain or "Report",
                          summary=answer, sql=sql, domain=domain)
        _export_cache[session_id] = (data, "application/pdf", "ioh_report.pdf")
    else:
        data = export_xlsx(columns=columns, rows=rows, title=domain or "Report",
                           sql=sql, domain=domain)
        _export_cache[session_id] = (
            data,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ioh_report.xlsx",
        )


def _do_export_from_result(session_id, fmt, result, summary, domain, label, explanation):
    """Generate export from a fresh query result."""
    if fmt == "pdf":
        data = export_pdf(
            columns=result["columns"], rows=result["rows"],
            title=label or domain, summary=summary,
            sql=result.get("sql", ""), explanation=explanation, domain=label,
        )
        _export_cache[session_id] = (data, "application/pdf", "ioh_report.pdf")
    else:
        data = export_xlsx(
            columns=result["columns"], rows=result["rows"],
            title=label or domain, sql=result.get("sql", ""),
            explanation=explanation, domain=label,
        )
        _export_cache[session_id] = (
            data,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ioh_report.xlsx",
        )


@app.get("/api/export/last/{session_id}")
def export_last(session_id: str):
    """Download the last generated export for a session."""
    entry = _export_cache.get(session_id)
    if not entry:
        return Response(content='{"error":"no export available"}',
                        media_type="application/json", status_code=404)
    data, media_type, filename = entry
    return Response(
        content=data,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


class SQLReq(BaseModel):
    sql: str
    limit: int | None = None


@app.post("/api/run_sql")
def run_sql(req: SQLReq):
    """Escape hatch: run a vetted read-only SQL directly (for power users)."""
    try:
        return run_query(req.sql, req.limit)
    except QueryError as e:
        return {"error": str(e), "kind": "validation"}
    except Exception as e:
        return {"error": str(e), "kind": "execution"}


# ---- Export (manual, keeps backward compat) ----

class ExportReq(BaseModel):
    format: str = "xlsx"
    columns: list[str]
    rows: list[dict]
    title: str = "Query Result"
    summary: str = ""
    sql: str = ""
    explanation: str = ""
    domain: str = ""


@app.post("/api/export")
def export_data(req: ExportReq):
    """Generate a branded XLSX or PDF from the given data."""
    if req.format == "pdf":
        data = export_pdf(
            columns=req.columns, rows=req.rows,
            title=req.title, summary=req.summary,
            sql=req.sql, explanation=req.explanation,
            domain=req.domain,
        )
        return Response(
            content=data,
            media_type="application/pdf",
            headers={"Content-Disposition": f'attachment; filename="ioh_report.pdf"'},
        )
    else:
        data = export_xlsx(
            columns=req.columns, rows=req.rows,
            title=req.title, sql=req.sql,
            explanation=req.explanation, domain=req.domain,
        )
        return Response(
            content=data,
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            headers={"Content-Disposition": f'attachment; filename="ioh_report.xlsx"'},
        )
