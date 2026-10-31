---
title: Mobile (Flutter app)
type: architecture
updated: 2026-10-04
---

# Mobile: Flutter Android app

`mobile/`: `bizplan_java_agent`. Talks to the same backend as web. `graphify query "mobile screen"`.

## Run

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:8000   # default = production host
flutter build apk
```

Flutter binary at `/home/ubuntu/flutter/bin`.

## Key facts

- Backend base URL is **compile-time** via `--dart-define=API_BASE=...` (`lib/src/config.dart`),
  defaulting to the production host. Override it for local dev.
- JWT auth + refresh against backend. Expired token → 401 → mobile refreshes ([[auth-optional-chat]]).
- Screens (`lib/src/screens/`): map query, site performance, reports, chat, profile, login.
- Theme in `lib/src/theme.dart` (`AppTheme`).

## Performance data UX architecture

- `reports_screen.dart` presents a summary-first cockpit, pinned report context, chapter navigation,
  complete expandable sections, and domain-specific Snapshot and FTTH visuals.
- `site_performance_screen.dart` follows a diagnostic journey from site discovery to overview,
  commercial drivers, network and availability, portfolio, then complete attributes.
- `widgets/report_ui.dart` owns reusable context bars, chapter controls, and lossless responsive
  tables. Tables switch to stacked rows at narrow widths or large text scales without row limits.
- `widgets/performance_visuals.dart` owns accessible KPI, distribution, stage, and single-unit trend
  primitives. Null stays `N/A`, observed zero stays `0`, and stage charts do not infer conversion.
- Async screen requests use generation guards. Site search also uses a 350 ms debounce. Reports
  fetch on selection and use territory/brand-specific cache keys, without unopened-report prefetch.
- Platform text scaling is passed through unchanged in `lib/main.dart`. Interactive controls target
  at least 48 logical pixels and expose TalkBack semantics.
- Existing backend routes, report period semantics, brand rules, FTTH scope vocabulary, and raw data
  detail remain authoritative. Visual summaries are companions to full tables, never replacements.

## Release / version bump

Bump `mobile/pubspec.yaml` version AND `backend/data/app_release.json`
(`version_name`/`version_code`/`notes`). Build APK → copy to `Bizplan-Java-Agent.apk`.
Full steps → [[deploy-restart]]. Current release noted there.

### Legacy updater diagnosis, 2026-10-04

Inspected APK 1.47.0+62 embeds `http://agent-02.bizplan-java.com:8000`, including
`/api/app/version`. A live curl cannot resolve that hostname. The active
`https://agent.bizplan-java.com/api/app/version` returns 1.48.0+63, available=true.
Changing the base URL in a new APK cannot repair a previously installed binary.
Legacy automatic updates need the old endpoint restored or a one-time manual
installation from the active host; no DNS/proxy changes were authorized here.

Before the fix below, `UpdateService.check()` returned null for HTTP/JSON/network failures as well as
an up-to-date build, so the automatic dialog was silently skipped and the manual
Profile check could incorrectly say the app was current. Automatic checks were
triggered by ChatScreen initialization, not by app-resume events.

### Updater fix and release 1.48.1+64, 2026-10-04

`widgets/app_update_checker.dart`, mounted from `main.dart`, now checks on startup
and app resume across all routes, including login. Successful checks repeat every
five minutes in the foreground; failed checks retry after 30 seconds. Backgrounding
cancels polling and prevents a newly fetched update from opening a dialog. Checks
and automatic/manual dialogs cannot overlap. Release notes are scrollable.

`UpdateService.check()` now distinguishes network, HTTP, malformed metadata, and
unavailable-download failures from an up-to-date build. The manual Profile action
displays check errors rather than saying the installed version is current. The
version endpoint sends `Cache-Control: no-store, max-age=0` and returns the absolute
HTTPS download URL configured in `backend/data/app_release.json`.

Published 1.48.1+64 at `https://agent.bizplan-java.com/api/app/download`. Public
version and health endpoints were curled after restarting the backend, and the
downloaded APK matched SHA-256
`845b641ab0fbc517d7a07a1dc1262fa7301f703e48e3b8686d320995a07cec52`.
Package name and existing signer are unchanged; the signer is the existing Android
Debug certificate, not a newly provisioned production keystore. The prior 1.48.0+63
APK is retained as `Bizplan-Java-Agent-1.48.0+63.apk` for rollback.

At publication, the user had authorized legacy endpoint restoration, but no
DNS-management connection or credentials were available. Both authoritative and
public DNS checks returned NXDOMAIN for `agent-02.bizplan-java.com`.
The requested DNS change was A record `agent-02`
to `43.129.52.9`, TTL 300. The old port-8000 version route responds with build 64
when explicitly resolved to that IP, which proves the server route works but does
not restore DNS. Already-installed APK 1.47.0+62 could not show automatic
updates until DNS was restored, or the user manually installed the new APK. Actual
notification and installation on a physical Android device remain to be validated.

Verification: 359 backend tests and 67 mobile tests passed; Flutter analysis is
clean. Lifecycle tests cover login startup, resume, foreground polling, retry,
background behavior, and duplicate-dialog prevention. Deterministic Graphify code
refresh succeeded; no runtime KB change was needed for this updater fix.

### Legacy DNS restored by user, 2026-10-04

After the user added the domain, authoritative DNS and public resolvers 1.1.1.1
and 8.8.8.8 resolve `agent-02.bizplan-java.com` to `43.129.52.9` (TTL 14400).
A normal curl, without `--resolve`, to the APK 1.47 endpoint
`http://agent-02.bizplan-java.com:8000/api/app/version` returns HTTP 200,
available=true, version 1.48.1+64, and the active HTTPS download URL. Its health
endpoint is healthy; the APK downloaded through the legacy host also matches
the published build-64 SHA-256 above. The DNS blocker is resolved. No additional
application or proxy change was needed. APK 1.47 still checks automatically only
when Chat initializes, so fully close/reopen it and enter Chat, or use Profile's
manual update check. Physical-device notification remains a user smoke test.

## Related

- [[system-overview]] · [[deploy-restart]] · [[reports]]
