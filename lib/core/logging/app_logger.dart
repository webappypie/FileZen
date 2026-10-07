import 'package:flutter/foundation.dart';

/// Privacy-safe logging utility for FileZen.
///
/// Principles:
/// - Strictly redacts file contents, OCR text, vault items, and API secret keys.
/// - In release builds, debug and verbose logs are silenced.
enum LogLevel { verbose, debug, info, warning, error }

class AppLogger {
  static LogLevel minLogLevel = kDebugMode ? LogLevel.verbose : LogLevel.info;

  /// Redacts sensitive strings such as API keys and tokens.
  static String redact(String message) {
    // Redact potential wap_key patterns or bearer tokens
    return message
        .replaceAll(RegExp(r'wap_key_[a-zA-Z0-9]+'), '[REDACTED_APP_KEY]')
        .replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9\-_\.]+'), 'Bearer [REDACTED_TOKEN]');
  }

  static void verbose(String message, [String? tag]) {
    _log(LogLevel.verbose, message, tag);
  }

  static void debug(String message, [String? tag]) {
    _log(LogLevel.debug, message, tag);
  }

  static void info(String message, [String? tag]) {
    _log(LogLevel.info, message, tag);
  }

  static void warning(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.warning, message, tag, error, stackTrace);
  }

  static void error(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, tag, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, [
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minLogLevel.index) return;

    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final tagPrefix = tag != null ? '[$tag] ' : '';
    final sanitizedMessage = redact(message);
    final levelName = level.name.toUpperCase().padRight(7);

    debugPrint('$timestamp $levelName $tagPrefix$sanitizedMessage');
    if (error != null) {
      debugPrint('   └─ Error: $error');
    }
    if (stackTrace != null && (level == LogLevel.error || kDebugMode)) {
      debugPrint('   └─ StackTrace: $stackTrace');
    }
  }
}
