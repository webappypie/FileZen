# FileZen — Independent Pre-Release Remediation Plan

**Status:** RELEASE BLOCKED  
**Purpose:** Remediate findings from the independent Claude pre-release audit before final Play Store submission.

---

## 1. Purpose & Source of Truth

This document is a **remediation/execution document** created from the independent pre-release audit findings.

It does **not** replace or rewrite the existing FileZen documentation.

The existing FileZen documentation remains the primary source of truth for:

- Product requirements
- Feature scope
- Architecture
- UI/UX
- Security model
- Development roadmap
- Phase definitions
- Testing strategy
- Release requirements

This document exists only to:

1. Capture the independent audit blockers.
2. Define the required remediation order.
3. Give the development AI a controlled fix workflow.
4. Prevent fake/stub implementations from reaching production.
5. Establish the verification gate before final release approval.

---

# 2. Current Release Status

## RELEASE BLOCKED

The independent audit identified critical production, security, billing, implementation, and release issues.

**Phase 13 must NOT be approved as release-complete yet.**

The application must remain in remediation until all release-blocking findings are fixed and independently re-audited.

---

# 3. Critical Findings Identified

The following findings were reported by the independent Claude audit.

## P0-01 — Release Signing Uses Debug Key

### Finding

The release APK is reportedly signed using the debug signing key.

### Risk

Google Play release submission cannot proceed with an incorrectly configured release signing setup.

### Required remediation

- Configure proper production release signing.
- Use the correct release keystore.
- Never commit the private keystore/password to Git.
- Verify release signing configuration.
- Verify generated release APK/AAB.
- Confirm debug signing is not used by release builds.
- Verify application ID and signing configuration.
- Verify R8/release configuration.
- Perform a clean release build after fixing.

### Acceptance criteria

- Release build is signed with the intended production/release key.
- Debug signing is impossible for the production release variant.
- No signing secrets are committed to the repository.
- Release AAB/APK passes signing verification.

---

# 4. P0-02 — Vault Encryption Is Not the Required AES-256-GCM Implementation

### Finding

The audit reports that the current implementation uses a homebrew HMAC-SHA256/CTR-style construction rather than the required AES-256-GCM encryption.

### Risk

The implementation does not satisfy the documented Vault security architecture and may provide inadequate confidentiality/integrity guarantees.

### Required remediation

Replace the unsafe custom construction with a properly designed authenticated-encryption implementation using:

- Android Keystore
- AES-256-GCM
- cryptographically secure random IV/nonce per encryption operation
- authentication tag verification
- secure key lifecycle
- authenticated metadata where required

Do not invent a custom cryptographic protocol.

Do not reuse IVs/nonces with the same key.

### Migration requirement

Determine whether existing vault data needs migration.

Do not silently destroy existing user vault data.

If migration is required:

1. Detect legacy vault format.
2. Safely decrypt legacy data only where possible.
3. Re-encrypt using the new secure format.
4. Verify integrity.
5. Preserve user files.
6. Provide safe failure/recovery behavior.

### Acceptance criteria

- AES-256-GCM is actually used.
- Keys are protected using Android Keystore.
- IV/nonce uniqueness is guaranteed.
- Authentication failures are handled safely.
- No plaintext sensitive vault content remains unnecessarily on disk.
- Tests cover encryption/decryption, tampering, wrong key/PIN, corruption, and migration.

---

# 5. P0-03 — Biometric Vault Authentication Is a Stub

### Finding

The audit reports that the biometric flow does not actually invoke the Android biometric API and effectively unlocks without genuine biometric verification.

### Risk

This is a critical security failure.

### Required remediation

Implement real Android biometric authentication using the appropriate Android biometric APIs.

Verify:

- biometric prompt
- authentication success
- authentication failure
- cancellation
- lockout
- unavailable biometric hardware
- no enrolled biometric
- device credential fallback if intentionally supported
- lifecycle interruption
- app background/foreground transitions
- vault lock state

The Flutter layer must not be able to bypass native authentication.

