---
title: ADR - agent quality gates and the empty-result contract
type: decision
updated: 2026-08-21
---

# ADR: agent quality gates

Executed 2026-08-21 from `docs/agent-improvement-plan.md`. Records the durable rules,
not the code (use `graphify query` for that).

## An empty or all-NULL result is a FAILURE, not an answer

Rows returned does not mean the question was answered. `result_profiler` classifies a
result as **degenerate** when every metric column is NULL, or when the ORDER BY column
is NULL across the leading rows (BigQuery sorts NULLs first on ASC, so a "worst N"
query happily returns N rows of nothing). Empty and degenerate results each buy ONE
deterministic refine round with a targeted hint before any critique model call. If it
is still empty, the synthesizer must state what was checked and why it is likely empty.
Never a fabricated number, never a top-N built on NULLs.

The benchmark runner enforces the same contract: `rows=0` scores FAIL. The old runner
scored it OK, which is how the FTTH funnel bug stayed invisible.

## Only an OUTER ORDER BY proves a ranking

`ranking_verified` gates the synthesizer's permission to make top-N claims. An ORDER BY
inside a CTE, a subquery, a window function, a comment, or a string literal proves
nothing about the returned order. It now requires an ORDER BY at paren depth zero.

## Truncated SQL needs a SMALLER query AND more room

A generation cut off mid-CTE is structurally invalid. `check_sql_balance` catches it
locally (paren, quote, and comment aware) before paying a BigQuery round trip, and the
retry hint asks for FEWER CTEs rather than an in-place syntax fix.

The simplify instruction alone is not enough: a retry that reuses the budget which just
overflowed tends to overflow again. A truncation retry also gets a larger budget
(`SQL_MAX_TOKENS_TRUNCATED`, default 12000 vs the normal 8000). Truncation is therefore
its own failure class everywhere, separate from a plain syntax error, because the two
call for different fixes.

## The policy gate must not fail a legitimate join

Two escape hatches, both bounded by governance:
- A table the gate rejected becomes a retrieval HINT on the retry. Retrieval still only
  honours hints for tables approved in that domain.
- Province, region, branch, and circle questions get the canonical territory reference
  offered explicitly, because most fact tables carry only kabkota/kecamatan. Offered
  only when the question needs a level the fact table lacks.

## CORRELATE requires two DIFFERENT domains

A plan with A == B is not a correlation. The planner retries once, then the pipeline
falls back to single-domain routing rather than running an invalid join. A contrast
pair ("X tinggi TAPI Y rendah") is a necessary but NOT sufficient signal: map each
metric to its owning domain first. `ROUTER_CONTRAST_HINT` supplies a deterministic
advisory naming the two strongest domains; it can never force CORRELATE.

## Reasoning tags never reach the user

Models on the proxy emit `<think>...</think>`. `llm.ReasoningFilter` strips it at BOTH
choke points: `chat_stream_complete` for every streaming agent, and `chat` for the
non-streaming callers (advisory answer, profile compiler) whose text is equally
user-facing. Two subtleties that
cost real leaks when they were missed: an opener can carry long attributes (so a
fixed-length "too long to be a tag" cutoff is wrong), and one filter instance must span
the whole generation because a block can straddle a token-cap continuation. The
continuation guard measures the RAW stream, not the filtered text, or an all-reasoning
segment ends the answer early.

## Measurement hygiene

The benchmark is only as trustworthy as the harness. FOUR "regressions" in the
2026-08-21 session were harness bugs, not agent bugs: a block-splitting SSE parser
dropped `result` events, fixed session ids let stored context divert turns to the
advisory path, a mid-run backend restart produced a wall of `no_route` failures, and a
110 s client timeout cut long-but-healthy turns into route-with-zero-tokens captures
that scored as `no_answer`.

A hard analytic turn legitimately takes 60 to 120 seconds. Budget at least 300 s per
question, and treat a capture with no terminal `done` event as `truncated_capture`,
never as an agent failure.

Rules: verify an unexplained failure against BigQuery or the transcript BEFORE calling
it an agent defect, never restart the backend during a live run, and never let a
partial run (`--only`/`--limit`) overwrite the stored baseline.

## After a KB edit, rebuild the graph artifact

`knowledge_base.json` edits invalidate `runtime_knowledge_graph.json` (SHA-keyed).
Without a rebuild the backend silently falls back to in-memory compilation and reports
a degraded health status. Order: `tools_kb_edit.py`, `tools_runtime_graph.py`,
`tools_graphify_kb.py`, restart. See [[knowledge-base-json]].

## Partition pruning needs a LITERAL filter value

BigQuery cannot prune a partition on a value it has to compute. Writing the latest
period as `month_id = (SELECT MAX(month_id) ...)` or as a JOIN to a MAX() CTE scans
every partition. Measured on `rham_site_data_rev_product_mth` (2026-08-22): **45.0 GB
dynamic versus 1.6 GB literal** for the same aggregate. The dynamic form alone is
enough to trip the 50 GB cap. KB facts added to `product` and `revenue`.

