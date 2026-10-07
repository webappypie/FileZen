import 'file_entity.dart';

/// Clipboard mode: copying or cutting (moving) files.
enum ClipboardMode {
  copy,
  cut,
}

/// In-memory clipboard state for file transfer operations.
class FileClipboard {
  final ClipboardMode mode;
  final List<FileEntity> items;

  const FileClipboard({
    required this.mode,
    required this.items,
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get count => items.length;

  int get totalBytes => items.fold(0, (acc, item) => acc + item.size);

  List<String> get paths => items.map((i) => i.path).toList();

  @override
  String toString() => 'FileClipboard(mode: $mode, count: $count, bytes: $totalBytes)';
}
