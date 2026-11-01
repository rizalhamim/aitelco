#!/usr/bin/env bash
# Redesign v2 step 2 of 2: publish APK 1.50.0 (69). First copy the APK from the PC:
#
#   scp build/app/outputs/flutter-apk/app-release.apk agent-02:/home/ubuntu/telco-ai/Agent-Java-1.50.0.apk
#   tr -d '\r' < 02-server-release-apk.sh | ssh agent-02 'bash -s'
#
# The old APK stays downloadable from the Unduh page (Riwayat versi).
set -euo pipefail

APP=/home/ubuntu/telco-ai
NEW=Agent-Java-1.50.0.apk
SIGNER=038aa1bfa5d283f5ea3f65fc4aee1d1d35c754ab9b45e0d84c78cc810ade0458
cd "$APP"

[ -f "$NEW" ] || { echo "$APP/$NEW not found. Copy the APK first (see the top of this script)."; exit 1; }

echo "== 1. Check the signing key (Android refuses updates signed by another key)"
FP=""
AS=$(ls -d "$HOME"/Android/Sdk/build-tools/*/apksigner "$HOME"/android-sdk/build-tools/*/apksigner 2>/dev/null | tail -1 || true)
if [ -n "$AS" ]; then
  FP=$("$AS" verify --print-certs "$NEW" | sed -n 's/.*SHA-256 digest: //p' | head -1)
else
  CERT=$(unzip -Z1 "$NEW" | grep -E '^META-INF/.*\.(RSA|DSA|EC)$' | head -1 || true)
  [ -n "$CERT" ] && FP=$(unzip -p "$NEW" "$CERT" | openssl pkcs7 -inform DER -print_certs | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
fi
echo "signer: ${FP:-unknown}"
if [ "$FP" != "$SIGNER" ]; then
  echo "Signer does not match $SIGNER. Not publishing."
  exit 1
fi

echo "== 2. Register the release in backend/data/app_release.json"
python3 - "$NEW" <<'PY'
import datetime, hashlib, json, os, shutil, sys
new = sys.argv[1]
path = "backend/data/app_release.json"
rel = json.load(open(path, encoding="utf-8"))
if rel.get("version_code") == 69:
    print("already 1.50.0 (69), only refreshing hash and size")
else:
    old = {k: rel[k] for k in ("version_name", "version_code", "notes", "released_at", "mandatory", "summary") if k in rel}
    cur = rel.get("apk_filename") or "Bizplan-Java-Agent.apk"
    if os.path.exists(cur):
        keep = f"Bizplan-Java-Agent-{rel['version_name']}.apk"
        shutil.copy2(cur, keep)
        old["apk_filename"] = keep
    old.setdefault("summary", "Sesi kedaluwarsa kembali ke login")
    rel["history"] = [old] + [h for h in rel.get("history", []) if h.get("version_name") != old.get("version_name")]
    rel.update({
        "version_name": "1.50.0",
        "version_code": 69,
        "released_at": datetime.date.today().isoformat(),
        "mandatory": False,
        "summary": "Redesign v2, nama baru Agent Java",
        "notes": "Tampilan baru Redesign v2 dan nama baru Agent Java. Peta Agent lewat chat dengan titik dan poligon SHP, halaman Performance kembali dengan data dump Parquet, Watchlist dan alert, Profil dari semua tab, Statistik untuk Admin.",
        "highlights": [
            {"icon": "map", "title": "Peta Agent", "text": "Tanya lewat chat, jawaban muncul di peta. Warnai dengan Performance, Site productivity, atau Profile wilayah."},
            {"icon": "pulse", "title": "Performance kembali", "text": "Drill-down Circle Java sampai site, data dari dump Parquet jadi lebih cepat."},
            {"icon": "bell", "title": "Watchlist dan alert push", "text": "Pantau KPI dengan kalimat biasa, notifikasi masuk saat lewat ambang."},
            {"icon": "user", "title": "Profil dari semua tab", "text": "Avatar di app bar membuka profil, tema, notifikasi, dan unduhan."},
        ],
    })
rel["apk_filename"] = new
rel["size_bytes"] = os.path.getsize(new)
rel["apk_sha256"] = hashlib.sha256(open(new, "rb").read()).hexdigest()
tmp = path + ".tmp"
json.dump(rel, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
os.replace(tmp, path)
print(rel["version_name"], rel["version_code"], rel["apk_sha256"][:16], rel["size_bytes"])
PY

echo "== 3. Restart backend and verify"
sudo systemctl restart telco-backend
for i in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8000/api/app/version > /dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://127.0.0.1:8000/api/app/version | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version_name"], d["version_code"], d["available"], d["sha256"])'
curl -fsS -o /tmp/dl.apk http://127.0.0.1:8000/api/app/download && sha256sum /tmp/dl.apk "$NEW"
curl -fsS http://127.0.0.1:8000/api/app/releases | python3 -c 'import json,sys; [print(r["version_name"], r.get("available"), r.get("download_url")) for r in json.load(sys.stdin)["releases"]]'
echo "Done. Phones on 1.49.x get the update offer the next time they open the app."
