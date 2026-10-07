import '../../domain/models/ai_models.dart';
import '../../domain/models/file_category.dart';
import '../../domain/models/file_entity.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/search_result_item.dart';
import '../../domain/repositories/i_search_repository.dart';
import '../../domain/repositories/i_smart_collections_service.dart';

/// Evaluates virtual smart collections dynamically across indexed storage.
/// Files are never physically moved — collections represent intelligent semantic views.
class SmartCollectionsService implements ISmartCollectionsService {
  const SmartCollectionsService({
    required this.searchRepository,
  });

  final ISearchRepository searchRepository;

  static final List<SmartCollection> _predefinedCollections = [
    const SmartCollection(
      id: 'invoices_receipts',
      title: 'Invoices & Receipts',
      description: 'Financial receipts, invoices, statements, and payment confirmations',
      ruleType: SmartCollectionRuleType.receiptsAndInvoices,
      iconCodePoint: 0xf00b8, // Icons.receipt_long_rounded
      colorHex: 0xFF10B981,
    ),
    const SmartCollection(
      id: 'identity_documents',
      title: 'Identity & Cards',
      description: 'Passports, identity cards, licenses, and official certificates',
      ruleType: SmartCollectionRuleType.identityAndDocuments,
      iconCodePoint: 0xf59a, // Icons.badge_rounded
      colorHex: 0xFF3B82F6,
    ),
    const SmartCollection(
      id: 'screenshots',
      title: 'Screenshots',
      description: 'Captured device screenshots and screen recordings',
      ruleType: SmartCollectionRuleType.screenshots,
      iconCodePoint: 0xf0149, // Icons.screenshot_rounded
      colorHex: 0xFF8B5CF6,
    ),
    const SmartCollection(
      id: 'large_media',
      title: 'Large Media (>50MB)',
      description: 'High-definition videos and heavy media assets',
      ruleType: SmartCollectionRuleType.largeMedia,
      iconCodePoint: 0xf028c, // Icons.video_file_rounded
      colorHex: 0xFFF59E0B,
    ),
    const SmartCollection(
      id: 'work_code',
      title: 'Code & Projects',
      description: 'Source code files, scripts, configurations, and project docs',
      ruleType: SmartCollectionRuleType.workAndCode,
      iconCodePoint: 0xe188, // Icons.code_rounded
      colorHex: 0xFF06B6D4,
    ),
    const SmartCollection(
      id: 'archives',
      title: 'Archives & Backups',
      description: 'ZIP, 7Z, TAR, RAR, and compressed packages',
      ruleType: SmartCollectionRuleType.archives,
      iconCodePoint: 0xf03b, // Icons.folder_zip_rounded
      colorHex: 0xFFEC4899,
    ),
  ];

  @override
  Future<List<SmartCollection>> getSmartCollections() async {
    final results = <SmartCollection>[];

    for (final col in _predefinedCollections) {
      final files = await getFilesInCollection(col.id);
      final totalBytes = files.fold<int>(0, (acc, file) => acc + file.size);
      results.add(
        col.copyWith(
          fileCount: files.length,
          totalSizeBytes: totalBytes,
        ),
      );
    }

    return results;
  }

  @override
  Future<List<FileEntity>> getFilesInCollection(String collectionId) async {
    SearchQuery query;

    switch (collectionId) {
      case 'invoices_receipts':
        query = const SearchQuery(text: 'receipt OR invoice OR bill OR payment OR statement OR tax');
        break;
      case 'identity_documents':
        query = const SearchQuery(text: 'passport OR license OR id OR card OR aadhaar OR identity OR certificate');
        break;
      case 'screenshots':
        query = const SearchQuery(text: 'screenshot OR screenshots', category: FileCategory.image);
        break;
      case 'large_media':
        query = const SearchQuery(text: '*', minSize: 50 * 1024 * 1024);
        break;
      case 'work_code':
        query = const SearchQuery(text: 'dart OR py OR js OR ts OR java OR kt OR html OR css OR json OR yaml OR toml OR sh OR sql');
        break;
      case 'archives':
        query = const SearchQuery(text: '*', category: FileCategory.archive);
        break;
      default:
        return [];
    }

    final searchResult = await searchRepository.search(query);
    final searchResults = searchResult.when(
      success: (items) => items,
      failure: (_) => <SearchResultItem>[],
    );
    final entities = searchResults.map((r) => r.file).toList();

    // Additional local filtering if needed
    if (collectionId == 'large_media') {
      return entities.where((e) => e.size >= 50 * 1024 * 1024).toList();
    }

    return entities;
  }
}
