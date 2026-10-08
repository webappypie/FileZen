# Phase 09 — Vault & Security Engine (Authenticated Enclave)

## Objective
Establish an enterprise-grade, privacy-centric Vault & Security architecture for FileZen. The engine guarantees hardware-backed and authenticated cryptographic isolation, strict memory safeguards, rate-limiting protections, and zero disk leakage for sensitive user files.

Key capabilities introduced:
1. **Authenticated Cryptographic Container Engine (`.zenvault`)**:
   - Proprietary authenticated container format: `ZENVAULT\x01` magic header.
   - Key derivation using **PBKDF2-HMAC-SHA256** with 10,000 rounds and 32-byte cryptographically secure random salts.
   - Separate 32-byte **Encryption Key** and 32-byte **Authentication Key** derivation.
   - Authenticated stream encryption with AES-CTR keystream and Encrypt-then-MAC **HMAC-SHA256**.
   - Constant-time verification tag validation preventing side-channel and timing attacks.
   - Strict tamper detection: any single-bit modification of ciphertext, initialization vector, metadata, or authentication tag causes immediate rejection.
2. **Master PIN & Biometric Rate-Limiting Enclave (`VaultAuthService`)**:
   - Salted HMAC-SHA256 PIN storage.
   - 5-attempt rate-limiting with automated 30-second lockout cooldown upon consecutive failures.
   - Biometric authentication abstraction with biometric unlock toggles.
   - Secure memory key zeroing: session keys are wiped (`fillRange(0, length, 0)`) immediately upon locking.
3. **Zero Disk Leakage & Private In-Memory Viewer (`VaultPreviewScreen`)**:
   - Decrypts files strictly in volatile memory as `Uint8List`.
   - Never writes unencrypted bytes to device flash or temporary directories.
   - Complete isolation from Android MediaStore indexing, OS thumbnail generators, and public system galleries.
   - Interactive zoomable image viewer and monospace text/code document viewer.
4. **App Lifecycle Auto-Lock & Recents Privacy (`WidgetsBindingObserver`)**:
   - Real-time lifecycle observer auto-locks the vault whenever the application transitions to `paused` or `inactive` states.
   - Configurable auto-lock policy (Immediately on background, 30s, 1m, 5m).
   - Screenshot & recents preview protection toggles.
5. **Secure Sharing Safeguards (`SecureShareDialog`)**:
   - Explicit security warning modal before exporting or sharing decrypted vault items externally.
   - Highlights the boundary crossing and loss of vault hardware safeguards once files leave FileZen.
6. **Encrypted Enclave Management (`VaultStorageService`)**:
   - Import unencrypted files into the vault with automated deletion of plaintext sources.
   - Export vault files back to public storage with collision resolution (`_restored` suffix).
   - Permanent deletion and complete vault emptying.

---

## Architecture & Clean Design Principles

### 1. Authenticated Cryptographic Container Specification
```
[Magic Header: "ZENVAULT\x01" (9 bytes)]
[Salt: 32 bytes (Random.secure)]
[IV: 16 bytes (Random.secure)]
[Metadata Length: 4 bytes (BigEndian uint32)]
[Encrypted Metadata JSON (AES-CTR Keystream)]
[Encrypted Payload (AES-CTR Keystream)]
[HMAC-SHA256 Authentication Tag: 32 bytes (Computed over all preceding bytes)]
```

### 2. Clean Architecture Layering
```
Presentation Layer:
  - VaultScreen (Locked PIN/Biometric View, Unlocked Dashboard & Stats)
  - VaultSettingsScreen (PIN change, biometrics toggle, screenshot protection, auto-lock timeout)
  - VaultPreviewScreen (Zero-disk in-memory viewer for photos and documents)
  - SecureShareDialog (Enclave boundary warning modal)
        ↓
Riverpod Providers:
  - vault_providers.dart:
    * vaultCipherProvider
    * vaultAuthServiceProvider
    * vaultStorageServiceProvider
    * vaultSecurityConfigProvider
    * vaultSessionProvider (VaultSessionNotifier: PIN unlock, biometric unlock, lock)
    * vaultItemsProvider (VaultItemsNotifier: list, import, export, delete)
        ↓
Domain Interfaces & Models:
  - IVaultAuthService, IVaultStorageService
  - VaultSecurityConfig, VaultItem, VaultAuthResult
        ↓
Data Implementation:
  - VaultCipher (PBKDF2-HMAC-SHA256, CTR Keystream, Encrypt-then-MAC HMAC-SHA256)
  - VaultAuthService (Salted PIN verification, 5-failure lockout, biometrics, secure zeroing)
  - VaultStorageService (Container packaging, manifest tracking, source deletion, export restoration)
```

