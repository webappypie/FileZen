import 'file_category.dart';
import 'file_entity.dart';

/// Represents a file moved to the FileZen Recycle Bin / Trash with restoration metadata.
class TrashItem {
  final String id;
  final String originalPath;
  final String trashPath;
  final String fileName;
  final int size;
  final DateTime trashedAt;
  final String? mimeType;
  final FileCategory category;

  const TrashItem({
    required this.id,
    required this.originalPath,
    required this.trashPath,
    required this.fileName,
    required this.size,
    required this.trashedAt,
    this.mimeType,
    required this.category,
  });

  /// Days remaining before automatic purging (default policy: 30 days).
  int get daysUntilPurge {
    final expiry = trashedAt.add(const Duration(days: 30));
    final diff = expiry.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalPath': originalPath,
        'trashPath': trashPath,
        'fileName': fileName,
        'size': size,
        'trashedAt': trashedAt.toIso8601String(),
        'mimeType': mimeType,
        'category': category.name,
      };

  factory TrashItem.fromJson(Map<String, dynamic> json) => TrashItem(
        id: json['id'] as String,
        originalPath: json['originalPath'] as String,
        trashPath: json['trashPath'] as String,
        fileName: json['fileName'] as String,
        size: json['size'] as int,
        trashedAt: DateTime.parse(json['trashedAt'] as String),
        mimeType: json['mimeType'] as String?,
        category: FileCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => FileCategory.other,
        ),
      );

  factory TrashItem.fromFileEntity(FileEntity entity, String trashPath) => TrashItem(
        id: entity.id,
        originalPath: entity.path,
        trashPath: trashPath,
        fileName: entity.name,
        size: entity.size,
        trashedAt: DateTime.now(),
        mimeType: entity.mimeType,
        category: entity.category,
      );
}
