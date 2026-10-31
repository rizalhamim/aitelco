---
title: Frontend (Next.js web app)
type: architecture
updated: 2026-07-26
---

# Frontend — Next.js 16 web app

`frontend/`. Next.js 16 + React 19, TypeScript, Tailwind. `graphify query "frontend page"` for code.

## Run

```bash
cd frontend
npm install
npm run dev      # http://localhost:3000
npm run build
npm run lint     # eslint flat config: eslint.config.mjs
```

## Key facts

- **Next.js 16 / React 19** — APIs differ from older docs. Read `node_modules/next/dist/docs/`
  before writing code (per `frontend/AGENTS.md`). `frontend/CLAUDE.md` just re-exports `@AGENTS.md`.
- `next.config.ts` rewrites `/api/*` → `BACKEND_URL` (default `http://localhost:8000`).
  Browser calls same-origin `/api/*`, so CORS is usually a non-issue. Point `BACKEND_URL` at a
  remote backend to use one.
- `@/*` → `./src/*`. App Router pages in `src/app/`: `map/`, `profile/`, `admin/`, `login/`,
  `reports/`, `site/`.

## Design system

Web app uses the **teal** design system (Teal-500 `#15A697` primary, Poppins + Prompt).
See [[style-brand]]. Reports page brand model → [[reports]].

## Related

- [[reports]] · [[system-overview]] · [[deploy-restart]]