### Acceptance criteria

- Vault unlock requires genuine authentication.
- Failed authentication never unlocks the vault.
- No fake/mock biometric success remains in production.
- Automated/unit/platform tests cover failure paths.

---

# 6. P0-04 — Vault Uses Plaintext PIN in Memory / Public Getter

### Finding

The audit reports that the active PIN is retained as a plaintext String and exposed through a public getter.

### Required remediation

- Remove unnecessary plaintext PIN retention.
- Never expose the PIN through public getters/logging/state.
- Review PIN verification architecture.
- Use secure derivation/storage appropriate to the documented design.
- Minimize sensitive data lifetime in memory.
- Remove debug logging of authentication data.
- Ensure sensitive state is cleared as soon as practical.

### Acceptance criteria

- No plaintext PIN is persisted to disk.
- No public API exposes the active PIN.
- No logs contain the PIN.
- No analytics/crash payload contains the PIN.
- Authentication tests pass.

---

# 7. P0-05 — Vault Manifest Exposes File Names/Paths

### Finding

The audit reports that the Vault manifest contains file names/paths in plaintext.

### Risk

Vault contents can potentially be enumerated without successful Vault authentication.

### Required remediation

Review the vault metadata architecture.

Protect sensitive metadata such as:

- filenames
- original paths
- internal paths
- thumbnails
- metadata
- relationships

Where appropriate, encrypt sensitive metadata and ensure unauthenticated users cannot enumerate Vault contents.

### Acceptance criteria

- Vault filenames are not unnecessarily exposed in plaintext.
- Original user paths are protected.
- Vault thumbnails/previews cannot leak content.
- File enumeration requires proper authentication.

---

# 8. P0-06 — Vault Data Is Not Properly Excluded From Backup

### Finding

The audit reports that Vault data can be included in Android/ADB backup.

### Risk

Encrypted vault files plus authentication-related material could be extracted together.

### Required remediation

Review Android backup behavior and explicitly protect Vault data from inappropriate backup/export.

Review:

- backup rules
- Auto Backup
- device transfer
- debug/ADB backup behavior where applicable
- exported files
- cache
- temporary files

### Acceptance criteria

- Vault secrets/data are not unintentionally backed up.
- Vault files cannot be restored into an unsafe state.
- Backup configuration is explicitly tested.

---

# 9. P0-07 — FLAG_SECURE Is Not Actually Applied

### Finding

The audit reports that screenshot protection is stored as application state but is not applied to the Android Window.

### Required remediation

Implement actual Android window-level screenshot protection.

Verify:

- Vault screen
- Vault previews
- sensitive authentication screens
- transitions
- background/foreground behavior
- multi-window behavior where relevant

### Acceptance criteria

Screenshot/screen-recording protection is enforced at the Android Window level for the intended sensitive screens.

---

# 10. P0-08 — Billing / Ad Removal Is a Free Local Boolean Bypass

### Finding

The audit reports that tapping the ad-removal purchase effectively sets an `isAdFreePurchased` state without real Google Play Billing.

### Risk

This is not a valid production purchase implementation.

### Required remediation

Implement the documented one-time ad-removal purchase using the current Google Play Billing requirements.

Verify:

- product ID
- product configuration
- purchase flow
- purchase acknowledgement
- purchase state
- pending purchases
- failed purchases
- restored purchases
- reinstall behavior
- device/account restoration
- entitlement state
- cancellation
- refund/revocation behavior
- offline/degraded behavior
- duplicate handling

Never grant permanent purchase entitlement solely because a UI button was tapped.

### Acceptance criteria

- Real Google Play Billing is used.
- Entitlement is based on verified purchase state.
- Purchase restoration works.
- No local boolean can unlock premium/ad-free status without valid entitlement.
- Billing failures are handled safely.

---

# 11. P0-09 — Ad Integrations Are Placeholders

### Finding

The audit reports that claimed AdMob/Meta/AppLovin advertising currently renders placeholder/gray boxes instead of real production ad integrations.

### Required remediation

