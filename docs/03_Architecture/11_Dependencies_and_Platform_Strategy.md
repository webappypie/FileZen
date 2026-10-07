# Dependencies and Platform Strategy

## Dependency rules

- Prefer mature, actively maintained libraries.
- Minimize duplicate libraries solving the same problem.
- Pin compatible versions through normal project dependency management.
- Review license compatibility.
- Avoid libraries that require unnecessary network access.
- Isolate provider-specific SDKs behind adapters.

## Platform strategy

Flutter is the primary application layer. Native Android is used for capabilities requiring direct platform integration.

## Required architectural review for every new dependency

Before adding a dependency, document:
- why it is needed;
- why existing code cannot solve it;
- maintenance status;
- size/performance impact;
- Android compatibility;
- privacy/network behavior;
- license;
- fallback if dependency fails.

## Approved Platform Baseline (Phase 00)

- **Platform Target:** Android-first / current scope Android-only (minSdk: 24 / Android 7.0, targetSdk: 35).
- **Framework:** Flutter 3.47+, Dart 3.13+.
- **State Management & DI:** `flutter_riverpod` (Riverpod provider architecture).
- **Database & Search:** SQLite + Drift (`drift`, `drift_flutter`) + FTS5 full-text search.
- **WAPCentral Integration:** Sourced from local `D:/Mobile-App/WAPCentral/sdks/` (`wap_core_sdk`, `wap_ads_sdk`, `wap_notifications_sdk`, `wap_promo_sdk`); foundation client abstraction established in Phase 01.
- **Firebase Scope:** Android-only (`google-services.json` required; iOS `GoogleService-Info.plist` omitted).
