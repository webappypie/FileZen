import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../domain/models/indexing_progress.dart';
import '../../../../domain/repositories/i_permission_service.dart';
import '../../../ai/presentation/providers/ai_providers.dart';
import '../../../clean/presentation/providers/clean_providers.dart';
import '../../../files/presentation/providers/category_files_providers.dart';
import '../../../files/presentation/providers/storage_providers.dart';
import 'search_providers.dart';

/// Keeps the index current without the user starting full scans by hand.
///
/// * an incremental scan shortly after launch, once storage access is granted;
/// * another when the app returns to the foreground (at most every
///   [minInterval]) and periodically while it stays open;
/// * indexing pauses while the app is in the background (no work while the
///   user is elsewhere; Android may also freeze the process).
///
/// Scans are incremental: unchanged files are skipped, new/changed files are
/// indexed, deleted files are pruned. When a scan changed anything, every view
/// derived from the index (Home counts, category lists, collections, Storage
/// Intelligence) is refreshed.
///
/// Work while FileZen is closed would need a WorkManager job (a new
/// dependency, not approved yet); this covers foreground use only.
class IndexingCoordinator with WidgetsBindingObserver {
  IndexingCoordinator(this._ref) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;
  Timer? _pending;
  Timer? _periodic;
  DateTime? _lastStartedAt;
  bool _disposed = false;

  static const startupDelay = Duration(seconds: 3);
  static const minInterval = Duration(minutes: 10);
  static const periodicInterval = Duration(minutes: 30);

  bool get _hasPermission =>
      _ref.read(storagePermissionStateProvider).valueOrNull == StoragePermissionStatus.granted;

  void onPermissionChanged(StoragePermissionStatus? status) {
    if (status == StoragePermissionStatus.granted) {
      _schedule(startupDelay);
      _startPeriodic();
    }
  }

  void onProgress(IndexingProgress? previous, IndexingProgress next) {
    final finished = next.status == IndexingStatus.completed && previous?.status != IndexingStatus.completed;
    if (!finished) return;
    if (next.indexedCount + next.removedCount == 0 && (previous?.pendingOcrCount ?? 0) == next.pendingOcrCount) {
      return;
    }
    _ref.invalidate(categoryFileCountsProvider);
    _ref.invalidate(categoryFilesListProvider);
    _ref.invalidate(collectionFilesProvider);
    _ref.invalidate(smartCollectionsProvider);
    _ref.invalidate(storageOverviewProvider);
    _ref.invalidate(topFoldersProvider);
    _ref.invalidate(largestFilesProvider);
  }

  void _schedule(Duration delay) {
    if (_disposed) return;
    _pending?.cancel();
    _pending = Timer(delay, () => unawaited(_run()));
  }

  void _startPeriodic() {
    if (_disposed) return;
    _periodic?.cancel();
    _periodic = Timer.periodic(periodicInterval, (_) => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_disposed || !_hasPermission) return;
    final notifier = _ref.read(indexingProgressProvider.notifier);
    if (_ref.read(indexingProgressProvider).isRunning) return;
    _lastStartedAt = DateTime.now();
    try {
      await notifier.startIndexing();
    } catch (e) {
      AppLogger.warning('Automatic indexing failed: $e', 'IndexingCoordinator');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = _ref.read(indexingServiceProvider);
    if (state == AppLifecycleState.paused) {
      service.pause();
      _pending?.cancel();
      _periodic?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      service.resume();
      // Free space may have changed while away; access may have been granted in Settings.
      _ref.invalidate(deviceStorageStatsProvider);
      unawaited(_ref.read(storagePermissionStateProvider.notifier).refresh());
      final last = _lastStartedAt;
      if (last == null || DateTime.now().difference(last) >= minInterval) {
        _schedule(const Duration(seconds: 1));
      }
      if (_hasPermission) _startPeriodic();
    }
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _periodic?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Keep-alive provider; read once at app start.
final indexingCoordinatorProvider = Provider<IndexingCoordinator>((ref) {
  final coordinator = IndexingCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  ref.listen<IndexingProgress>(indexingProgressProvider, coordinator.onProgress);
  ref.listen<AsyncValue<StoragePermissionStatus>>(
    storagePermissionStateProvider,
    (_, next) => coordinator.onPermissionChanged(next.valueOrNull),
    fireImmediately: true,
  );
  return coordinator;
});
