# Audit Remediation Status — Documentation-Driven Re-Audit

**Date:** 2026-10-10  
**Basis:** `FileZen_PreRelease_Remediation_Plan.md` (P0-01 … P0-12, secrets, Play gate) re-verified against the actual code, not against earlier sprint claims.  
**Overall state:** `RELEASE BLOCKED` — see §6 (owner decisions) and §7 (device testing). Nothing here has been committed or pushed.

> Principle applied: *no fake feature stays in the app.* Where a documented feature could not be completed safely it was made
> honest (disabled / failing with a clear message) and the product impact is recorded in §3, rather than hidden or left simulated.

---

## 1. Finding-by-finding status

| ID | Finding | Verified state | Action taken |
|---|---|---|---|
| P0-01 | Release signing | Release AAB is signed with the `CN=FileZen` release certificate (checked with `keytool -printcert`, no secrets read); no debug fallback | None needed (re-verified) |
| P0-02 | Vault not AES-256-GCM | **Confirmed defective** (HMAC-CTR, shared IV for metadata + content) | Replaced: native AES-256-GCM (`VaultCrypto.kt`), v2 container, migration of v1 data |
| P0-03 | Biometric stub / bypass | **Confirmed defective**: `catch` fell through to unlock; the existing test asserted the bypass | Fail-closed gate; Keystore enforces a recent system authentication before releasing the key |
| P0-04 | Plaintext PIN | **Confirmed defective**: session key = PIN bytes; biometric token = PIN XOR key derived from the on-disk salt | Random master key wrapped by PBKDF2-derived KEK + device-bound Keystore key; no PIN-derived secret persisted |
| P0-05 | Manifest leaks names/paths | **Confirmed**: plaintext JSON + original file name in container file name | Encrypted index (`vault_manifest.enc`), random container names |
| P0-06 | Backup exclusion | Verified (`allowBackup=false` + both rule files; `backup_exclusion_test`) | Added `.filezen_network_servers.json` to the exclusions |
| P0-07 | `FLAG_SECURE` not applied | **Confirmed**: setting stored, never applied | Applied natively via ref-counted `SecureSurface` (Vault tab + vault screens; respects the setting) |
| P0-08 | Billing is a local boolean | **Confirmed, in two places** (Settings tile, which could even toggle itself, and a Diagnostics "Simulate Buy" button) | Settings: no control can grant/revoke entitlement ("Coming soon"). Diagnostics: simulation limited to `kDebugMode`. **Real Google Play Billing is not implemented** (owner decision, §6) |
| P0-09 | Ads are placeholders | Ads are rendered by the external WAPCentral SDKs (`wap_ads_sdk`, `wap_promo_sdk`), not placeholders; `FileZenAdBanner` collapses on failure/ad-free | **Not verifiable here** (SDKs live outside the repo; needs device + test ad IDs) |
| P0-10 | OCR is a stub | Real ML Kit (Latin) is wired into indexing. A host-only fallback scraped printable bytes from the image file | Fallback removed: unavailable ⇒ empty result. Real per-line confidence + language reported. Tests use an injected recognizer |
| P0-11 | Cloud providers fake | **Confirmed, and wider than the audit**: cloud, FTP, SFTP, SMB all returned canned data / fabricated downloads / fake upload success; the transfer queue simulated progress for *every* protocol and posted "Transfer Completed" without calling any adapter | Cloud/FTP/SFTP/SMB now fail honestly and are not offered in the UI. Transfer queue now executes through the adapter (only WebDAV is real) |
| P0-12 | ZIP traversal | Verified hardened (`archive_security_test`) | Added enforcement on *actual* decompressed size (header sizes are attacker-controlled); gzip-bomb guard in the viewer |
| Secret | Leaked X-App-Key | Value was still quoted verbatim in `sprint_01_release_gate_remediation.md` | Redacted in the working tree. **Key remains in Git history ⇒ must be rotated (owner)**. `08_Credentials.md` was not opened (rule); it is modified/uncommitted — please review it yourself before committing |

---

## 2. Additional defects found and fixed

