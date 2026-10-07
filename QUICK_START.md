# FileZen — Quick Start

## Before coding

Read these files in order:

1. `README.md`
2. `01_Project_Vision.md`
3. `02_Master_PRD.md`
4. `03_Architecture.md`
5. `04_Development_Roadmap.md`
6. `06_Testing_Strategy.md`
7. `07_Release_Checklist.md`
8. `08_Credentials.md`
9. The relevant phase prompt under `prompts/`

Then read the detailed documents referenced by the relevant index files.

## AI-agent startup protocol

Before changing code:

- inspect the existing repository;
- inspect the current phase document;
- inspect the current phase prompt;
- identify dependencies and existing implementations;
- do not refactor unrelated modules;
- do not introduce a new library when an existing approved dependency already solves the problem;
- do not make product decisions silently;
- preserve offline-first behavior;
- preserve privacy boundaries;
- run the phase tests before declaring completion.

## Phase execution

For the active phase:

1. IMPLEMENT
2. TEST
3. FIX
4. REVIEW
5. DOCUMENT
6. GIT COMMIT
7. GIT PUSH
8. STOP

Report the commit hash and test result. Do not continue to the next phase without explicit approval.

## Secrets

Never place production credentials, API secrets, signing keys, private certificates, or user data in Git. `08_Credentials.md` contains only the credential inventory and sourcing rules.

## WAPCentral

Before implementing WAPCentral-controlled functionality, read the separately supplied `WAPCentral_App_Integration_Guide`. Treat it as authoritative for integration parameters and SDK wiring.
