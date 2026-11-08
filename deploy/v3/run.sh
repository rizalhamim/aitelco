#!/usr/bin/env bash
# Agent Java v3 deploy (Diagnosa, Brief Pagi, Klasemen, Ruang Saya, Tindak Lanjut,
# Simulasi Target), one command from Git Bash on the PC:
#
#   ssh agent-02 'cd /home/ubuntu/telco-ai && git fetch -q github claude/project-thread-kjx27g && git show FETCH_HEAD:deploy/v3/run.sh' > ~/aj-deploy.sh && bash ~/aj-deploy.sh all
#
# Steps (argument):
#   deploy   server: code, gates, web build, restart, v3 endpoint checks, smoke
#   apk      PC: build APK 1.51.0 (70) in its own clone and copy it to the server
#   release  server: check the signer and publish the APK
#   all      deploy, apk, release in order, stopping at the first failure
#   rollback server: back to the state before deploy
set -euo pipefail

STEP="${1:-}"
HOST="${HOST:-agent-02}"
BRANCH="claude/project-thread-kjx27g"
REPO_URL="https://github.com/rizalhamim/aitelco.git"
BUILD_DIR="${BUILD_DIR:-/d/Project/Project.Bizplan-Java.com/aitelco-release}"
LOGDIR="$HOME/aj-deploy-logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/$(date +%Y%m%d-%H%M%S)-$STEP.txt"
exec > >(tee -a "$LOG") 2>&1
echo "Log: $LOG"

# Server scripts are read from the branch by the server's own git fetch, so the GitHub
# raw CDN (which can serve a copy minutes old) is never involved.
remote() {
  ssh "$HOST" "cd /home/ubuntu/telco-ai && git fetch -q github $BRANCH && git show FETCH_HEAD:deploy/v3/$1 | tr -d '\r' | bash -s"
}

# Release signing: the PC repo's android/key.properties if there is one, otherwise the
# debug keystore. Gradle refuses any key other than the published signer.
signing() {
  local kp app
  kp="$(find /d/Project "$HOME" -maxdepth 6 -path '*/mobile/android/key.properties' -not -path "$BUILD_DIR/*" 2>/dev/null | head -1 || true)"
  if [ -n "$kp" ]; then
    echo "signing from $kp"
    KP_DIR="$(dirname "$kp")"
    app="$KP_DIR/app"
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

newest() { printf '%s\n' "$@" | grep -v '^$' | sort -V | tail -1; }

bump_agp() {
  local st=android/settings.gradle wr=android/gradle/wrapper/gradle-wrapper.properties pc="" agp gr
  [ -n "${KP_DIR:-}" ] && pc="$KP_DIR"
  agp="$(newest 8.11.1 \
    "$(sed -n 's/.*com.android.application"* version "\([0-9.]*\)".*/\1/p' "$st")" \
    "$( [ -n "$pc" ] && sed -n 's/.*com.android.application"* version "\([0-9.]*\)".*/\1/p' "$pc/settings.gradle" 2>/dev/null)")"
  gr="$(newest 8.14 \
    "$( [ -n "$pc" ] && sed -n 's/.*gradle-\([0-9.]*\)-all.zip.*/\1/p' "$pc/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null)")"
  echo "Android Gradle Plugin -> $agp, Gradle -> $gr (hanya di folder build ini)"
  sed -i "s/\(com.android.application\"* version \"\)[0-9.]*\"/\1$agp\"/" "$st"
  sed -i "s/gradle-[0-9.]*-all.zip/gradle-$gr-all.zip/" "$wr"
  grep -n 'com.android.application' "$st"; grep distributionUrl "$wr"
}

do_deploy() { echo "== 1/3 Deploy server ($HOST)"; remote 01-server-deploy.sh; }

do_apk() {
  echo "== 2/3 Build APK di PC ($BUILD_DIR)"
  command -v flutter >/dev/null || { echo "flutter tidak ada di PATH. Berhenti."; exit 1; }
  if [ ! -d "$BUILD_DIR/.git" ]; then git clone "$REPO_URL" "$BUILD_DIR"; fi
  cd "$BUILD_DIR"
  git fetch origin "$BRANCH"
  git checkout -B agent-java-v3-release FETCH_HEAD
  git reset --hard FETCH_HEAD
  grep -q '^version: 1.51.0+70' mobile/pubspec.yaml || { echo "pubspec bukan 1.51.0+70, berhenti."; exit 1; }
  signing
  # The tracked gradle.properties pins the Linux server JDK; on the PC let Flutter pick its own JDK.
  if grep -q '^org.gradle.java.home=' mobile/android/gradle.properties; then
    jh="$(sed -n 's/^org.gradle.java.home=//p' mobile/android/gradle.properties | tr -d '\r')"
    [ -d "$jh" ] || sed -i '/^org.gradle.java.home=/d' mobile/android/gradle.properties
  fi
  cd mobile
  flutter pub get
  # Newer Flutter on the PC asks for a newer Android Gradle Plugin than the repo pins (8.7.3).
  # First build as the repo is; if Flutter rejects the AGP, use the PC repo's AGP and Gradle
  # when they are newer, at least AGP 8.11.1, and build again.
  if ! flutter build apk --release --android-skip-build-dependency-validation; then
    bump_agp
    flutter build apk --release --android-skip-build-dependency-validation
  fi
  scp build/app/outputs/flutter-apk/app-release.apk "$HOST:/home/ubuntu/telco-ai/Agent-Java-1.51.0.apk"
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
