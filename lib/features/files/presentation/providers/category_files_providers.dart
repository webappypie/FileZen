import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/database/app_database.dart';
import '../../../../data/database/database_provider.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/file_entity.dart';

/// Provider for dynamic category file counts displayed on the Home screen.
final categoryFileCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  try {
    final counts = await db.getCategoryCounts();
    final downloadCount = await db.getDownloadFilesCount();
    counts['Downloads'] = downloadCount;
    return counts;
  } catch (_) {
    return {};
  }
});

/// Index-backed lists a category screen can show instead of one category.
enum FileListKind { recent, favorites }

/// Query parameter record for category file listings.
typedef CategoryQuery = ({FileCategory? category, bool isDownloads});

/// Number of entries in the "Recent files" list.
const recentFilesLimit = 50;

/// Provider fetching files for a given category from the indexed database.
/// Does NOT perform an unnecessary full filesystem scan.
final categoryFilesListProvider =
    FutureProvider.family<List<FileEntity>, CategoryQuery>((ref, query) async {
  final db = ref.watch(appDatabaseProvider);

  try {
    final records = query.isDownloads
        ? await db.getDownloadFiles()
        : (query.category != null
            ? await db.getFilesForCategory(query.category!.displayName)
            : <FileRecord>[]);

    return records.map(_toEntity).toList();
  } catch (_) {
    return [];
  }
});

/// Recently modified indexed files (Home "Recent files" and its full list).
final recentFilesProvider = FutureProvider<List<FileEntity>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  try {
    return (await db.getRecentFiles(limit: recentFilesLimit)).map(_toEntity).toList();
  } catch (_) {
    return [];
  }
});

/// Files marked as favorite.
final favoriteFilesProvider = FutureProvider<List<FileEntity>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  try {
    return (await db.getFavoriteFiles()).map(_toEntity).toList();
  } catch (_) {
    return [];
  }
});

/// Whether an entity read from the index is marked favorite.
bool isFavoriteEntity(FileEntity file) => file.metadata['isFavorite'] == true;

FileEntity _toEntity(FileRecord record) => FileEntity(
      id: record.id,
      path: record.path,
      name: record.name,
      size: record.size.toInt(),
      modifiedAt: record.modifiedAt,
      createdAt: record.createdAt,
      isDirectory: false,
      mimeType: record.mimeType,
      extension: record.extension,
      category: FileCategory.fromExtension(record.extension, record.mimeType),
      metadata: {'isFavorite': record.isFavorite},
    );
