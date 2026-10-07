# Storage and Indexing Architecture

## Pipeline

```text
Storage Sources
 → Scanner
 → Change Detection
 → Metadata Extraction
 → Content/OCR Extraction
 → Classification
 → Index Writer
 → Search/Query Layer
```

## Requirements

- Incremental indexing.
- Resume after interruption.
- Prioritize recently changed files.
- Avoid rescanning unchanged content.
- Batch database writes.
- Throttle background work based on battery/charging/system conditions.
- Avoid keeping entire libraries in memory.
- Maintain index versioning for schema/model changes.

## File identity

Prefer stable platform/document identifiers where available. Fall back to normalized path plus metadata/signature when necessary. Identity strategy must handle renames/moves without creating avoidable duplicates.

## Duplicate detection

Use tiers:
1. cheap metadata candidates;
2. cryptographic hash for exact duplicates;
3. media similarity signals for similar items.

Never delete solely because an algorithm labels two items as duplicates.

## Database and Search Engine Baseline

Approved in Phase 00:
- **Primary Engine:** SQLite with Drift (`drift`, `drift_flutter`) abstraction.
- **Search Index:** SQLite FTS5 for high-performance full-text search across filenames, paths, tags, extracted document text, and OCR text.
- **Thread Isolation:** Database writes, scans, checksums, and indexing are isolated from the Flutter UI thread using background workers and throttled based on battery/charging conditions.
