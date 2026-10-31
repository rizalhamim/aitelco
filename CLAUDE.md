@AGENTS.md

# Claude Code specifics

`AGENTS.md` above is the shared guide for every model. This section only adds what is
specific to Claude Code (Opus 5.5 default, Fable 5.1 escalation).

## Model use

- Default: `opus` (Opus 5.5), effort high, pinned in `.claude/settings.json`.
- Escalate one task with `/model fable` (Fable 5.1) when it is architecture-level: a new
  pipeline stage, a cross-component contract change, or a quality miss that two Opus passes
  did not fix. Return to Opus afterwards. Roster and rationale: vault
  `40-decisions/model-roster.md`.
- Cross-model review is welcome: a diff written by one model can be reviewed by another
  (GPT 6.1 Sol via Codex, Astra 6.1) since all read `AGENTS.md`.

## Token budget

Orient with vault + graphify, never a directory sweep. One node or one query beats "look
around". Do not re-read files you just wrote. Quote only the decisive line of an error.
Never read whole: `session-ses_16ca.md` (5 MB), `FTTH_KNOWLEDGE_BASE.txt`, `GRAPH_REPORT.md`
(see vault `90-references/big-docs.md` for what each holds).

## Delegation

- Locate/search: `cavecrew-investigator`. Mechanical 1-2 file edit: `cavecrew-builder`.
  Diff review: `cavecrew-reviewer`. Do not spawn a general agent to look around.
- These subagents are pinned to the `haiku` alias. If it is mapped to an unavailable model
  (`model_not_found`), pass `model: "opus"` on the Agent call.
- Run independent tool calls in parallel in one turn.

## graphify

Knowledge graph at `graphify-out/`. For code questions run `graphify query "<question>"`
first; `graphify path "<A>" "<B>"` for relationships, `graphify explain "<concept>"` for one
concept, `graphify affected "<concept>"` for impact. Use `graphify-out/wiki/index.md` for broad
navigation if present; `GRAPH_REPORT.md` only for architecture review. After code changes:
`graphify update .` (AST only, no API cost). `/graphify` invokes the installed skill.

## Vault writes

Use the obsidian skills for notes, `.base`, `.canvas`, and `defuddle` for pulling a web page
into a note. `vault/.claude/skills/` are local symlinks, gitignored; never commit them.
