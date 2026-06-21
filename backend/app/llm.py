"""LLM client for the 9Router (OpenAI-compatible) endpoint.

Note: the endpoint streams SSE by default, so we always parse stream chunks
even for non-streaming calls.
"""
import json
import urllib.request
import urllib.error

from . import config


def _post(messages, model=None, max_tokens=2000, temperature=0.0, stream=False):
    model = model or config.LLM_MODEL
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "stream": stream,
    }
    # Some models (e.g. claude-opus-4-7) reject `temperature`. Only send it
    # when explicitly non-default and allowed; default 0.0 -> omit to be safe.
    if temperature not in (None, 0.0) and not config.LLM_OMIT_TEMPERATURE:
        payload["temperature"] = temperature
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        config.LLM_BASE.rstrip("/") + "/chat/completions",
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + config.LLM_KEY,
        },
    )
    return urllib.request.urlopen(req, timeout=90)


_last_usage = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}

def get_last_usage() -> dict:
    return dict(_last_usage)

def reset_usage():
    global _last_usage
    _last_usage = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}

def _accumulate_usage(usage: dict):
    global _last_usage
    _last_usage = {
        "prompt_tokens": _last_usage["prompt_tokens"] + (usage.get("prompt_tokens") or 0),
        "completion_tokens": _last_usage["completion_tokens"] + (usage.get("completion_tokens") or 0),
        "total_tokens": _last_usage["total_tokens"] + (usage.get("total_tokens") or 0),
    }

# Tracks the finish_reason of the most recent stream (per generation). When the
# model stops because it hit max_tokens, this is set to "length" so callers can
# auto-continue instead of delivering a truncated answer.
_last_finish_reason = {"value": None}

def get_last_finish_reason():
    return _last_finish_reason["value"]


def _parse_sse(resp):
    """Yield content deltas from an SSE stream. Records the finish_reason of the
    final chunk in _last_finish_reason (e.g. 'stop', 'length')."""
    _last_finish_reason["value"] = None
    for raw in resp:
        line = raw.decode("utf-8", "replace").strip()
        if not line or not line.startswith("data:"):
            continue
        data = line[len("data:"):].strip()
        if data == "[DONE]":
            break
        try:
            obj = json.loads(data)
        except json.JSONDecodeError:
            continue
        usage = obj.get("usage")
        if usage:
            _accumulate_usage(usage)
        choices = obj.get("choices") or []
        if not choices:
            continue
        fr = choices[0].get("finish_reason")
        if fr:
            _last_finish_reason["value"] = fr
        delta = choices[0].get("delta") or {}
        piece = delta.get("content")
        if piece:
            yield piece


def chat(messages, model=None, max_tokens=2000, temperature=0.0) -> str:
    """Non-streaming convenience call. Collapses the SSE stream into a string."""
    try:
        resp = _post(messages, model=model, max_tokens=max_tokens,
                     temperature=temperature, stream=True)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"LLM HTTP {e.code}: {detail}")
    return "".join(_parse_sse(resp))


def chat_stream(messages, model=None, max_tokens=2000, temperature=0.0):
    """Generator yielding content tokens as they arrive.

    Falls back to LLM_MODEL (the general, more stable model) when the
    specialized model returns an HTTP error — same fallback strategy
    chat_json uses. This protects against transient or permanent upstream
    issues with specialized model routes (e.g. provider misconfig on
    one specific model variant).
    """
    primary = model or config.LLM_MODEL
    fallback = config.LLM_MODEL if primary != config.LLM_MODEL else None
    try:
        resp = _post(messages, model=primary, max_tokens=max_tokens,
                     temperature=temperature, stream=True)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        if fallback:
            # try fallback model once
            try:
                resp = _post(messages, model=fallback, max_tokens=max_tokens,
                             temperature=temperature, stream=True)
            except urllib.error.HTTPError as e2:
                detail2 = e2.read().decode("utf-8", "replace")[:500]
                raise RuntimeError(
                    f"LLM HTTP {e.code} on {primary}, fallback {fallback} also failed: {detail2}"
                )
        else:
            raise RuntimeError(f"LLM HTTP {e.code}: {detail}")
    yield from _parse_sse(resp)


