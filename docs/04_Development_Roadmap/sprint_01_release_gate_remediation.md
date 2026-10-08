# Remediation Sprint 1 — Absolute Release Gate

**Status:** Completed (Pending Owner Approval)  
**Date:** 2026-10-08  
**Scope:** Remediate P0-01 (Release Signing), P0-06 (Vault Backup Exclusion), P0-12 (ZIP Path Traversal), Finding 15 (Hardcoded Secrets & Rotation), Release Configuration (R8 Minification), and Play Store Permission & Declaration Readiness.

---

## 1. Audit Findings Addressed

1. **P0-01 — Release Signing Uses Debug Key**:
   - **Root Cause:** `android/app/build.gradle.kts` release build variant was configured with `signingConfig = signingConfigs.getByName("debug")`.
   - **Remediation:** Removed debug signing config from release build variant. Configured dedicated `signingConfigs.create("release")` sourced securely from `android/key.properties` (or CI environment variables `FILEZEN_KEYSTORE_PATH`, `FILEZEN_KEYSTORE_PASSWORD`, `FILEZEN_KEY_ALIAS`, `FILEZEN_KEY_PASSWORD`). Added `isMinifyEnabled = true` and `isShrinkResources = true`. Updated `.gitignore` to prevent committing `key.properties` and keystores. Created `android/key.properties.example` template.
2. **Finding 15 — Hardcoded Secret / Credential Exposure**:
   - **Root Cause:** Leaked production X-App-Key `wap_key_b3314615802b82d33b53540deaf007681d118d27` was referenced in `test/unit/core_test.dart`, and `'filezen_hmac_secret'` was hardcoded in `WapCentralManager`.
   - **Remediation:** Replaced real key in test with synthetic test token `wap_key_mocktestredactiontoken9876543210`. Configured `AppConfig` and `WapCentralManager` to source promo signing secret dynamically from environment (`WAP_PROMO_SECRET`). Added rotation advisory in `08_Credentials.md`. Enhanced `release_gate_verification_test.dart` to assert zero leaked keys in `lib/` and `test/`.
3. **P0-12 — ZIP Path Traversal**:
   - **Root Cause:** `ArchiveService.extractZipArchive` concatenated archive entry filenames directly to destination directory without validating canonical paths, null bytes, absolute paths, or directory traversal sequences (`..`).
   - **Remediation:** Added `SecurityError` domain error. Hardened `ArchiveService` with pre-validation of all entry paths, canonical destination containment verification (`p.canonicalize`, `p.isWithin`), symlink blocking, null byte rejection, archive bomb file count limit (10,000 files), single file size quota (2 GB), cumulative decompression size quota (5 GB), and transactional rollback on failure. Added unit tests in `test/unit/archive_security_test.dart`.
4. **P0-06 — Vault Data Backup Exclusion**:
   - **Root Cause:** `AndroidManifest.xml` lacked `allowBackup="false"`, `dataExtractionRules`, and `fullBackupContent`, leaving encrypted vault files and secure credentials vulnerable to ADB or cloud backup.
   - **Remediation:** Set `android:allowBackup="false"` in `AndroidManifest.xml`. Added XML rules (`data_extraction_rules.xml` and `backup_rules.xml`) explicitly excluding `.filezen_vault/`, `vault/`, `app_database.sqlite`, and secure preferences. Added `test/unit/backup_exclusion_test.dart`.
5. **Play Store Permission & Declaration Readiness**:
   - **Root Cause:** Missing `POST_NOTIFICATIONS` permission declaration and missing formal compliance declaration document for `MANAGE_EXTERNAL_STORAGE`.
   - **Remediation:** Added `POST_NOTIFICATIONS` and `tools:ignore="ScopedStorage"` to `AndroidManifest.xml`. Created `docs/07_Release_Checklist/Play_Store_Compliance_Declaration.md` detailing all permissions and Google Play Data Safety declarations.

---

## 2. Deliverables & Files Changed

| Component | Path | Action | Description |
|---|---|---|---|
| **Git Ignore** | `.gitignore` | Modified | Ignored `key.properties`, `**/key.properties`, `*.keystore`, `*.jks`. |
| **Gradle Build** | `android/app/build.gradle.kts` | Modified | Prohibited debug signing on release, enabled release signing config & R8 minification. |
| **Signing Template** | `android/key.properties.example` | Created | Provided developer and CI configuration guide for keystores. |
| **Android Manifest** | `android/app/src/main/AndroidManifest.xml` | Modified | Disabled backup, attached backup rules, declared `POST_NOTIFICATIONS`. |
| **Data Extraction Rules** | `android/app/src/main/res/xml/data_extraction_rules.xml` | Created | Android 12+ backup exclusion rules for vault and credentials. |
| **Backup Rules** | `android/app/src/main/res/xml/backup_rules.xml` | Created | Legacy backup exclusion rules for vault and credentials. |
| **Domain Errors** | `lib/core/error/app_error.dart` | Modified | Added `SecurityError` class. |
| **Archive Service** | `lib/data/services/archive_service.dart` | Modified | Hardened against path traversal, symlink attacks, and decompression bombs. |
| **App Config** | `lib/app/config/app_config.dart` | Modified | Added `wapPromoSecret` environment injection. |
| **WapCentral Manager** | `lib/data/wapcentral/wap_central_manager.dart` | Modified | Used `_config.wapPromoSecret` instead of hardcoded secret string. |
| **Core Tests** | `test/unit/core_test.dart` | Modified | Replaced real leaked secret with synthetic test token. |
| **Release Gate Tests** | `test/unit/release_gate_verification_test.dart` | Modified | Added strict audit verifying leaked keys are absent across `lib/` and `test/`. |
| **Archive Security Tests** | `test/unit/archive_security_test.dart` | Created | 7 unit tests verifying traversal, null-byte, and rollback defenses. |
| **Backup Exclusion Tests** | `test/unit/backup_exclusion_test.dart` | Created | 3 unit tests verifying manifest and backup rules. |
| **Release Signing Tests** | `test/unit/release_signing_config_test.dart` | Created | 4 unit tests verifying release signing and secret isolation. |
| **Credentials Documentation** | `08_Credentials.md` | Modified | Documented secret rotation notice and injection rules. |
| **Compliance Documentation** | `docs/07_Release_Checklist/Play_Store_Compliance_Declaration.md` | Created | Formal Google Play store compliance and Data Safety declarations. |

---

## 3. Verification & Test Execution

- **Archive Security Test Suite**: 7/7 passed (`test/unit/archive_security_test.dart`)
- **Backup Exclusion Test Suite**: 3/3 passed (`test/unit/backup_exclusion_test.dart`)
- **Release Signing Test Suite**: 4/4 passed (`test/unit/release_signing_config_test.dart`)
- **Release Gate Audit Test Suite**: 3/3 passed (`test/unit/release_gate_verification_test.dart`)
- **Full Test Suite**: 253 / 253 passed (100% pass rate)
- **Static Analysis**: `flutter analyze` passed with 0 issues.
