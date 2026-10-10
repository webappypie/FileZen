# FileZen Architectural Decision Log: Vault Authentication & Encryption Model

**Status**: Approved — **implementation revised 2026-10-10** (see §5)  
**Original date**: October 8, 2026  
**Context**: Pre-Release Remediation — Issue 7: System Device Lock Integration Decision  
**Decision Owner**: Security & Mobile Architecture  

> **Correction notice.** The first version of this log described guarantees that the shipped code did
> not provide (a plaintext PIN was used as the session key, the biometric "token" was the PIN XOR-masked with a
> key derivable from the on-disk salt, biometric failures fell through to unlock, and the cipher was a
> hand-rolled HMAC-CTR construction). The decision below (hybrid PIN + biometrics) is unchanged; §5 records
> the defects and the corrected implementation. Statements in §1–§4 now describe the **corrected** design.

---

## 1. Executive Summary & Decision

FileZen adopts a **Hybrid Defense-in-Depth Model**:

1. **Dedicated Master Vault PIN** (4–6 digits) protects a **random 256-bit master key**.
   `KEK = PBKDF2-HMAC-SHA256(PIN, 32-byte random salt, 210,000 iterations)` wraps the master key with AES-256-GCM.
2. The wrapped master key is wrapped **again by a hardware-backed Android Keystore key** (device-bound, no user
   authentication). A copy of the app data directory therefore cannot be brute-forced offline: the PIN alone is not enough.
3. **Android system `BiometricPrompt`** (via `local_auth`, `biometricOnly: false`) provides fast unlock. The master
   key is additionally wrapped by a second Keystore key whose use the **Keystore itself** only permits for 15 seconds
   after a successful biometric / device-credential authentication. The Flutter layer cannot unwrap it without a real prompt.
4. **Ephemeral session key in volatile memory**, zeroed in place on lock and when the app is backgrounded (per the auto-lock policy).

All vault content, metadata and the item index are encrypted with **AES-256-GCM** (`javax.crypto`, 96-bit random nonce per encryption,
128-bit tag).

---

## 2. Options Evaluated

### Option A: Rely Exclusively on System Device Lock (Android Keystore / BiometricPrompt alone)
- *Pros*: Zero onboarding friction for users who already have a phone PIN.
- *Cons*:
  - **Zero Protection if Phone is Handed Unlocked**: If a user unlocks their phone to show photos to a friend or child, an intruder has full access to the Vault without additional authentication.
  - **No Protection on Devices Without Screen Lock**: Many users disable screen lock; on such devices, Vault would have zero security.
  - **Data Loss on Device Lock Reset**: If Android lock credentials change, keys bound to `setUserAuthenticationRequired(true)` can be invalidated by the hardware Keymaster, causing permanent loss of vaulted files.
  - **Not Truly Zero-Knowledge**: Does not allow exportable backup or cross-device container recovery.

### Option B: Rely Exclusively on Dedicated Vault PIN (Isolated Custom Lock)
- *Pros*: 100% self-contained, independent of Android device lock state.
- *Cons*: Poor UX requiring manual PIN entry every time the user checks a private receipt or photo.

### Option C: Hybrid Defense-in-Depth Architecture (SELECTED)
- Combines the independence of Option B with the seamless biometric ergonomics of Option A.
- The **vault never depends on the biometric key for recoverability**: files are always recoverable with the PIN.
  The biometric Keystore key is a convenience copy that can be invalidated and re-created.

---

## 3. Threat Model & Edge-Case Analysis

| Scenario | Behavior in Hybrid Model |
| :--- | :--- |
| **User has device lock & biometrics** | `BiometricPrompt` appears. On success the Keystore releases the biometric-wrapped master key. Failure, cancel, lockout or any exception leaves the vault locked (fail closed). |
| **User has no device lock enabled** | Biometric unlock cannot be enabled (Keystore refuses auth-bound keys). The vault stays fully protected by the PIN + device-bound Keystore wrap. |
| **User changes system PIN / enrolls a new fingerprint** | The biometric Keystore key is invalidated. Biometric unlock reports it, switches itself off, and the user re-enables it after a PIN unlock. **No data loss**: files are keyed by the master key, which the PIN path still unwraps. |
| **Phone handed to friend/family while unlocked** | Vault remains locked. Opening Vault prompts for fingerprint or Vault PIN. |
| **Biometric sensor failure / dirty finger** | Fall back to the Vault PIN. |
| **Wrong PIN guessing on the device** | 5 consecutive failures trigger a 30-second lockout (persisted). Biometric unlock does not bypass it. |
| **Compromised / rooted device storage extraction** | `.zenvault` containers and the item index are AES-256-GCM ciphertext under random names. Without the Keystore key (hardware-backed, non-exportable) the wrapped master key cannot even be attempted offline. |
| **Factory reset / app data restored onto another device** | The device Keystore key does not exist there, so the vault cannot be opened. By design: backup is disabled (`allowBackup=false`) and the vault is excluded from device transfer. Vault contents are **not recoverable** in this case — users must be told this (see §6). |
| **App goes to background** | Locks immediately (default) or after the configured timeout, evaluated app-wide by `VaultLifecycleGuard`. Only `paused` counts; `inactive` (biometric prompt, dialogs) does not. |
| **Screenshots / recents thumbnail** | `FLAG_SECURE` is applied to the window while the Vault tab or any Vault screen is visible and "Screenshot Protection" is on (default on; fails closed while the setting loads). |

