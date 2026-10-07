import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/logging/app_logger.dart';
import '../../domain/models/ai_models.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/repositories/i_auto_rename_service.dart';
import '../../domain/repositories/i_document_service.dart';
import '../../domain/repositories/i_ocr_service.dart';
import '../../domain/repositories/i_storage_repository.dart';

/// Intelligent file renaming engine proposing clean, contextual file names
/// based on document headers, OCR tokens, camera EXIF, and timestamps.
class AutoRenameService implements IAutoRenameService {
  AutoRenameService({
    required this.storageRepository,
    this.documentService,
    this.ocrService,
  });

  final IStorageRepository storageRepository;
  final IDocumentService? documentService;
  final IOcrService? ocrService;

  final List<AutoRenameHistoryItem> _history = [];

  @override
  List<AutoRenameHistoryItem> getRenameHistory() => List.unmodifiable(_history);

  @override
  Future<AutoRenameSuggestion> generateRenameSuggestion(FileEntity file) async {
    final originalName = file.name;
    final parentDir = p.dirname(file.path);
    final ext = file.extension.toLowerCase();
    final nameWithoutExt = p.basenameWithoutExtension(file.path);

    String candidateName = nameWithoutExt;
    String reason = 'Standardized naming format';
    double confidence = 0.80;

    try {
      // 1. Text and Markdown Document Signal
      if (file.category == FileCategory.document || ext == '.md' || ext == '.txt') {
        if (documentService != null) {
          final content = await documentService!.readDocumentText(file.path, maxBytes: 4096);
          final titleCandidate = _extractHeadingFromText(content);
          if (titleCandidate != null && titleCandidate.isNotEmpty) {
            candidateName = _cleanFilename(titleCandidate);
            reason = 'Extracted title from document content';
            confidence = 0.95;
          }
        }
      }

      // 2. Image / Screenshot / Camera Signal
      if (candidateName == nameWithoutExt && file.category == FileCategory.image) {
        if (nameWithoutExt.startsWith('IMG_') || nameWithoutExt.startsWith('PXL_')) {
          // Camera photos
          final dateStr = _formatDate(file.modifiedAt);
          candidateName = 'Photo_$dateStr';
          reason = 'Formatted camera photo date stamp';
          confidence = 0.88;
        } else if (nameWithoutExt.toLowerCase().contains('screenshot')) {
          // Screenshots
          if (ocrService != null) {
            final ocr = await ocrService!.extractTextFromImage(file.path);
            if (ocr.extractedText.toLowerCase().contains('receipt') ||
                ocr.extractedText.toLowerCase().contains('invoice')) {
              candidateName = 'Screenshot_Receipt_${_formatDate(file.modifiedAt)}';
              reason = 'Identified receipt content via OCR';
              confidence = 0.92;
            } else if (ocr.extractedText.toLowerCase().contains('otp') ||
                ocr.extractedText.toLowerCase().contains('verification')) {
              candidateName = 'Screenshot_OTP_${_formatDate(file.modifiedAt)}';
              reason = 'Detected verification code in screenshot';
              confidence = 0.92;
            } else {
              candidateName = 'Screenshot_${_formatDate(file.modifiedAt)}';
              reason = 'Cleaned screenshot timestamp';
              confidence = 0.85;
            }
          } else {
            candidateName = 'Screenshot_${_formatDate(file.modifiedAt)}';
            reason = 'Cleaned screenshot timestamp';
            confidence = 0.85;
          }
        }
      }

      // 3. Clean up generic ugly patterns (e.g., "download (1)", "Untitled 2", "doc_final_v2_FINAL")
      if (candidateName == nameWithoutExt) {
        final cleaned = _sanitizeMessyName(nameWithoutExt);
        if (cleaned != nameWithoutExt) {
          candidateName = cleaned;
          reason = 'Cleaned duplicate numberings and messy characters';
          confidence = 0.75;
        }
      }
    } catch (e) {
      AppLogger.warning('Auto-rename suggestion failed for ${file.path}: $e', 'AutoRenameService');
    }

    // Ensure valid extension
    final fullSuggestedName = ext.isNotEmpty ? '$candidateName$ext' : candidateName;
    final targetPath = p.join(parentDir, fullSuggestedName);

    // Collision check
    bool hasCollision = false;
    String finalSuggestedName = fullSuggestedName;
    String finalSuggestedPath = targetPath;

    if (finalSuggestedName != originalName && File(targetPath).existsSync()) {
      hasCollision = true;
      var counter = 1;
      while (File(p.join(parentDir, '${candidateName}_$counter$ext')).existsSync()) {
        counter++;
      }
      finalSuggestedName = '${candidateName}_$counter$ext';
      finalSuggestedPath = p.join(parentDir, finalSuggestedName);
    }

    return AutoRenameSuggestion(
      originalPath: file.path,
      originalName: originalName,
      suggestedName: finalSuggestedName,
      suggestedPath: finalSuggestedPath,
      confidence: confidence,
      reason: reason,
      hasCollision: hasCollision,
    );
  }