def chat_stream_complete(messages, model=None, max_tokens=2000,
                         temperature=0.0, max_continuations=3):
    """Like chat_stream, but if the model stops because it hit the token cap
    (finish_reason == 'length'), it automatically continues the generation so the
    answer is never delivered truncated. Streams all tokens transparently.

    Implementation: after each streamed segment, if finish_reason is 'length',
    we append the partial assistant text and ask the model to CONTINUE exactly
    where it left off (no repetition, no preamble), up to `max_continuations`
    times."""
    convo = list(messages)
    produced = ""
    for _i in range(max_continuations + 1):
        segment = []
        for piece in chat_stream(convo, model=model, max_tokens=max_tokens,
                                 temperature=temperature):
            segment.append(piece)
            yield piece
        seg_text = "".join(segment)
        produced += seg_text
        # Different OpenAI-compatible backends report the token-cap stop reason as
        # 'length' or 'max_tokens'. Treat both as "truncated → continue".
        if get_last_finish_reason() not in ("length", "max_tokens"):
            return  # completed naturally (or stopped for another reason)
        if not seg_text.strip():
            return  # nothing produced — avoid an infinite continue loop
        # Continue: feed back what we have so far and ask to resume seamlessly.
        convo = list(messages) + [
            {"role": "assistant", "content": produced},
            {"role": "user", "content":
                "Lanjutkan jawaban tepat dari posisi terakhir tadi. JANGAN mengulang "
                "teks yang sudah ditulis, JANGAN menambahkan pembuka/penutup baru — "
                "langsung sambung kalimat/tabel yang terpotong sampai selesai."},
        ]


def chat_json(messages, model=None, max_tokens=2000, retries=4) -> dict:
    """Call and parse a JSON object out of the reply (robust to code fences).
    Retries with backoff on empty or unparseable responses (the upstream
    endpoint intermittently returns empty bodies under load). If the primary
    model keeps returning empty OR raises an HTTP error, falls back to the
    main model (LLM_MODEL) which historically is more stable.

    Fallback timing: switch to LLM_MODEL on attempt 1 (the SECOND try) — earlier
    code waited until attempt N-1 which wasted ~2 min when the specialized model
    is permanently broken (e.g. provider-side config mismatch).
    """
    import time as _t
    primary = model or config.LLM_MODEL
    fallback = config.LLM_MODEL if primary != config.LLM_MODEL else None
    last_err = None
    for attempt in range(retries + 1):
        # Switch to fallback on attempt >= 1 if available — faster recovery when
        # the specialized model is broken upstream.
        use_model = primary if (attempt == 0 or not fallback) else fallback
        try:
            text = chat(messages, model=use_model, max_tokens=max_tokens, temperature=0.0)
            if not text or not text.strip():
                last_err = ValueError("LLM returned empty response")
                _t.sleep(0.6 * (attempt + 1))
                continue
            return extract_json(text)
        except (json.JSONDecodeError, ValueError) as e:
            last_err = e
            _t.sleep(0.4 * (attempt + 1))
            if attempt < retries:
                continue
        except RuntimeError as e:
            # chat() raises RuntimeError("LLM HTTP ...") for non-2xx upstream.
            # Burn the attempt and continue — the fallback model will kick in next loop.
            last_err = e
            _t.sleep(0.3 * (attempt + 1))
            if attempt < retries:
                continue
    raise last_err


