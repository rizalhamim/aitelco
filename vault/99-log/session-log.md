---
title: Session log
type: log
updated: 2026-10-04
---

# Session log

Append-only. Newest first. Record durable decisions/changes with an absolute date. Link to the
node that changed.

## 2026-09-21: legacy KPI highlevel sources retired from agent routing

The runtime KB and governance registry now route daily KPI questions to
`rham_mkt_kpi_highlevel_dly`, MTD questions to `rham_mkt_highlevel_mtd`, and monthly
questions to `rham_mkt_highlevel_mth`. The three legacy `rham_kpi_highlevel_*` tables are
marked superseded and hard-blocked so the agent cannot generate new queries against sources
planned for deletion. Live BigQuery checks confirmed target coverage through 2026-09-19.
See [[bigquery-tables]].

## 2026-09-17: java_precalc re-audit, 18 new tables onboarded, discovery gate added

The dataset had drifted badly since the 2026-08-19 review: 274 live objects against
238 governed and 157 in the runtime KB. Discovery reported success the whole time,
because `--check` only validated governance against itself and never against BigQuery.

- `tools_knowledge_refresh.py` now emits a `delta` (new objects, missing objects,
  schema drift, partition drift) and fails `--check` on any of them. `promote()`
  refuses an approved table whose schema or partitioning changed unreviewed.
- Found and fixed a real bug: a table DELETED from BigQuery stayed in the KB,
  because `promote()` only removed tables it found in the catalog. The whole
  `rham_subs_traffic_*` family was gone, and three of them were still being shown
  to the SQL writer as valid schema.
- `physical_hash` is deliberately separate from `schema_hash`: folding
  partitioning into the column hash would mark all 238 records drifted at once.
- Reviewed contracts now survive a metadata refresh. Previously every promotion
  overwrote hand-reviewed grain, period, and aliases with name-based guesses.
- New `tools_profile_candidate.py` profiles a table that is NOT yet in the KB
  (the old tool reads the KB, so it could never look at a table under review).
  Every query is dry-run and refused above 8 GB.
- New `tools_apply_review.py` applies a reviewed decision file incrementally.
  `--rebuild-governance` resets every decision_history and must not be used for
  onboarding.
- Decisions for all 50 objects: `backend/governance/review_2026_09_17.json`.
  175 approved (up from 157), 58 candidate, 26 quarantined, 12 rejected, 3 superseded.
- Blocked by evidence, not by guesswork: MSISDN-keyed tables, employee-level
  postpaid tables (`id_sales`, `nik_sales`), FTTH ticket detail with customer ids,
  staging, backups, two empty tables, a 60 GB dated snapshot, and duplicated
  `_ex_dtu` copies.
- Profiling changed three decisions. `rham_kec_wise_tnr_mtd` has 68 of 184 numeric
  columns completely EMPTY, so the empty list ships as `warning_columns`.
  `rham_ftth_tt_mttr` mixes WEEKLY and MONTHLY rows and contains a `Grand Total`
  bucket. `rham_outlet_secondary_mtd` is NOT unique on its apparent grain.
- Measured why the partition constraints matter: literal versus `MAX()` subquery
  is 0.28 GB against 4.98 GB on `rham_site_traffic_usage_mth`, and 0.01 GB
  against 0.71 GB on `rham_outlet_low_stock`.
- `run_hard_questions.py` never compared the expected domain it had been reading
  for every case, so a wrong route scored OK. Added the `wrong_route` class.
- Gates: 335 backend tests (70 new), knowledge benchmark 24/24 (11 new cases),
  governance/graph/projection checks clean, and 10 hand-written SQL probes against
  the real tables all returned rows. Live chat could not be smoke-tested: the
  upstream LLM at `LLM_BASE` is refusing connections, unrelated to this change.

## 2026-09-17: closed the self-learning loop (no Agents SDK port)

User asked to make the agent smarter and self-learning, suggesting a port to the OpenAI
Agents SDK. Rejected the port: handoffs, guardrails, sessions, and the tool-retry loop
already exist in [[chat-pipeline]], the LLM is the in-house `Agent-Java` family behind a
custom base URL, and the SDK does not learn anything by itself. The real gap was that
`analytics` and `learning_notes` were write-only, so every failure was forgotten.

- New `backend/app/lessons.py` counts recent failures per domain, classifies them with
  the taxonomy already used by `tools_weekly_review.py`, and returns a curated lesson.