---

## 4. Implementation Impact & Key Guarantees

1. **Native Fragment Activity**: `MainActivity.kt` extends `FlutterFragmentActivity` (required by AndroidX `BiometricPrompt`) and hosts the vault `MethodChannel` (`com.webappypie.filezen/vault`).
2. **Manifest Permissions**: `USE_BIOMETRIC` and `USE_FINGERPRINT`, no runtime popups.
3. **No plaintext PIN anywhere.** The PIN exists only transiently as input to PBKDF2; no `activePin`, no PIN-derived session key, no PIN-reversible token. `activeSessionKey` is the random master key.
4. **Active memory zeroing**: `lock()` zeroes the master key in place. Storage operations copy the key immediately before each crypto call and refuse an all-zero key, so a concurrent lock can never encrypt with a zeroed key.
5. **Container format v2** (`ZENVAULT\x02`): metadata and content are separate AES-GCM blobs with independent random nonces; the content blob authenticates the metadata blob as AAD (no splicing between containers).
6. **Encrypted item index** (`vault_manifest.enc`) and **random container names**: file names, original paths, sizes and categories never appear on disk in the clear, and the vault cannot be enumerated while locked.
7. **PIN change** re-wraps the master key only; vault files are untouched (the previous implementation derived file keys from the PIN, so changing the PIN stranded every file).
8. **Config integrity**: a present-but-unreadable `vault_auth.json` is treated as *configured but damaged* and can never be silently replaced by a new PIN (which would orphan the vault). `setupPin` refuses to overwrite an existing vault. Writes are atomic (temp file + rename).
9. **Size limit**: single-shot AEAD needs the item in memory, so items over **100 MB** are refused with a clear error (see §6).
10. **No Manual Path Entry**: Users move files into Vault via context menus, category views, or multi-selection action bars.

---

## 5. Revision Record (2026-10-10)

**Old design (as shipped):** PIN → `utf8(pin)` used directly as the session/file key; PBKDF2 (10,000 iterations) then derived
per-container keys from it; HMAC-SHA256 "CTR" keystream with one IV shared by metadata and content; single-iteration
`HMAC(salt, pin)` verifier; "biometric token" = PIN XOR `HMAC(salt, constant)`, stored beside the salt; plaintext
`vault_manifest.json` and `<timestamp>_<original name>.zenvault` file names; `catch` around the biometric prompt fell through to unlock;
`screenshotProtectionEnabled` stored but never applied to the window; auto-lock ignored its timeout setting.

**Problems:**
- Biometric bypass: any exception (no hardware, platform error, lockout) unlocked the vault.
- The PIN was recoverable from `vault_auth.json` alone (token XOR key derived from the stored salt); a 4–6 digit PIN also fell to trivial brute force.
- Not AES-GCM; metadata and content reused the same keystream (two-time pad leaks `plaintext_a XOR plaintext_b`).
- Index and file names leaked content metadata without authentication.
- Changing the PIN made existing vault files undecryptable.
- `FLAG_SECURE` never set; auto-lock only worked while the Vault tab object existed and ignored the configured timeout.

**New design:** §1 and §4 above.

**Migration impact:** On the first PIN unlock after upgrade the config is upgraded in place (insecure `pinHash`, `saltHex`, `biometricToken` removed;
biometrics switched off until re-enabled). The storage layer then re-encrypts every v1 container into a v2 container under a random name,
rebuilds the encrypted index, deletes the plaintext manifest and removes each v1 file only after the v2 index is saved. The upgrade is idempotent
(`legacyMigrationPending`) and resumes on the next PIN unlock if interrupted. Containers that cannot be decrypted are left untouched and logged.
Biometric unlock before the first PIN unlock cannot migrate (the PIN is the legacy key).

**Tests:**
- `android/app/src/test/.../VaultCryptoTest.kt` (JVM, 10 tests): RFC PBKDF2-HMAC-SHA256 vectors, AES-GCM round trip, empty plaintext, nonce uniqueness, tamper (ciphertext/tag/nonce), wrong key, wrong AAD, truncation, key length.
- `test/unit/vault_service_test.dart`: container format and tamper/splice detection; key hierarchy; no secrets in config; lockout; Keystore trouble not counted as wrong PIN; PIN change keeps files; damaged-config safety; every biometric failure path fails closed (including a mutation check that the tests fail if the gate is bypassed); index/file-name privacy; legacy migration incl. interrupted resume.
- `test/widget/vault_security_surface_test.dart`: `FLAG_SECURE` wiring and auto-lock behavior.

---

## 6. Known Limitations / Follow-ups

- **Device-bound by design**: if the device Keystore key is lost (factory reset, restore to a new phone, Keystore corruption) the vault is unrecoverable. The UI should state this during onboarding (not yet added).
- **100 MB per item**. Larger files need a chunked/streaming AEAD (for example Tink streaming AEAD) — a product/engineering decision.
- The Android-specific code (`VaultKeystore.kt`, `MainActivity` channel, biometric + `FLAG_SECURE` behavior) compiles and its pure-crypto core is unit-tested on the JVM,
  but **has not been exercised on a physical device or emulator**. See `docs/04_Development_Roadmap/audit_remediation_status.md` for the manual test checklist.
- Secure deletion of the original file after import is a normal filesystem delete; per the Security Architecture we make no physical-overwrite claim.
