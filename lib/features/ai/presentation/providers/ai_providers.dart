import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filezen/data/ai/auto_rename_service.dart';
import 'package:filezen/data/ai/ocr_service.dart';
import 'package:filezen/data/ai/query_interpreter_service.dart';
import 'package:filezen/data/ai/related_files_service.dart';
import 'package:filezen/data/ai/smart_collections_service.dart';
import 'package:filezen/domain/models/ai_models.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/search_result_item.dart';
import 'package:filezen/domain/repositories/i_auto_rename_service.dart';
import 'package:filezen/domain/repositories/i_ocr_service.dart';
import 'package:filezen/domain/repositories/i_query_interpreter_service.dart';
import 'package:filezen/domain/repositories/i_related_files_service.dart';
import 'package:filezen/domain/repositories/i_smart_collections_service.dart';
import 'package:filezen/features/documents/presentation/providers/document_providers.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/search/presentation/providers/search_providers.dart';

/// Provider for IOcrService.
final ocrServiceProvider = Provider<IOcrService>((ref) {
  return const OcrService();
});

/// Provider for IQueryInterpreterService.
final queryInterpreterServiceProvider = Provider<IQueryInterpreterService>((ref) {
  final searchRepo = ref.watch(searchRepositoryProvider);
  return QueryInterpreterService(searchRepository: searchRepo);
});

/// Provider for IAutoRenameService.
final autoRenameServiceProvider = Provider<IAutoRenameService>((ref) {
  final storageRepo = ref.watch(storageRepositoryProvider);
  final docService = ref.watch(documentServiceProvider);
  final ocrService = ref.watch(ocrServiceProvider);
  return AutoRenameService(
    storageRepository: storageRepo,
    documentService: docService,
    ocrService: ocrService,
  );
});

/// Provider for ISmartCollectionsService.
final smartCollectionsServiceProvider = Provider<ISmartCollectionsService>((ref) {
  final searchRepo = ref.watch(searchRepositoryProvider);
  return SmartCollectionsService(searchRepository: searchRepo);
});

/// Provider for IRelatedFilesService.
final relatedFilesServiceProvider = Provider<IRelatedFilesService>((ref) {
  final storageRepo = ref.watch(storageRepositoryProvider);
  final searchRepo = ref.watch(searchRepositoryProvider);
  return RelatedFilesService(
    storageRepository: storageRepo,
    searchRepository: searchRepo,
  );
});

/// Active natural query text for "Ask Your Files".
final askYourFilesQueryTextProvider = StateProvider<String>((ref) => '');

/// Interpreted intent for the active Ask Your Files query.
final activeNaturalQueryIntentProvider = Provider<NaturalQueryIntent?>((ref) {
  final query = ref.watch(askYourFilesQueryTextProvider).trim();
  if (query.isEmpty) return null;
  final interpreter = ref.watch(queryInterpreterServiceProvider);
  return interpreter.interpretQuery(query);
});

/// Async execution of Ask Your Files natural query.
final askYourFilesResultsProvider = FutureProvider<List<SearchResultItem>>((ref) async {
  final query = ref.watch(askYourFilesQueryTextProvider).trim();
  if (query.isEmpty) return [];
  final interpreter = ref.watch(queryInterpreterServiceProvider);
  return interpreter.executeAskYourFiles(query);
});

/// Smart collections overview provider with dynamic item counts.
final smartCollectionsProvider = FutureProvider<List<SmartCollection>>((ref) async {
  final service = ref.watch(smartCollectionsServiceProvider);
  return service.getSmartCollections();
});

/// Files belonging to a specific smart collection.
final collectionFilesProvider = FutureProvider.family<List<FileEntity>, String>((ref, collectionId) async {
  final service = ref.watch(smartCollectionsServiceProvider);
  return service.getFilesInCollection(collectionId);
});

/// Related files family provider for any given target file.
final relatedFilesProvider = FutureProvider.family<List<RelatedFileItem>, FileEntity>((ref, file) async {
  final service = ref.watch(relatedFilesServiceProvider);
  return service.findRelatedFiles(file);
});

/// Auto-rename history and undo manager state notifier.
class AutoRenameHistoryNotifier extends StateNotifier<List<AutoRenameHistoryItem>> {
  AutoRenameHistoryNotifier(this._service) : super(_service.getRenameHistory());

  final IAutoRenameService _service;

  void refresh() {
    state = _service.getRenameHistory();
  }

  Future<bool> undo(AutoRenameHistoryItem item) async {
    final success = await _service.undoRename(item);
    if (success) {
      refresh();
    }
    return success;
  }
}

final autoRenameHistoryNotifierProvider = StateNotifierProvider<AutoRenameHistoryNotifier, List<AutoRenameHistoryItem>>((ref) {
  final service = ref.watch(autoRenameServiceProvider);
  return AutoRenameHistoryNotifier(service);
});
