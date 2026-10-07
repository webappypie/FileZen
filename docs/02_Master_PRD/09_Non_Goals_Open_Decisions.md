# Non-Goals and Open Decisions

## Confirmed non-goals

- Full office-suite editing in early phases.
- Mandatory account.
- Server-side storage.
- Mandatory cloud AI.
- Subscription paywall.
- Aggressive automatic deletion.
- Perfect AI-understanding claims.

## Decisions finalized in Phase 00

- **Minimum Android API and target device matrix:** Android minSdk 24 (Android 7.0), targetSdk 35. Android-only scope for V1.
- **Exact database technology and search engine:** SQLite + Drift + FTS5.
- **Exact local AI/OCR model stack:** On-device ML Kit / local processing first, deterministic fallback.
- **Exact state-management package:** Riverpod (`flutter_riverpod`).
- **Exact dependency-injection approach:** Riverpod-based provider architecture (no `get_it`, no Bloc).
- **WAPCentral SDK sourcing and integration boundary:** Local packages in `D:/Mobile-App/WAPCentral/sdks/` (`wap_core_sdk`, `wap_ads_sdk`, `wap_notifications_sdk`, `wap_promo_sdk`); foundation client abstraction established in Phase 01.
- **Firebase scope:** Android-only (`google-services.json` required; iOS `GoogleService-Info.plist` omitted).

## Downstream implementation parameters (addressed in relevant phases)

- Thumbnail/cache quotas (Phase 05).
- Background scheduling policy by Android version (Phase 03/07/08).
- Trash/recovery implementation (Phase 04/08).
- Supported RAW/codec/document formats by device class (Phase 05/06).
- Notification retention limit (Phase 10).
- Analytics event taxonomy (Phase 12).
- Exact ad-removal purchase product configuration (Phase 12).

These are not to be silently guessed by implementation agents.