| Area | Defect | Fix |
|---|---|---|
| Vault | `changePin` re-keyed from the new PIN ⇒ **all existing vault files became undecryptable** | PIN change re-wraps the master key only |
| Vault | Unreadable `vault_auth.json` looked like "not configured" ⇒ a new PIN could orphan the vault; manifest read errors returned `[]` and the next write erased the index | Damaged config is "configured but damaged"; unreadable index fails writes instead of replacing it; atomic writes |
| Vault | Concurrent imports raced on the manifest; a concurrent `lock()` could zero the key mid-encryption (encrypting with a zero key) | Serialised operations; key copied right before each crypto call; zero key refused |
| Vault | Auto-lock ignored its timeout and locked on `inactive` (i.e. during the biometric prompt) | App-wide `VaultLifecycleGuard`: `paused` only, honours the timeout |
| Vault | Import deleted the source without proving the encrypted copy decrypts | Round-trip verification before the source is deleted; no orphan container on failure |
| Vault | Debug-mode `CircularDependencyError` after every PIN unlock (redundant `ref.invalidate`) | Removed |
| Files browser | After "Move to Vault" the moved file stayed in the list (broken thumbnail) until a manual refresh | Listing is invalidated on success (single and multi-select) |
| Vault | "Share Securely" only showed a "safeguards verified" message and shared nothing | Real hand-off: decrypted copy in a per-share cache folder opened in an external app, deleted after 2 minutes, swept at next start (`VaultShareService`) |
| Vault / Search | **Privacy leak**: after a file moved into the Vault, its name, path and extracted/OCR text stayed in the public search index (nothing pruned it), so it still appeared in normal Search | Vault import now removes the original from the index (`removeFileByPath`); end-to-end test over real index + vault |
| Indexing | Index row ids (`file_<pathHash>_<size>`) never matched `FileEntity.id` (md5), so every `removeFile(entity.id)` — including the delete flows in `files_screen.dart` — silently deleted nothing; editing a file so its size changed inserted a second row for the same path, after which every scan hit `getSingleOrNull` "too many elements" for that file | New path-keyed `removeFileByPath` (used by delete + vault flows); superseded rows are replaced on re-index; scans heal existing duplicates |
| UI | Image thumbnails set both `cacheWidth` and `cacheHeight`, decoding to an exact square and distorting non-square photos | `cacheWidth` only |
| Transfers | Queue never transferred anything; pause/cancel were cosmetic; downloads overwrote existing files | Real execution, cancel stops the stream and deletes `.part` data, pause stops + restarts on resume, unique local names |
| WebDAV | Crash on malformed percent-escapes / absolute hrefs; truncated files left under the final name | Robust href parsing; stream to `.part` then rename |
| Network UI | Seeded "starter" servers pointing at made-up LAN IPs; SMB default | No seeding (legacy starters are dropped on load); WebDAV default |
| Credentials | Saved server passwords stored in plaintext JSON | Keystore-wrapped (device-bound); never written in the clear if wrapping fails |
| LAN web share | 4-digit PIN from a non-secure RNG, unlimited guesses, wildcard CORS ⇒ any web page could brute-force it; PIN written to logs and the notification | 6-digit secure PIN, 5-strikes/60 s per-client lockout, no CORS, raw-PIN header auth removed, PIN no longer logged/notified |
| LAN web share | Portal **Download link always returned 401** (token in URL, server read headers only) | Query token accepted for `/api/download/` only |
| LAN web share | Stored XSS through file names (`innerHTML`); portal destroyed its own file input after the first upload; non-ASCII names broke uploads; drag-and-drop advertised but absent | DOM built with `textContent`, CSP + `nosniff`, percent-encoded upload name, drop handlers |
| LAN web share | Uploads went to the app cache (invisible, auto-cleared), overwrote same-named files, unlimited size; reported port 0 when an ephemeral port was requested | `Downloads/FileZen`, unique names, 2 GiB cap rejected from the header, real bound port |
| Viewers | Archive viewer listed TAR/GZ/TGZ but "Extract" only handled ZIP; 7z/rar/bz2 always errored; unbounded in-memory inflate | Extract offered for ZIP only (message otherwise); 7z/rar/bz2 hand off to an external app; size guards |
| Viewers | XML viewer read arbitrarily large files into memory | 20 MB cap with a clear message |
| Manifest | `usesCleartextTraffic="true"` | Removed — see §4 |

