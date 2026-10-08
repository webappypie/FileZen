import '../models/analytics_models.dart';

/// Abstract contract for privacy-first user action and navigation analytics.
abstract class IAnalyticsService {
  /// Whether analytics tracking is actively enabled by the user.
  bool get isEnabled;

  /// Updates user consent for analytics collection.
  Future<void> setEnabled(bool enabled);

  /// Logs a privacy-sanitized feature event.
  /// Any parameter containing file paths, contents, or secrets is automatically filtered out.
  Future<void> logEvent(
    String eventName, {
    Map<String, dynamic>? parameters,
  });

  /// Logs a screen navigation event.
  Future<void> logScreenView(String screenName);

  /// Returns recent sanitized events captured during the session.
  List<AnalyticsEvent> getRecentEvents();

  /// Clears in-memory analytics event log.
  void clearEvents();
}