def _repair_json(text: str) -> str:
    """Attempt to repair truncated / malformed JSON from LLM output.

    Common issues:
    - Unterminated strings: {"sql": "SELECT ...   (no closing quote)
    - Missing closing braces: {"sql": "...", "explanation": "...
    - Trailing commas before }
    - Single quotes instead of double quotes
    """
    import re
    t = text.strip()

    # Replace single quotes used as JSON delimiters (heuristic)
    # Only if there are no double quotes at all (very rare)
    if '"' not in t and "'" in t:
        t = t.replace("'", '"')

    # Try to close unterminated strings and objects
    # Count unescaped quotes
    in_string = False
    escaped = False
    brace_depth = 0
    last_good = 0
    for i, c in enumerate(t):
        if escaped:
            escaped = False
            continue
        if c == '\\':
            escaped = True
            continue
        if c == '"':
            in_string = not in_string
            last_good = i
        elif not in_string:
            if c == '{':
                brace_depth += 1
            elif c == '}':
                brace_depth -= 1
                last_good = i

    # If we're stuck inside a string, close it and try to add missing keys
    if in_string:
        # If the truncated string is the "sql" value, we need to close it
        # and provide a minimal valid JSON
        t = t + '"'
        # Check if we might need to close the explanation field too
        if '"explanation"' not in t and '"sql"' in t:
            t = t + ', "explanation": "truncated"'

    # Remove trailing comma before we close braces
    t = re.sub(r',\s*$', '', t)

    # Close any unclosed braces
    # Recount after potential quote fix
    brace_depth = 0
    in_string = False
    escaped = False
    for c in t:
        if escaped:
            escaped = False
            continue
        if c == '\\':
            escaped = True
            continue
        if c == '"':
            in_string = not in_string
        elif not in_string:
            if c == '{':
                brace_depth += 1
            elif c == '}':
                brace_depth -= 1
    if brace_depth > 0:
        t = t + '}' * brace_depth

    return t


def _sql_from_markdown(text: str) -> dict | None:
    """Fallback: if the model returned prose + a ```sql fence instead of JSON,
    extract the SQL and wrap it into the expected {sql, explanation} shape.
    Only accept a real data query against the mart (must reference a backtick
    fully-qualified table) and reject INFORMATION_SCHEMA / system queries."""
    import re
    m = re.search(r"```(?:sql)?\s*(.*?)```", text, re.DOTALL | re.IGNORECASE)
    candidate = m.group(1).strip() if m else None
    if not candidate:
        return None
    if not re.search(r"\b(SELECT|WITH)\b", candidate, re.IGNORECASE):
        return None
    # must query the actual mart (fully-qualified `project.dataset.table`)
    if "`" not in candidate:
        return None
    # reject schema-introspection / system queries
    if re.search(r"INFORMATION_SCHEMA|__TABLES__|\.COLUMNS\b", candidate, re.IGNORECASE):
        return None
    return {"sql": candidate.rstrip(";").strip(),
            "explanation": "Generated query."}


def extract_json(text: str) -> dict:
    text = text.strip()
    # strip ```json ... ``` fences
    if text.startswith("```"):
        inner = text.split("\n", 1)[-1]
        if inner.rstrip().endswith("```"):
            inner = inner.rstrip()[:-3]
        # only adopt the stripped version if it looks like JSON
        if inner.lstrip().startswith("{"):
            text = inner
    # find first { and try to parse balanced braces
    start = text.find("{")
    if start == -1:
        # Fallback: model returned prose + SQL fence instead of JSON
        fallback = _sql_from_markdown(text)
        if fallback is not None:
            return fallback
        raise ValueError(f"No JSON object found in: {text[:200]}")
    # Try parsing from the first { — json.loads will stop at the end of the object
    # Use raw_decode to handle trailing content gracefully
    decoder = json.JSONDecoder()
    try:
        obj, _ = decoder.raw_decode(text, start)
        if isinstance(obj, dict):
            return obj
    except json.JSONDecodeError:
        pass
    # Fallback: first { to last }
    end = text.rfind("}")
    if end > start:
        try:
            return json.loads(text[start:end + 1])
        except json.JSONDecodeError:
            pass
    # Repair attempt: fix truncated strings, unclosed braces
    chunk = text[start:] if start >= 0 else text
    repaired = _repair_json(chunk)
    try:
        return json.loads(repaired)
    except json.JSONDecodeError:
        pass
    # Last resort: try the whole text
    return json.loads(text)