- `orchestrator.write_sql` appends that block to the SQL system prompt.
- Safety by construction: the database picks WHICH lesson fires, the text is a constant
  in `PROMPT_LESSONS`, so no user or error text ever reaches the prompt. A bucket needs
  `LESSON_MIN_COUNT` hits in `LESSON_DAYS` to qualify, at most `LESSON_MAX` lessons and
  700 chars are injected, and `LESSONS_ENABLED=false` removes the loop entirely.
- Inspect what is live with `GET /api/lessons/{domain_key}`.
- Gates: backend 236 tests pass (9 new in `tests/test_lessons.py`), knowledge benchmark
  13/13. Live smoke could not run: the upstream LLM at `LLM_BASE` was refusing
  connections at the time, which is unrelated to this change.

## 2026-08-23: charts moved to the backend, answers made unit-aware

User reported charts and answers were not representative. Root cause was not styling:
the clients split columns into numeric and non-numeric and plotted the FIRST numeric
one, so `rank` was drawn as bars, rupiah and percent shared one axis (21 percent of
real results carry both), and a wide result produced no chart at all.

- New `backend/app/chart_spec.py` classifies a result by column ROLE and streams a
  `chart_spec` SSE event. Web and mobile now render it; both keep a fixed fallback for
  old chat history. Decision recorded in [[chart-spec-backend-owned]].
- Charts now carry units, dual axes, honest pie rules, funnel detection, ranked-subset
  captions ("24 teratas dari 38 kabkota"), and period spans instead of row counts.
- `SYNTH_SYS` gained answer-first structure, period plus scope in the opening sentence,
  Indonesian number and unit formatting (one magnitude per column), and a requirement
  that the narration agree with the chart it sits next to.
- Fixed a real retrieval bug found on the way: a validated table hint was only a scoring
  nudge, so the territory-reference injection could evict the very table the policy gate
  had just demanded. Hints are now guaranteed to survive selection.
- Gates: backend 223 tests, mobile 50 tests, flutter analyze clean, frontend lint and
  build clean, knowledge benchmark 13/13. Verified live on ranking, trend, composition
  and funnel questions.

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
- hard-30 reached 28/30 on the first run with a correct pipeline, then both remaining
  failures were fixed: an "aggregations of aggregations" SQL error (prompt rule added) and
  the retrieval-miss guard being too narrow. Case 6 verified stable across 3 consecutive
  runs after the fix.
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

## 2026-08-29 | Login page: fluid background, responsive rework, BigQuery wording removed

The login page no longer names BigQuery anywhere. The warehouse was leaking into
user-facing copy through the capability cards, the pipeline steps, the lede, the stat
block, and the page metadata. Copy now says "Data Engine" and "business data"; the stats
dropped the two warehouse figures (118 tables, 2.56B rows) for `5 Domains` and `24/7 Ready`.
The vendor is an implementation detail, not a selling point, and it was the only thing on
the page a reader could not act on.

The old background was a particle-network canvas whose motion came from `Math.sin` on a
fixed period, so it visibly repeated. It is replaced by `frontend/src/lib/fluid.ts`: one
3D simplex field drives two layers, low-res metaball blobs (upscaled and CSS-blurred into
a liquid mesh) plus particles advected by that same field. Time advances monotonically and
is never wrapped, which is what keeps the motion from looping. The right panel runs the
same engine at 0.4x speed with no particles, so the two halves read as one surface.

Tiering is by `(hover: none)` and a 900px `matchMedia`, not by `hardwareConcurrency` alone.
Core count under-reports badly (this build server reports 2), and gating on it silently
killed the particle layer on real desktops. Cores now only size the swarm. Both queries are
subscribed, so rotating a phone or dragging a window across the breakpoint rebuilds the
correct tier instead of freezing whatever was true at first paint.

`.login-left` is no longer `display: none` under 900px. It becomes a compact hero above the
form, keeping the fluid on phones, and `.login-right` goes transparent there so the stacked
panels have no seam. Inputs are 16px (below that iOS zooms the viewport on focus) and tap
targets are 48px minimum.

Verified live at 1600px, 1440px, and iPhone 13 against the running service, not from unit
tests: forgot-password pane, a real failed login (the error tint is `--ioh-danger`, since
`--ioh-red` is the legacy alias for teal and would have rendered a green error), the
reduced-motion path still painting a static frame, and a shrink-then-grow across the
breakpoint returning a fully repainted canvas with no console errors.

Two defects came out of review before shipping: `resize()` early-returned on a zero-size
host while leaving stale dimensions, so the hidden right canvas kept a rAF loop drawing
against them on phones, exactly the battery cost the light tier exists to avoid; and
particles spawned before first layout piled at the origin and stayed there. Both are fixed
by treating a zero-size host as dormant and respawning once the host gains size.

