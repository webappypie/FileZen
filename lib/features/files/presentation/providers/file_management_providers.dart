import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/archive_service.dart';
import '../../../../domain/models/file_clipboard.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/models/file_operation_models.dart';
import '../../../../domain/models/file_sort_criteria.dart';
import '../../../../domain/repositories/i_archive_service.dart';
import 'storage_providers.dart';

/// Provider for IArchiveService (ZIP creation and extraction).
final archiveServiceProvider = Provider<IArchiveService>((ref) {
  return ArchiveService();
});

/// Current file sorting criteria (field, direction, foldersFirst).
final fileSortCriteriaProvider = StateProvider<FileSortCriteria>((ref) {
  return const FileSortCriteria();
});

/// Whether hidden files (starting with dot) are visible.
final showHiddenFilesProvider = StateProvider<bool>((ref) => false);

/// Active clipboard state for copy/cut operations.
final fileClipboardProvider = StateProvider<FileClipboard?>((ref) => null);

/// Currently running background file operation progress.
final activeOperationProgressProvider = StateProvider<FileOperationProgress?>((ref) => null);

/// Set of selected file paths for multi-selection mode.
final selectedFilePathsProvider =
    StateNotifierProvider<SelectedFilesNotifier, Set<String>>((ref) {
  return SelectedFilesNotifier();
});

class SelectedFilesNotifier extends StateNotifier<Set<String>> {
  SelectedFilesNotifier() : super({});

  void toggle(String path) {
    if (state.contains(path)) {
      state = Set.from(state)..remove(path);
    } else {
      state = Set.from(state)..add(path);
    }
  }

  void selectAll(Iterable<String> paths) {
    state = Set.from(paths);
  }

  void clear() {
    state = {};
  }
}

/// Provider that returns filtered and sorted files for a directory path.
final sortedDirectoryContentsProvider =
    Provider.family<AsyncValue<List<FileEntity>>, String>((ref, path) {
  final contentsAsync = ref.watch(directoryContentsProvider(path));
  final criteria = ref.watch(fileSortCriteriaProvider);
  final showHidden = ref.watch(showHiddenFilesProvider);

  return contentsAsync.whenData((list) {
    final filtered = showHidden ? list : list.where((f) => !f.isHidden).toList();
    return criteria.apply(filtered);
  });
});
