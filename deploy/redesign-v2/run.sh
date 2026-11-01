#!/usr/bin/env bash
# Redesign v2 (Agent Java) deploy, one command from Git Bash on the PC:
#
#   curl -fsSL https://raw.githubusercontent.com/rizalhamim/aitelco/claude/project-thread-mnz2kt/deploy/redesign-v2/run.sh -o ~/aj-deploy.sh && bash ~/aj-deploy.sh all
#
# Steps (argument):
#   deploy   server: code, Parquet dump, map cache, gates, web build, restart, smoke
#   apk      PC: build APK 1.50.0 (69) in its own clone and copy it to the server
#   release  server: check the signer and publish the APK
#   all      deploy, apk, release in order, stopping at the first failure
#   rollback server: back to the state before deploy
set -euo pipefail

STEP="${1:-}"
HOST="${HOST:-agent-02}"
BRANCH="claude/project-thread-mnz2kt"
REPO_URL="https://github.com/rizalhamim/aitelco.git"
RAW="https://raw.githubusercontent.com/rizalhamim/aitelco/$BRANCH/deploy/redesign-v2"
BUILD_DIR="${BUILD_DIR:-/d/Project/Project.Bizplan-Java.com/aitelco-release}"
LOGDIR="$HOME/aj-deploy-logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$(date +%Y%m%d-%H%M%S)-$STEP.txt"
exec > >(tee -a "$LOG") 2>&1
echo "Log: $LOG"

# Server scripts come straight from the branch, so nothing has to be copied by hand.
remote() {
  local tmp; tmp="$(mktemp)"
  curl -fsSL "$RAW/$1?$(date +%s)" -o "$tmp"
  tr -d '\r' < "$tmp" | ssh "$HOST" 'bash -s'
  rm -f "$tmp"
}

# Release signing: the PC repo's android/key.properties if there is one, otherwise the
# debug keystore. Gradle refuses any key other than the published signer.
signing() {
  local kp app
  kp="$(find /d/Project "$HOME" -maxdepth 6 -path '*/mobile/android/key.properties' -not -path "$BUILD_DIR/*" 2>/dev/null | head -1 || true)"
  if [ -n "$kp" ]; then
    echo "signing from $kp"
    app="$(dirname "$kp")/app"
    while IFS='=' read -r k v; do
      k="$(echo "$k" | tr -d '\r ')"; v="$(echo "$v" | tr -d '\r')"
      case "$k" in
        TELCO_RELEASE_STORE_FILE)
          case "$v" in /*|?:*) ;; *) v="$app/$v" ;; esac
          export TELCO_RELEASE_STORE_FILE="$(cygpath -w "$v" 2>/dev/null || echo "$v")" ;;
        TELCO_RELEASE_*) export "$k=$v" ;;
      esac
    done < "$kp"
  else
    local ks="$HOME/.android/debug.keystore"
    [ -f "$ks" ] || { echo "Tidak ada key.properties maupun ~/.android/debug.keystore. Berhenti."; exit 1; }
    echo "signing from $ks"
    export TELCO_RELEASE_STORE_FILE="$(cygpath -w "$ks" 2>/dev/null || echo "$ks")"
    export TELCO_RELEASE_STORE_PASSWORD=android TELCO_RELEASE_KEY_ALIAS=androiddebugkey TELCO_RELEASE_KEY_PASSWORD=android
  fi
}

do_deploy() { echo "== 1/3 Deploy server ($HOST)"; remote 01-server-deploy.sh; }

do_apk() {
  echo "== 2/3 Build APK di PC ($BUILD_DIR)"
  command -v flutter >/dev/null || { echo "flutter tidak ada di PATH. Berhenti."; exit 1; }
  if [ ! -d "$BUILD_DIR/.git" ]; then git clone "$REPO_URL" "$BUILD_DIR"; fi
  cd "$BUILD_DIR"
  git fetch origin "$BRANCH"
  git checkout -B redesign-v2-release FETCH_HEAD
  git reset --hard FETCH_HEAD
  grep -q '^version: 1.50.0+69' mobile/pubspec.yaml || { echo "pubspec bukan 1.50.0+69, berhenti."; exit 1; }
  signing
  cd mobile
  flutter pub get
  flutter build apk --release
  scp build/app/outputs/flutter-apk/app-release.apk "$HOST:/home/ubuntu/telco-ai/Agent-Java-1.50.0.apk"
}

do_release() { echo "== 3/3 Terbitkan APK"; remote 02-server-release-apk.sh; }

do_rollback() {
  read -rp "Yakin kembalikan server ke kondisi sebelum deploy? Ketik YA: " ok < /dev/tty
  [ "$ok" = "YA" ] || { echo "Dibatalkan."; exit 1; }
  remote 03-rollback.sh
}

case "$STEP" in
  deploy) do_deploy ;;
  apk) do_apk ;;
  release) do_release ;;
  all) do_deploy; do_apk; do_release ;;
  rollback) do_rollback ;;
  *) echo "Pakai: bash ~/aj-deploy.sh deploy|apk|release|all|rollback"; exit 2 ;;
esac
echo
echo "SELESAI: $STEP berhasil. Log: $LOG"
