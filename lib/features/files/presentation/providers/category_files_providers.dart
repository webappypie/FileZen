import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Query parameter record for category file listings.
typedef CategoryQuery = ({FileCategory? category, bool isDownloads});

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
            : <dynamic>[]);

    return records.map((record) {
      return FileEntity(
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
    }).toList();
  } catch (_) {
    return [];
  }
});
