# Bizplan Java agent: improvement plan and execution journey

Owner doc for making the chat agent (routing, SQL, knowledge, synthesis) more precise, fluid,
and natural. Written 2026-08-21. Executable by Claude opus (or codex) following the operating
protocol in `AGENTS.md`. Never use em-dashes in any change this plan produces.

## Ground rules for every phase

- Measure first, change second, measure again. Baseline and after-numbers go in the phase log
  at the bottom of this file.
- One lever per experiment. Router change and SQL prompt change never land in the same run.
- Knowledge fixes go in `backend/data/knowledge_base.json` only (then backend restart,
  `tools_graphify_kb.py`). Never patch an agent prompt with a table-specific fact.
- Gates that must stay green after every phase:
  `venv/bin/python -m pytest tests/ -q` (34 pass) and
  `venv/bin/python tools_agent_knowledge_benchmark.py` (13/13).
- Full measurement protocol: restart backend, then run
  `backend/data/training/run_hard_questions.py` (hard-30) and
  `run_correlation_questions.py` (correlation-30). Results overwrite `*_results_latest.json`;
  copy the previous file to `*_results_<date>.json` before rerunning so history is kept.

## Measured baseline (2026-08-21)

- hard-30: 28/30 OK.
  - #1 FAIL: BigQuery syntax error on a 3-family revenue MoM share question (multi-CTE
    generation still breaks despite the 8000-token budget fix in ecad072).
  - #20 FAIL: FTTH SO to SA to PA funnel per kabkota returns rows=null with NO error
    (silent empty result reaches the user as a non-answer).
- correlation-30: 26/30 routed, 25/30 plan_ok.
  - #13, #17: router sends the question to a single domain because both metrics live in the
    SAME domain (competitive; customer_hvc). Per the router prompt this is CORRECT behavior;
    the benchmark expectation is wrong. Fix the benchmark, not the router.
  - #18 (voice/SMS revenue down vs data revenue up), #30 (VLR high, usage low, relate to
    revenue): genuine misses, cross-domain but routed to one domain.
  - #26: routed CORRELATE but planner picked A == B == site_performance, invalid plan.
- Known infra risk: 9Router upstream still 400s on Haiku-routed models
  (`docs/9router-haiku-long-context-bug.md`); llm.py fallback masks it at latency cost.

## Phase 1: fix the measurement itself (cheap, do first)

Goal: benchmarks tell the truth so later phases are trustworthy.

1. Correct correlation-30 expectations for #13 and #17 (same-domain pairs are single-domain
   routes by design). Either change the expected outcome or replace with true cross-domain
   questions. Record the decision in the file header.
2. In the correlation planner (correlate_agent.py, locate with
   `graphify query "correlation plan domains A B"`), reject A == B plans and re-ask the
   planner once with an explicit "two DIFFERENT domains" reminder; on second failure fall
   back to single-domain routing instead of shipping an invalid plan. Covers #26.
3. Add the two hard-30 failures as named regression cases so they stay visible.
4. Expand hard-30 with 10 new questions drawn from real user traffic:
   `backend/data/sessions.db` table `analytics` (question, domain, success, error_msg).
   Prefer questions that failed in production. Keep total runtime under ~15 min.

Exit: rerun both runners; expectation-corrected correlation score becomes the new baseline.

## Phase 2: SQL generation robustness (hard #1 class)

Goal: zero syntax-error failures on the corpus.

1. Reproduce #1 in isolation: capture the exact generated SQL from the run (the runner saves
   err; rerun with the same question and log the SQL SSE event). Diagnose whether the CTE is
   truncated (token limit again) or malformed (prompt issue).
2. If truncated: the retry loop should detect BigQuery syntax errors that look like
   truncation (unbalanced parens near end of statement) and retry with an instruction to
   produce a SIMPLER query (fewer CTEs, no redundant subselects), not just retry the same
   prompt. Locate with `graphify query "write_sql error retry loop"`.
3. If malformed: add the failing pattern (multi-family share-of-revenue MoM) as a worked
   example in the product domain SQL prompt inside knowledge_base.json.
4. Deterministic pre-flight: before dry-run, run a cheap balance check (parens, quotes,
   trailing keyword) and trigger the simplify-retry immediately instead of spending a
   BigQuery round trip.

Exit: hard-30 has no syntax-error failures; pytest and knowledge benchmark green.

## Phase 3: silent empty results (hard #20 class)

