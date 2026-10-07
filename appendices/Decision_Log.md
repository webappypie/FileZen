# Decision Log

Use this file for explicit owner-approved architectural/product decisions.

| ID | Date | Decision | Rationale | Affected docs | Status |
|---|---|---|---|---|---|
| DEC-001 | 2026-10-08 | Local-first AI | Privacy, offline capability, cost | AI Architecture, PRD | Approved |
| DEC-002 | 2026-10-08 | Ads + one-time ad removal | Product monetization direction | PRD | Approved |
| DEC-003 | 2026-10-08 | WAPCentral as external integration boundary | Client-side only; boundary established in Phase 01 | Architecture, Integration | Approved |
| DEC-004 | 2026-10-08 | Bell-icon Notifications Center | Centralized user-facing notifications | PRD/Architecture | Approved |
| DEC-005 | 2026-10-08 | Riverpod for state management & DI | Consistent provider architecture; no get_it or Bloc | Flutter Architecture | Approved |
| DEC-006 | 2026-10-08 | SQLite + Drift + FTS5 for database & search | Type-safe, background indexing, scalable full-text search | Storage Architecture | Approved |
| DEC-007 | 2026-10-08 | Android-first/only for current V1 scope | Min SDK 24, Target SDK 35; iOS deferred to future roadmap | Platform Strategy | Approved |
| DEC-008 | 2026-10-08 | Firebase Android-only scope | google-services.json required; GoogleService-Info.plist omitted | Credentials, Setup | Approved |
| DEC-009 | 2026-10-08 | WAPCentral SDK sourcing from local project sdks/ | Located under D:/Mobile-App/WAPCentral/sdks/ | External Integrations | Approved |

Do not mark a decision approved without explicit owner approval.
