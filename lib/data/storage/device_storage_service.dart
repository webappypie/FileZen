import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/storage_intelligence_models.dart';

/// Reads real volume capacity from the OS.
abstract class IDeviceStorageService {
  /// Current stats of the shared-storage volume, or `null` when the device
  /// cannot be measured (never a guessed/nominal value).
  Future<DeviceStorageStats?> getStats();
}

class DeviceStorageService implements IDeviceStorageService {
  DeviceStorageService({MethodChannel? channel, bool? isAndroid})
      : _channel = channel ?? const MethodChannel('com.webappypie.filezen/device'),
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _isAndroid;

  @override
  Future<DeviceStorageStats?> getStats() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('storageStats');
      final total = (raw?['totalBytes'] as num?)?.toInt() ?? 0;
      final free = (raw?['availableBytes'] as num?)?.toInt() ?? 0;
      if (total <= 0 || free < 0 || free > total) return null;
      return DeviceStorageStats(totalBytes: total, freeBytes: free, measuredAt: DateTime.now());
    } catch (e) {
      AppLogger.warning('Device storage stats unavailable: $e', 'DeviceStorage');
      return null;
    }
  }
}
