import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler/permission_handler.dart' as ph show openAppSettings;
import '../../core/logging/app_logger.dart';
import '../../domain/repositories/i_permission_service.dart';

/// Implementation of IPermissionService using permission_handler.
class PermissionService implements IPermissionService {
  @override
  Future<StoragePermissionStatus> checkStoragePermission() async {
    // Non-Android platforms (e.g. Windows during development/testing) grant access by default
    if (!Platform.isAndroid) {
      return StoragePermissionStatus.granted;
    }

    try {
      // Check MANAGE_EXTERNAL_STORAGE first for Android 11+
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) {
        return StoragePermissionStatus.granted;
      }

      // Check legacy storage permission for Android 10 and below
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) {
        return StoragePermissionStatus.granted;
      }

      if (manageStatus.isPermanentlyDenied || storageStatus.isPermanentlyDenied) {
        return StoragePermissionStatus.permanentlyDenied;
      }

      if (manageStatus.isRestricted || storageStatus.isRestricted) {
        return StoragePermissionStatus.restricted;
      }

      return StoragePermissionStatus.denied;
    } catch (e) {
      AppLogger.warning('Failed to check storage permission: $e', 'PermissionService');
      return StoragePermissionStatus.denied;
    }
  }

  @override
  Future<StoragePermissionStatus> requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return StoragePermissionStatus.granted;
    }

    try {
      // First attempt MANAGE_EXTERNAL_STORAGE (Android 11+)
      var status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        return StoragePermissionStatus.granted;
      }

      // Fall back to legacy STORAGE permission for Android 10 and below
      status = await Permission.storage.request();
      if (status.isGranted) {
        return StoragePermissionStatus.granted;
      }

      if (status.isPermanentlyDenied) {
        return StoragePermissionStatus.permanentlyDenied;
      }

      return StoragePermissionStatus.denied;
    } catch (e) {
      AppLogger.error('Failed to request storage permission: $e', 'PermissionService');
      return StoragePermissionStatus.denied;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await ph.openAppSettings();
    } catch (e) {
      AppLogger.error('Failed to open app settings: $e', 'PermissionService');
      return false;
    }
  }
}
