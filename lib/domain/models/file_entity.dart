import 'file_category.dart';

/// Domain entity representing a file or directory in FileZen.
class FileEntity {
  final String id;
  final String path;
  final String name;
  final String extension;
  final int size;
  final DateTime modifiedAt;
  final DateTime createdAt;
  final bool isDirectory;
  final bool isHidden;
  final String? mimeType;
  final FileCategory category;
  final String? checksum;
  final Map<String, dynamic> metadata;

  const FileEntity({
    required this.id,
    required this.path,
    required this.name,
    required this.extension,
    required this.size,
    required this.modifiedAt,
    required this.createdAt,
    required this.isDirectory,
    this.isHidden = false,
    this.mimeType,
    required this.category,
    this.checksum,
    this.metadata = const {},
  });

  /// Creates a copy of this FileEntity with updated fields.
  FileEntity copyWith({
    String? id,
    String? path,
    String? name,
    String? extension,
    int? size,
    DateTime? modifiedAt,
    DateTime? createdAt,
    bool? isDirectory,
    bool? isHidden,
    String? mimeType,
    FileCategory? category,
    String? checksum,
    Map<String, dynamic>? metadata,
  }) {
    return FileEntity(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      isDirectory: isDirectory ?? this.isDirectory,
      isHidden: isHidden ?? this.isHidden,
      mimeType: mimeType ?? this.mimeType,
      category: category ?? this.category,
      checksum: checksum ?? this.checksum,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          path == other.path;

  @override
  int get hashCode => id.hashCode ^ path.hashCode;

  @override
  String toString() =>
      'FileEntity(id: $id, name: $name, isDir: $isDirectory, size: $size)';
}
