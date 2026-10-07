# FileZen Phase 07 — AI intelligence

## Role

You are the implementation AI agent for FileZen Mobile.

## Mandatory reading

Before editing code, read:
- `README.md`
- `QUICK_START.md`
- `01_Project_Vision.md`
- `02_Master_PRD.md`
- `03_Architecture.md`
- `04_Development_Roadmap.md`
- `06_Testing_Strategy.md`
- the relevant detailed documents for this phase;
- this phase prompt.

For WAPCentral work, also read the separately supplied `WAPCentral_App_Integration_Guide`.

## Objective

Implement local OCR/model integration, categorization, smart collections, AI rename, related files, semantic/local search signals, Ask Your Files query planning, and deterministic fallbacks.

## Rules

1. Inspect the existing repository before making changes.
2. Preserve approved architecture and existing working behavior.
3. Do not invent unresolved product decisions.
4. Do not silently expand scope.
5. Do not upload user files to cloud services unless an explicitly approved feature requires it.
6. Do not place secrets in source code, logs, tests, or Git.
7. Keep long-running work off the UI thread.
8. Add/update tests with implementation.
9. Handle loading, empty, error, permission-denied, offline, and cancellation states where relevant.
10. Keep changes focused on this phase.

## Required execution sequence

### 1. IMPLEMENT
Implement only the approved scope.

### 2. TEST
Run the relevant unit, integration, UI, and device tests. Add tests for newly introduced behavior.

### 3. FIX
Fix failures, regressions, crashes, performance problems, and unsafe edge cases.

### 4. REVIEW
Review the implementation against the PRD, architecture, security/privacy rules, accessibility expectations, and phase acceptance criteria.

### 5. DOCUMENT
Update affected documentation, schemas, decisions, known limitations, and test records.

### 6. GIT COMMIT
Create a focused commit:
`feat(filezen): phase 07 ai intelligence`

### 7. GIT PUSH
Push the commit to the configured repository/branch.

### 8. STOP
Do not start the next phase. Report:
- what changed;
- files/modules changed;
- tests run and results;
- known limitations;
- documentation updated;
- commit hash;
- push result;
- items requiring owner approval.

## Hard stop

If a required decision is missing, stop and mark it `OPEN DECISION` rather than guessing.
