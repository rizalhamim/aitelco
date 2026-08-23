---
title: Session log
type: log
updated: 2026-08-18
---

# Session log

Append-only. Newest first. Record durable decisions/changes with an absolute date. Link to the
node that changed.

## 2026-08-21 (later): agent improvement plan executed, phases 1 to 6

Full detail and numbers in `docs/agent-improvement-plan.md` phase log. Durable rules
extracted to [[agent-quality-gates]].

- Correlation routing 26/30 to 29/30, every expected-CORRELATE case now also yields a valid
  two-domain plan. pytest 34 to 105. Knowledge benchmark stayed 13/13.
- FIVE of the 30 correlation expectations were themselves wrong (same-domain pairs). Verified
  each against the KB schema before correcting. Lesson: verify the benchmark before trusting
  a "model miss".
- FTTH root cause found by probing BigQuery: `sales_region '05. East Java'` also contains Bali
  and stray out-of-Java rows, so a province question must filter `province`. KB fact added,
  recorded in [[ftth]].
- Empty and degenerate results (all-NULL metric, NULL ranking column) now buy one deterministic
  refine round and, failing that, an honest answer. The old benchmark runner scored `rows=0` as
  OK, which is how this class stayed invisible.
- `ranking_verified` no longer matches an ORDER BY inside a CTE, comment, or window function.
  This was letting the synthesizer assert a top-N that was not ordered.
- Live defect fixed: `<think>...</think>` from proxy models was streaming into the top of user
  answers. Filtered at the single `llm` streaming choke point.
- New tooling: `tools_kb_edit.py` (atomic KB edits + backup), `tools_runtime_graph.py` (rebuild
  the SHA-keyed runtime artifact after a KB edit, previously a silent gap), and
  `tools_weekly_review.py` (report-only weekly failure buckets from real traffic).
- hard-30 final 25/30 (not comparable to the old 28/30: that runner passed `rows=0` and had
  no truncated-capture class). Every remaining failure diagnosed against BigQuery, not guessed.
- **Process gap found the hard way**: that fix shipped with a one-line scoping regression
  (`scope_table_hints` initialised inside the scope-gate block, which the fast path skips)
  that broke 17 of 30 questions while all 165 unit tests stayed green. `/api/chat/stream` is
  one generator no unit test executes. Smoke-run 3 questions after any pipeline edit, BEFORE
  a full benchmark. Now mandated in CLAUDE.md, AGENTS.md and [[agent-quality-gates]].
- **Pipeline bug fixed: a domain rerouting to ITSELF killed the turn.** The scope gate sees
  only a bounded table subset; when the table it needs is missing it names that table and
  suggests its own domain. That suggestion was discarded, the turn bounced, and the user got
  "di luar cakupan data" for an answerable question. Now the named table becomes a retrieval
  hint. See [[agent-quality-gates]].
- **Placement rule learned the hard way**: a KB fact can be present in the prompt and still
  be ignored. Facts ABOUT DATA belong in `knowledge_base.json`; constraints on SQL SHAPE
  (never force two tables onto one shared period, rank instead of thresholding) belong in the
  SQL system prompt, guarded by `tests/test_sql_prompt_rules.py`.
- **Biggest generic win: rank, do not guess a threshold.** The SQL writer invented absolute
  cut-offs for vague "tinggi"/"rendah" wording. Kabkota 4G availability spans 98.77 to 100.0,
  so `< 95` matched nothing and looked like missing data. Now the SQL prompt requires
  ORDER BY plus LIMIT or an APPROX_QUANTILES-derived cut-off. See [[agent-quality-gates]].
- QSSO and QURO exist only at kecamatan/branch grain, never per outlet. The agent had been
  silently substituting `sellin_sp_hits_mtd` as a QSSO proxy under the user's own label.
