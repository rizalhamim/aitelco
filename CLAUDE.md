# Operating loop (any coding model: opus, codex, fable)

This project is maintained by different coding agents over time. Quality must come from the
PROCESS below, not from the model tier. Follow the loop for every non-trivial task:

1. **Orient** (cheap, bounded): `vault/INDEX.md` route table for why/what/which, then
   `graphify query "..."` for where/how in code. Never bulk-read source to orient.
2. **Plan** (2-3 lines): state target files, the change, and the verification you will run.
   No exploratory edits. If the plan touches more than ~3 files or changes agent/pipeline
   logic, write the plan first and keep it visible while executing.
3. **Execute**: smallest diff that does the job. Match surrounding style. No em-dashes.
4. **Verify** (mandatory, pick every gate that applies):
   - Backend logic touched: `cd backend && venv/bin/python -m pytest tests/ -q`
   - Knowledge/routing/KB touched: `cd backend && venv/bin/python tools_agent_knowledge_benchmark.py`
     (must stay 13/13; add a case when you add a domain/table)
   - Chat pipeline touched: restart the backend, then SMOKE-RUN before anything else:
     `venv/bin/python data/training/run_hard_questions.py --only 2,11,20 --run-tag smoke`
     (about 90 s). `/api/chat/stream` is one long generator that no unit test executes,
     so a scoping or import error there passes every unit test and only shows up live.
     Only after the smoke run is green is a full benchmark worth starting.
   - Frontend touched: `cd frontend && npm run lint && npm run build`
   - Mobile touched: `cd mobile && flutter analyze` (+ `flutter test` if tests exist for the area)
   - Any claim about live behavior: curl the running API. Never assert from memory.
5. **Self-review**: read `git diff` once before declaring done. For risky backend changes run
   `/code-review` or the `cavecrew-reviewer` subagent (Claude) or a second review pass (codex).
6. **Record**: durable decision or domain fact learned -> update the ONE relevant vault node +
   append `vault/99-log/session-log.md` (absolute date). Code changed -> `graphify update .`.
   Runtime KB changed -> `tools_graphify_kb.py` then restart backend (KB is lru_cached).

Definition of done: gates green + diff reviewed + vault/graph updated + services restarted if
their code changed. A task that skips a gate is NOT done; say so explicitly instead.

Escalation: if an architecture-level task exceeds the current model's quality, say so and
suggest re-running that one task with `/model fable`. Never silently degrade.

Delegation (Claude only): locate/search work -> `cavecrew-investigator`; mechanical 1-2 file
edits -> `cavecrew-builder`; diff review -> `cavecrew-reviewer`. Never spawn a general agent
to "look around". Codex: do the equivalent inline, still respecting the token budget below.

# Token budget — DO NOT load the whole codebase

Default to the smallest read that answers the question. NEVER read many source files, big docs,
or whole directories to orient yourself. The four workflows below exist so you almost never
touch raw source in bulk. Use them IN THIS ORDER before any broad `Read`/`Grep`/`Glob`:

1. **vault** (`vault/INDEX.md`) — why/what/which: domains, decisions, report rules, conventions.
   Read ONE small node (~1-2KB), not `AGENTS.md`/`FTTH_KNOWLEDGE_BASE.txt`/`session-ses_16ca.md`.
2. **graphify** (`graphify query "..."`) — where/how in code. Returns a scoped subgraph, far
   smaller than grep/GRAPH_REPORT.md. This is how you locate code, not by reading files.
3. **obsidian-skills** — when creating/editing vault notes, `.base`, `.canvas`, or pulling a web
   page into a note (use `defuddle`, not a raw full-page fetch). Keeps writes small and correct.
4. **caveman** — terse output mode; keep responses compressed (this session's default).

Hard rules:
- Orient with vault + graphify FIRST. Only open a raw file to edit/debug specific lines, or when
  a node/query explicitly points you there. A single targeted `Read` beats a directory sweep.
- Never read a big source doc whole when a vault node covers it. Never grep the tree when
  `graphify query` answers it. The graphify hook-guard enforces this on Read/Grep/Bash.
- Prefer one node or one query over "let me look around". Looking around is the expensive path.
- Do not re-read files you just wrote. Do not cat build artifacts. Quote only the decisive
  line of an error, never the whole log.

## vault (knowledge layer — read FIRST)

This project has a distilled knowledge vault at `vault/`. For any question about domains,
architecture, decisions (why something is done a certain way), report rules, or conventions,
read `vault/INDEX.md` FIRST and follow ONE wikilink to the relevant small node. This is
deliberate to save tokens: a node is ~1-2KB, versus reading `AGENTS.md` (14KB),
`FTTH_KNOWLEDGE_BASE.txt` (48KB), or `session-ses_16ca.md` (5.2MB) whole.

Rules:
- Read `vault/INDEX.md`, pick the node from its route table, read that node. Do NOT slurp the
  big source docs unless the node points you there (`vault/90-references/big-docs.md`).
- Vault answers why/what/which (decisions, domain rules, conventions). graphify answers
  where/how in code. Use them together.
- After a durable decision/change, update the relevant vault node and append `vault/99-log/session-log.md`.
- `vault/.claude/skills/` are local symlinks (obsidian-skills), gitignored — do not commit them.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

# Agent-quality work (bizplan-java chat agent)

Any task that touches routing, SQL generation, knowledge, or synthesis quality MUST follow
`docs/agent-improvement-plan.md` (phased plan + measurement protocol). Rules of thumb:
- Measure before and after: hard-30 + correlation-30 runners under `backend/data/training/`,
  plus `tools_agent_knowledge_benchmark.py`. Never claim improvement without numbers.
- Knowledge lives ONLY in `backend/data/knowledge_base.json` (see vault [[knowledge-base-json]]).
  Fix wrong answers by fixing KB facts/table selection, not by patching agent prompts per-case.
- One lever per experiment. Do not change router + SQL prompt + KB in a single pass.