Goal: the user never receives a shrug; an empty result set always becomes either a corrected
query or an explicit, natural explanation of what was checked and found empty.

1. Trace #20: FTTH funnel per kabkota in East Java returned no rows. Likely cause family:
   detail tables have shp_kabkota NULL (see vault [[ftth]]), so a kabkota GROUP BY on the
   wrong column yields nothing. Verify against the actual generated SQL.
2. In the result profiler / critique path (`graphify query "result_profiler empty rows"`):
   when rows == 0 or all-NULL group keys, feed a targeted hint into one refine iteration
   ("result was empty; check territory column choice and filter values against the schema
   facts") before synthesis.
3. If still empty after refine, synthesize an honest answer: state the tables and filters
   checked and the most likely reason (e.g. FTTH territory vocabulary differs), in the
   user's language. Never fabricate.
4. Add a KB key fact to the ftth domain if the root cause is the kabkota column choice, so
   the first generation is already correct.

Exit: #20 passes or produces an explicit honest-empty answer; no regression on ftth cases in
the knowledge benchmark.

## Phase 4: routing precision for implicit correlation (#18, #30 class)

Goal: cross-domain relational questions reach CORRELATE without explicit "korelasikan".

1. The misses share a shape: "X tinggi tapi Y rendah" / "penurunan X vs kenaikan Y" where X
   and Y live in different domains. Add this contrast-pair shape to the router prompt as a
   CORRELATE cue with 2-3 examples, keeping the same-domain exclusion rule intact.
2. Cheap deterministic assist: if the question contains a contrast marker (tapi, namun,
   sementara, padahal, vs) and knowledge retrieval finds strong table hits in TWO different
   domains, pass a router hint listing both domains. Locate with
   `graphify query "router domain_overview_text selection_for_question"`.
3. Re-verify the fixed benchmark: #13/#17 must STILL route to their single domain (the
   exclusion rule must not weaken).

Exit: correlation-30 routed >= 29/30 with plan_ok matching, hard-30 unchanged.

## Phase 5: knowledge freshness loop (make learning continuous)

Goal: the agent gets better from real usage on a weekly rhythm, safely.

1. Weekly review script (new, `backend/tools_weekly_review.py`): pull last 7 days from
   sessions.db analytics; bucket failures by (domain, error class: syntax, empty, timeout,
   reroute-loop, clarify); emit a compact markdown report to `backend/data/training/weekly/`.
   Report-only, no auto-changes, mirrors the tools_knowledge_refresh.py philosophy.
2. Each weekly finding becomes either: a KB key-fact edit, a benchmark case, or a code fix
   ticket in this file's phase log. `learning_notes` stays write-only telemetry;
   `knowledge_route_edges` stays the only bounded runtime self-learning (see vault
   [[knowledge-base-json]]). Do not add any new prompt-feedback loop from raw chat logs.
3. Keep table governance the gate for new tables: candidate objects surface via
   `tools_knowledge_refresh.py --write-catalog --check`, promotion stays a reviewed decision.

Exit: first weekly report generated and at least one finding converted into a KB fact plus a
benchmark case.

## Phase 6: fluid and natural responses (synthesis quality)

Goal: answers read like a sharp analyst, not a table dump; consistent in id/en.

1. Build a 10-question synthesis review set (mix: single metric, ranking, MoM/YoY, empty
   result, clarify). Store transcripts under `backend/data/training/synth_review/`.
2. Review against a fixed rubric: leads with the direct answer; numbers formatted per locale
   with units; states period and scope; flags data caveats from the result profiler
   (truncation, partial month, provenance) in one natural sentence, not a disclaimer wall;
   no hallucinated rankings beyond returned rows.
3. Tune ONLY the synthesizer system prompt in orchestrator/main (locate with
   `graphify query "synthesizer system prompt"`), one rubric dimension at a time. Keep the
   50-row preview rule intact.
4. Verify SSE streaming stays intact after every prompt change (event order, token flow)
   with one live curl.

Exit: rubric pass on all 10; spot-check 5 hard-30 answers read naturally in Indonesian.

## Phase 7 (conditional): model routing hygiene

Only if 9Router upstream gets fixed or replaced. Restore per-role fast/SQL models in .env,
remeasure latency and cost per question, and remove the fallback latency penalty. Until then
do NOT spend time tuning per-role models; the fallback makes it moot. See
`docs/9router-haiku-long-context-bug.md` and vault [[llm-model-roles]].

## Phase log (append results here, newest first)

