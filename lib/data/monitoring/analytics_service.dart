import 'dart:async';
import '../../core/logging/app_logger.dart';
import '../../domain/models/analytics_models.dart';
import '../../domain/repositories/i_analytics_service.dart';

/// Concrete implementation of IAnalyticsService with strict privacy enforcement.
///
/// Principles:
/// - Absolute privacy: Prohibits logging file names, file paths, content excerpts, and secrets.
/// - In-memory event buffer (last 100 events) for local transparency and diagnostics inspection.
/// - Drop-on-disable: If the user opts out, all incoming events are immediately dropped.
class AnalyticsService implements IAnalyticsService {
  bool _isEnabled = true;
  final List<AnalyticsEvent> _events = [];
  static const int _maxEvents = 100;

  // Forbidden keys that could carry PII or confidential file metadata
  static final RegExp _forbiddenKeyPattern = RegExp(
    r'(path|filename|file_name|content|ocr|secret|key|token|password|pin|hash|url)',
    caseSensitive: false,
  );

  AnalyticsService({bool initialEnabled = true}) : _isEnabled = initialEnabled;

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
  }

  /// Sanitizes parameter map, removing any key or string value that contains PII or sensitive patterns.
  Map<String, dynamic> _sanitizeParameters(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const {};

    final sanitized = <String, dynamic>{};
    raw.forEach((key, value) {
      if (_forbiddenKeyPattern.hasMatch(key)) {
        // Redact or drop sensitive keys
        sanitized[key] = '[REDACTED]';
      } else if (value is String) {
        // Redact potential emails, tokens, or paths in strings
        sanitized[key] = AppLogger.redact(value);
      } else if (value is num || value is bool) {
        sanitized[key] = value;
      } else {
        sanitized[key] = value.toString();
      }
    });
    return sanitized;
  }

  @override
  Future<void> logEvent(
    String eventName, {
    Map<String, dynamic>? parameters,
  }) async {
    if (!_isEnabled) return;

    final sanitizedParams = _sanitizeParameters(parameters);
    final event = AnalyticsEvent(
      id: 'evt_${DateTime.now().millisecondsSinceEpoch}_${_events.length + 1}',
      name: eventName,
      timestamp: DateTime.now(),
      parameters: sanitizedParams,
    );

    _events.insert(0, event);
    if (_events.length > _maxEvents) {
      _events.removeLast();
    }

    AppLogger.debug('Analytics event: $eventName $sanitizedParams', 'Analytics');
  }

  @override
  Future<void> logScreenView(String screenName) async {
    await logEvent('screen_view', parameters: {'screen_name': screenName});
  }

  @override
  List<AnalyticsEvent> getRecentEvents() {
    return List.unmodifiable(_events);
  }

  @override
  void clearEvents() {
    _events.clear();
  }
}
