# Error, Logging and Observability Architecture

## Error model

Use typed/domain errors rather than raw platform exceptions leaking to UI.

Suggested categories:
- permission;
- file-not-found;
- access-denied;
- storage-full;
- unsupported-format;
- corrupted-file;
- cancelled;
- timeout;
- provider-unavailable;
- AI-unavailable;
- database;
- unknown.

## Logging

Logs must be structured and privacy-safe.

Never log:
- file contents;
- OCR text;
- vault content;
- user secrets;
- access tokens;
- x-app-key;
- sensitive file paths where unnecessary.

## Crash monitoring

Crash reports should include technical context needed for diagnosis without transmitting private file content.

## Performance monitoring

Track aggregate startup, screen responsiveness, background job duration, indexing throughput, memory pressure, and failure rates subject to privacy policy.
