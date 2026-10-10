import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';

/// Asynchronous, UI-friendly directory walks for services that need files
/// outside the index (explicit scan roots). Never blocks the UI isolate the
/// way a recursive `listSync` over shared storage does.
class FileWalker {
  const FileWalker._();

  /// Files under [roots] (hidden entries and `Android/` skipped).
  static Future<List<FileEntity>> files(Iterable<String> roots) async {
    final out = <FileEntity>[];
    var sinceYield = 0;
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File || _hidden(root, entity.path)) continue;
          if (++sinceYield >= 200) {
            sinceYield = 0;
            await Future<void>.delayed(Duration.zero);
          }
          try {
            final stat = entity.statSync();
            out.add(FileEntity(
              id: entity.path,
              path: entity.path,
              name: p.basename(entity.path),
              extension: p.extension(entity.path),
              size: stat.size,
              modifiedAt: stat.modified,
              createdAt: stat.changed,
              isDirectory: false,
              category: FileCategory.fromExtension(p.extension(entity.path)),
            ));
          } catch (_) {
            // Unreadable entry: skip it.
          }
        }
      } catch (_) {
        // Root became unreadable mid-walk: keep what was collected.
      }
    }
    return out;
  }

  /// Empty folders under [roots] (hidden folders and `Android*` excluded).
  static Future<List<String>> emptyFolders(Iterable<String> roots) async {
    final result = <String>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (await dir.exists()) await _collectEmpty(dir, result);
    }
    return result;
  }

  static Future<void> _collectEmpty(Directory dir, List<String> result) async {
    try {
      final children = <Directory>[];
      var hasEntries = false;
      await for (final entry in dir.list(followLinks: false)) {
        hasEntries = true;
        if (entry is Directory) children.add(entry);
      }
      final name = p.basename(dir.path);
      if (!hasEntries) {
        if (!name.startsWith('.') && !name.startsWith('Android')) result.add(dir.path);
        return;
      }
      for (final child in children) {
        final childName = p.basename(child.path);
        if (childName.startsWith('.') || childName == 'Android') continue;
        await _collectEmpty(child, result);
      }
    } catch (_) {
      // Unreadable folder: not reported as empty.
    }
  }

  static bool _hidden(String root, String path) => p
      .split(p.relative(path, from: root))
      .any((segment) => segment.startsWith('.') || segment == 'Android');
}
