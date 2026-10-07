/// Domain models for document classification, text analysis, and PDF Studio operations.
library;

enum DocumentType {
  markdown,
  plainText,
  csv,
  json,
  xml,
  code,
  pdf,
  unsupported;

  String get displayName => switch (this) {
        DocumentType.markdown => 'Markdown',
        DocumentType.plainText => 'Plain Text',
        DocumentType.csv => 'Spreadsheet (CSV)',
        DocumentType.json => 'JSON Data',
        DocumentType.xml => 'XML Document',
        DocumentType.code => 'Source Code',
        DocumentType.pdf => 'PDF Document',
        DocumentType.unsupported => 'Document',
      };

  bool get isMarkdown => this == DocumentType.markdown;
  bool get isCsv => this == DocumentType.csv;
  bool get isPdf => this == DocumentType.pdf;
}

class DocumentMetadata {
  const DocumentMetadata({
    required this.filePath,
    required this.type,
    required this.fileSize,
    required this.lineCount,
    required this.wordCount,
    required this.characterCount,
    this.encoding = 'UTF-8',
    this.isEditable = true,
  });

  final String filePath;
  final DocumentType type;
  final int fileSize;
  final int lineCount;
  final int wordCount;
  final int characterCount;
  final String encoding;
  final bool isEditable;
}

class PdfDocumentInfo {
  const PdfDocumentInfo({
    required this.filePath,
    required this.pageCount,
    required this.fileSize,
    this.title,
    this.author,
    this.subject,
    this.creator,
    this.creationDate,
    this.isEncrypted = false,
  });

  final String filePath;
  final int pageCount;
  final int fileSize;
  final String? title;
  final String? author;
  final String? subject;
  final String? creator;
  final DateTime? creationDate;
  final bool isEncrypted;

  String get authorOrUnknown => (author != null && author!.isNotEmpty) ? author! : 'Unknown Author';
  String get titleOrFilename => (title != null && title!.isNotEmpty) ? title! : 'Untitled Document';
}

class PdfOperationResult {
  const PdfOperationResult({
    required this.success,
    required this.outputPath,
    required this.pagesProcessed,
    required this.outputSizeBytes,
    this.errorMessage,
  });

  final bool success;
  final String outputPath;
  final int pagesProcessed;
  final int outputSizeBytes;
  final String? errorMessage;
}
