---
title: "ADR: Auth is optional on chat"
type: decision
updated: 2026-07-26
---

# ADR: Auth optional on chat

**Decision**: `/api/chat` accepts requests with no token (anonymous), but an EXPIRED token
returns 401 instead of falling back to anonymous.

## Why

- Anonymous access lets the chat work without forcing login (lower friction).
- But a request carrying an expired token means a real logged-in client (mobile) whose session
  lapsed. Returning 401 makes the client refresh its token, instead of silently saving the turn
  as anonymous and losing it from the user's history.

## Rules

- No token → anonymous, allowed.
- Expired token → 401 (mobile refreshes). See [[mobile]].
- JWT `sub` is the **username** — resolve to user PK via the `User` table, NEVER `int(sub)`.

## Where

`auth.py`, `routes_auth.py`, `database.py`. JWT auth + refresh, users, chat history, usage logs.
`User` is a god node (64 edges). `graphify query "auth get_current_user"`.

## Related

- [[chat-pipeline]] · [[backend-modules]] · [[mobile]]
