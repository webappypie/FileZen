import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/logging/app_logger.dart';
import '../../domain/models/file_entity.dart';

/// Service responsible for extracting searchable text tokens from local files.
class TextExtractor {
  static const int maxTextExtractBytes = 64 * 1024; // 64 KB safety limit

  static const _textExtensions = {
    'txt', 'md', 'markdown', 'json', 'csv', 'tsv', 'xml', 'html', 'htm',
    'log', 'yaml', 'yml', 'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'java',
    'kt', 'c', 'cpp', 'h', 'hpp', 'css', 'scss', 'sql', 'sh', 'bat', 'ps1',
    'env', 'conf', 'config', 'ini', 'properties'
  };

  /// Extracts searchable textual content from a FileEntity.
  Future<String> extractContent(FileEntity entity) async {
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

    // Default metadata tokens for binary/media/document files
    return _generateMetadataTokens(entity);
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
