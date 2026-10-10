import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/logging/app_logger.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/repositories/i_ocr_service.dart';
import '../ai/ocr_service.dart';

/// Service responsible for extracting searchable text tokens and OCR content from local files.
class TextExtractor {
  const TextExtractor({
    IOcrService? ocrService,
  }) : _ocrService = ocrService ?? const OcrService();

  final IOcrService? _ocrService;

  static const int maxTextExtractBytes = 64 * 1024; // 64 KB safety limit

  static const _textExtensions = {
    'txt', 'md', 'markdown', 'json', 'csv', 'tsv', 'xml', 'html', 'htm',
    'log', 'yaml', 'yml', 'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'java',
    'kt', 'c', 'cpp', 'h', 'hpp', 'css', 'scss', 'sql', 'sh', 'bat', 'ps1',
    'env', 'conf', 'config', 'ini', 'properties'
  };

  /// Whether images can be OCR'd on this platform.
  Future<bool> get isOcrAvailable async => await _ocrService?.isOcrAvailable() ?? false;

  /// On-device OCR text of an image ('' when none or unavailable).
  Future<String> extractOcrText(FileEntity entity) async {
    if (entity.category != FileCategory.image || _ocrService == null) return '';
    try {
      final ocrResult = await _ocrService.extractTextFromImage(entity.path);
      return ocrResult.hasText ? _cleanText(ocrResult.extractedText) : '';
    } catch (e) {
      AppLogger.warning('OCR indexing failed for ${entity.path}: $e', 'TextExtractor');
      return '';
    }
  }

  /// Extracts searchable textual content from a FileEntity, including on-device
  /// OCR for images unless [includeOcr] is false (the indexer runs OCR in a
  /// separate, deferrable pass).
  Future<String> extractContent(FileEntity entity, {bool includeOcr = true}) async {
    final cleanExt = entity.extension.toLowerCase().replaceAll('.', '');

    // For supported text files, read head bytes asynchronously
    if (_textExtensions.contains(cleanExt)) {
      try {
        final file = File(entity.path);
        if (await file.exists()) {
          final stream = file.openRead(0, maxTextExtractBytes);
          final bytes = await stream.expand((chunk) => chunk).toList();
          final text = utf8.decode(bytes, allowMalformed: true);
          return _cleanText(text);
        }
      } catch (e) {
        AppLogger.warning('Failed reading text file for index: ${entity.path} ($e)', 'TextExtractor');
      }
    }

    final buffer = StringBuffer();
    buffer.write(_generateMetadataTokens(entity));

    // For images, extract on-device OCR text tokens to index in FTS5
    if (includeOcr && entity.category == FileCategory.image && _ocrService != null) {
      try {
        final ocrResult = await _ocrService.extractTextFromImage(entity.path);
        if (ocrResult.hasText) {
          buffer.write(' ');
          buffer.write(ocrResult.extractedText);
        }
      } catch (e) {
        AppLogger.warning('OCR indexing failed for ${entity.path}: $e', 'TextExtractor');
      }
    }

    return _cleanText(buffer.toString());
  }

  /// Generates searchable metadata tokens when direct body text is unavailable or binary.
  String _generateMetadataTokens(FileEntity entity) {
    final pathSegments = p.split(entity.path).where((s) => s.isNotEmpty && s != '/');
    final nameKeywords = entity.name.replaceAll(RegExp(r'[._\-]'), ' ');

    final buffer = StringBuffer();
    buffer.write(nameKeywords);
    buffer.write(' ');
    buffer.write(entity.category.displayName);
    buffer.write(' ');
    buffer.write(entity.extension);
    buffer.write(' ');
    buffer.write(pathSegments.join(' '));

    return buffer.toString();
  }

  String _cleanText(String input) {
    // Replace non-printable characters or excessive whitespace
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
