#!/usr/bin/env bash
# Agent Java v3 step 1 of 2: code, dependencies, gates, web build, restart and checks of
# the six new features on agent-02. Normally run by run.sh; by hand from Git Bash:
#
#   tr -d '\r' < 01-server-deploy.sh | ssh agent-02 'bash -s'
#
# Optional: SKIP_GATES=1 (skip pytest and the KB benchmark), BRANCH=<name>,
# FORCE=1 (deploy even if the server runs commits this branch does not contain).
# Rollback: 03-rollback.sh puts the previous commit and database back.
set -euo pipefail

APP=/home/ubuntu/telco-ai
BRANCH="${BRANCH:-claude/project-thread-kjx27g}"
LOCAL=agent-java-v3
STAMP=$(date +%Y%m%d-%H%M)
cd "$APP"

say() { printf '\n== %s\n' "$*"; }

say "1. Pre-check"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Tracked files have local changes on the server. Stopping so nothing is overwritten:"
  git status --short --untracked-files=no
  exit 1
fi
if [ "$(git rev-parse --abbrev-ref HEAD)" = "$LOCAL" ] && [ -f "$HOME/telco-ai-prev-commit" ]; then
  # A re-run after a stopped deploy: keep the commit from before the first attempt for rollback.
  read -r PREV _ < "$HOME/telco-ai-prev-commit"
  echo "re-run, rollback point stays $(cat "$HOME/telco-ai-prev-commit")"
else
  PREV=$(git rev-parse HEAD)
  echo "$PREV $(git rev-parse --abbrev-ref HEAD)" > "$HOME/telco-ai-prev-commit"
  echo "current: $PREV (saved to ~/telco-ai-prev-commit)"
fi
df -h "$APP" | tail -1

say "2. Backup database"
mkdir -p "$HOME/backup"
cp -a backend/data/telco_ai.db "$HOME/backup/telco_ai-$STAMP.db"
cp -a backend/data/app_release.json "$HOME/backup/app_release-$STAMP.json"
ls -la "$HOME/backup/telco_ai-$STAMP.db"

say "3. Fetch $BRANCH from GitHub"
git fetch github "$BRANCH"
# Never drop code the server runs today (for example an unmerged fix deployed by hand).
if ! git merge-base --is-ancestor HEAD FETCH_HEAD; then
  echo "The server runs commits that $BRANCH does not contain:"
  git log --oneline FETCH_HEAD..HEAD | head -20
  if [ "${FORCE:-0}" != "1" ]; then
    echo "Stopping so they are not lost. Merge them into the branch first, or run again with FORCE=1."
    exit 1
  fi
  echo "FORCE=1: continuing."
fi
git checkout -B "$LOCAL" FETCH_HEAD
git log --oneline -1

say "4. Backend dependencies"
cd "$APP/backend"
venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt

say "5. Targets for Simulasi Target and Klasemen (data/targets.json)"
venv/bin/python - <<'PY'
import datetime, json, os
p = "data/targets.json"
m = datetime.date.today().strftime("%Y%m")
if not os.path.exists(p):
    print(f"WARNING: {p} is missing. Simulasi and Klasemen work, but show 'target belum diisi' until it is added.")
else:
    raw = open(p, encoding="utf-8").read()
    print(f"{p} found, {len(raw)} bytes; month {m} {'present' if m in raw else 'NOT present (fill it in for this month)'}")
PY
mkdir -p data/uploads/tasks

if [ "${SKIP_GATES:-0}" != "1" ]; then
  say "6. Gates: pytest and KB benchmark"
  # Only new failures block: a test that also fails on the commit running now is reported, not blocking.
  ids() { grep -E '^(FAILED|ERROR) ' "$1" | sed -E 's/^(FAILED|ERROR) //; s/ - .*//' | sort -u; }
  if venv/bin/python -m pytest tests/ -q -rfE --continue-on-collection-errors > /tmp/pytest.log 2>&1; then
    tail -1 /tmp/pytest.log
  else
    tail -1 /tmp/pytest.log
    echo "some tests fail; comparing with the previous commit $PREV"
    WT=/tmp/telco-prev-tests
    git -C "$APP" worktree remove --force "$WT" 2>/dev/null || true
    git -C "$APP" worktree add --detach "$WT" "$PREV" > /dev/null
    ln -s "$APP/backend/data" "$WT/backend/data" 2>/dev/null || true
    (cd "$WT/backend" && "$APP/backend/venv/bin/python" -m pytest tests/ -q -rfE --continue-on-collection-errors > /tmp/pytest_prev.log 2>&1 || true)
    git -C "$APP" worktree remove --force "$WT"
    NEWFAIL=$(comm -23 <(ids /tmp/pytest.log) <(ids /tmp/pytest_prev.log))
    if [ -n "$NEWFAIL" ]; then
      echo "New failures (not failing before):"; echo "$NEWFAIL"
      grep -E -A25 '^_{5,} ' /tmp/pytest.log | head -80
      echo "pytest failed, backend NOT restarted"; exit 1
    fi
    echo "no new failures; already failing before this deploy:"; ids /tmp/pytest.log
  fi
  venv/bin/python tools_agent_knowledge_benchmark.py > /tmp/kb_bench.log 2>&1 || { tail -30 /tmp/kb_bench.log; echo "KB benchmark failed, backend NOT restarted"; exit 1; }
  tail -3 /tmp/kb_bench.log
fi

say "7. Web build"
cd "$APP/frontend"
if ! git diff --quiet "$PREV" HEAD -- package-lock.json; then npm ci; fi
npm run build > /tmp/next_build.log 2>&1 || { tail -30 /tmp/next_build.log; echo "web build failed, nothing restarted"; exit 1; }
tail -3 /tmp/next_build.log

say "8. Restart (the new v3 tables are created on start)"
sudo systemctl restart telco-backend telco-frontend
for i in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8000/api/app/version > /dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://127.0.0.1:8000/api/app/version | head -c 300; echo

say "9. The six features answer (401 = route exists and asks for login)"
bad=0
for p in /api/brief /api/diagnosa /api/klasemen /api/simulasi /api/ruang/boards /api/tindak/tasks /api/tindak/count /api/notify/pending; do
  c=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8000$p")
  echo "api $p $c"
  case "$c" in 401|403|200) ;; *) bad=1 ;; esac
done
for p in /login /brief /diagnosa /klasemen /ruang /tindak /simulasi /unduh; do
  c=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:3000$p")
  echo "web $p $c"
  case "$c" in 200|307|308) ;; *) bad=1 ;; esac
done
[ "$bad" = 0 ] || { echo "A v3 route does not answer. Check the log, or run 03-rollback.sh"; exit 1; }

say "10. Chat smoke (3 hard questions, does not touch the stored baseline)"
cd "$APP/backend"
venv/bin/python data/training/run_hard_questions.py --only 2,11,20 --run-tag smoke > /tmp/smoke.log 2>&1 || { tail -30 /tmp/smoke.log; echo "SMOKE FAILED: check the chat before releasing the APK, or run 03-rollback.sh"; exit 1; }
tail -8 /tmp/smoke.log

say "Done. Web and backend run Agent Java v3. Next: build APK 1.51.0 on the PC and run 02-server-release-apk.sh."
