# FileZen Mobile — Documentation Repository

FileZen is an advanced, premium, AI-powered mobile file manager built as a long-term production application.

**Positioning:** Your files, understood by AI.

## Documentation philosophy

This repository is intentionally modular. Product requirements, UX, architecture, implementation prompts, testing, release operations, and integration boundaries are separated so that both human developers and AI coding agents can consume the project safely.

### Source of truth hierarchy

1. Current approved product decisions in this documentation repository.
2. The attached/source FileZen Master PRD supplied for this project.
3. Explicit decisions made by the project owner in the conversation.
4. Approved phase documents and implementation prompts.
5. General engineering best practices only where the project documentation does not already define a decision.

If a requirement is ambiguous, do not invent a product decision. Mark it as `OPEN DECISION` and stop at the relevant approval gate.

## Repository structure

```text
FileZen/
├── README.md
├── QUICK_START.md
├── 01_Project_Vision.md
├── 02_Master_PRD.md
├── 03_Architecture.md
├── 04_Development_Roadmap.md
├── 05_AI_Prompts.md
├── 06_Testing_Strategy.md
├── 07_Release_Checklist.md
├── 08_Credentials.md
├── docs/
│   ├── 02_Master_PRD/
│   ├── 03_Architecture/
│   ├── 04_Development_Roadmap/
│   ├── 06_Testing_Strategy/
│   └── 07_Release_Checklist/
├── prompts/
│   ├── phase-00-foundation/
│   ├── phase-01-project-bootstrap/
│   └── ...
└── appendices/
```

## Mandatory development gate

No implementation starts until Product Vision, Master PRD, Feature List, User Flows, Screen Architecture, UX Architecture, Technical Architecture, AI Architecture, Storage Architecture, Security/Privacy, Monetization, Testing Strategy, and Development Roadmap are explicitly approved.

Every implementation phase follows:

**IMPLEMENT → TEST → FIX → REVIEW → DOCUMENT → GIT COMMIT → GIT PUSH → STOP**

The next phase must not begin until the project owner explicitly approves it.

## WAPCentral boundary

WAPCentral is an external central control/integration system. FileZen documentation must define only the app-side integration contract. The separate `WAPCentral_FileZen_Integration_Guide` is the implementation source for app ID, x-app-key, Firebase configuration, SDK integration, notification/ad control, and related credentials/configuration. Do not duplicate WAPCentral infrastructure design here.

## Notification requirement

FileZen includes a bell-icon Notifications Center. It supports manual/admin notifications, app-generated notifications, unread/read state, individual dismissal, and Clear All. The app must remain usable if notification services are unavailable.

## Monetization

Normal FileZen functionality remains available to all users. Monetization is primarily non-intrusive advertising plus a one-time purchase to remove ads. Subscription paywalls are not part of normal V1 functionality.

## AI principle

On-device/local processing is the default. Cloud AI is an explicit fallback for cases where it is genuinely required and must never silently upload user files.

## Current status

This documentation package defines the planned product and engineering structure. Coding begins only after explicit approval and after the phase-00 foundation gate is completed.

## GitHub Repository

- Repository URL: `https://github.com/webappypie/FileZen.git`
- Primary Branch: `main`