Determine which ad networks are actually enabled by the current WAPCentral/FileZen configuration.

For each enabled network:

- verify real SDK integration
- verify initialization
- verify test-ad configuration
- verify production configuration
- verify ad loading
- verify ad failure fallback
- verify frequency controls
- verify consent/privacy requirements
- verify placement safety

Do not claim a network is integrated when it is only represented by a placeholder.

### Acceptance criteria

- Production ad behavior matches the actual implementation.
- Test ads are used during testing.
- Production ad IDs/configuration are separated appropriately.
- Failed ads do not break FileZen.
- No deceptive ad placement exists.

---

# 12. P0-10 — OCR Is a Stub / Not Genuine OCR

### Finding

The audit reports that the current OCR behavior is based on filename keywords and/or JPEG ASCII header inspection rather than genuine OCR.

### Required remediation

Implement the documented on-device OCR architecture.

The FileZen PRD requires local OCR capability for intelligence/search workflows.

Use the approved on-device OCR implementation and verify:

- actual image text recognition
- supported image formats
- rotation
- multilingual text where supported
- confidence/failure handling
- background processing
- indexing integration
- no silent cloud upload

### Acceptance criteria

- OCR processes actual image pixels.
- OCR results are not generated from filenames as a substitute.
- OCR output is correctly stored/indexed.
- OCR works offline where the model is available.
- OCR failures degrade gracefully.

---

# 13. P0-11 — Cloud Providers Are Fake/Stubs

### Finding

The audit reports that Google Drive/OneDrive functionality returns hardcoded file lists and writes placeholder text instead of performing real provider operations.

### Required remediation

Do not ship fake cloud functionality.

For every provider exposed in the UI:

- implement genuine provider authentication
- list files from the provider
- retrieve metadata
- download actual files
- handle authentication expiry
- handle network failures
- handle permission failures
- handle rate limits
- safely disconnect/revoke access

If a provider is not production-ready, do not present it as a working feature.

### Acceptance criteria

- Every enabled cloud provider performs genuine operations.
- No hardcoded fake file lists remain.
- No fake downloads remain.
- Unsupported/incomplete providers are clearly disabled or removed from production UI.

---

# 14. P0-12 — ZIP Path Traversal

### Finding

The audit reports a potential archive extraction path-traversal vulnerability.

### Required remediation

Harden archive extraction against:

- `../`
- absolute paths
- canonical path escape
- malicious nested paths
- symlink attacks where applicable
- archive bombs
- excessive extraction size
- excessive file counts

Every extracted destination must be validated against the intended destination directory.

### Acceptance criteria

Malicious archives cannot write outside the selected extraction directory.

Add security regression tests for traversal payloads.

---

# 15. Hardcoded Secret / Credential Exposure

The independent audit also reported a hardcoded secret.

### Required remediation

- Identify the secret.
- Remove it from source code.
- Rotate/revoke it if it has been exposed.
- Remove unsafe copies from configuration.
- Review Git history if the secret was committed.
- Move appropriate runtime configuration to a secure mechanism.
- Ensure production credentials are not bundled unnecessarily.

### Acceptance criteria

No production secret is exposed in the source repository or application bundle unless its exposure is explicitly required and safe.

---

# 16. Play Store Compliance Gate

After implementation fixes, perform another independent policy review covering at minimum:

- storage/file permissions
- `MANAGE_EXTERNAL_STORAGE` justification if used
- media permissions
- user data
- Data Safety declarations
- privacy policy
- ads
- advertising identifiers
- third-party SDK behavior
- notifications
- billing
- in-app product declarations
- app claims
- screenshots/store listing
- background behavior
- sensitive data handling

Do not submit until all release-blocking policy findings are resolved.

---

# 17. Remediation Sprint Order

## Sprint 1 — Absolute Release Gate

Fix first:

1. Release signing
2. Hardcoded secret
3. ZIP traversal
4. Backup exclusion
5. Release configuration
6. Play Store permission/declaration readiness

Then:

