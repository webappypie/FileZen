import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/database/database_provider.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../providers/category_files_providers.dart';

/// Favorites live on the file's index row (they survive re-indexing).
class Favorites {
  const Favorites._();

  /// Current mark of [path] (false when the file is not indexed).
  static Future<bool> isFavorite(WidgetRef ref, String path) async {
    final db = ref.read(appDatabaseProvider);
    final rows = await (db.select(db.fileRecords)..where((t) => t.path.equals(path))).get();
    return rows.any((r) => r.isFavorite);
  }

  /// Sets the mark, indexing the file first if needed. Returns false when the
  /// file could not be indexed (e.g. it no longer exists).
  static Future<bool> setFavorite(WidgetRef ref, FileEntity file, bool favorite) async {
    final db = ref.read(appDatabaseProvider);
    var changed = await db.setFavorite(file.path, favorite);
    if (changed == 0 && favorite) {
      final indexed = await ref.read(indexingServiceProvider).indexSingleFile(file);
      if (!indexed.isSuccess) return false;
      changed = await db.setFavorite(file.path, true);
    }
    ref.invalidate(favoriteFilesProvider);
    ref.invalidate(recentFilesProvider);
    ref.invalidate(categoryFilesListProvider);
    ref.invalidate(searchResultsProvider);
    return changed > 0 || !favorite;
  }
}
