import '../models/performance_models.dart';

/// Abstract contract for tracking latency and execution performance.
abstract class IPerformanceMonitor {
  /// Starts a performance trace with the given name.
  void startTrace(String name);

  /// Stops a running trace and records the elapsed latency.
  void stopTrace(
    String name, {
    bool success = true,
    Map<String, dynamic>? metadata,
  });

  /// Executes an asynchronous block and measures its duration.
  Future<T> measure<T>(
    String name,
    Future<T> Function() action, {
    Map<String, dynamic>? metadata,
  });

  /// Returns recent traces recorded in the active session.
  List<PerformanceTrace> getRecentTraces();

  /// Calculates statistical summaries (count, average, p95, min, max) per metric.
  Map<String, PerformanceSummary> getSummaries();

  /// Clears in-memory performance traces.
  void clearTraces();
}