---

## 3. Product impact of making features honest

| Feature | Before (as presented) | Now |
|---|---|---|
| Cloud Drives (Drive/OneDrive/Dropbox/Box) | Appeared to connect and browse (fake data) | Screen says "not available yet"; no accounts, no fake files |
| FTP / SFTP / SMB | Appeared to connect and browse (fake data) | Not selectable when adding a server ("coming soon"); saved ones fail with "not supported" |
| WebDAV | Listing real, transfers simulated | Listing + download + upload are real |
| Ad-Free Pro | Free toggle | Disabled "Coming soon" until Play Billing exists |
| OCR on non-mobile hosts | Pseudo-text from file bytes | No text (honest) |

Docs that still describe these as delivered (`phase_11_network_transfer_cloud.md`, `phase_12_analytics_monitoring_wapcentral.md`, `phase_13_...`) now carry a pointer to this document. The PRD was not changed.

---

## 4. Decision records requested in the audit

### 4.1 Release cleartext-traffic flag — **removed**

* Evidence: the flag was added by the uncommitted Gemini changes (HEAD had none). Every FileZen network client is `dart:io`
  (`HttpClient`, `Socket`, `HttpServer`), which opens BSD sockets and is **not governed** by `usesCleartextTraffic` / Network Security Config; that flag
  only affects the Java/Android stacks (WebView, OkHttp/HttpURLConnection, ExoPlayer, MediaPlayer, ad SDKs). `video_player` is used with `VideoPlayerController.file`
  only; no `UrlSource`/`NetworkImage`; WAPCentral base URL is HTTPS; the WAPCentral SDKs declare no cleartext requirement.
* Features that use plain HTTP: the LAN web share (inbound `HttpServer`, browser → phone) and WebDAV on non-443 ports (outbound `dart:io`). Neither needs the flag.
* Security trade-off: leaving it `true` only widened the attack surface (any WebView/ad/media request over HTTP in production). Removing it changes no FileZen feature.
* Residual risk (documented, unchanged): LAN share and WebDAV-on-port-80 are cleartext by design (PIN/token/Basic credentials cross the LAN unencrypted). Recommended follow-up: per-server "use TLS" for WebDAV; keep the LAN share limited to trusted Wi-Fi and stop it when done.
* **Must be confirmed on a device** (§7, item 1) because this was reasoned from platform behavior, not observed.

### 4.2 R8 `-dontwarn` rules — appropriately scoped

* Rules: four packages `com.google.mlkit.vision.text.{chinese,devanagari,japanese,korean}.**`, plus `com.google.android.play.core.**`.
* Why safe: `OcrService` only ever constructs `TextRecognizer(script: latin)`; the plugin references the other options' classes only inside branches for other scripts.
  Play Core is referenced by Flutter's deferred-components code, which FileZen does not use.
* Remaining runtime risk: **none for current code**. If non-Latin OCR is ever added, add the matching ML Kit `…-text-recognition-<script>` Gradle dependency, or the
  recognizer will crash with `NoClassDefFoundError`. The release bundle (with the new native code) was built to confirm R8 completes.

### 4.3 pdfx "plugin applies Kotlin Gradle Plugin" warning — not safely fixable here

pdfx 2.11.0 is already the latest release and applies `kotlin-android` (KGP 1.9.23) itself; the project opts out of built-in Kotlin via the Flutter template
(`android.builtInKotlin=false`). It is a warning today. Fixing it requires replacing the PDF-view plugin (for example with a maintained alternative) — a dependency change that needs owner approval.

### 4.4 Drift "multiple AppDatabase" warning — fixed (test isolation)

Cause: `search_screen_test.dart` did not override `appDatabaseProvider`, so each test opened the real on-disk `AppDatabase()`. The tests now use an isolated in-memory database. The warning is gone; nothing was suppressed.

