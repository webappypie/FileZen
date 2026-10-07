import '../models/document_models.dart';

/// Clean Architecture interface for document text reading, editing, and CSV parsing.
abstract class IDocumentService {
  /// Read document text from file, with optional byte limitation.
  Future<String> readDocumentText(String filePath, {int? maxBytes});

  /// Analyze text metrics (word count, line count, character count, type).
  Future<DocumentMetadata> analyzeDocument(String filePath);

  /// Save edited text back to disk atomically.
  Future<bool> saveDocumentText(String filePath, String content);

  /// Parse CSV data into rows and columns.
  Future<List<List<dynamic>>> parseCsv(String filePath);

  /// Determine document type from file extension and content hints.
  DocumentType resolveDocumentType(String filePath);
}
