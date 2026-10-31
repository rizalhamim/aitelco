---
title: Deploy / restart / version bump
type: convention
updated: 2026-07-26
---

# Deploy / restart / version bump

Services are systemd, live in production, need `sudo` to restart. Restart the specific service
after editing its component.

## Backend

```bash
cd backend && source venv/bin/activate   # venv required for python/pip
# edit...
sudo systemctl restart telco-backend     # 127.0.0.1:8000
```

**Restart is mandatory after editing `knowledge_base.json`** — `load_kb()` is `@lru_cache`d and
won't reload otherwise ([[knowledge-base-json]]).

## Frontend

```bash
cd frontend && npm run build
sudo systemctl restart telco-frontend    # 127.0.0.1:3000
```

## Mobile

```bash
cd mobile && flutter build apk --release   # flutter at /home/ubuntu/flutter/bin
cp build/app/outputs/flutter-apk/app-release.apk /home/ubuntu/telco-ai/Bizplan-Java-Agent.apk
sudo systemctl restart telco-backend       # picks up the new app_release.json
```

Bump BOTH `mobile/pubspec.yaml` version AND `backend/data/app_release.json`
(`version_name` / `version_code` / `apk_sha256` / `size_bytes` / `notes`).
Current release: read `backend/data/app_release.json` (authoritative; 1.48.3+66 on 2026-10-14).

### Release signing

Credentials come from `mobile/android/key.properties` (gitignored, build host only);
a Gradle property or an environment variable of the same names also works.
`android/app/build.gradle` refuses any release build whose signer is not

```
038aa1bfa5d283f5ea3f65fc4aee1d1d35c754ab9b45e0d84c78cc810ade0458
```

That guard is deliberate. **Android refuses an update signed by a different key**, so a
new keystore would force a manual uninstall on every installed device and would silently
kill in-app auto-update. The current signer is `~/.android/debug.keystore`
(alias `androiddebugkey`), which is what every shipped build so far has used.

Verify the signer of any APK before serving it:

```bash
unzip -p Bizplan-Java-Agent.apk META-INF/CERT.RSA \
  | openssl pkcs7 -inform DER -print_certs \
  | openssl x509 -noout -fingerprint -sha256
```

### Auto-update flow

`chat_screen._init` calls `UpdateService.check()` on every app start. It compares its own
`buildNumber` against `GET /api/app/version` (`backend/app/app_update.py`, reading
`data/app_release.json`), and on a higher `version_code` prompts the user, downloads from
`GET /api/app/download`, and hands the file to the Android package installer. So a release
is live for existing users the moment the APK is copied and the backend is restarted.
Verify end to end with:

```bash
curl -s http://127.0.0.1:8000/api/app/version | python3 -m json.tool
curl -s -o /tmp/dl.apk http://127.0.0.1:8000/api/app/download && sha256sum /tmp/dl.apk
```

## Hosts

- Prod: `agent-02.bizplan-java.com` (nginx: `/api/` → 8000 with `proxy_buffering off`, `/` → 3000).
- Separate `system-monitor.service` serves `server-02.bizplan-java.com` on :8080.
- SSE needs `X-Accel-Buffering: no` ([[chat-pipeline]]).

## Testing

No Python linter/unit tests. `test_batch.py` / `rerun_failures.py` / `test_pipeline.py` are
integration scripts that POST real questions to a running `localhost:8000` — need server + BQ live.

## Related

- [[backend-modules]] · [[knowledge-base-json]] · [[mobile]] · [[frontend]]