### 2026-08-21 to 2026-08-22: phases 1 to 6 executed

Numbers: pytest 34 to 145 pass. Knowledge benchmark 13/13 throughout. Correlation
routing 26/30 to 29/30 (expectations corrected AND the router improved; every
expected-CORRELATE case now also produces a valid two-domain plan). hard-30 went
through several runs before the harness itself was trustworthy; the final numbers are
in the "Final hard-30 run" section below.

Phase 1, measurement:
- Corrected 5 wrong expectations in `hard_correlation_30.txt` (13, 17, 18, 26, 30),
  each verified against the KB schema first, with the reasoning recorded in the file
  header. #18 and #30 were previously listed as "genuine misses"; they were not.
  `rev_voice`/`rev_sms`/`rev_data` sit in one `kpi_summary` table and product splits
  DATA vs NON DATA via `kpi_group`, so single-domain routing was right both times.
- Both runners rewritten: no `/tmp` paths, corpus-driven expectations, results land in
  `data/training/`, and the hard runner now FAILS a silent empty result instead of
  scoring it OK (that is how #20 hid).
- `plan_is_valid` + one retry in `correlate_agent.plan_correlation`; the CORRELATE
  branch in `main.py` now plans FIRST and falls back to single-domain routing when the
  plan collapses to one domain, rather than shipping an invalid A == B join.
- Added `prod_regressions.txt`: 10 real production failures sampled from sessions.db.

Phase 2, SQL robustness:
- `bigquery_tool.check_sql_balance`: paren/quote/comment-aware pre-flight that catches
  truncated generations locally instead of paying a BigQuery round trip for an opaque
  parser error.
- `_error_hint` now routes truncation to a "write a SIMPLER query" instruction (fewer
  CTEs, conditional SUM over joins) BEFORE the generic in-place syntax fix.
- A table rejected by the policy gate now becomes a retrieval hint on the retry
  (`_policy_rejected_tables`), so one missing join table no longer burns all three
  attempts. Retrieval still filters hints against the domain's approved tables.

Phase 3, silent empty results:
- Root cause of #20 found by probing BigQuery, not by reasoning: FTTH `sales_region`
  is a SALES vocabulary. `'05. East Java'` contains Bali plus stray Aceh/Sumut rows,
  and the generated query grouped on `city` with an ASC ordering, so NULL conversions
  sorted to the top and filled the whole result. Added the corrective KB fact (use
  `province` when the user names a province) via a new `tools_kb_edit.py`.
- `result_profiler` now detects degenerate results (all-NULL metric columns, NULL
  ranking column) and `empty_result_hint` produces a targeted correction. `main.py`
  spends one deterministic refine round on it before any critique model call.
- Synthesizer prompt gained a DEGENERATE RESULTS block: never present a top-N built on
  NULLs, state what was checked, never call NULL "0".

Phase 4, implicit correlation routing:
- Router prompt gained the contrast-pair rule with 7 worked examples showing that a
  contrast pair is necessary but NOT sufficient (map each metric to its owner first).
- `contrast_domain_hint` is a deterministic advisory assist behind
  `ROUTER_CONTRAST_HINT`: when a contrast marker is present and two DIFFERENT domains
  both retrieve strongly, the router is told which two. It cannot force CORRELATE.

Phase 5, knowledge loop:
- `tools_weekly_review.py`: report-only weekly bucketing of real failures by class with
  a prescribed action per class. First report generated. No auto-feedback into prompts.
- `tools_column_population.py`: profiles how many rows actually carry a value for each
  numeric column, plus the value range. Written after the FWA diagnosis, because
  "column exists in the schema" and "column holds data" are different facts and only
  the first is visible to the SQL writer. Run it first whenever a metric returns empty.
- `tools_runtime_graph.py`: rebuilds `runtime_knowledge_graph.json` after a KB edit.
  This was a real gap: the KB edit alone left the artifact stale and health degraded.

Phase 6, synthesis quality:
- Found and fixed a live defect while reviewing answers: models on the proxy emit
  `<think>...</think>` and it was streaming verbatim into the top of user answers.
  `llm.ReasoningFilter` handles it at BOTH choke points: `chat_stream_complete` for the
  streaming agents and `chat` for the non-streaming callers (advisory answer, profile
  compiler), whose text reaches the user just as directly.
- Added `synth_review_10.txt` (10 shapes) for rubric review.

Found while running the live corpus (each verified against BigQuery or the KB, not
assumed):
- **Territory reference was unreachable from most domains.** Fact tables carry
  kabkota/kecamatan but no province column, so "kecamatan di Jawa Timur" needs a join to
  `zz_territory_kecamatan`, which lives in `territory_reference` and was therefore
  rejected by the policy gate. `write_sql` now offers the reference (schema plus allowed
  tables) when the question names a level the fact table lacks. Verified live: the case
  now returns a correct top-10 by non-data share.
- **`revenue` had no scan-cap rule** while `product` did, so multi-week daily revenue
  questions blew the 50 GB cap (hard-30 case 5 and several production failures). Added
  the equivalent key fact: aggregate weekly and monthly trends from `_mth`/`_mtd`, use
  `_daily` only for a short pinned window.
- **The runner leaked state between runs.** Session ids were fixed strings, so a rerun
  hit the advisory path (answering from stored context, no query, no route event) and
  scored a false failure. Session ids are now run-tagged, and a missing route event is
  classified explicitly instead of looking like a pipeline error.
- **The runner's SSE parser was dropping events.** It split the stream on the blank-line
  separator, so any event whose JSON payload contained a blank line was lost. That is
  what produced the `rows=0` and `no_result_event` failures for cases 6 and 9: both were
  real successes (case 9 verified independently, 20 rows, and the site table has 1,280
  Surabaya rows in the latest month). Replaced with a stateful line-oriented parser and
  covered by tests. Lesson: an unexplained benchmark failure gets verified against the
  database or the transcript BEFORE it is treated as an agent defect. Three of the
  apparent regressions in this session were measurement bugs, not model bugs.
- Failure classes are now distinguished in the runner output (`scan_cap`, `sql_syntax`,
  `empty_result`, `no_route`, `clarify`, `timeout`) so a rerun shows what kind of
  problem moved, not just the count.
- **Never restart the backend during a live run.** Doing so kills every remaining
  request and produces a wall of `no_route` failures that reads exactly like an agent
  regression. Noted in the runner docstring.
- **The client timeout was far too tight.** The runner used a 110 s curl timeout, but a
  hard analytic turn legitimately takes 60 to 120 s (router, analyst, scope gate, SQL
  write with retries, BigQuery, refine, synthesis). Timed-out turns returned a truncated
  capture with a route but zero tokens, which scored as `no_answer` and made a run look
  like 8/30. Measured directly: case 14 takes 75 s standalone and passes. Timeout raised
  to 300 s, and a capture with no terminal `done` event is now classified
  `truncated_capture` so a harness cut can never again be read as an agent failure.
  Spot-checked cases 2, 14 and 20 after the fix: all three OK.

hard-30 progression on a trustworthy harness: **25/30, then 27/30** after the first
round of data-fact fixes. Every failure in both runs was diagnosed against BigQuery
before being called an agent defect. The 28/30 baseline is NOT comparable: the old
runner scored `rows=0` as a pass and had no notion of a truncated capture.

Second round of findings (from the 27/30 run), both KB gaps rather than code bugs:
- **#16 outlet QSSO: the metric does not exist at that grain.** `quro` and `qsso` live
  only in `rham_snd_kecwise_mtd/_mth` and `rham_snd_kpi_highlevel_*` (871,596 rows, 100
  percent populated, kecamatan/branch grain). `rham_outlet_wise_mtd` (grain=outlet) has
  neither. The agent silently substituted `sellin_sp_hits_mtd` as a QSSO proxy and
  `rebuy_hit` as a URO proxy, answering a different question under the user's label.
  The new `sales_distribution` fact says: answer at kecamatan grain and say so, or state
  the metric is unavailable per outlet, and never present a proxy under the original
  label without naming it as a proxy.
- **#11 network: two separate causes, the second one general.** First, the period fact
  was true but not actionable: it said what NOT to do without giving a working join.
  Rewrote it with the verified recipe (one CTE per table, each filtered to its own
  `MAX(month_id)`, joined on `UPPER(TRIM(...))` because the tables spell the column
  differently: `kabkota` vs `kabkot`).
  Second, and more important, the agent then generated `WHERE avg_avail_pct_4g < 95`.
  Measured: kabkota-level 4G availability spans **98.77 to 100.0** across all 120
  kabkota, zero below 95 and only one below 99. The threshold could never match. This
  is a general defect, not an FTTH-style data quirk, so the fix went into the SQL prompt
  as well as the KB: **when the user says "tinggi"/"rendah" without a number, RANK
  (`ORDER BY ... LIMIT N`) or derive the cut-off with `APPROX_QUANTILES`, never invent an
  absolute constant.** A guessed cut-off on a tight distribution returns zero rows and
  reads to the user as missing data. Confirmed by hand that the ranked shape returns
  rows (KOTA SURABAYA 2,587 congested sites at 99.85 percent availability).
- #19 was a `truncated_capture` on a CORRELATE-shaped question that had already produced
  194 rows, so the fan-out timeout applies to it too. The keyword list for the long
  timeout now includes contrast markers, because the router sends implicit contrast
  questions to CORRELATE without the word "korelasi" ever appearing. Verified: 97 rows.

Third round on #11, which taught the most durable lesson of the session. After the
threshold fix the agent stopped inventing `< 95` and correctly used `APPROX_QUANTILES`,
but it still returned nothing, because it built a `common_month` CTE and filtered BOTH
tables by that one shared month. Occupancy stops at 202512 and availability runs to
202607, so the shared month is empty by construction.

The KB fact forbidding exactly this was verified to be present in the prompt (it reaches
the model through `agent_persona`), and the model did not obey it. The conclusion is a
placement rule, now recorded in the ADR: a fact ABOUT THE DATA belongs in
`knowledge_base.json`, but a constraint on the SHAPE OF THE SQL belongs in the SQL system
prompt, where it binds every domain and is guarded by `tests/test_sql_prompt_rules.py`.
Both the ranking rule and the shared-period ban now live there. Verified after the fix:
#11 returns 20 rows.

All five failures from the 27/30 run are now individually verified passing (11, 16, 19
plus the earlier 2 and 6), so every known hard-30 defect has a diagnosed root cause and a
guarded fix.

Fourth round, a real pipeline bug: **a domain rerouting to ITSELF killed the turn.**
Case 6 (market share plus SOGA per kabkota) had `competitive` reroute to `competitive`,
because the kabkota market-share table was not in the four-table subset the scope gate
was shown, even though retrieval ranks it FIRST at a wider budget. The suggestion equalled
the current domain, so it was discarded, the turn bounced to `kpi_summary`, that domain
also rerouted, and the user was told the question was out of scope. The warehouse answers
it fine.

That fix then shipped with a scoping regression that broke 17 of 30 questions:
`scope_table_hints` was initialised INSIDE the scope-gate block, but the fast path and
map mode skip that block entirely and still reach SQL generation, so every fast-path
turn died with `cannot access local variable 'scope_table_hints'`. Unit tests passed
throughout, because `/api/chat/stream` is one long generator that cannot be exercised
without a live server, so the tests could only inspect the source text.

The process lesson, and it is on me: **165 green unit tests did not catch a
one-line scoping error on the hot path.** The operating loop already requires a live
spot-run after a pipeline change, and I ran the benchmark instead of a smoke test first,
so the regression only surfaced after a full hour-long run. A three-question smoke run
takes about 90 seconds and would have caught it immediately. Two guards added:
`test_scope_table_hints_is_initialised_outside_the_gate` and an AST check that every
name passed to `write_sql` is not branch-local.

Fifth round, on the 28/30 run (the first with a correct pipeline):

- **#19 aggregation of aggregations.** The generated SQL wrote
  `HAVING SUM(total_ga) > 0` where `total_ga` was ALREADY a `SUM()` from the CTE, which
  BigQuery rejects outright. Added a prompt rule: never wrap an already-aggregated CTE
  column in another aggregate; reference it directly, or add another CTE level.
  Verified: 97 rows.
- **#6 was the self-reroute guard being too narrow.** My first version keyed off
  `suggested_domain == domain`, but the live gate usually blames ANOTHER domain while
  still describing a retrieval miss ("... tersedia di rham_report_fb_ms_kabkota (domain
  competitive)"). The guard now keys off the TABLE NAMED IN THE REASON, and a new
  `domain_owning_named_table` sends the turn back to the table's real owner with it
  forced into retrieval, instead of ending with "di luar cakupan data". This is why the
  case was intermittent: whether it passed depended on which domain the gate happened to
  blame. Verified stable: 3 consecutive runs, 10 rows each.

A self-reroute is a retrieval miss, not a scope problem. The gate now detects it, extracts
the table named in its own reason (`orchestrator.tables_named_in`, restricted to approved
tables of that same domain so the policy gate cannot widen), and passes it into
`write_sql` as a retrieval hint instead of bouncing the user. The two cases 27 and 29 that
failed in the same run passed when rerun individually, so they were load artefacts of a
long sequential run rather than defects. Verified after the fix: case 6 returns 10 rows.

- **#2 ARPT: partition pruning, measured.** After the truncation fix the query ran but
  scanned 52.1 GB. Dry-run comparison on `rham_site_data_rev_product_mth`: the same
  aggregate scans **45.0 GB** when the month comes from a JOIN or scalar subquery versus
  **1.6 GB** with a literal `month_id`, a 28x difference. BigQuery cannot prune a
  partition on a value it has to compute, so "latest month" written dynamically reads all
  39 months. Added as a key fact to `product` and `revenue`.
- **#11 network: the two tables do not share a period.**
  `rham_site_wise_occupancy` is frozen at month_id **202512** while
  `rham_avail_stat_site_monthly` runs to **202607**, so joining both on a shared latest
  month can only return zero rows. Added a `network` key fact telling the agent to take
  each side at its own latest month and disclose that the periods differ. Verified after
  the fix: the case now returns rows.
- **#21 FWA: the agent was ranking on empty columns.** Profiled every 90d column at the
  latest `dt_id` (~112k rows): `fwa_net_add_90_closing` is populated on 72,140 rows,
  but `fwa_net_add_90_formula` and `fwa_net_churn90` carry exactly **one** row each, and
  `fwa_grosschurn90` is populated on only 480 rows nationwide with **negative** values
  (a churn of -3 means 3 subscribers lost, so "high churn" is a large ABSOLUTE value,
  not `> 0`). None of those 480 rows are in Surabaya. The agent had picked the empty
  columns and filtered `> 0` on a negative metric, so the query could never match. Added
  the measured population profile as a `fwa` key fact. Verified after the fix: 100 rows.
- **#6 fixed** by the truncation budget change (verified: 10 rows).
- **#30 was a harness limit, not an agent failure.** PROFILE fans out into several full
  sub-queries plus a compiled deck, which exceeds even the 300 s timeout. The runner now
  picks `FANOUT_TIMEOUT` (900 s) for PROFILE and CORRELATE shaped questions.

Truncation recovery, found and fixed during the final run:
- hard-30 case 2 (ARPT per channel_group) ended its SQL on `AND kpi_group = '`.
  `check_sql_balance` rejected it correctly and the SIMPLER-query hint fired, yet all
  three attempts still ran out of room, because every retry reused the same 8000-token
  budget that had just overflowed. `_is_truncation_error` now escalates the retry to
  `SQL_MAX_TOKENS_TRUNCATED` (12000, env-overridable) on top of the simplify
  instruction. Verified separately after the benchmark run finished.
- The runner scores this as its own `truncated_sql` class, distinct from a plain
  `sql_syntax` error, because the two need different fixes.

Second review pass (`cavecrew-reviewer`, over the changes made after the first review)
produced five findings, all fixed:
- The reasoning filter flushed the buffer when an opener exceeded 24 characters, so an
  attribute-carrying `<think ...>` leaked raw markup and its whole block. The filter is
  now a `ReasoningFilter` class with a proper "could this still become a tag" test.
- Filter state did not survive a token-cap continuation, so a reasoning block spanning
  the boundary resumed at depth zero and leaked. One filter instance now spans the
  whole generation.
- The continuation guard measured FILTERED text, so a segment that was entirely
  reasoning ended the answer early. It now measures the raw stream.
- The territory reference extended `allowed_tables` without the governance approval
  filter that the schema text goes through. Added `approved_territory_ref_tables`.
- The runner overwrote the baseline results file on a `--limit` run, and its default
  run tag was constant per corpus (so reruns still collided on session ids).

Review pass: `cavecrew-reviewer` over the backend diff produced two real findings, both
fixed. `ranking_verified` was matching an ORDER BY inside a CTE or comment, which let
the synthesizer assert a top-N that was not actually ordered; it now requires an OUTER
ORDER BY at paren depth zero. The policy-gate retry gap is the `_policy_rejected_tables`
fix above.

Not done, deliberately: Phase 7 (model routing hygiene) stays blocked on the upstream
9Router fix, and the Phase 6 rubric scoring of all 10 answers is a review activity for
the next session rather than a code change.

### 2026-08-21: plan created

- Baseline hard-30 28/30, correlation-30 26/30 routed 25/30 plan_ok, knowledge
  benchmark 13/13, pytest 34 pass.