### Same day, follow-up: the card was invisible in both themes

The first pass hardcoded the form card as `rgba(255,255,255,0.82)` with a white border.
That fails twice. In light mode the card sat on `--ioh-panel` (`#F5F9F8`), a 1.06 contrast
ratio, so the box had no visible edge at all. In dark mode it was worse: the card stayed
white while `--ioh-ink` inverted to `#E8EEEC`, putting near-white text on a near-white
surface. The page has no theme toggle of its own, it inherits `prefers-color-scheme` from
the tokens file, so this only showed up when the OS was set to dark.

The fix is a set of `--login-*` surface tokens declared on `.login-shell` and re-declared
under both the media query and the explicit `.dark` / `[data-theme="dark"]` selectors, the
same dual pattern `ioh-tokens.css` already uses. Card, input, veil, page background, and
fluid opacity all read from those tokens now. The rule for this block: never hardcode white,
because the fluid canvas means every surface is translucent glass over moving colour.

Three elements are deliberately pinned to literal values rather than tokens, each with a
comment saying why: the terminal block and the agent icon chips stay `#0F1F1D` because
`--ioh-ink` inverts and would wash out the text sitting on them, and the submit label and
spinner stay `#FFFFFF` because the button is teal in both themes.

Card separation was measured, not eyeballed: a script composites the translucent card over
the page background and computes WCAG ratios. Light card-vs-page went 1.06 to 1.16 and the
border 1.16 to 1.37 after deepening `--login-right-bg` to `#E4EFEC` and tinting the border
with brand teal instead of the flat grey `--ioh-rule`. All text passes AA in both themes
(lowest is 5.57 on the eyebrow and footer).

## 2026-10-04 - Territory, source-grain, scan-budget, and mobile migration

Implemented public Area=legacy Branch and District=legacy MC, retained legacy API aliases,
and migrated approved commercial source families to Kecamatan detail. Refreshed live
schemas/governance without deleting warehouse data. Added shared literal-partition and
5 GiB execution-budget guards, bounded site/history queries, fixed January rollover,
and preserved explicit AI grouping during rephrasing. Product dry-run scan fell from
2,542,643,162 to 186,676,031 bytes for the same aggregate. Updated web/mobile filters,
compact shared mobile theme, polygon holes/boundaries, GPS uncertainty/refresh, map
legends, and full-field detail sheets. Release 1.48.0+63 uses the existing signer and
retains the previous APK for rollback. Durable evidence, limitations, and cost-control
checklist are in [[bigquery-tables]].

Final verification: 357 backend tests, 28/28 knowledge cases, 53 mobile tests,
clean Flutter analysis, clean frontend lint/build, and restarted live chat smoke
3/3 (product/network/FTTH). Comprehensive Area, Data Revenue, Site Performance,
nearest-site, and Product Demand District APIs were exercised live. Product
Demand retains full YTD/LYTD through two-month partitioned batches; batching
does not itself reduce total billed bytes. Removed unopened-report prefetches
and corrected territory/brand-specific cache keys. Web District Product Demand
at 390x844 has no page-wide horizontal overflow. Public host verified as
agent.bizplan-java.com. Final downloaded APK SHA-256:
66502dcd3154b815420500b77f32163a968a0f0e0924b83cf380031b6415452a.
Runtime KB graph/projection checks are current. Developer semantic extraction
was partial due to provider regional rejection/timeouts; deterministic code
refresh succeeded. No physical-device GPS field validation or warehouse DDL.

## 2026-10-04 - Missing legacy mobile update notification diagnosis

APK 1.47.0+62 still calls http://agent-02.bizplan-java.com:8000/api/app/version;
verified the embedded URL and a live DNS resolution failure. Active endpoint
https://agent.bizplan-java.com/api/app/version serves available 1.48.0+63.
Updater swallows check errors as null and only automatically checks on chat
initialization. Recorded findings in [[mobile]]. No application, DNS, or proxy
changes made in this diagnostic turn.

## 2026-10-04 - Mobile updater fix and legacy endpoint recovery

Published 1.48.1+64 with route-independent startup/resume checks, five-minute
foreground polling, 30-second failed-check retries, explicit check errors in
Profile, and a single scrollable update dialog. Version metadata is non-cacheable
and points to the active HTTPS download URL. Backend restarted; public health,
version 64, availability, and downloaded APK were verified live. APK SHA-256:
845b641ab0fbc517d7a07a1dc1262fa7301f703e48e3b8686d320995a07cec52.
Package and existing Android Debug signer are unchanged. Retained release 63 as
an explicit rollback APK. Passed 359 backend tests, 67 mobile tests, clean Flutter
analysis, release build, and deterministic Graphify refresh. Details in [[mobile]].

