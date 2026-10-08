import 'package:flutter/foundation.dart';
import '../models/crash_models.dart';

/// Abstract contract for privacy-preserving crash and error reporting.
abstract class ICrashReporter {
  /// Whether crash reporting and error recording is enabled (opt-in/opt-out).
  bool get isEnabled;

  /// Sets whether crash reporting is enabled.
  Future<void> setEnabled(bool enabled);

  /// Records an unhandled or caught application error with scrubbed metadata.
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool isFatal = false,
    String? context,
    Map<String, dynamic>? metadata,
  });

  /// Records a Flutter framework error details.
  Future<void> recordFlutterError(FlutterErrorDetails details);

  /// Retrieves locally stored crash and error reports for inspection.
  Future<List<CrashReport>> getCrashReports();

  /// Clears all locally stored crash reports.
  Future<void> clearCrashReports();
}