## Unit tests cannot cover the streaming generator: smoke-run before benchmarking

`/api/chat/stream` is one long inline generator, so no unit test executes it. A one-line
scoping error (a variable initialised inside the scope-gate block, which the fast path
skips) broke 17 of 30 benchmark questions while all 165 unit tests stayed green.

Rule: after ANY edit to the chat pipeline, run a 3-question smoke test against the
restarted server (about 90 seconds) BEFORE starting a full benchmark run:

```bash
venv/bin/python data/training/run_hard_questions.py --only 2,11,20 --run-tag smoke
```

An hour-long benchmark is for measuring quality, not for discovering that the pipeline
does not run. When a variable is consumed by SQL generation, initialise it OUTSIDE every
conditional branch, because the fast path and map mode skip the scope gate.

## A domain rerouting to ITSELF is a retrieval miss, not out-of-scope

The scope gate sees a bounded table subset, not the whole domain. When it says "the
table I need is not in my retrieval", it names that table and suggests its OWN domain.
The old code discarded a suggestion equal to the current domain, bounced to another
domain, and ended with "di luar cakupan data" for a question the warehouse answers.

Now a self-reroute extracts the table named in the gate's own reason and feeds it back
as a retrieval hint (`orchestrator.tables_named_in`, filtered to approved tables of that
same domain, so the policy gate is never widened). Guarded by `tests/test_self_reroute.py`,
including the ordering requirement that the check runs BEFORE the domain is added to
`_tried_domains`.

## Where a fact belongs: KB facts describe data, prompt rules constrain SQL shape

A domain key fact reaches the model through `agent_persona` (verified), but reaching the
prompt is not the same as being obeyed. The occupancy/availability period fact was
present and correctly worded, and the model STILL built a `common_month` CTE that forced
both tables onto one shared month, which is empty by construction.

The rule that emerged: a fact ABOUT THE DATA ("this column is negative", "this table
stops at 202512") belongs in `knowledge_base.json`. A constraint on the SHAPE OF THE SQL
("never force two tables onto one shared period", "rank instead of inventing a
threshold") belongs in the SQL system prompt, where it applies to every domain and is
covered by `tests/test_sql_prompt_rules.py`. Putting a structural rule only in a KB fact
leaves it advisory.

## Rank, do not guess a threshold

The single most productive fix of the 2026-08-22 session. When a user says "tinggi",
"rendah", "bagus", or "jelek" without a number, the SQL writer used to invent an
absolute cut-off. On a tightly-distributed metric that silently matches nothing:
kabkota-level 4G availability spans **98.77 to 100.0** across all 120 kabkota, so
`WHERE avail_pct < 95` can never return a row, and the user reads the empty result as
"no such kabkota exists".

The rule, now in the SQL prompt and in the `network` KB facts: express vague
high/low as `ORDER BY ... LIMIT N`, or derive the cut-off from the data with
`APPROX_QUANTILES`. Never an invented constant. If a sign assumption returns nothing,
rank by `ABS()` rather than guessing again.

## A column existing in the schema does not mean it holds data

Schema presence and population are different facts, and the SQL writer only sees the
schema. On `rham_site_fwa_daily` at the latest `dt_id` (~112k rows, measured 2026-08-22):
`fwa_net_add_90_closing` has 72,140 values, while `fwa_net_add_90_formula` and
`fwa_net_churn90` have exactly one each, and `fwa_grosschurn90` has 480 nationwide with
NEGATIVE values (churn of -3 means 3 subscribers lost, so "high churn" is a large
ABSOLUTE value, never `> 0`). An agent ranking on the empty column with a `> 0` filter
produces a permanently empty result that looks like missing data.

When a metric returns nothing, profile the column before concluding the data is absent,
and record the population profile as a KB fact so the next generation picks the right
column. Sign convention belongs in that fact too. `backend/tools_column_population.py`
does the profiling in one command.

## Tables in one domain do not share a period

`rham_site_wise_occupancy` is frozen at month_id 202512 while
`rham_avail_stat_site_monthly` runs to the current month. Joining them on a shared
`MAX(month_id)` returns zero rows every time. When two tables have different coverage,
take each side at ITS OWN latest period and state both periods in the answer. An empty
result is sometimes the honest truth about the data, not a defect to engineer away, and
the answer must say what was checked.

## Measurement is the gate

Never claim an agent improvement without before and after numbers from
`data/training/run_hard_questions.py`, `run_correlation_questions.py`, and
`tools_agent_knowledge_benchmark.py`. Benchmark expectations get verified against the
KB schema before they are trusted: five correlation expectations were themselves wrong.

## Related

- [[workflow-operating-loop]] · [[knowledge-base-json]] · [[chat-pipeline]] · [[ftth]]
