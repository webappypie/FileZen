# System Architecture

## Layers

```text
Presentation
  ↓
Application / Use Cases
  ↓
Domain
  ↓
Repositories
  ↓
Data / Platform Services
  ├─ Filesystem
  ├─ SAF
  ├─ Database
  ├─ Media
  ├─ Document engines
  ├─ Local AI
  ├─ Background workers
  └─ Optional integrations
```

## Key rule

UI never directly performs filesystem, database, network, or AI-provider work. UI invokes use cases/application services.

## Core modules

- app shell
- navigation
- file domain
- storage/indexing
- search
- media
- documents
- AI
- cleanup
- vault
- notifications
- integrations
- analytics/observability
- settings

## Dependency direction

Infrastructure depends on domain contracts; domain must not depend on concrete Android plugins. Platform adapters implement interfaces exposed by the domain/application layer.
