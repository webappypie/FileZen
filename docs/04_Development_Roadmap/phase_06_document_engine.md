# Phase 06 — Document Engine & PDF Studio

## Objective
Establish an advanced, on-device document rendering and productivity engine for FileZen: multi-format text and code viewing with syntax and line numbers, in-document search and live text editing with atomic persistence; high-performance Markdown rendering with source code toggle; interactive CSV spreadsheet table viewing with row and cell filtering; PDF viewing with interactive page navigation and metadata inspection; and a comprehensive PDF Studio suite for converting images to PDF, merging multiple PDF files, and extracting selected page ranges into standalone PDF documents.

## Scope
- Domain Models & Enums:
  - `DocumentType`: Enum categorizing documents into `markdown`, `plainText`, `csv`, `json`, `xml`, `code`, `pdf`, and `unsupported` with display name helpers and format capabilities (`isMarkdown`, `isCsv`, `isPdf`).
  - `DocumentMetadata`: Model encapsulating document metrics including `filePath`, `type`, `fileSize`, `lineCount`, `wordCount`, `characterCount`, `encoding`, and `isEditable`.
  - `PdfDocumentInfo`: Model capturing PDF container metadata including `filePath`, `pageCount`, `fileSize`, `title`, `author`, `subject`, `creator`, `creationDate`, and encryption status (`isEncrypted`).
  - `PdfOperationResult`: Model reporting operation outcomes for PDF Studio actions (`success`, `outputPath`, `pagesProcessed`, `outputSizeBytes`, `errorMessage`).
- Document Engine Service:
  - `IDocumentService` & `DocumentService`:
    - File extension and content analysis to resolve document types across text formats, source code (.dart, .py, .js, .ts, .java, .kt, .c, .cpp, .cs, .sh, .bat, .ps1, .yaml, .yml, .toml, .sql), markup (.xml, .html, .htm), CSV/TSV spreadsheets, and PDF documents.
    - Pure Dart UTF-8 document reading with byte limitations to protect memory on large files.
    - Fast metrics analysis computing line counts, word counts, character counts, and editability.
    - Atomic text file saving (`saveDocumentText`) with UTF-8 flushing.
    - CSV spreadsheet parsing powered by `csv: ^6.0.0` with CRLF/LF normalization and quoted string handling.
- PDF Studio Service:
  - `IPdfStudioService` & `PdfStudioService`:
    - Binary header and trailer inspection for fast on-device extraction of PDF metadata (Title, Author, Creator, CreationDate, Page count, and Encryption detection) with fallback to `pdfx`.
    - Pure-Dart Images-to-PDF compilation leveraging `pdf: ^3.12.0` with A4 page formatting and margin management.
    - Multi-PDF document merging with high-resolution page rendering and compilation.
    - Arbitrary page extraction and page range parsing (e.g. `1, 3-5`) into new PDF documents.
- Riverpod Presentation Architecture:
  - `document_providers.dart`:
    - `documentServiceProvider`: Service provider for text analysis and CSV parsing.
    - `pdfStudioServiceProvider`: Service provider for PDF studio operations.
    - `documentTextProvider`: FutureProvider loading UTF-8 document content.
    - `documentMetadataProvider`: FutureProvider analyzing document metrics.
    - `csvTableDataProvider`: FutureProvider parsing CSV tabular rows.
- Presentation Screens & UI Components:
  - **`DocumentViewerScreen`**:
    - Clean Material 3 top app bar with document title and type subtitle.
    - Live in-document search mode with filter and clear action.
    - Rendered Markdown view backed by `flutter_markdown_plus`.
    - Raw source toggle switching between rendered Markdown/CSV and monospaced text.
    - Interactive CSV DataTable with horizontal and vertical scrolling, header formatting, and real-time text query filtering across columns.
    - Monospaced code and plain text viewer with right-aligned line numbers and match highlighting.
    - Live text editor mode with change detection, cancel confirmation, and atomic save with snackbar feedback.
    - Document properties bottom sheet displaying file size, line count, word count, character count, encoding, and absolute path.
    - Fixed bottom status bar summarizing line count, word count, file size, and encoding.
  - **`PdfViewerScreen`**:
    - High-performance pinch-to-zoom PDF viewer backed by `pdfx.PdfViewPinch`.
    - Dynamic page indicator (`Page X of Y`).
    - Jump-to-page dialog with input validation.
    - PDF metadata inspection modal bottom sheet displaying title, author, creator, page count, and encryption status.
  - **`PdfStudioScreen`**:
    - Tabbed studio interface:
      1. **Images to PDF**: Document title customization, multi-line image path input, and instant A4 compilation.
      2. **Merge PDFs**: Output naming, multi-document path input, and sequential merge compiler.
      3. **Extract Pages**: Source PDF picker, comma-separated and range page specifiers (e.g., `1, 2-4`), and standalone PDF generation.
    - Validation error snackbars with queue clearing.
    - Operation result feedback cards displaying processed page count, output file size, output path, and shortcut button to view the newly created PDF in `PdfViewerScreen`.
- Integration:
  - **`FilesScreen`**:
    - Added quick-access PDF Studio shortcut in the top app bar actions.
    - Routed document clicks to `PdfViewerScreen` (for `.pdf`) and `DocumentViewerScreen` (for `.txt`, `.md`, `.csv`, `.json`, `.xml`, source code).
    - Added "View PDF" and "View Document" context menu actions.
  - **`SearchScreen`**:
    - Universal search result tap navigation updated to open PDFs in `PdfViewerScreen` and documents in `DocumentViewerScreen`.

## Verification & Testing
- Unit Tests:
  - `test/unit/document_service_test.dart`:
    - Extension to `DocumentType` classification.
    - Capability flags (`isMarkdown`, `isCsv`, `isPdf`).
    - Non-existent file handling.
    - Markdown metrics analysis (lines, words, characters, size).
    - Atomic document text saving.
    - CSV spreadsheet parsing with comma-separated numbers and quoted strings with commas.
    - Empty and missing CSV handling.
  - `test/unit/pdf_studio_service_test.dart`:
    - Input guard validation (empty image list, single document merge, empty page extraction list).
    - Non-existent PDF metadata inspection.
    - Pure Dart Images-to-PDF compilation from raw PNG bytes and binary metadata verification.
    - Missing image paths handling.
- Widget Tests:
  - `test/widget/document_viewers_test.dart`:
    - `DocumentViewerScreen`: Markdown rendering and toggle to raw source view with line numbers.
    - `DocumentViewerScreen`: CSV table rendering and in-table search filtering.
    - `DocumentViewerScreen`: Live editing mode, text input, and save execution.
    - `DocumentViewerScreen`: Document properties modal bottom sheet presentation.
    - `PdfStudioScreen`: Tab switching and validation snackbars on empty inputs.
- Quality Metrics:
  - Full test suite: **88 passing tests (100% pass rate)**.
  - Analyzer: **0 errors, 0 warnings (No issues found!)**.
