# FileZen — Google Play Store Compliance & Permission Declarations

**Date:** 2026-10-08  
**Application ID:** `com.webappypie.filezen`  
**Target SDK:** 35 (Android 15)  
**Min SDK:** 24 (Android 7.0)  

---

## 1. High-Risk Permission Declarations

### 1.1 `MANAGE_EXTERNAL_STORAGE` (All Files Access)

- **Permitted Google Play Core Use Case:** File Management Application (`Core functionality: File managers`)
- **Justification:**
  - FileZen is a universal local file management and productivity tool whose primary functionality requires scanning, indexing, organizing, batch-operating (copy, move, rename, delete, batch zip compression and extraction), and deduplicating user files across all shared storage directories (`/storage/emulated/0/`).
  - Without `MANAGE_EXTERNAL_STORAGE`, the application cannot perform its advertised core purpose: browsing non-media files, reading documents in custom directories, detecting duplicate and redundant clutter, and moving files between arbitrary directories on device storage.
- **User Disclosure & Consent:**
  - A prominent pre-permission disclosure dialog explains the necessity of All Files Access before navigating the user to `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`.
  - The app gracefully supports denied and restricted permissions without crashing.

### 1.2 `POST_NOTIFICATIONS` (Android 13+, API 33+)

- **Purpose:** Display operational progress alerts for long-running batch operations (indexing, large ZIP compression/extraction, deduplication runs) and notify users of important app/system updates in the Notifications Center.
- **Behavior:**
  - Notifications are strictly transactional or opt-in.
  - Notifications are not used for unsolicited spam.

### 1.3 Media Permissions (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`)

- **Purpose:** Used on Android 13+ devices to index and display thumbnails, image galleries, video playback, and audio playback.
- **Behavior:** Read-only access requested gracefully and scoped to media categories.

### 1.4 Network Permissions (`INTERNET`, `ACCESS_NETWORK_STATE`)

- **Purpose:**
  - Local Area Network (LAN) HTTP server for peer-to-peer file transfer over Wi-Fi.
  - Opt-in user connections to remote network storage (FTP, SFTP, SMB, WebDAV).
  - Opt-in cloud file storage synchronization (Google Drive, OneDrive).
  - WAPCentral platform coordination and ad serving.
- **Privacy Principle:**
  - Zero local user files are uploaded automatically or silently.
  - Core file management remains 100% operational offline.

---

## 2. Google Play Data Safety Disclosures

| Data Type | Collected | Shared | Purpose | Optional / Mandatory | Ephemeral |
|---|---|---|---|---|---|
| **User Files & Documents** | **No** | **No** | Stored and processed strictly locally on-device | N/A | Local |
| **Photos & Videos** | **No** | **No** | Local indexing, thumbnailing, and playback only | N/A | Local |
| **Audio Files** | **No** | **No** | Local playback only | N/A | Local |
| **Contacts / SMS / Personal Info** | **No** | **No** | Not accessed by application | N/A | N/A |
| **Device or other identifiers** | Optional | Yes (WAPCentral / Ads) | Analytics & Ad Serving (if ad-supported mode active) | Optional | Transferred securely via HTTPS |
| **App Performance & Crash Logs** | Optional | Yes (WAPCentral / Crashlytics) | Stability and diagnostics (PII/secrets redacted) | Optional | Redacted |

---

## 3. Data Protection & Backup Isolation (`P0-06`)

- **Cloud Backup Exclusion:**
  - `android:allowBackup="false"` is set in `AndroidManifest.xml` to prevent arbitrary ADB extraction or uncontrolled cloud restoration.
  - `android:dataExtractionRules` (Android 12+) and `android:fullBackupContent` (Android 11 and lower) explicitly exclude:
    - `.filezen_vault/` (Encrypted containers and manifest)
    - `vault/`
    - `app_database.sqlite` (Local file index)
    - `FlutterSecureStorage` / `flutter_secure_storage` (Platform Keystore tokens)
    - Monetization cache
- **Device-to-Device Transfer:**
  - Sensitive vault containers and platform key tokens are explicitly excluded from device-to-device migration rules to ensure vault contents cannot be decrypted on an unauthenticated destination device.

---

## 4. Release Signing & Binary Hardening (`P0-01`)

- **Signing Config:** Production release variants are strictly configured to sign using production release keys via `android/key.properties` or CI environment variables. Debug signing is structurally prohibited for the release buildType.
- **Code Shrinking & R8/ProGuard:** R8 code shrinking (`isMinifyEnabled = true`), resource shrinking (`isShrinkResources = true`), and targeted ProGuard preservation rules (`proguard-rules.pro`) are enabled for release builds.
- **Zero Committed Secrets:** All signing passwords, keystore binaries, and production API secrets are strictly ignored by `.gitignore` and omitted from the repository.
