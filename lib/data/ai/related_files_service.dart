import 'package:path/path.dart' as p;
import '../../core/logging/app_logger.dart';
import '../../domain/models/ai_models.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/search_result_item.dart';
import '../../domain/repositories/i_related_files_service.dart';
import '../../domain/repositories/i_search_repository.dart';
import '../../domain/repositories/i_storage_repository.dart';

/// Service analyzing directory proximity, naming patterns, and FTS5 tokens
/// to discover related files and companion assets.
class RelatedFilesService implements IRelatedFilesService {
  const RelatedFilesService({
    required this.storageRepository,
    required this.searchRepository,
  });

  final IStorageRepository storageRepository;
  final ISearchRepository searchRepository;

  @override
  Future<List<RelatedFileItem>> findRelatedFiles(FileEntity file) async {
    final relatedItems = <String, RelatedFileItem>{};

    try {
      final normalizedTarget = p.normalize(file.path).toLowerCase();
      final parentDir = p.dirname(file.path);
      final baseName = p.basenameWithoutExtension(file.path).toLowerCase();
      final tokens = baseName.split(RegExp(r'[._\-\s]+')).where((t) => t.length > 2).toList();

      // 1. Scan directory siblings for naming similarity and timestamp proximity
      final siblings = await storageRepository.listDirectory(parentDir);
      for (final sibling in siblings) {
        final sibNorm = p.normalize(sibling.path).toLowerCase();
        if (sibNorm == normalizedTarget || sibling.isDirectory) continue;

        final sibBase = p.basenameWithoutExtension(sibling.path).toLowerCase();

        // Exact prefix or suffix match (e.g. proposal.docx vs proposal_signed.pdf)
        if (sibBase.startsWith(baseName) || baseName.startsWith(sibBase)) {
          relatedItems[sibling.path] = RelatedFileItem(
            file: sibling,
            relationship: 'Matching naming prefix in same folder',
            confidenceScore: 0.95,
          );
          continue;
        }

        // Shared significant token in same directory
        final hasCommonToken = tokens.any((t) => sibBase.contains(t));
        if (hasCommonToken) {
          relatedItems[sibling.path] = RelatedFileItem(
            file: sibling,
            relationship: 'Shared topic in same folder',
            confidenceScore: 0.85,
          );
          continue;
        }

        // Timestamp proximity (modified within 15 minutes)
        final timeDiff = (sibling.modifiedAt.difference(file.modifiedAt)).abs();
        if (timeDiff.inMinutes <= 15) {
          relatedItems[sibling.path] = RelatedFileItem(
            file: sibling,
            relationship: 'Created within ${timeDiff.inMinutes}m in same folder',
            confidenceScore: 0.70,
          );
        }
      }

      // 2. Query FTS5 for significant keywords across full storage library
      if (tokens.isNotEmpty) {
        final queryStr = tokens.take(3).join(' ');
        final searchResult = await searchRepository.search(SearchQuery(text: queryStr));
        final searchResults = searchResult.when(
          success: (items) => items,
          failure: (_) => <SearchResultItem>[],
        );
        for (final res in searchResults) {
          if (res.file.path == file.path || relatedItems.containsKey(res.file.path)) continue;

          relatedItems[res.file.path] = RelatedFileItem(
            file: res.file,
            relationship: 'Shared content and topic across storage',
            confidenceScore: 0.65,
          );
        }
      }
    } catch (e) {
      AppLogger.warning('Failed finding related files for ${file.path}: $e', 'RelatedFilesService');
    }

    final list = relatedItems.values.toList();
    list.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
    return list.take(10).toList();
  }
}
