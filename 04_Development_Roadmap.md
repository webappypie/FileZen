# 04 — Development Roadmap

The roadmap is intentionally gated. Each phase is independently implemented, tested, reviewed, documented, committed, and pushed.

## Phase sequence

| Phase | Focus | Gate |
|---|---|---|
| 00 | Foundation and architecture freeze | Approval of project documentation |
| 01 | Flutter project bootstrap | Build + baseline tests |
| 02 | Storage access and file abstraction | Real-device storage tests |
| 03 | Database, indexing and universal search | Large-library benchmarks |
| 04 | File manager operations and navigation | File-operation test suite |
| 05 | Media viewers and playback | Media compatibility tests |
| 06 | Document engine and PDF Studio | Document test matrix |
| 07 | Local AI intelligence | AI accuracy/fallback tests |
| 08 | Storage intelligence and cleanup | Safety/destructive-action tests |
| 09 | Vault and security | Security/privacy tests |
| 10 | Notifications Center | Notification and offline tests |
| 11 | Network transfer and cloud sources | Protocol/integration tests |
| 12 | Analytics, crash monitoring and WAPCentral app integration | Privacy/failure tests |
| 13 | Performance hardening and release | Full release gate |

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
