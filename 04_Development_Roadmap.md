# 04 — Development Roadmap

The roadmap is intentionally gated. Each phase is independently implemented, tested, reviewed, documented, committed, and pushed.

## Phase sequence

| Phase | Focus | Gate | Status |
|---|---|---|---|
| 00 | Foundation and architecture freeze | Approval of project documentation | Completed & Approved |
| 01 | Flutter project bootstrap | Build + baseline tests | Completed (Pending Approval) |
| 02 | Storage access and file abstraction | Real-device storage tests |
| 03 | Database, indexing and universal search | Large-library benchmarks |
| 04 | File manager operations and navigation | File-operation test suite |
| 05 | Media viewers and playback | Media compatibility tests |
| 06 | Document engine and PDF Studio | Document test matrix |
| 07 | Local AI intelligence | AI accuracy/fallback tests |
| 08 | Storage intelligence and cleanup | Safety/destructive-action tests | Completed (Pending Approval) |
| 09 | Vault and security | Security/privacy tests | Completed (Pending Approval) |
| 10 | Notifications Center | Notification and offline tests | Completed (Pending Approval) |
| 11 | Network transfer and cloud sources | Protocol/integration tests | Completed (Pending Approval) |
| 12 | Analytics, crash monitoring and WAPCentral app integration | Privacy/failure tests | Completed (Pending Approval) |
| 13 | Performance hardening and release | Full release gate | Completed (Pending Approval) |

## Remediation Sprints (Pre-Release Audit)

| Sprint | Focus | Audit Findings | Status |
|---|---|---|---|
| Sprint 1 | Absolute Release Gate | P0-01 (Signing), P0-06 (Backup Exclusion), P0-12 (ZIP Traversal), Finding 15 (Secrets) | Completed (Pending Approval) |
| Sprint 2 | Vault Security | P0-02 (AES-GCM), P0-03 (Biometrics), P0-04 (PIN), P0-05 (Manifest), P0-07 (FLAG_SECURE) | Pending |
| Sprint 3 | Billing & Ads | P0-08 (In-App Billing), P0-09 (Ad SDKs) | Pending |
| Sprint 4 | Local AI / OCR | P0-10 (Genuine OCR) | Pending |
| Sprint 5 | Cloud Provider Integrity | P0-11 (Cloud Providers) | Pending |
| Sprint 6 | Full Production Regression | Play Store compliance, performance, 100k+ file regression | Pending |

## Mandatory phase workflow

**IMPLEMENT → TEST → FIX → REVIEW → DOCUMENT → GIT COMMIT → GIT PUSH → STOP**

No next-phase work is allowed after STOP until explicit approval.

## Phase documentation

Every phase must record:
- objective;
- scope;
- dependencies;
- modules/files touched;
- implementation notes;
- test results;
- known issues;
- documentation updates;
- commit hash;
- push result;
- approval status.
