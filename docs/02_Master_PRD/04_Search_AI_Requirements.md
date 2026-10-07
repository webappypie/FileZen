# Search and AI Requirements

## Local-first principle

Search planning and retrieval must use local indexes first. Cloud AI is optional and explicit.

## Universal search

Queries may combine:
- text;
- date;
- size;
- type;
- location/path;
- OCR;
- document text;
- metadata;
- category;
- semantic similarity where supported.

## Ask Your Files

Examples include finding the latest resume, PDFs containing a word, large videos, screenshots containing OTP, storage-heavy folders, receipts by month, recently modified documents, and likely ID images.

Results must be actionable file cards with Open, Share, Rename, Move, Favorite, and Details actions.

## AI Auto Rename

- Generate suggestions from local signals.
- Preview before applying.
- Support batch preview.
- Handle name collisions.
- Support undo.
- Never silently mass-rename.

## Smart Collections

Virtual by default. Files are not physically moved unless the user chooses to move them.

## AI failure behavior

If AI is unavailable, the underlying file operation/search must continue through deterministic local logic wherever possible.