`IMPLEMENT → TEST → FIX → REVIEW → DOCUMENT → GIT COMMIT → GIT PUSH → STOP`

Do not start Sprint 2 automatically.

---

## Sprint 2 — Vault Security

Fix:

1. AES-256-GCM
2. Android Keystore
3. secure IV/nonce
4. biometric authentication
5. PIN handling
6. protected metadata
7. screenshot protection
8. backup protection
9. migration/recovery

Then test and STOP.

---

## Sprint 3 — Billing & Ads

Fix:

1. Google Play Billing
2. purchase acknowledgement
3. entitlement
4. restore
5. refund/revocation handling
6. actual enabled ad SDKs
7. ad placement safety
8. ad failure handling
9. test/production ad configuration

Then test and STOP.

---

## Sprint 4 — Local AI / OCR

Fix:

1. genuine on-device OCR
2. OCR indexing
3. background processing
4. offline behavior
5. OCR error handling

Then verify existing AI features against the PRD.

Then test and STOP.

---

## Sprint 5 — Cloud Provider Integrity

For each provider actually enabled:

1. real authentication
2. real file listing
3. real metadata
4. real download/upload if supported
5. error handling
6. authentication expiry
7. disconnect/revoke

Any unfinished provider must be disabled from production UI rather than shipped as a fake implementation.

Then test and STOP.

---

## Sprint 6 — Full Production Regression

Run:

- functional regression
- security regression
- performance tests
- 100k+ file tests
- offline tests
- low-storage tests
- permission denial tests
- lifecycle tests
- crash/ANR tests
- release AAB verification
- Play Store policy review
- Data Safety review
- ads review
- billing review

---

# 18. Mandatory Development Workflow

Every sprint must follow:

`READ → IMPLEMENT → TEST → FIX → REVIEW → DOCUMENT → GIT COMMIT → GIT PUSH → STOP`

Do not automatically continue to the next sprint.

After each sprint, provide:

- files changed
- features fixed
- tests executed
- test results
- remaining findings
- Git commit
- push status
- known risks

---

# 19. Important Anti-Shortcut Rules

The following are NOT acceptable fixes:

- hiding a broken feature and claiming it is complete
- replacing real OCR with filename heuristics
- replacing real billing with a local boolean
- replacing real ads with placeholder UI
- pretending cloud providers work
- weakening Vault security to make tests pass
- disabling security checks
- suppressing errors instead of fixing the root cause
- removing a feature from the UI without documenting the product impact
- changing the PRD simply to make the current implementation appear compliant

If a documented production feature cannot be completed safely, report it as incomplete and stop for owner approval.

---

# 20. Final Release Gate

FileZen must NOT be marked release-ready until:

- all P0 findings are fixed
- all P1 findings are fixed or explicitly approved
- release signing is verified
- Vault security is independently verified
- Billing is independently verified
- Ads are independently verified
- permissions are independently verified
- Data Safety/privacy disclosures match implementation
- release AAB is verified
- regression tests pass
- no known critical security vulnerability remains
- no fake/stub production feature remains for a claimed feature
- independent Claude re-audit passes

Final state:

`RELEASE READY — INDEPENDENT AUDIT PASSED`

Only then should the final Play Store submission process begin.

---

# APPENDIX A — GEMINI REMEDIATION MASTER PROMPT

Copy the following prompt to the development AI.

---

## FileZen — Independent Audit Remediation Master Prompt

You are now responsible for remediating the independent pre-release audit findings for FileZen.

The application was previously developed using your development workflow, but an independent Claude audit has identified serious release blockers.

**Do not assume the existing implementation is correct.**

Your first task is to understand this remediation document and the complete existing FileZen documentation before changing code.

### STEP 1 — READ FIRST

Read:

1. Existing FileZen README
2. Master PRD
3. Architecture documentation
4. UI/UX documentation
5. Development roadmap
6. Testing strategy
7. Release checklist
8. Relevant phase documentation
9. Phase 13 documentation
10. `FileZen_PreRelease_Remediation_Plan.md`