  @override
  Future<List<AutoRenameSuggestion>> generateBatchRenameSuggestions(List<FileEntity> files) async {
    final list = <AutoRenameSuggestion>[];
    for (final file in files) {
      list.add(await generateRenameSuggestion(file));
    }
    return list;
  }

  @override
  Future<bool> applyRename(AutoRenameSuggestion suggestion) async {
    if (suggestion.isSameName) return true;

    try {
      final res = await storageRepository.rename(
        suggestion.originalPath,
        suggestion.suggestedName,
      );

      final success = res.isSuccess;
      if (success) {
        _history.add(
          AutoRenameHistoryItem(
            timestamp: DateTime.now(),
            originalPath: suggestion.originalPath,
            renamedPath: suggestion.suggestedPath,
            originalName: suggestion.originalName,
            renamedName: suggestion.suggestedName,
          ),
        );
        AppLogger.info(
          'Applied auto-rename: ${suggestion.originalName} -> ${suggestion.suggestedName}',
          'AutoRenameService',
        );
      }
      return success;
    } catch (e) {
      AppLogger.error('Failed to apply rename: $e', 'AutoRenameService');
      return false;
    }
  }

  @override
  Future<bool> undoRename(AutoRenameHistoryItem historyItem) async {
    try {
      final res = await storageRepository.rename(
        historyItem.renamedPath,
        historyItem.originalName,
      );

      final success = res.isSuccess;
      if (success) {
        _history.remove(historyItem);
        AppLogger.info(
          'Reverted auto-rename: ${historyItem.renamedName} -> ${historyItem.originalName}',
          'AutoRenameService',
        );
      }
      return success;
    } catch (e) {
      AppLogger.error('Failed to undo rename: $e', 'AutoRenameService');
      return false;
    }
  }

  String? _extractHeadingFromText(String text) {
    if (text.isEmpty) return null;
    final lines = text.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Markdown # Heading
      if (line.startsWith('#')) {
        final heading = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty && heading.length < 50) return heading;
      }

      // Title line
      if (line.length >= 3 && line.length <= 40 && !line.contains('{') && !line.contains(';')) {
        return line;
      }
    }
    return null;
  }

  String _cleanFilename(String input) {
    // Replace punctuation and spaces with underscores
    var clean = input.replaceAll(RegExp(r'[^\w\s\-]'), '');
    clean = clean.trim().replaceAll(RegExp(r'\s+'), '_');
    return clean;
  }

  String _sanitizeMessyName(String name) {
    // Remove duplicate trailing copy indicators like " (1)", "_copy", " copy"
    var clean = name.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    clean = clean.replaceAll(RegExp(r'[\s_]+copy$', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'[._\-]{2,}'), '_');
    return clean.trim();
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