- Measured data facts added to the KB, all worth remembering:
  **partition pruning needs a LITERAL month_id** (45.0 GB via a MAX() subquery or JOIN versus
  1.6 GB with a literal, same aggregate, so the dynamic form alone trips the 50 GB cap);
  **occupancy is frozen at 202512 while availability runs to 202607**, so joining them on a
  shared latest month always returns zero rows; and **FWA 90d columns are mostly empty**
  (`fwa_net_add_90_closing` has 72k values, `fwa_net_add_90_formula` has one, and
  `fwa_grosschurn90` has 480 nationwide with NEGATIVE values, so "high churn" is a large
  absolute value and never `> 0`). Details in [[agent-quality-gates]].
- SQL truncation retries now get a bigger budget (12000 vs 8000) as well as a simplify
  instruction: reusing the budget that just overflowed simply overflowed again.

## 2026-08-21

- Rewrote `CLAUDE.md` "Model & cost policy" into a model-agnostic 6-step operating loop
  (orient, plan, execute, verify gates, self-review, record) so opus or codex deliver
  fable-parity via process. Mirrored in `AGENTS.md` for codex. ADR: [[workflow-operating-loop]].
- Scoped the 5-agent design panel down to significant UI work only, one condensed round
  (was: mandatory on every prompt, 5+ proposals each). Hard constraints kept always-on.
- Installed pytest in backend venv (`requirements-dev.txt`); suite runs 34 pass in ~2s and is
  now a mandatory gate. Knowledge benchmark 13/13.
- Created `docs/agent-improvement-plan.md`: measured baseline (hard-30 28/30,
  correlation-30 26/30 routed 25/30 plan_ok) plus 7 phases: fix benchmark truth, SQL syntax
  robustness, silent-empty handling, implicit-correlation routing, weekly knowledge loop,
  synthesis fluency rubric, conditional model-routing hygiene.
- Fixed stale release line in `AGENTS.md` (1.44.2+52 -> 1.47.0+62, points at
  `app_release.json` as authority).

## 2026-08-18

- Redesigned Flutter Performance Outlook and Site Performance for release `1.45.0+55`.
- Added summary-first KPI cockpits, pinned context, complete expandable chapters, responsive all-data
  tables, Snapshot distribution, FTTH stage values, site diagnostic charts, TalkBack semantics, and
  uncapped platform text scaling.
- Added request generation guards, 350 ms site-search debounce, and bounded report prefetch while
  preserving existing APIs, deep links, report definitions, FTTH filters, and every detail field.
- Added Flutter widget coverage for 200 percent text scale, null versus zero, full table reachability,
  Snapshot buckets, and non-conversion stage charts. See [[mobile]] and [[reports]].
- Integrated Graphify into the root Codex workflow and documented the three knowledge planes.
- Added a safe deterministic projection from `backend/data/knowledge_base.json` into
  `graphify-knowledge/`, with SHA-256 drift checking and structural validation.
- Added corpus exclusions for secrets, databases, geodata, generated tests, the large historical
  session transcript, and Graphify self-documentation.
- Established separate code AST and semantic document freshness lanes. Graphify remains
  development-only and outside FastAPI, web, mobile, and production chat retrieval.
- Decision: [[graphify-development-index]].

## 2026-07-29

- Obsidian installed headless on the server (AppImage 1.12.7 extracted to
  `~/opt/obsidian/squashfs-root`). Runs under systemd `obsidian-headless.service` via Xvfb
  `:99`, memory-capped (`MemoryMax=1200M`, `OOMScoreAdjust=800` so it dies before telco under
  memory pressure). Uses ~200MB. Enabled on boot.
- Vault `telco-ai/vault/` registered in the app's global `obsidian.json`; CLI enabled via
  `cli:true` in that same global config (NOT the vault app.json). CLI reachable as `obsidian`
  in PATH (`~/.local/bin/obsidian` wrapper sets DISPLAY/HOME/XDG). Verified: read/search work.
- Added a 4Gi swapfile (`/swapfile2`, in fstab) earlier because swap was full. This is what
  made headless Obsidian safe to run.

## 2026-07-26 (later)

