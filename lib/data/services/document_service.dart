import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import '../../core/logging/app_logger.dart';
import '../../domain/models/document_models.dart';
import '../../domain/repositories/i_document_service.dart';

/// Implementation of IDocumentService for reading, analyzing, saving, and parsing document files.
class DocumentService implements IDocumentService {
  const DocumentService();

  @override
  DocumentType resolveDocumentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return switch (ext) {
      'md' || 'markdown' => DocumentType.markdown,
      'csv' || 'tsv' => DocumentType.csv,
      'json' => DocumentType.json,
      'xml' || 'html' || 'htm' => DocumentType.xml,
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'java' ||
      'kt' ||
      'c' ||
      'cpp' ||
      'cs' ||
      'sh' ||
      'bat' ||
      'ps1' ||
      'yaml' ||
      'yml' ||
      'toml' ||
      'sql' => DocumentType.code,
      'pdf' => DocumentType.pdf,
      'txt' || 'log' || 'conf' || 'ini' || 'env' || 'properties' => DocumentType.plainText,
      _ => DocumentType.unsupported,
    };
  }

  @override
  Future<String> readDocumentText(String filePath, {int? maxBytes}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return '';
    }

    try {
      final size = await file.length();
      final bytesToRead = (maxBytes != null && maxBytes < size) ? maxBytes : size;

      final raf = await file.open(mode: FileMode.read);
      final bytes = await raf.read(bytesToRead);
      await raf.close();

      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      AppLogger.warning('Failed to read text from $filePath: $e', 'DocumentService');
      return '';
    }
  }

  @override
  Future<DocumentMetadata> analyzeDocument(String filePath) async {
    final file = File(filePath);
    final exists = await file.exists();
    final fileSize = exists ? await file.length() : 0;
    final type = resolveDocumentType(filePath);

    if (!exists || fileSize == 0) {
      return DocumentMetadata(
        filePath: filePath,
        type: type,
        fileSize: fileSize,
        lineCount: 0,
        wordCount: 0,
        characterCount: 0,
      );
    }

    try {
      // Analyze first 512KB for metrics
      final text = await readDocumentText(filePath, maxBytes: 524288);
      final lines = text.split('\n');
      final lineCount = lines.length;
      final characterCount = text.length;

      // Fast word count calculation
      var wordCount = 0;
      final regex = RegExp(r'\S+');
      for (final match in regex.allMatches(text)) {
        if (match.group(0) != null) wordCount++;
      }

      final isEditable = type != DocumentType.pdf && type != DocumentType.unsupported && fileSize < 5242880;

      return DocumentMetadata(
        filePath: filePath,
        type: type,
        fileSize: fileSize,
        lineCount: lineCount,
        wordCount: wordCount,
        characterCount: characterCount,
        isEditable: isEditable,
      );
    } catch (e) {
      AppLogger.error('Document analysis failed for $filePath: $e', 'DocumentService');
      return DocumentMetadata(
        filePath: filePath,
        type: type,
        fileSize: fileSize,
        lineCount: 0,
        wordCount: 0,
        characterCount: 0,
      );
    }
  }

  @override
  Future<bool> saveDocumentText(String filePath, String content) async {
    final file = File(filePath);
    try {
      await file.writeAsString(content, flush: true, encoding: utf8);
      AppLogger.info('Successfully saved document: $filePath', 'DocumentService');
      return true;
    } catch (e) {
      AppLogger.error('Failed to save document $filePath: $e', 'DocumentService');
      return false;
    }
  }

  @override
  Future<List<List<dynamic>>> parseCsv(String filePath) async {
    final rawText = await readDocumentText(filePath);
    if (rawText.isEmpty) return [];

    try {
      // Normalize CRLF to LF
      final normalized = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final converter = CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: true,
        allowInvalid: true,
      );
      return converter.convert(normalized);
    } catch (e) {
      AppLogger.warning('Failed to parse CSV $filePath: $e', 'DocumentService');
      return [];
    }
  }
}
