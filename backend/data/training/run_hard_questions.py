"""Hard-question live benchmark against the running backend.

Posts each question in `hard_questions_30.txt` to /api/chat/stream and records the
routed domain, row count, SQL, error, and whether the answer streamed at all. A case
FAILS on an error, on a silent empty result (no rows and no narration), or on a
timeout.

Run from `backend/` with the backend already restarted and live:
    venv/bin/python data/training/run_hard_questions.py [--limit N] [--only 1,20]

Costs real LLM + BigQuery spend. Results are written next to the corpus so history is
kept in git; copy `hard_results_latest.json` to `hard_results_<date>.json` before a
rerun if you want to keep the previous numbers.

Do NOT restart the backend while a run is in flight. Every in-flight and subsequent
request dies with no route event, which reads as a wall of `no_route` failures and
looks exactly like an agent regression. Finish the run, then restart.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = HERE / "hard_questions_30.txt"
OUT_JSON = HERE / "hard_results_latest.json"
OUT_TXT = HERE / "hard_results_latest.txt"
ENDPOINT = "http://127.0.0.1:8000/api/chat/stream"


def parse_sse(stream: str):
    """Yield (event, parsed_data) pairs from an SSE stream.

    Line-oriented and stateful, per the SSE spec: an event is dispatched on a blank
    line, and consecutive `data:` lines are joined with a newline. A naive split on
    the blank-line separator loses events whose JSON payload itself contains a blank
    line, which silently dropped `result` events for long answers.
    """
    event = None
    data_lines: list[str] = []
    for raw in stream.split("\n"):
        line = raw.rstrip("\r")
        if line.startswith(":"):
            continue
        if line == "":
            if data_lines:
                payload = "\n".join(data_lines)
                try:
                    yield event, json.loads(payload)
                except Exception:
                    pass
            event, data_lines = None, []
            continue
        if line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
    if data_lines:
        try:
            yield event, json.loads("\n".join(data_lines))
        except Exception:
            pass


# A hard analytic turn legitimately runs 60-120 s (router, analyst, scope gate, SQL
# write plus retries, BigQuery, refine, synthesis). A tight client timeout cuts the
# stream mid-answer and the truncated capture then looks like the agent produced
# nothing, which reads as a fleet-wide regression. Keep this generous.
DEFAULT_TIMEOUT = 300
# PROFILE and CORRELATE fan out into several full sub-queries plus a compiled deck, so
# they legitimately take several times a single-domain turn.
FANOUT_TIMEOUT = 900
# Keyword hints only cover the questions that SAY "profile" or "korelasi". The router
# also sends implicit contrast questions to CORRELATE, and those fan out just as wide,
# so anything with a contrast marker gets the long budget too. A generous timeout costs
# nothing on a fast question (the run ends when the stream ends); a tight one turns a
# healthy slow turn into a fake failure.
_FANOUT_HINTS = ("profile", "profil", "deck", "dashboard", "semua kpi", "lengkap",
                 "korelasi", "korelasikan", "comprehensive", "silang", "silangkan",
                 "hubungan", " tapi ", " namun ", " padahal ", " justru ", " vs ",
                 "sekaligus", "efektif")


def timeout_for(question: str) -> int:
    lower = f" {(question or '').lower()} "
    return FANOUT_TIMEOUT if any(h in lower for h in _FANOUT_HINTS) else DEFAULT_TIMEOUT


def ask(msg: str, sid: str, timeout: int = DEFAULT_TIMEOUT) -> dict:
    body = json.dumps({"message": msg, "session_id": sid, "language": "id", "history": []})
    try:
        p = subprocess.run(
            ["curl", "-s", "-N", "-m", str(timeout), "-X", "POST", ENDPOINT,
             "-H", "Content-Type: application/json", "-d", body],
            capture_output=True, text=True, timeout=timeout + 15)
        out = p.stdout
    except Exception as e:
        return {"route": "TIMEOUT", "rows": None, "err": str(e)[:120], "ntok": 0,
                "sql": "", "clarify": "", "done": False}

    route = rows = err = None
    sql = ""
    clarify = ""
    ntok = 0
    done = False
    for ev, d in parse_sse(out):
        if ev == "done":
            done = True
        if ev == "route":
            route = d.get("domain")
        elif ev in ("result", "profile_domain_result"):
            rows = d.get("row_count")
            sql = d.get("sql") or sql
        elif ev == "sql":
            sql = d.get("sql") or sql
        elif ev == "error":
            err = str(d.get("error"))[:200]
        elif ev == "clarify":
            clarify = str(d.get("question") or "")[:200]
        elif ev == "token":
            ntok += 1
    return {"route": route, "rows": rows, "err": err, "ntok": ntok, "sql": sql,
            "clarify": clarify, "done": done}


def classify(r: dict, expected: str = "") -> tuple[str, str]:
    """Return (status, failure_class). A silent empty result is a FAIL, not an OK.

    `expected` is compared against the routed domain. The corpus has always
    carried an expected domain per line, but nothing ever checked it, so a
    question answered from the WRONG domain still scored OK as long as rows came
    back. That is the failure this benchmark exists to catch.
    """
    if r["route"] == "TIMEOUT":
        return "FAIL", "timeout"
    if r["route"] is None:
        # No route event at all means the turn never entered the data pipeline (the
        # advisory path answers from stored context instead of querying). For a data
        # benchmark that is a non-answer.
        return "FAIL", "no_route"
    if r["err"]:
        low = r["err"].lower()
        if ("structurally invalid" in low or "looks cut off" in low
                or "dangling keyword" in low):
            # The generation ran out of room. A distinct class from a plain syntax
            # error because the fix is a SIMPLER query, not a patched one.
            return "FAIL", "truncated_sql"
        if "syntax error" in low or "expected" in low:
            return "FAIL", "sql_syntax"
        if "exceeding the" in low or "would scan" in low:
            return "FAIL", "scan_cap"
        return "FAIL", "error"
    if r.get("clarify"):
        # The scope gate asked a clarifying question. That is a legitimate outcome for a
        # genuinely ambiguous question, but every corpus question here is specific, so it
        # is scored as a miss and kept visible under its own class.
        return "FAIL", "clarify"
    if not r.get("done"):
        # No terminal `done` event: the capture was cut off (client timeout or a
        # restarted server), so nothing about the agent can be concluded from it.
        return "FAIL", "truncated_capture"
    if r["ntok"] == 0:
        return "FAIL", "no_answer"
    if r["rows"] == 0:
        return "FAIL", "empty_result"
    if r["rows"] is None:
        return "FAIL", "no_result_event"
    # Route check runs LAST: an answer that is wrong for a different reason keeps
    # its more specific failure class, which is the one worth acting on.
    # `multi` means the question legitimately fans out (PROFILE/CORRELATE), so any
    # route is acceptable for it.
    if expected and expected not in {"multi", "any"} and r["route"] != expected:
        return "FAIL", "wrong_route"
    return "OK", ""


def load_cases(path: Path) -> list[tuple[str, str]]:
    cases = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "|" not in line:
            continue
        expected, question = line.split("|", 1)
        cases.append((expected.strip(), question.strip()))
    return cases


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--only", type=str, default="", help="comma-separated case numbers")
    parser.add_argument("--out", type=Path, default=None,
                        help="results json (defaults to <corpus stem>_results_latest.json)")
    parser.add_argument("--run-tag", type=str, default="",
                        help="suffix for session ids; set this per run so a previous "
                             "run's stored context cannot trigger the advisory path")
    parser.add_argument("--corpus", type=Path, default=CORPUS,
                        help="question corpus (default hard_questions_30.txt; "
                             "prod_regressions.txt holds real production failures)")
    args = parser.parse_args()
    # The tag must differ between runs: session ids are server-side keys, and reusing
    # one lets the previous run's stored context send the turn down the advisory path
    # (answered from memory, no query, no route event).
    tag = args.run_tag or time.strftime("%m%d%H%M%S")

    # Results are keyed to the corpus so running prod_regressions.txt never overwrites
    # the hard-30 baseline.
    if args.corpus.resolve() == CORPUS.resolve():
        out_json, out_txt = OUT_JSON, OUT_TXT
    else:
        out_json = HERE / f"{args.corpus.stem}_results_latest.json"
        out_txt = HERE / f"{args.corpus.stem}_results_latest.txt"
    if args.out:
        out_json = args.out

    cases = load_cases(args.corpus)
    wanted = {int(x) for x in args.only.split(",") if x.strip()} if args.only else set()
    results = []
    txt = open(out_txt, "w") if not wanted and not args.limit else None

    for i, (expected, question) in enumerate(cases, 1):
        if wanted and i not in wanted:
            continue
        if args.limit and len(results) >= args.limit:
            break
        r = ask(question, f"hq{tag}_{i}", timeout=timeout_for(question))
        status, fail_class = classify(r, expected)
        row = {"n": i, "exp": expected, "got": r["route"], "rows": r["rows"],
               "err": r["err"], "status": status, "fail_class": fail_class,
               "sql": r["sql"], "clarify": r.get("clarify", ""),
               "done": r.get("done", False), "q": question}
        results.append(row)
        line = (f"{i:02d} [{status:4s}] exp={expected:16s} got={r['route']} "
                f"rows={r['rows']} tok={r['ntok']} {fail_class} {(r['err'] or '')[:60]}")
        print(line)
        sys.stdout.flush()
        if txt:
            txt.write(line + "\n")
            txt.flush()

    # Only a full-corpus run may overwrite the stored baseline. A partial run
    # (--only or --limit) would silently replace it with an incomplete result.
    partial = bool(wanted or args.limit)
    if not partial:
        out_json.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    elif args.out:
        args.out.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    ok = sum(1 for r in results if r["status"] == "OK")
    summary = f"\nSUMMARY total={len(results)} OK={ok} FAIL={len(results) - ok}"
    print(summary)
    for r in results:
        if r["status"] != "OK":
            print(f"  FAIL {r['n']:02d} [{r['fail_class']}] {r['exp']} -> {r['got']} "
                  f":: {(r['err'] or r['q'])[:80]}")
    if txt:
        txt.write(summary + "\n")
        txt.close()
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
