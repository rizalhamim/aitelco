# 9Router proxy: Haiku-4-5 calls failing with `long_context_beta` error

## Summary

Two `Agent-Java-*` model variants are currently broken at the upstream proxy:

- `Agent-Java-v02.3-Flash`
- `Agent-Java-v02.3-SQL`

Both route to `claude-haiku-4-5-20251001` with a `long_context_beta` flag the Anthropic subscription does not have, causing **every** call to return HTTP 400.

## Reproduction

Direct call to the proxy (same key telco-ai uses):

```
curl -X POST -H "Authorization: Bearer sk-..." -H "Content-Type: application/json" \
  http://43.129.52.9:20128/v1/chat/completions \
  -d '{"model":"Agent-Java-v02.3-Flash","messages":[{"role":"user","content":"hi"}],"max_tokens":10}'
```

Response:

```json
{"error":{"message":"[claude/claude-haiku-4-5-20251001] [400]: {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The long context beta is not yet available for this subscription.\"},\"request_id\":\"req_011CcGGq3YQCmQuWoNzP7iHV\"} (reset after 30s)"}}
```

Same payload against the other variants:

| Model | Status | Underlying |
|---|---|---|
| `Agent-Java-v02.3` | ✅ works | claude-opus-4-8 |
| `Agent-Java-v02.3-Flash` | ❌ 400 | claude-haiku-4-5-20251001 |
| `Agent-Java-v02.3-SQL` | ❌ 400 | claude-haiku-4-5-20251001 |
| `Agent-Java-v02.3-Coder` | ✅ works | claude-opus-4-8 |
| `Agent-Java-v02.3-Analyst` | ✅ works | claude-opus-4-8 |

## Root cause (hypothesis)

The proxy is sending `anthropic-beta: long-context-context-1m` (or similar) when calling Anthropic for Haiku-4-5. The Anthropic account being used doesn't have that beta enabled — only Opus 4.8 does (which is why those variants work).

## Suggested fix at the proxy

Either:
- **A.** Remove the `long_context_beta` header for Haiku-4-5 calls, or
- **B.** Drop Haiku-4-5 from the routing pool until the subscription has the beta, or
- **C.** Enable the long-context beta on the Anthropic subscription this proxy uses.

(A) and (B) are zero-cost fixes. (C) requires account-side action.

## Impact on telco-ai

Until fixed:
- Router, Analyst, Domain-fit gate, and SQL writer all hit this error first.
- Backend recovers via in-process fallback to `Agent-Java-v02.3` (claude-opus-4-8) — see `app/llm.py`.
- Per-call latency is ~30s higher than ideal (one wasted attempt before fallback fires).
- SQL prompt is tuned for the specialized SQL model; opus-4-8 occasionally writes differently-formatted SQL (5 known regressions in `test_results/post_fix_v2.json` vs `baseline_pre.json`).

Restoring the Haiku route should reduce latency and very likely improve accuracy further.
