#!/usr/bin/env bash
# Put agent-02 back on the commit saved by 01-server-deploy.sh, with the database and
# app_release.json from that run. Only for a failed deploy:
#
#   tr -d '\r' < 03-rollback.sh | ssh agent-02 'bash -s'
#
# Access requests and logins made after the deploy are lost with the database restore.
set -euo pipefail
APP=/home/ubuntu/telco-ai
cd "$APP"
read -r PREV PREV_BRANCH < "$HOME/telco-ai-prev-commit"
# The newest backup is from the last deploy attempt, taken before any restart.
DB=$(ls -t "$HOME"/backup/telco_ai-*.db | head -1)
REL=$(ls -t "$HOME"/backup/app_release-*.json | head -1)
echo "back to $PREV ($PREV_BRANCH), database $DB, release $REL"
git checkout "$PREV_BRANCH" 2>/dev/null || git checkout "$PREV"
sudo systemctl stop telco-backend
cp -a "$DB" backend/data/telco_ai.db
cp -a "$REL" backend/data/app_release.json
(cd frontend && npm run build > /tmp/next_build.log 2>&1) || { tail -20 /tmp/next_build.log; exit 1; }
sudo systemctl restart telco-backend telco-frontend
sleep 5
curl -fsS http://127.0.0.1:8000/api/app/version | head -c 200; echo