---

## 5. Verified vs. not verified

| Verified (executed) | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test` (full suite) | 330 passed, 0 failed |
| Native JVM unit tests `:app:testDebugUnitTest` | 10 passed (RFC vectors + AES-GCM tamper/AAD/nonce) |
| `flutter build apk --debug` | Built |
| `flutter build appbundle --release` | Built (81.0 MB); R8 completes with the new native code; signer is the release certificate (`CN=FileZen`), not the Android debug key |

**Not verified (cannot be from this machine):** anything on a physical device/emulator — BiometricPrompt, Android Keystore wrap/unwrap and invalidation, `FLAG_SECURE`,
scoped/all-files storage behavior, ML Kit OCR output, Play Billing/ads/WAPCentral SDK behavior, and real WebDAV servers/NAS devices.

---

## 6. Decisions needed from the owner

1. **Google Play Billing** for Ad-Free Pro: approve the `in_app_purchase` dependency, supply the product ID and Play Console setup; entitlement must come from verified purchase state with restore/refund handling.
2. **Cloud drives**: real OAuth/REST clients need provider developer registrations (client IDs). Decide scope (which providers) or remove from the roadmap/store listing.
3. **FTP/SFTP/SMB**: implement (needs new dependencies, e.g. an SSH/SMB client) or drop from the PRD/store listing.
4. **Vault size cap (100 MB/item)**: accept, or fund a streaming AEAD (chunked) design.
5. **Vault key custody wording**: confirm the "vault is lost on factory reset/new device" behavior is acceptable and should be shown in onboarding and the privacy policy.
6. **Rotate the leaked WAPCentral X-App-Key** and review the uncommitted `08_Credentials.md`.
7. **pdfx replacement** (§4.3), and WebDAV "use TLS" option (§4.1).
8. Dead code from the Gemini sprint: `IndexingService.pause/resume/startPeriodicBackgroundSync` and `IndexingProgressNotifier.pause/resumeIndexing` are never called (no runtime effect); wire them to the documented battery/charging throttling or remove.
   *Update 2026-10-10:* `IndexingService.pause/resume` are now driven by the app lifecycle (`IndexingCoordinator`) and OCR is deferred on battery saver / low battery / thermal stress. `startPeriodicBackgroundSync` remains unused (the coordinator schedules scans). See `full_audit_2026-10-10.md`.

---

## 7. Manual device test checklist (required before release)

1. **Cleartext**: add a WebDAV server on an `http://` LAN address (port 80/8080); list, download and upload a file. Open the LAN web share from a PC browser, sign in, download and upload.
2. **Vault first run**: create PIN; enable biometrics (prompt must appear); lock; unlock by biometrics; cancel the prompt (must stay locked); add a fingerprint in system settings → biometric unlock must disable itself and the PIN must still open the vault.
3. **Vault no screen lock**: on a device without a lock screen, biometric enable must fail with the explanatory message; PIN vault must work.
4. **Vault data**: import photo/PDF/video (<100 MB), preview, export, change PIN then re-open, force-stop the app then unlock, large file (>100 MB) shows the limit message.
   **Secure share**: share a vault PDF/photo to another app (FileProvider access to the cache folder must work); the temporary copy must disappear after ~2 minutes or at next launch.
5. **Upgrade path**: install the previous build, create a vault with files, install this build over it, unlock with the PIN; files must be present; the biometric setting is off.
6. **Screen capture**: with the Vault tab open, screenshot/screen-record must be blocked and the recents thumbnail blank; with the setting off, allowed; other tabs unaffected.
7. **Auto-lock**: background the app with timeout "immediately", "30 s"; foreground after shorter/longer; biometric prompt must not lock the vault itself.
8. **OCR**: index a photo of printed text; search for a word in it (offline, airplane mode).
9. **Storage permission flows**: grant / deny / revoke All-files access; app must not crash.
10. **Release AAB** installed via Play internal testing: sign-in with the release key, ads behavior, notification permission on Android 13+.
