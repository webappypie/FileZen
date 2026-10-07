import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/services/permission_service.dart';
import '../../../../data/storage/filesystem_storage_repository.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/models/storage_location.dart';
import '../../../../domain/repositories/i_permission_service.dart';
import '../../../../domain/repositories/i_storage_repository.dart';

/// Provider for IPermissionService.
final permissionServiceProvider = Provider<IPermissionService>((ref) {
  return PermissionService();
});

/// Provider for IStorageRepository.
final storageRepositoryProvider = Provider<IStorageRepository>((ref) {
  return FilesystemStorageRepository();
});

/// Provider managing storage permission state.
final storagePermissionStateProvider =
    AsyncNotifierProvider<StoragePermissionNotifier, StoragePermissionStatus>(StoragePermissionNotifier.new);

class StoragePermissionNotifier extends AsyncNotifier<StoragePermissionStatus> {
  @override
  Future<StoragePermissionStatus> build() async {
    final service = ref.watch(permissionServiceProvider);
    return await service.checkStoragePermission();
  }

  Future<StoragePermissionStatus> requestPermission() async {
    state = const AsyncValue.loading();
    final service = ref.read(permissionServiceProvider);
    final status = await service.requestStoragePermission();
    state = AsyncValue.data(status);
    return status;
  }

  Future<void> refresh() async {
    final service = ref.read(permissionServiceProvider);
    final status = await service.checkStoragePermission();
    state = AsyncValue.data(status);
  }
}

/// Provider loading available storage locations.
final storageLocationsProvider = FutureProvider<List<StorageLocation>>((ref) async {
  final repo = ref.watch(storageRepositoryProvider);
  return await repo.getStorageLocations();
});

/// Currently active directory path in the Files tab.
final currentDirectoryPathProvider = StateProvider<String?>((ref) => null);

/// Provider loading file entries for a specific directory path.
final directoryContentsProvider =
    FutureProvider.family<List<FileEntity>, String>((ref, path) async {
  final repo = ref.watch(storageRepositoryProvider);
  return await repo.listDirectory(path);
});
