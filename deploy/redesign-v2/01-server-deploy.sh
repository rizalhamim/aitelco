#!/usr/bin/env bash
# Redesign v2 (Agent Java) step 1 of 2: code, dependencies, Parquet dump, map cache,
# gates, web build and restart on agent-02. Run from Git Bash on the PC:
#
#   tr -d '\r' < 01-server-deploy.sh | ssh agent-02 'bash -s'
#
# Optional: SKIP_GATES=1 (skip pytest and the KB benchmark), BRANCH=<name>.
# Rollback: 03-rollback.sh puts the previous commit and database back.
set -euo pipefail

APP=/home/ubuntu/telco-ai
BRANCH="${BRANCH:-claude/project-thread-mnz2kt}"
STAMP=$(date +%Y%m%d-%H%M)
cd "$APP"

say() { printf '\n== %s\n' "$*"; }

say "1. Pre-check"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Tracked files have local changes on the server. Stopping so nothing is overwritten:"
  git status --short --untracked-files=no
  exit 1
fi
if [ "$(git rev-parse --abbrev-ref HEAD)" = "redesign-v2" ] && [ -f "$HOME/telco-ai-prev-commit" ]; then
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
git checkout -B redesign-v2 FETCH_HEAD
git log --oneline -1

say "4. Backend dependencies (adds pyarrow for the Parquet dump)"
cd "$APP/backend"
venv/bin/pip install -q -r requirements.txt

say "5. Performance dump to Parquet (first run, then daily at 05.00 WIB from the backend)"
PYTHONPATH=. venv/bin/python -m app.perf_dump --check > /tmp/perf_dump_check.log 2>&1 || { tail -20 /tmp/perf_dump_check.log; exit 1; }
tail -5 /tmp/perf_dump_check.log
PYTHONPATH=. venv/bin/python -m app.perf_dump > /tmp/perf_dump.log 2>&1 || { tail -20 /tmp/perf_dump.log; exit 1; }
tail -5 /tmp/perf_dump.log

say "6. Map geometry cache for Peta Agent"
PYTHONPATH=. venv/bin/python -m app.map_agent --build-geo > /tmp/build_geo.log 2>&1 || { tail -20 /tmp/build_geo.log; exit 1; }
tail -3 /tmp/build_geo.log

if [ "${SKIP_GATES:-0}" != "1" ]; then
  say "7. Gates: pytest and KB benchmark"
  venv/bin/python -m pytest tests/ -q > /tmp/pytest.log 2>&1 || { tail -30 /tmp/pytest.log; echo "pytest failed, backend NOT restarted"; exit 1; }
  tail -1 /tmp/pytest.log
  venv/bin/python tools_agent_knowledge_benchmark.py > /tmp/kb_bench.log 2>&1 || { tail -30 /tmp/kb_bench.log; echo "KB benchmark failed, backend NOT restarted"; exit 1; }
  tail -3 /tmp/kb_bench.log
fi

say "8. Web build"
cd "$APP/frontend"
if ! git diff --quiet "$PREV" HEAD -- package-lock.json; then npm ci; fi
npm run build > /tmp/next_build.log 2>&1 || { tail -30 /tmp/next_build.log; echo "web build failed, nothing restarted"; exit 1; }
tail -3 /tmp/next_build.log

say "9. Restart (database columns and tables are added on start)"
sudo systemctl restart telco-backend telco-frontend
for i in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8000/api/app/version > /dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://127.0.0.1:8000/api/app/version | head -c 300; echo
curl -fsS -o /dev/null -w "web /login %{http_code}\n" http://127.0.0.1:3000/login
curl -fsS -o /dev/null -w "web /statistik %{http_code}\n" http://127.0.0.1:3000/statistik
curl -fsS -o /dev/null -w "web /unduh %{http_code}\n" http://127.0.0.1:3000/unduh

say "10. Chat smoke (3 hard questions, does not touch the stored baseline)"
cd "$APP/backend"
venv/bin/python data/training/run_hard_questions.py --only 2,11,20 --run-tag smoke > /tmp/smoke.log 2>&1 || { tail -30 /tmp/smoke.log; echo "SMOKE FAILED: check the chat before releasing the APK, or run 03-rollback.sh"; exit 1; }
tail -8 /tmp/smoke.log

say "Done. Web and backend run Redesign v2. Next: build the APK on the PC and run 02-server-release-apk.sh."
