import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/cleanup/deduplication_service.dart';
import '../../../../data/cleanup/storage_hygiene_service.dart';
import '../../../../data/cleanup/timeline_service.dart';
import '../../../../data/cleanup/trash_recovery_service.dart';
import '../../../../data/database/database_provider.dart';
import '../../../../domain/models/cleanup_models.dart';
import '../../../../domain/models/deduplication_models.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/models/storage_intelligence_models.dart';
import '../../../../domain/models/timeline_models.dart';
import '../../../../domain/models/trash_item.dart';
import '../../../../domain/repositories/i_deduplication_service.dart';
import '../../../../domain/repositories/i_storage_hygiene_service.dart';
import '../../../../domain/repositories/i_timeline_service.dart';
import '../../../../domain/repositories/i_trash_recovery_service.dart';
import '../../../files/presentation/providers/storage_providers.dart';

/// Provider for ITrashRecoveryService.
final trashRecoveryServiceProvider = Provider<ITrashRecoveryService>((ref) {
  final storageRepo = ref.watch(storageRepositoryProvider);
  return TrashRecoveryService(storageRepo: storageRepo);
});

/// Provider for IStorageHygieneService.
final storageHygieneServiceProvider = Provider<IStorageHygieneService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final storageRepo = ref.watch(storageRepositoryProvider);
  return StorageHygieneService(db: db, storageRepo: storageRepo);
});

/// Provider for IDeduplicationService.
final deduplicationServiceProvider = Provider<IDeduplicationService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final storageRepo = ref.watch(storageRepositoryProvider);
  final trashService = ref.watch(trashRecoveryServiceProvider);
  return DeduplicationService(
    db: db,
    storageRepo: storageRepo,
    trashService: trashService,
  );
});

/// Provider for ITimelineService.
final timelineServiceProvider = Provider<ITimelineService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final storageRepo = ref.watch(storageRepositoryProvider);
  return TimelineService(db: db, storageRepo: storageRepo);
});

/// Storage overview provider. Device totals are the shared
/// [deviceStorageStatsProvider] measurement (the same value the Home card shows).
final storageOverviewProvider = FutureProvider<StorageOverview>((ref) async {
  final hygieneService = ref.watch(storageHygieneServiceProvider);
  final deviceStats = await ref.watch(deviceStorageStatsProvider.future);
  // Builds the 12-hourly usage history from real measurements only.
  unawaited(hygieneService.recordCurrentStorageSnapshot(deviceStats: deviceStats));
  return await hygieneService.getStorageOverview(deviceStats: deviceStats);
});

/// Storage historical trends provider.
final storageTrendsProvider = FutureProvider<List<StorageTrendPoint>>((ref) async {
  final hygieneService = ref.watch(storageHygieneServiceProvider);
  return await hygieneService.getStorageTrends();
});

/// Top space-consuming directories provider.
final topFoldersProvider = FutureProvider<List<FolderStorageItem>>((ref) async {
  final hygieneService = ref.watch(storageHygieneServiceProvider);
  return await hygieneService.getTopFolders();
});

/// Largest individual files provider.
final largestFilesProvider = FutureProvider<List<FileEntity>>((ref) async {
  final hygieneService = ref.watch(storageHygieneServiceProvider);
  return await hygieneService.getLargestFiles();
});

/// Aggregated cleanup opportunities provider across all 10 hygiene categories.
final cleanupOpportunitiesProvider = FutureProvider<List<CleanupCandidateGroup>>((ref) async {
  final dedupService = ref.watch(deduplicationServiceProvider);
  return await dedupService.scanAllCleanupOpportunities();
});

/// Exact duplicate clusters provider.
final exactDuplicatesProvider = FutureProvider<List<DuplicateGroup>>((ref) async {
  final dedupService = ref.watch(deduplicationServiceProvider);
  return await dedupService.scanExactDuplicates();
});

/// Timeline groups family provider.
final timelineGroupsProvider =
    FutureProvider.family<List<TimelineGroup>, FileCategory?>((ref, categoryFilter) async {
  final timelineService = ref.watch(timelineServiceProvider);
  return await timelineService.getTimelineGroups(categoryFilter: categoryFilter);
});

/// Async notifier managing Recycle Bin / Trash items and operations.
class TrashItemsNotifier extends AsyncNotifier<List<TrashItem>> {
  @override
  Future<List<TrashItem>> build() async {
    final trashService = ref.watch(trashRecoveryServiceProvider);
    return await trashService.listTrash();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final trashService = ref.read(trashRecoveryServiceProvider);
    state = AsyncValue.data(await trashService.listTrash());
  }

  Future<bool> restore(TrashItem item) async {
    final trashService = ref.read(trashRecoveryServiceProvider);
    final res = await trashService.restoreFromTrash(item);
    if (res.isSuccess) {
      await refresh();
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(storageOverviewProvider);
      return true;
    }
    return false;
  }

  Future<bool> batchRestore(List<TrashItem> items) async {
    final trashService = ref.read(trashRecoveryServiceProvider);
    final res = await trashService.batchRestoreFromTrash(items);
    if (res.isSuccess) {
      await refresh();
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(storageOverviewProvider);
      return true;
    }
    return false;
  }

  Future<bool> permanentlyDelete(TrashItem item) async {
    final trashService = ref.read(trashRecoveryServiceProvider);
    final res = await trashService.permanentlyDelete(item);
    if (res.isSuccess) {
      await refresh();
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(storageOverviewProvider);
      return true;
    }
    return false;
  }

  Future<bool> batchPermanentlyDelete(List<TrashItem> items) async {
    final trashService = ref.read(trashRecoveryServiceProvider);
    final res = await trashService.batchPermanentlyDelete(items);
    if (res.isSuccess) {
      await refresh();
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(storageOverviewProvider);
      return true;
    }
    return false;
  }

  Future<bool> emptyTrash() async {
    final trashService = ref.read(trashRecoveryServiceProvider);
    final res = await trashService.emptyTrash();
    if (res.isSuccess) {
      await refresh();
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(storageOverviewProvider);
      return true;
    }
    return false;
  }
}

final trashItemsProvider =
    AsyncNotifierProvider<TrashItemsNotifier, List<TrashItem>>(TrashItemsNotifier.new);
