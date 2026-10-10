import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';

/// Decides whether CPU-heavy background work (OCR) may run right now.
///
/// Heavy work is deferred while battery saver is on, the battery is low and
/// not charging, or Android reports thermal status SEVERE or worse.
class DeviceConditionsService {
  DeviceConditionsService({MethodChannel? channel, bool? isAndroid})
      : _channel = channel ?? const MethodChannel('com.webappypie.filezen/device'),
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _isAndroid;

  static const int lowBatteryPercent = 20;

  /// `PowerManager.THERMAL_STATUS_SEVERE`.
  static const int severeThermalStatus = 3;

  Future<bool> heavyWorkAllowed() async {
    if (!_isAndroid) return true;
    try {
      final c = await _channel.invokeMapMethod<String, dynamic>('deviceConditions');
      if (c == null) return true;
      final powerSave = c['powerSave'] == true;
      final charging = c['charging'] == true;
      final battery = (c['batteryPercent'] as num?)?.toInt() ?? 100;
      final thermal = (c['thermalStatus'] as num?)?.toInt() ?? 0;
      return !powerSave &&
          thermal < severeThermalStatus &&
          (charging || battery >= lowBatteryPercent);
    } catch (e) {
      AppLogger.debug('Device conditions unavailable: $e', 'DeviceConditions');
      return true;
    }
  }
}
