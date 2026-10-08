# Phase 12 — Analytics, Crash Monitoring, and WAPCentral App Integration

## Objective
Implement privacy-safe analytics, structured crash monitoring, latency performance tracking, and the app-side WAPCentral SDK ecosystem integration strictly according to the `WAPCentral_App_Integration_Guide` and Master PRD specifications.

Key capabilities introduced:
1. **Privacy-Preserving Crash Reporting (`CrashReporter`)**:
   - Captures unhandled Flutter errors (`FlutterError.onError`) and unhandled platform zone errors (`PlatformDispatcher.instance.onError`).
   - Strict sanitization: scrubs local file system paths (`/storage/emulated/0/...`, `/data/user/0/...`, `[USER_PROFILE_DIR]`), user emails, bearer tokens, and `wap_key_*` credentials.
   - Circular buffer local persistence (`.filezen_crash_reports.json`, up to 50 entries) with graceful degradation (crash logging never crashes the host app).
   - Opt-in/opt-out user controls in Settings.
2. **Performance Telemetry (`PerformanceMonitor`)**:
   - In-memory latency tracker for key user workflows: app startup, universal FTS5 search, indexing batch runs, storage hygiene scans, vault encryption, and file operations.
   - Computes statistical summaries: sample count, minimum, maximum, average latency, and 95th percentile (p95) execution times.
3. **Privacy-Preserving Analytics (`AnalyticsService`)**:
   - Logs non-identifying user actions and screen views (`screen_view`).
   - Automatically masks or drops any parameter containing forbidden keys (`file_path`, `file_name`, `content`, `ocr`, `password`, `key`, `token`, `secret`).
   - Drop-on-disable behavior: when user opts out in Settings, all events are dropped immediately.
4. **WAPCentral SDK Stack Integration (`WapCentralManager`)**:
   - Integrates the 4 authoritative WAP SDKs from `WAPCentral/sdks`:
     - **`wap_core_sdk`**: Core connection runtime, request ID correlation, authentication headers (`X-App-Id: app_1791324566055`, `X-App-Key`), and retry logic.
     - **`wap_ads_sdk`**: Ad mediation across Google AdMob, Meta Audience Network, AppLovin MAX, and first-party WAPAds with decoupled promotion hook.
     - **`wap_notifications_sdk`**: FCM push registration and remote notification feed integration with FileZen's in-app Notifications Center.
     - **`wap_promo_sdk`**: Cache-first, non-blocking self-promotions with HMAC cryptographic verification and frequency capping.
   - Ad-Free Pro Support: One-time purchase state persists across app restarts (`.filezen_monetization.json`). When active, ads are completely silenced and never requested.
   - Graceful offline fallback: 100% local-first resilience if WAPCentral gateway is temporarily unreachable.
5. **Presentation & Diagnostics Dashboard (`DiagnosticsScreen` & `SettingsScreen`)**:
   - Dedicated "Diagnostics & Observability" dashboard under Settings with 4 tabs: Ecosystem, Performance, Crash Logs, and Telemetry.
   - Live WAPCentral gateway connection probe.
   - One-tap "Export Anonymous Diagnostics (JSON)" to clipboard.
   - "Ad-Free Pro" status indicator and simulated one-time purchase toggle in Settings.
   - Non-intrusive `FileZenAdBanner` at the bottom of the Home dashboard that cleanly collapses when offline or Ad-Free.

---

## Architecture & Clean Design Principles

```
Presentation Layer:
  - SettingsScreen (Telemetry opt-in switch, Ad-Free Pro tile, Diagnostics navigation)
  - DiagnosticsScreen (4 Tabs: Ecosystem, Performance Traces, Crash Reports, Telemetry)
  - FileZenAdBanner (WapAds banner with fallback to WapPromoBanner or zero height)
  - FileZenPromoCard (WapPromoBuilder native card for cross-promotions)
        ↓
Riverpod Providers:
  - monitoring_providers.dart:
    * crashReporterProvider
    * performanceMonitorProvider
    * analyticsServiceProvider
    * wapCentralManagerProvider
    * monetizationStateProvider (StateNotifierProvider)
    * telemetryOptInProvider
    * crashReportsFutureProvider
    * performanceSummariesProvider
    * recentAnalyticsEventsProvider
        ↓
Domain Interfaces & Models:
  - ICrashReporter, IPerformanceMonitor, IAnalyticsService, IWapCentralManager
  - CrashReport, PerformanceTrace, PerformanceSummary, AnalyticsEvent, MonetizationState
        ↓
Data Implementation:
  - CrashReporter (Sanitization regexes, circular JSON buffer)
  - PerformanceMonitor (Stopwatch registry, latency percentiles)
  - AnalyticsService (PII filter, drop-on-disable)
  - WapCentralManager (Coordinates wap_core, wap_ads, wap_notifications, wap_promo)
```

