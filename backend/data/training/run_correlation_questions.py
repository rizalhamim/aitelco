"""Correlation routing benchmark.

Scores the router against the per-line EXPECTED value in `hard_correlation_30.txt`:
CORRELATE means the two metrics live in two DIFFERENT domains, anything else means
both metrics live in ONE domain and single-domain routing is the correct answer.
For CORRELATE cases it also checks the planner produces a valid two-domain plan.

Run from `backend/` with the venv:
    venv/bin/python data/training/run_correlation_questions.py [--limit N]

No live server needed (it calls the router and planner in-process) but it does hit
the LLM endpoint, so it costs tokens and takes a few minutes.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from app import orchestrator as o, correlate_agent as ca  # noqa: E402

HERE = Path(__file__).resolve().parent
CORPUS = HERE / "hard_correlation_30.txt"
OUT_JSON = HERE / "correlation_results_latest.json"


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
    parser.add_argument("--limit", type=int, default=0, help="only run the first N cases")
    parser.add_argument("--out", type=Path, default=OUT_JSON)
    args = parser.parse_args()

    cases = load_cases(CORPUS)
    if args.limit:
        cases = cases[: args.limit]

    results = []
    route_ok = plan_ok_n = 0
    for i, (expected, question) in enumerate(cases, 1):
        got = (o.route(question) or {}).get("domain", "none")
        routed_correctly = got == expected
        plan_ok = None
        a = b = ""
        if got == "CORRELATE":
            try:
                plan = ca.plan_correlation(question)
                a = (plan.get("sub_a") or {}).get("domain", "") or plan.get("single_domain", "")
                b = (plan.get("sub_b") or {}).get("domain", "")
                plan_ok = ca.plan_is_valid(plan)
            except Exception as e:  # planner crash is a real failure, record it
                a = f"ERR:{str(e)[:60]}"
                plan_ok = False
        route_ok += routed_correctly
        if plan_ok:
            plan_ok_n += 1
        results.append({
            "n": i, "expected": expected, "got": got,
            "route_ok": routed_correctly, "plan_ok": plan_ok,
            "A": a, "B": b, "q": question,
        })
        flag = "OK " if routed_correctly else "BAD"
        plan_flag = "-" if plan_ok is None else ("OK" if plan_ok else "NO")
        print(f"{i:02d} [{flag}] exp={expected:16s} got={got:16s} plan={plan_flag} A={a} B={b}")
        sys.stdout.flush()

    args.out.write_text(json.dumps(results, ensure_ascii=False, indent=1))
    n_corr = sum(1 for r in results if r["expected"] == "CORRELATE")
    print(f"\nSUMMARY route_ok={route_ok}/{len(results)}  "
          f"plan_ok={plan_ok_n}/{n_corr} (of expected-CORRELATE cases)")
    for r in results:
        if not r["route_ok"] or r["plan_ok"] is False:
            print(f"  MISS {r['n']:02d} exp={r['expected']} got={r['got']} "
                  f"plan={r['plan_ok']} :: {r['q'][:70]}")
    return 0 if route_ok == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