- Added "Token budget: DO NOT load the whole codebase" block to `CLAUDE.md`, ranking the four
  workflows (vault → graphify → obsidian-skills → caveman) as the path before any bulk read.
- obsidian-skills installed globally via `npx skills add` → `~/.agents/skills/` (symlinked into
  `~/.claude/skills/`), available across all projects, not just this vault.
- [[agent-protocol]] division-of-labor updated to cover all four workflows.

## 2026-07-26

- Vault created. Seeded from `AGENTS.md`, `FTTH_KNOWLEDGE_BASE.txt`, `design-rule.txt`,
  `docs/design-system-teal.md`, and the report/agent knowledge docs. Structure + index-first
  token-saving model in [[README]] and [[agent-protocol]].
- Wired into `telco-ai/CLAUDE.md` so agents read [[INDEX]] before answering knowledge questions.
- obsidian-skills (kepano) symlinked into `vault/.claude/skills/` (local-only, gitignored).

## Earlier (from source docs, absolute-dated)

- **2026-06**: FTTH "Indosat HiFi" report went LIVE. Apple-to-apple YTD/LYTD fix landed
  ([[ytd-lytd-apple-to-apple]]). `rham_ftth_sitewise_monthly` added to the `ftth` domain.
  KB `data_facts` gained circle→region mapping, `kabkot` column note, `_mth` exact-month-filter
  rule, FWA/unlimited definitions ([[bigquery-tables]], [[knowledge-base-json]]).

## 2026-07-29: opus cost policy

- Pinned project model to opus (effort high) in `.claude/settings.json`; fable only via explicit `/model fable`.
- Disabled 7 unused plugins project-wide, hid dataviz/deep-research from model skill listing.
- Added "Model & cost policy" block to CLAUDE.md: plan-first, diff self-review, verify-live, cavecrew delegation.
- ADR: [[opus-cost-policy]].

## 2026-08-19 | Release 1.47.0+62: report UI unification and signed release

Six phases across mobile and backend, then a signed release.

- **`mobile/lib/src/format/report_format.dart` (new)**: the only place `NumberFormat` is
  called. Fixes the dangling-comma bug (`'#,##0.' + ''` renders `3` as `3,`), adds an
  adaptive magnitude so a small revenue reads Mn instead of `0,0 Bn`, and centralises
  polarity so churn rising is red everywhere.
- **`Brands` in `theme.dart`**: IOH teal, IM3 orange, 3ID magenta, TSEL red (was blue),
  XLSMART blue. `reports_network.py` now emits `*_xlsmart_4g` merged sample-weighted, the
  same rule `reports_competitive._facebook_query` already used.
- **`ReportPeriodTable` in `report_ui.dart`**: replaces four hand-rolled period tables;
  `reports_screen.dart` dropped 4403 to 3784 lines. Growth colour now also reaches every
  `ReportAllDataTable` path, which is what the fwa, internal, and benchmark tabs use.
- **IOH aggregate**: `/comprehensive` M2M and all six `/market-insight` panels now carry an
  IOH row (IM3 plus 3ID). This fixed a live bug where the client looked for an `IOH` actor
  that never existed and silently fell back to `Industry`, labelling industry totals as IOH.
- **`ReportCacheService` (new)**: cache moved out of screen state so it survives navigation,
  with in-flight de-duplication and a bounded LRU. All tabs warm on first load.
- **Map sheet**: rebuilt on the shared panel and attribute widgets. Field values are now
  key-aware, so `month_id` stays `202608` rather than becoming `202.608`.

Three real defects surfaced while verifying, each of which would have shipped:
`whenComplete(() => _inflight.remove(key))` returned the removed Future so it awaited
itself and every tab request would have hung forever; row-height measurement ignored both
the ambient text style and bold weight, overflowing cells in every table; and the insight
cockpit read `history.last`, which is the *oldest* month because the payload is descending.

Release signing now reads `mobile/android/key.properties` (gitignored), so a release build
is reproducible without exported environment variables. See [[deploy-restart]] for why the
signer fingerprint is pinned.