---

## File Deliverables

| Module / Component | Path | Description |
|---|---|---|
| **Domain Models** | `lib/domain/models/crash_models.dart` | Structured crash and error model with technical diagnostics. |
| **Domain Models** | `lib/domain/models/performance_models.dart` | `PerformanceTrace` and `PerformanceSummary` statistical models. |
| **Domain Models** | `lib/domain/models/analytics_models.dart` | Privacy-safe `AnalyticsEvent` representation. |
| **Domain Models** | `lib/domain/models/monetization_models.dart` | `MonetizationState` model with Ad-Free and provider flags. |
| **Repository Interface** | `lib/domain/repositories/i_crash_reporter.dart` | Contract for crash reporting, sanitization, and persistence. |
| **Repository Interface** | `lib/domain/repositories/i_performance_monitor.dart` | Contract for trace measurement and summary generation. |
| **Repository Interface** | `lib/domain/repositories/i_analytics_service.dart` | Contract for privacy-safe event and screen tracking. |
| **Repository Interface** | `lib/domain/repositories/i_wap_central_manager.dart` | Contract for coordinating the 4 WAPCentral SDKs. |
| **Data Service** | `lib/data/monitoring/crash_reporter.dart` | Local JSON persistence, path and secret scrubbing. |
| **Data Service** | `lib/data/monitoring/performance_monitor.dart` | Latency stopwatch tracker, statistical aggregations. |
| **Data Service** | `lib/data/monitoring/analytics_service.dart` | Parameter sanitization filter, event buffer. |
| **Data Service** | `lib/data/wapcentral/wap_central_manager.dart` | Coordinates WAP Core, Ads, Notifications, and Promo SDKs. |
| **Riverpod Providers** | `lib/features/monitoring/presentation/providers/monitoring_providers.dart` | Riverpod providers and `MonetizationNotifier`. |
| **Ad Banner Widget** | `lib/features/monitoring/presentation/widgets/filezen_ad_banner.dart` | Non-intrusive banner widget with Ad-Free and offline collapse. |
| **Promo Card Widget** | `lib/features/monitoring/presentation/widgets/filezen_promo_card.dart` | Cross-promotion native card using `WapPromoBuilder`. |
| **Diagnostics Screen** | `lib/features/monitoring/presentation/screens/diagnostics_screen.dart` | Observability dashboard with 4 tabs and export action. |
| **Settings Screen** | `lib/features/settings/presentation/screens/settings_screen.dart` | Integrated telemetry toggle, diagnostics tile, and Ad-Free Pro. |
| **Home Screen** | `lib/features/home/presentation/screens/home_screen.dart` | Integrated bottom `FileZenAdBanner`. |
| **App Bootstrap** | `lib/app/bootstrap/app_bootstrap.dart` | Global error hooks and startup latency measurement. |
| **Unit Tests** | `test/unit/crash_reporter_test.dart` | 4 unit tests covering scrubbing, persistence, opt-out, and clear. |
| **Unit Tests** | `test/unit/performance_monitor_test.dart` | 4 unit tests covering trace measurements, failures, percentiles. |
| **Unit Tests** | `test/unit/analytics_service_test.dart` | 5 unit tests covering event logging, PII filtering, opt-out. |
| **Unit Tests** | `test/unit/wap_central_manager_test.dart` | 4 unit tests covering test init, Ad-Free persistence, offline safety. |
| **Widget Tests** | `test/widget/diagnostics_screen_test.dart` | 4 widget tests covering 4 tabs, ecosystem info, telemetry toggle. |
| **Widget Tests** | `test/widget/ad_banner_and_settings_test.dart` | 2 widget tests covering Ad-Free collapse and settings toggle. |

---

## Verification & Test Results

- **Full Project Test Suite**: **226 / 226 passing tests** (100% pass rate).
- **Static Analysis**: `flutter analyze` reports **0 issues found** (0 errors, 0 warnings).
- **Unit & Widget Coverage for Phase 12**:
  - `crash_reporter_test.dart`: 4/4 passed.
  - `performance_monitor_test.dart`: 4/4 passed.
  - `analytics_service_test.dart`: 5/5 passed.
  - `wap_central_manager_test.dart`: 4/4 passed.
  - `diagnostics_screen_test.dart`: 4/4 passed.
  - `ad_banner_and_settings_test.dart`: 2/2 passed.

---

## Exit Criteria & Approval Status

- [x] All Phase 12 code and tests implemented according to Master PRD & Integration Guide.
- [x] 100% offline-safe; zero personal data or file metadata transmitted.
- [x] 226 unit & widget tests pass cleanly with 0 failures.
- [x] `flutter analyze` reports zero warnings or errors.
- [x] Sourced credentials and platform endpoints mapped to authoritative WAPCentral guide.
- **Status**: Completed (Pending Approval).
