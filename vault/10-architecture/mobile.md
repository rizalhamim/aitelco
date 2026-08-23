---
title: Mobile (Flutter app)
type: architecture
updated: 2026-08-18
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
- Async screen requests use generation guards. Site search also uses a 350 ms debounce, while report
  background prefetch is limited to two concurrent requests.
- Platform text scaling is passed through unchanged in `lib/main.dart`. Interactive controls target
  at least 48 logical pixels and expose TalkBack semantics.
- Existing backend routes, report period semantics, brand rules, FTTH scope vocabulary, and raw data
  detail remain authoritative. Visual summaries are companions to full tables, never replacements.

## Release / version bump

Bump `mobile/pubspec.yaml` version AND `backend/data/app_release.json`
(`version_name`/`version_code`/`notes`). Build APK → copy to `Bizplan-Java-Agent.apk`.
Full steps → [[deploy-restart]]. Current release noted there.

## Related

- [[system-overview]] · [[deploy-restart]] · [[reports]]
