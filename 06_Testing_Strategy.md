# 06 — Testing Strategy

Testing is a first-class product requirement, not a final-stage activity.

## Test layers

1. Unit tests — domain logic, parsers, search, ranking, file rules.
2. Repository/service tests — database, filesystem adapters, cache, background jobs.
3. Widget/UI tests — screens, states, navigation, accessibility.
4. Integration tests — platform channels, storage providers, media/document engines.
5. Device tests — real Android devices across API levels and hardware classes.
6. Performance tests — startup, memory, indexing throughput, thumbnail generation, search latency.
7. Long-duration tests — large libraries and background indexing.
8. Failure tests — corrupt files, permissions, unavailable providers, interrupted operations.
9. Security tests — vault, permissions, data leakage, screenshot protection where supported.
10. Release tests — install, upgrade, migration, rollback-safe behavior.

## Required scenarios

- Android version matrix.
- Different screen sizes and orientations.
- Low-RAM devices.
- Large storage volumes.
- 100k+ files.
- Huge media files.
- Corrupted/unsupported files.
- Permission denial and revocation.
- Offline mode.
- App killed during background work.
- Background/foreground transitions.
- Dark/light themes.
- Accessibility.
- Notification failures.
- Ad provider failures.
- WAPCentral integration unavailable.
- Database migration.
- Interrupted copy/move/delete.
- Vault lock/unlock and recovery behavior.

## Quality gates

A phase is not complete if:
- required tests fail;
- known crashes remain unexplained;
- ANR risk is introduced;
- destructive operations are unsafe;
- permissions are handled incorrectly;
- user data can be silently lost;
- documentation does not match implementation.

## Performance targets

Exact numeric thresholds should be established during Phase 00 benchmarking rather than invented here. The architecture must nevertheless target fast startup, bounded memory, incremental indexing, low battery impact, cancellable background work, and responsive UI.
