import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/crash_models.dart';
import '../../domain/repositories/i_crash_reporter.dart';

/// Implementation of ICrashReporter providing privacy-safe local crash logging.
///
/// Principles:
/// - Absolute privacy: scrubs local paths, user identifiers, secrets, and auth tokens.
/// - Circular buffer: retains the last 50 crash records to avoid storage inflation.
/// - Never crashes the host: errors during crash logging are safely caught and silenced.
class CrashReporter implements ICrashReporter {
  final String? customStoragePath;
  bool _isEnabled = true;
  List<CrashReport>? _cachedReports;
  static const int _maxStoredReports = 50;

  CrashReporter({this.customStoragePath, bool initialEnabled = true})
      : _isEnabled = initialEnabled;

  @override
  bool get isEnabled => _isEnabled;

  Future<File> _getStorageFile() async {
    if (customStoragePath != null) {
      final file = File(customStoragePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, '.filezen_crash_reports.json'));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<void> _ensureLoaded() async {
    if (_cachedReports != null) return;
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(text) as List<dynamic>;
          _cachedReports = jsonList
              .map((item) => CrashReport.fromJson(item as Map<String, dynamic>))
              .toList();
          return;
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to read crash reports from disk: $e', 'CrashReporter');
    }
    _cachedReports = [];
  }

  Future<void> _persist() async {
    if (_cachedReports == null) return;
    try {
      final file = await _getStorageFile();
      final jsonString = jsonEncode(_cachedReports!.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (e) {
      AppLogger.warning('Failed to persist crash reports: $e', 'CrashReporter');
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
  }

  /// Sanitizes text to remove local personal paths, secrets, and sensitive tokens.
  String _scrubSensitiveContent(String raw) {
    var sanitized = AppLogger.redact(raw);

    // Scrub Android internal/external user paths
    sanitized = sanitized.replaceAll(
      RegExp(r'/storage/emulated/\d+/[^\s,)]+'),
      '[EXTERNAL_STORAGE_PATH]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'/data/user/\d+/[^\s,)]+'),
      '[INTERNAL_APP_PATH]',
    );

    // Scrub Windows user folder paths
    sanitized = sanitized.replaceAll(
      RegExp(r'[A-Za-z]:\\Users\\[^\\]+\\', caseSensitive: false),
      '[USER_PROFILE_DIR]\\',
    );

    // Scrub email addresses
    sanitized = sanitized.replaceAll(
      RegExp(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+'),
      '[REDACTED_EMAIL]',
    );

    return sanitized;
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool isFatal = false,
    String? context,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isEnabled) return;

    try {
      await _ensureLoaded();

      final scrubbedMessage = _scrubSensitiveContent(error.toString());
      final scrubbedStack = _scrubSensitiveContent(stackTrace.toString());

      final report = CrashReport(
        id: 'crash_${DateTime.now().millisecondsSinceEpoch}_${(_cachedReports!.length + 1)}',
        timestamp: DateTime.now(),
        errorType: error.runtimeType.toString(),
        message: scrubbedMessage,
        stackTrace: scrubbedStack,
        isFatal: isFatal,
        deviceInfo: {
          'platform': defaultTargetPlatform.name,
          'isWeb': kIsWeb,
          'isRelease': kReleaseMode,
        },
        customContext: {
          if (context != null) 'context': context,
          if (metadata != null)
            ...metadata.map((k, v) => MapEntry(k, _scrubSensitiveContent(v.toString()))),
        },
      );

      _cachedReports!.insert(0, report);
      if (_cachedReports!.length > _maxStoredReports) {
        _cachedReports = _cachedReports!.sublist(0, _maxStoredReports);
      }

      await _persist();
      AppLogger.info('Recorded diagnostic crash report (${report.id})', 'CrashReporter');
    } catch (_) {
      // Never crash during error recording
    }
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    await recordError(
      details.exception,
      details.stack ?? StackTrace.empty,
      isFatal: false,
      context: details.context?.toString(),
      metadata: {
        'library': details.library ?? 'flutter_framework',
      },
    );
  }

  @override
  Future<List<CrashReport>> getCrashReports() async {
    await _ensureLoaded();
    return List.unmodifiable(_cachedReports ?? []);
  }

  @override
  Future<void> clearCrashReports() async {
    await _ensureLoaded();
    _cachedReports!.clear();
    await _persist();
    AppLogger.info('Cleared local crash reports', 'CrashReporter');
  }
}