---

## File Deliverables

| Module / Component | Path | Description |
|---|---|---|
| **Domain Models** | `lib/domain/models/vault_models.dart` | `VaultSecurityConfig`, `VaultItem`, `VaultAuthResult`. |
| **Auth Interface** | `lib/domain/repositories/i_vault_auth_service.dart` | Contract for PIN setup, verification, biometrics, lockout, and session keys. |
| **Storage Interface** | `lib/domain/repositories/i_vault_storage_service.dart` | Contract for file encryption, in-memory decryption, export, manifest tracking, and deletion. |
| **Cryptographic Engine** | `lib/data/vault/vault_cipher.dart` | PBKDF2-HMAC-SHA256 key derivation, CTR keystream, HMAC authentication tag, constant-time validation. |
| **Auth Service** | `lib/data/vault/vault_auth_service.dart` | 5-attempt rate-limiting, 30s cooldown lockout, biometric toggle, secure memory zeroing. |
| **Storage Service** | `lib/data/vault/vault_storage_service.dart` | `.zenvault` container generation, unencrypted file deletion, in-memory decryption, manifest management. |
| **Riverpod Providers** | `lib/features/vault/presentation/providers/vault_providers.dart` | State management for vault session, security configuration, items, and storage operations. |
| **Vault Dashboard** | `lib/features/vault/presentation/screens/vault_screen.dart` | Lifecycle observer auto-lock, PIN setup/entry view, biometric button, private items list, and import FAB. |
| **Security Settings** | `lib/features/vault/presentation/screens/vault_settings_screen.dart` | Master PIN update, biometric toggle, screenshot protection toggle, and auto-lock policy selector. |
| **In-Memory Viewer** | `lib/features/vault/presentation/screens/vault_preview_screen.dart` | Isolated in-memory preview with zero disk caching, secure share action, and export action. |
| **Share Warning** | `lib/features/vault/presentation/widgets/secure_share_dialog.dart` | Safeguard warning modal before exporting/sharing files outside the secure enclave. |
| **Unit Tests** | `test/unit/vault_service_test.dart` | 21 unit tests covering cipher round-trip, tamper detection, auth lockout, and storage operations. |
| **Widget Tests** | `test/widget/vault_screen_test.dart` | 9 widget tests covering PIN setup, lockout, unlock, dashboard, settings, preview, and share dialog. |

---

## Verification & Test Results
- **Full Test Suite**: 163/163 passing (100% pass rate).
- **Unit Tests**:
  - `VaultCipher`: 7/7 tests passing (key derivation, round-trip encryption/decryption, wrong PIN rejection, ciphertext tampering, tag tampering, truncated container).
  - `VaultAuthService`: 8/8 tests passing (unconfigured state, PIN setup, PIN length validation, secure session zeroing, verification & reset, 5-failure 30s lockout, master PIN change, biometric toggle & unlock).
  - `VaultStorageService`: 6/6 tests passing (locked access prevention, import with source deletion, in-memory decrypted bytes, export with collision handling, item deletion, empty vault).
- **Widget Tests**:
  - `VaultScreen`: 5/5 tests passing (unconfigured PIN prompt, short PIN validation, locked screen with PIN/biometrics, incorrect/correct PIN entry, unlocked dashboard, lock button).
  - `VaultSettingsScreen`: 1/1 test passing (all policies rendered).
  - `VaultPreviewScreen`: 1/1 test passing (in-memory text decryption and display).
  - `SecureShareDialog`: 1/1 test passing (warning dialog rendering and cancel handling).
- **Static Analysis**: `flutter analyze` reports **0 issues found** (clean).
