# 03 — Architecture

This file is the architecture index. Detailed architecture is split into focused documents.

## Architecture parts

1. `docs/03_Architecture/01_System_Architecture.md`
2. `docs/03_Architecture/02_Flutter_Dart_Architecture.md`
3. `docs/03_Architecture/03_Storage_Indexing_Architecture.md`
4. `docs/03_Architecture/04_AI_Architecture.md`
5. `docs/03_Architecture/05_UI_UX_Architecture.md`
6. `docs/03_Architecture/06_Security_Privacy_Architecture.md`
7. `docs/03_Architecture/07_Background_Performance_Architecture.md`
8. `docs/03_Architecture/08_External_Integrations.md`
9. `docs/03_Architecture/09_Error_Logging_Observability.md`
10. `docs/03_Architecture/10_Data_Models.md`
11. `docs/03_Architecture/11_Dependencies_and_Platform_Strategy.md`

## Architecture principles

- Feature modules must be independently testable.
- UI must not directly manipulate filesystem primitives.
- Repositories expose domain-oriented contracts.
- Platform-specific storage behavior is isolated behind adapters/services.
- Long-running operations must be cancellable and observable.
- Database/index operations must be incremental.
- AI must be replaceable and degrade gracefully.
- Cloud/network integrations must not contaminate local-only workflows.
- Secrets and provider configuration must not be hardcoded.
- Every destructive operation must have explicit user intent.