Legacy restoration is authorized but still pending external DNS access. Public and
authoritative DNS return NXDOMAIN for agent-02.bizplan-java.com. Explicit IP
resolution confirms its old port-8000 version route serves build 64, but this is
not a DNS repair. Requested A record agent-02 to 43.129.52.9, TTL 300, or a secure
DNS-management connection. APK 1.47 automatic notification remains dependent on
that restoration; manual installation is available now. No physical-device popup
or installer validation was claimed.

## 2026-10-04 - User restored legacy mobile DNS

Authoritative DNS, 1.1.1.1, and 8.8.8.8 now resolve agent-02.bizplan-java.com to
43.129.52.9 (TTL 14400). Normal live curl without forced IP resolution confirms
the APK 1.47 port-8000 version endpoint returns HTTP 200 and available release
1.48.1+64. Legacy health is healthy and its downloaded APK matches the published
SHA-256. DNS blocker resolved without additional code/proxy changes. User should
fully reopen the old app and enter Chat, or check updates from Profile, to trigger
the legacy checker. Physical-device popup still awaits user confirmation. [[mobile]]

## 2026-10-04 - Additional sources audit + HVC serving migration

Approved new precalc tables (FB 5G MS, FTTH install orders, outlet GA 5G/FWA, etc.)
via governance review, KB promoted with column descriptions for all tables. PII guard
for FTTH install orders; view pruning via `mth_dt`. HVC moved to serving views with
N/A rules (split/flow from 202609, MTD full-month revenue gate) in comprehensive,
map-explore, site perf, profile and kecamatan profile; backend returns `notes`,
mobile shows them. Gates: pytest 384, KB benchmark 32/32, smoke 3/3, flutter analyze
clean, flutter test 67. [[bigquery-tables]] [[knowledge-base-json]]
Review follow-up (same day): fixed PII bypass (`o.*`, bare alias / TO_JSON_STRING(o)),
constant-subquery propagation that broke FROM/JOIN/IN SQL, map-explore LLMTD mixed-HVC
check, LYTD HVC gate without reference, profile HVC table_hint to serving view. pytest 389.

## 2026-10-06 - Comprehensive Tertiary B Trad correction

Changed the Trade row to Tertiary B Trad in IDR, with IDR units on Inner/Outer.
Total now sums the two components instead of the source total, preserving NULL
when both are missing. Regression tests execute the report SQL with differing
raw totals, partial/missing/zero components, brand/period/territory filters, and
the dependent S/T ratio. pytest: 394 passed. Restarted telco-backend; public
agent.bizplan-java.com API health is healthy. Live East Java report (202610,
data as of 2026-10-04) verified all 15 brand-period totals and ratios; IOH MTD
is IDR 14,272,738,151.35135 = Inner 7,788,330,069.3693695 + Outer
6,484,408,081.981982. [[reports]]

## 2026-10-08 - Upstream schema drift + model-agnostic instruction rework

- Upstream reload 2026-10-07 renamed `rham_mkt_highlevel_*` SND columns (`primary_all` to
  `primary`, `secondary_nat` to `secondary`, other `_nat` dropped), cut `rham_snd_kpi_highlevel_*`
  to the `rham_ref_snd_metric` contract (`total_outlet` to `outlet_total`, `q_uro` to `quro`,
  `tertiary` gone, use `tertiary_b`), and dropped `rham_report_fb_ms_focus_gtm_high_potential`.
  Comprehensive report (Trade) and `profile_engine` SND SQL repointed.
- Governance: `review_2026_10_08_schema_drift.json` (re-approve mkt/snd highlevel, reject
  high_potential), `review_2026_10_08_new_objects.json` (candidates: congestion 4g/5g weekly,
  dse_tracker_dly, ref_snd_metric; bak/stage tables rejected). KB promoted, runtime graph rebuilt.
- `rham_hvc_highlevel_*_serving` stored view metadata lists old names, but the SELECT * EXCEPT
  output (dry-run) follows the base table; no recreate needed. The refresh tool dry-runs them.
- Instructions: `AGENTS.md` rewritten as the single shared guide (Opus 5.5, Fable 5.1, GPT 6.1
  Sol, Astra 6.1); `CLAUDE.md` imports it and keeps only Claude Code specifics. New ADR
  [[model-roster]] supersedes opus-cost-policy and workflow-operating-loop (kept as stubs).
  Gate counts no longer hardcoded. Gates: pytest 394, benchmark 32/32.