Do not rewrite these documents.

The existing FileZen documentation remains the source of truth.

This remediation document only defines the fixes required after the independent audit.

### STEP 2 — INSPECT BEFORE CODING

Before modifying code, map:

`Audit Finding → Existing Implementation → Affected File/Class → Root Cause → Required Fix → Tests Required`

Inspect the actual code.

Do not rely on the audit summary alone.

If an audit finding is already fixed in the current repository, verify it with code/tests instead of blindly changing it.

If confirmed, fix the root cause.

### STEP 3 — EXECUTE IN SPRINT ORDER

Start with **Sprint 1 only**.

Do not start Sprint 2 automatically.

After Sprint 1:

`IMPLEMENT → TEST → FIX → REVIEW → DOCUMENT → GIT COMMIT → GIT PUSH → STOP`

Wait for explicit owner approval:

`Start Sprint 2`

Then continue similarly for each sprint.

### CRITICAL RULES

Do NOT:

- invent APIs
- invent SDK behavior
- replace real functionality with mocks
- keep fake implementations
- hide incomplete functionality
- weaken security
- bypass billing
- bypass biometric authentication
- use custom cryptography when a standard secure implementation is required
- expose secrets
- commit keystores/passwords
- silently change product requirements

Use the existing architecture unless a security or correctness issue requires a documented architectural change.

If an architectural change is required, document:

- old design
- problem
- new design
- reason
- migration impact
- tests

### SECURITY PRIORITY

Security fixes have priority over cosmetic improvements.

Protect:

- Vault files
- Vault metadata
- PIN/authentication state
- encryption keys
- user documents
- user images/videos
- OCR content
- extracted text
- cloud credentials
- billing state
- production secrets

### FINAL REPORT FOR EACH SPRINT

Provide:

```text
SPRINT:
STATUS:

Audit findings addressed:
- ...

Files changed:
- ...

Security changes:
- ...

Tests executed:
- ...

Test results:
- ...

Remaining blockers:
- ...

Documentation updated:
- ...

Git commit:
- ...

Git push:
- ...

NEXT ACTION:
STOP — WAITING FOR OWNER APPROVAL
```

Do not claim completion without evidence.

---

# APPENDIX B — CLAUDE RE-AUDIT PROMPT

After Gemini completes all remediation sprints, give Claude this prompt:

> Perform a second independent pre-release audit of FileZen.
>
> The previous audit identified P0/P1 findings. Do not assume the developer actually fixed them.
>
> For every previous finding:
>
> 1. Locate the affected implementation.
> 2. Verify the actual code.
> 3. Run or inspect relevant tests.
> 4. Confirm the root cause is fixed.
> 5. Check for regressions.
> 6. Check whether the fix introduced a new security or policy issue.
>
> Pay particular attention to:
>
> - production release signing
> - Vault AES-256-GCM
> - Android Keystore
> - biometric authentication
> - PIN handling
> - Vault metadata privacy
> - backup exclusion
> - FLAG_SECURE
> - Google Play Billing
> - ad SDK integrations
> - ad placement policy
> - OCR implementation
> - cloud provider implementations
> - ZIP traversal
> - hardcoded secrets
> - storage permissions
> - Data Safety
> - privacy
> - third-party SDK behavior
> - crash/ANR
> - 100k+ file performance
> - offline behavior
>
> Do not accept:
>
> - commit messages as proof
> - developer claims as proof
> - UI hiding as a fix
> - mocks/stubs as production implementations
> - screenshots as proof of security
>
> Provide an evidence-based final verdict:
>
> `RELEASE BLOCKED`
>
> or
>
> `CONDITIONALLY READY`
>
> or
>
> `RELEASE READY`
>
> Release is allowed only when all critical blockers are demonstrably fixed.

---

# 21. Final State

Current state:

`RELEASE BLOCKED`

Next action:

**Read this document → execute Sprint 1 → test → commit → push → STOP.**

Do not approve Phase 13 as final release-complete until remediation and independent re-audit have passed.
