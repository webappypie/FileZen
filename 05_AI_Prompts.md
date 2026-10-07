# 05 — AI Development Prompts

This file is the prompt-system index. Detailed prompts are stored under `prompts/`.

## Prompt design rules

Every phase prompt must:
- state the phase objective;
- tell the AI to read the project documentation first;
- define scope and explicit non-scope;
- require repository inspection before edits;
- require implementation in small safe steps;
- require tests;
- require fixes before completion;
- require review against requirements;
- require documentation updates;
- require Git commit and push;
- stop after the phase;
- never begin the next phase automatically.

## Prompt folders

- `phase-00-foundation`
- `phase-01-project-bootstrap`
- `phase-02-storage-access`
- `phase-03-indexing-search`
- `phase-04-file-manager`
- `phase-05-media-viewers`
- `phase-06-document-engine`
- `phase-07-ai-intelligence`
- `phase-08-cleanup-storage-intelligence`
- `phase-09-vault-security`
- `phase-10-notifications`
- `phase-11-network-transfer-cloud`
- `phase-12-analytics-monitoring`
- `phase-13-hardening-release`

Each folder contains a dedicated implementation prompt and may later contain supporting prompt fragments.
