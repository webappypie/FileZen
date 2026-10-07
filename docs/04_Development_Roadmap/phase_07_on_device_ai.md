# Phase 07 — On-Device AI, OCR & Intelligence Engine

## Objective
Establish a 100% on-device, local-first intelligence and AI engine for FileZen that operates with zero cloud uploads and full offline functionality. The engine introduces:
1. **On-Device OCR & Text Extraction**: Extracts searchable text tokens from images, screenshots, receipts, and documents, ingesting them directly into SQLite and FTS5 full-text indexing tables.
2. **"Ask Your Files" (Natural Language Search)**: Rule-based heuristic NLP intent parsing converting natural language requests (e.g., resumes, OTP screenshots, receipts & invoices, large videos, recent documents, ID cards) into structured queries with relevance post-ranking.
3. **AI Auto-Rename Engine**: Contextual renaming suggestions based on document headers, OCR tokens, camera photo date stamps, and ugly/messy filename sanitization, featuring collision prevention (`_1`, `_2`), batch execution, and an instant undo stack.
4. **Smart Collections (Virtual Semantic Clusters)**: Dynamic, metadata-driven categorization without physical file movement across Invoices & Receipts, Identity & Cards, Screenshots, Large Media (>50MB), Code & Projects, and Archives.
5. **Related Files Intelligence**: Identifies companion assets and associated files based on directory naming patterns, timestamp proximity (<=15 minutes), and FTS5 semantic keyword overlap.

---

## Architecture & Design Principles

### 1. 100% On-Device & Privacy-Preserving
- No third-party AI cloud APIs or external server round-trips.
- User files, extracted OCR text, and search tokens remain strictly isolated on the physical device.
- Full offline availability with zero battery-draining network background processes.

### 2. Clean Architecture Integration
```
Presentation Layer:
  - AiScreen (AI Hub & Dashboard)
  - AutoRenameScreen (AI Auto-Rename Studio)
  - CollectionDetailScreen (Virtual Semantic Collection Viewer)
  - RelatedFilesSheet (Companion & Related Files Modal)
        ↓
Riverpod Providers:
  - ai_providers.dart (Services, query state, intent interpretation, undo history)
        ↓
Domain Interfaces & Models:
  - IOcrService, IQueryInterpreterService, IAutoRenameService,
    ISmartCollectionsService, IRelatedFilesService
  - OcrExtractionResult, NaturalQueryIntent, SpecialQueryIntent,
    AutoRenameSuggestion, AutoRenameHistoryItem, SmartCollection, RelatedFileItem
        ↓
Data Services:
  - OcrService, QueryInterpreterService, AutoRenameService,
    SmartCollectionsService, RelatedFilesService
        ↓
Storage & Search Engine:
  - SQLite (Drift) & FTS5 full-text indexing virtual tables
```

---

## Detailed Components

### 1. On-Device OCR Engine (`OcrService`)
- Fast, local ASCII and header text inspection for image containers and documents.
- Pattern-based heuristic recognition identifying verification codes/OTPs, receipts, and invoices.
- Integrated into `TextExtractor` and `IndexingService`, allowing images to be searched immediately via FTS5 by their visible textual contents.

### 2. "Ask Your Files" NLP Query Interpreter (`QueryInterpreterService`)
- Heuristic intent recognition parsing natural phrases:
  - `SpecialQueryIntent.resume`: Filters documents, matches resume/CV keywords, sorts by most recently modified.
  - `SpecialQueryIntent.otpScreenshot`: Filters images, matches screenshot and OTP/verification keywords.
  - `SpecialQueryIntent.receiptOrInvoice`: Filters financial terms (receipt, invoice, bill, tax, payment).
  - `SpecialQueryIntent.idCard`: Matches identity documents (passport, license, card, Aadhaar).
  - `SpecialQueryIntent.largeVideos`: Filters video category, enforces minimum size thresholds (e.g. 50MB, 100MB, 1GB), sorts descending by file size.
  - `SpecialQueryIntent.recentDocuments`: Filters documents modified within the last 7 days.
- Structured FTS5 query synthesis using boolean `OR` for expanded semantic synonyms and `AND` for multi-word general queries.

### 3. AI Auto-Rename Studio (`AutoRenameService`)
- Proposes clean, descriptive filenames from multiple local signals:
  - Markdown / Text headings: Extracts `# Heading` or primary title line.
  - Camera photos: Transforms messy names like `IMG_20261008_153022.jpg` to clean timestamp format `Photo_2026-10-08_153022.jpg`.
  - Screenshots: Adds contextual tags such as `Screenshot_Receipt_2026-10-08` or `Screenshot_OTP_2026-10-08`.
  - Messy files: Removes trailing copy suffixes like ` (1)`, `_copy`, and duplicate separators.
- Automatic collision avoidance appending numeric suffixes (`_1`, `_2`) when target filenames already exist in the directory.
- Atomic file renaming backed by `IStorageRepository` and a reversible undo stack.

### 4. Smart Collections (`SmartCollectionsService`)
- Predefined virtual clusters:
  1. **Invoices & Receipts**: Financial receipts, invoices, statements, tax papers.
  2. **Identity & Cards**: Passports, licenses, identity certificates.
  3. **Screenshots**: Screen captures and verification clips.
  4. **Large Media**: Media items occupying 50MB or more of device storage.
  5. **Code & Projects**: Source code, scripts, configuration files, and schemas.
  6. **Archives**: ZIP, TAR, 7Z, GZ compressed bundles.
- Dynamically queries indexed files without duplicating or moving physical files on disk.

### 5. Related Files Intelligence (`RelatedFilesService`)
- Discovers companion files based on three signals:
  - Directory sibling prefix/suffix match (e.g., `contract.docx` and `contract_signed.pdf`).
  - Shared topic token in the same directory.
  - Creation/modification time proximity (modified within 15 minutes of each other).
  - Cross-storage FTS5 semantic keyword overlap.

---

## Verification & Testing
- **Unit Tests (`test/unit/ai_services_test.dart`)**:
  - `OcrService`: Verified offline availability, ASCII extraction, receipt detection, and empty file handling.
  - `QueryInterpreterService`: Verified NLP parsing for resumes, OTP screenshots, large videos, receipts, identity documents, and end-to-end execution against in-memory SQLite/FTS5 database.
  - `AutoRenameService`: Verified photo date stamp formatting, heading extraction, collision suffix generation (`_1`), atomic rename, and undo restoration.
  - `SmartCollectionsService`: Verified dynamic counting and size aggregation across predefined collections.
  - `RelatedFilesService`: Verified companion file matching by prefix, time proximity, and path normalization.
- **Widget Tests (`test/widget/ai_screen_test.dart`)**:
  - `AiScreen`: Verified privacy badge, search bar, prompt chips, query interpretation banner, actionable file cards, smart collection grid cards, and studio navigation.
  - `AutoRenameScreen`: Verified tab switching, directory scanning, and action buttons.
  - `CollectionDetailScreen`: Verified file listing and open actions.
  - `RelatedFilesSheet`: Verified companion file presentation.