## 2026-10-08 - Unified SND and resolved HVC schema reconciliation

Corrected the previous metadata diagnosis: both HVC serving views are valid without
upstream recreation. Scoped zero-byte dry-run discovery replaces 18 stale column names
per view with the actual output schema. Applied dated HVC re-approval through the official
review tool, regenerated catalog/KB/runtime graph and 49 Graphify projection files.
Registered a newly discovered occupancy object as candidate only; no warehouse writes.

Updated SND metric guidance, period/source contracts, placeholder and NULL rules, and
the Profile SND question template. Territory selection now supplies an approved reference
for a secondary source that lacks native geography. Added four knowledge cases and nine
regression cases. Stable `primary_all`/`secondary_nat` report codes were retained.
Live GTM audit found residual `HIGH POTENTIAL`/`0`; these are recorded as legacy values,
not silently relabeled. [[knowledge-base-json]] owns the durable details.

Gates: 403 backend tests, 36/36 knowledge cases, zero missing declared columns for all
three requested physical schemas and both resolved views. Updated temporary API smoke
3/3 with live BigQuery; targeted Surabaya Profile SND/Channel Trade sections 2/2; production
Comprehensive HTTP 200 with populated IOH trade metrics. No whole-profile or broad
agent-quality benchmark claim. No frontend/mobile changes, commit, push, or loader edits.

Not fully deployed: production still caches the old KB because sandbox sudo is blocked.
Host benchmark visibility is also unavailable; user must check before the backend restart.
Production post-restart smoke remains pending. AST Graphify refresh passed; developer
semantic refresh timed out at the provider. The last-month outlet smoke still lacked a
literal partition bound (about 23.8 MB scanned), so full query-cost efficiency is not claimed.
- 2026-10-08 (later): second upstream load put all 54 SND metrics into `rham_mkt_highlevel_*`
  (`snd_ga_m1s`/`snd_ga_m2s` for SND survival) and dropped 14 zero placeholders (`q_uro`, `q_sso`,
  `qsc`, `vlr_postpaid`, `site_*_uro|quro|sso|qsso`, `site_20/40_qsc`). Review
  `review_2026_10_08_highlevel_snd_metrics.json` re-approved mkt highlevel + both HVC serving views;
  KB/catalog/runtime graph regenerated (0 missing columns vs live). Fixed
  `_refresh_distribution_guidance` stacking a stale kpi_summary fact (wrong prefix). Report codes
  `primary_all`/`secondary_nat` kept as stable codes. pytest 404, benchmark 36/36.

## 2026-10-08 (live verification after SND/highlevel load)
- Backend restarted 11:12; runtime graph kb_sha256 d8f76f98 matches canonical KB hash.
- Smoke 2,11,20 OK. Live SND questions (trade per brand Sep 2026, SSO/URO/QURO/QSSO MTD Oct, outlet+ONO/OSA per region) all ran on rham_snd_kpi_highlevel_*; first trade run returned 0 rows (LLM filtered circle LIKE '%B%' from "tertiary B Circle Java"), rerun OK.
- Live profile KOTA SURABAYA: Sales & Distribution KPI 13 rows, Channel Trade 6 rows. Found pre-existing bug: "Acquisition by Channel" template used ga_fwa, which never existed in rham_mkt_highlevel_*; replaced by ga_fwa_biometric (profile_engine.py). Needs backend restart.
- Mobile release 1.48.2+65 (2026-10-08): flutter analyze clean, flutter test all pass, signer 038aa1bf... verified, APK sha256 b88d1894..., app_release.json bumped; /api/app/version serves 65 and public /api/app/download returns the new hash. Previous APK kept at /tmp/Bizplan-Java-Agent-1.48.1+64.apk. Frontend lint + build green; telco-frontend restart handed to user.

## 2026-10-14 (mobile table density, release 1.48.3+66)
- ReportAllDataTable frozen layout inflated rows: measured height x1.15 (x2.4 at large text) + 12, cell padding 6, Prompt line box ~1.5 em, min row 42. Now: fixed line height 1.2 in both measurement and paint, padding 4, additive 3 dp (6 dp at large text) margin, min row/header 32. Tappable rows keep 48 dp target. Two-line Performance Outlook row 70 to 52 dp; 200 percent text 310 to 120 dp, no clipping.
- Scroll hint strip and ReportKeyValueRow padding tightened. Guard: mobile/test/report_table_density_test.dart.
- APK 1.48.3+66 sha256 f001ff83..., signer 038aa1bf... verified; /api/app/version serves 66, public download hash matches. Previous APK at /tmp/Bizplan-Java-Agent-1.48.2+65.apk.
