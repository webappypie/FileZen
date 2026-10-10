import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/media/thumbnail_provider.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../providers/category_files_providers.dart';
import '../providers/storage_providers.dart';

/// Outcome of a delete: which paths are really gone and which are not.
class FileDeletionResult {
  final List<String> deleted;
  final List<String> failed;
  const FileDeletionResult(this.deleted, this.failed);

  bool get allDeleted => failed.isEmpty;

  /// User-facing summary that never claims more than happened.
  String summary() {
    if (failed.isEmpty) {
      return 'Deleted ${deleted.length} item${deleted.length == 1 ? '' : 's'}';
    }
    if (deleted.isEmpty) {
      return 'Could not delete ${failed.length} item${failed.length == 1 ? '' : 's'} (no permission or file in use)';
    }
    return 'Deleted ${deleted.length}; ${failed.length} could not be deleted';
  }
}

/// Deletes files permanently, then removes only the ones that are verifiably
/// gone from the index (search, categories, collections) and the thumbnail
/// cache, and refreshes the counts derived from the index.
class FileDeletion {
  const FileDeletion._();

  static Future<FileDeletionResult> deleteFiles(WidgetRef ref, List<FileEntity> files) async {
    final repo = ref.read(storageRepositoryProvider);
    final index = ref.read(indexingServiceProvider);
    final thumbnails = ref.read(thumbnailServiceProvider);

    final deleted = <String>[];
    final failed = <String>[];
    for (final f in files) {
      await repo.delete(f.path);
      final stillThere = await FileSystemEntity.type(f.path) != FileSystemEntityType.notFound;
      if (stillThere) {
        failed.add(f.path);
        continue;
      }
      deleted.add(f.path);
      await index.removeFileByPath(f.path);
      await thumbnails.evictPath(f.path);
    }

    if (deleted.isNotEmpty) {
      ref.invalidate(categoryFileCountsProvider);
      ref.invalidate(categoryFilesListProvider);
      ref.invalidate(recentFilesProvider);
      ref.invalidate(favoriteFilesProvider);
      ref.invalidate(deviceStorageStatsProvider);
    }
    return FileDeletionResult(deleted, failed);
  }
}
