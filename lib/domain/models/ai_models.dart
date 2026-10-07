/// Domain models for local AI intelligence, OCR, natural language queries,
/// smart collections, and auto-rename operations.
library;

import 'package:flutter/material.dart';

import 'file_category.dart';
import 'file_entity.dart';

/// Result of an on-device OCR text extraction operation.
class OcrExtractionResult {
  const OcrExtractionResult({
    required this.filePath,
    required this.extractedText,
    this.detectedLanguage = 'en',
    this.confidence = 1.0,
    required this.timestamp,
    this.lines = const [],
  });

  final String filePath;
  final String extractedText;
  final String detectedLanguage;
  final double confidence;
  final DateTime timestamp;
  final List<String> lines;

  bool get hasText => extractedText.trim().isNotEmpty;
}

/// Predefined natural query intents recognized by Ask Your Files.
enum SpecialQueryIntent {
  resume,
  otpScreenshot,
  receiptOrInvoice,
  idCard,
  largeVideos,
  recentDocuments,
  general,
}

/// Structured query intent parsed from natural language.
class NaturalQueryIntent {
  const NaturalQueryIntent({
    required this.rawQuery,
    required this.interpretedKeywords,
    this.targetCategory,
    this.startDate,
    this.endDate,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.fileExtension,
    this.specialIntent = SpecialQueryIntent.general,
    required this.explanation,
  });

  final String rawQuery;
  final List<String> interpretedKeywords;
  final FileCategory? targetCategory;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? minSizeBytes;
  final int? maxSizeBytes;
  final String? fileExtension;
  final SpecialQueryIntent specialIntent;
  final String explanation;

  String get keywordsQuery => interpretedKeywords.join(' ');
}

/// Intelligent file rename proposal generated from local signals.
class AutoRenameSuggestion {
  const AutoRenameSuggestion({
    required this.originalPath,
    required this.originalName,
    required this.suggestedName,
    required this.suggestedPath,
    required this.confidence,
    required this.reason,
    this.hasCollision = false,
  });

  final String originalPath;
  final String originalName;
  final String suggestedName;
  final String suggestedPath;
  final double confidence;
  final String reason;
  final bool hasCollision;

  bool get isSameName => originalName.toLowerCase() == suggestedName.toLowerCase();
}

/// Record of an applied auto-rename for safe undo support.
class AutoRenameHistoryItem {
  const AutoRenameHistoryItem({
    required this.timestamp,
    required this.originalPath,
    required this.renamedPath,
    required this.originalName,
    required this.renamedName,
  });

  final DateTime timestamp;
  final String originalPath;
  final String renamedPath;
  final String originalName;
  final String renamedName;
}

/// Evaluation rule for virtual smart collections.
enum SmartCollectionRuleType {
  receiptsAndInvoices,
  identityAndDocuments,
  screenshots,
  largeMedia,
  workAndCode,
  archives,
  custom;

  IconData get icon => switch (this) {
        SmartCollectionRuleType.receiptsAndInvoices => Icons.receipt_long_rounded,
        SmartCollectionRuleType.identityAndDocuments => Icons.badge_rounded,
        SmartCollectionRuleType.screenshots => Icons.screenshot_rounded,
        SmartCollectionRuleType.largeMedia => Icons.video_file_rounded,
        SmartCollectionRuleType.workAndCode => Icons.code_rounded,
        SmartCollectionRuleType.archives => Icons.folder_zip_rounded,
        SmartCollectionRuleType.custom => Icons.auto_awesome_mosaic_rounded,
      };
}

/// Virtual collection metadata and grouping criteria.
class SmartCollection {
  const SmartCollection({
    required this.id,
    required this.title,
    required this.description,
    required this.ruleType,
    required this.iconCodePoint,
    required this.colorHex,
    this.fileCount = 0,
    this.totalSizeBytes = 0,
  });

  final String id;
  final String title;
  final String description;
  final SmartCollectionRuleType ruleType;
  final int iconCodePoint;
  final int colorHex;
  final int fileCount;
  final int totalSizeBytes;

  IconData get icon => ruleType.icon;

  SmartCollection copyWith({
    int? fileCount,
    int? totalSizeBytes,
  }) {
    return SmartCollection(
      id: id,
      title: title,
      description: description,
      ruleType: ruleType,
      iconCodePoint: iconCodePoint,
      colorHex: colorHex,
      fileCount: fileCount ?? this.fileCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
    );
  }
}

/// Companion or related file identified by local intelligence.
class RelatedFileItem {
  const RelatedFileItem({
    required this.file,
    required this.relationship,
    required this.confidenceScore,
  });

  final FileEntity file;
  final String relationship;
  final double confidenceScore;
}
