# Non-Functional Requirements

## Performance

- Fast startup.
- Responsive UI.
- Incremental indexing.
- Bounded memory usage.
- Low battery impact.
- Efficient thumbnails.
- Cancellable background work.
- Safe large-file handling.
- ANR/crash prevention.

## Scale

The architecture must remain usable with tens of thousands of files and must be tested against 100k+ file libraries.

## Reliability

Core file management must work offline. Optional services must fail gracefully.

## Privacy

No automatic cloud upload of user files. Local processing is preferred. Sensitive information must not enter logs or analytics.

## Accessibility

Support scalable text, touch targets, screen-reader semantics, contrast, reduced-motion considerations where relevant, and clear focus/selection states.

## Compatibility

Support a defined Android API/device matrix approved during Phase 00.
