enum StoragePermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

/// Domain contract for managing device storage permissions.
abstract class IPermissionService {
  /// Checks current storage permission status.
  Future<StoragePermissionStatus> checkStoragePermission();

  /// Requests storage permission from the user.
  Future<StoragePermissionStatus> requestStoragePermission();

  /// Opens the device app settings screen when permanently denied.
  Future<bool> openAppSettings();
}
