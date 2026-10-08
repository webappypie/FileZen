import 'dart:async';
import '../../core/logging/app_logger.dart';
import '../../domain/models/performance_models.dart';
import '../../domain/repositories/i_performance_monitor.dart';

/// Concrete implementation of IPerformanceMonitor for tracking operation latencies.
///
/// Principles:
/// - In-memory circular buffer with lightweight execution.
/// - Calculates aggregates (avg, min, max, p95) on demand without blocking UI thread.
class PerformanceMonitor implements IPerformanceMonitor {
  final Map<String, Stopwatch> _activeStopwatches = {};
  final List<PerformanceTrace> _traces = [];
  static const int _maxTraces = 100;

  @override
  void startTrace(String name) {
    final sw = Stopwatch()..start();
    _activeStopwatches[name] = sw;
  }

  @override
  void stopTrace(
    String name, {
    bool success = true,
    Map<String, dynamic>? metadata,
  }) {
    final sw = _activeStopwatches.remove(name);
    if (sw == null) return;
    sw.stop();

    final trace = PerformanceTrace(
      traceName: name,
      startTime: DateTime.now().subtract(sw.elapsed),
      durationMs: sw.elapsedMilliseconds,
      success: success,
      metadata: metadata ?? const {},
    );

    _recordTrace(trace);
  }

  @override
  Future<T> measure<T>(
    String name,
    Future<T> Function() action, {
    Map<String, dynamic>? metadata,
  }) async {
    final sw = Stopwatch()..start();
    bool success = true;
    try {
      return await action();
    } catch (_) {
      success = false;
      rethrow;
    } finally {
      sw.stop();
      final trace = PerformanceTrace(
        traceName: name,
        startTime: DateTime.now().subtract(sw.elapsed),
        durationMs: sw.elapsedMilliseconds,
        success: success,
        metadata: metadata ?? const {},
      );
      _recordTrace(trace);
    }
  }

  void _recordTrace(PerformanceTrace trace) {
    _traces.insert(0, trace);
    if (_traces.length > _maxTraces) {
      _traces.removeLast();
    }
    AppLogger.debug(
      'Performance trace [${trace.traceName}]: ${trace.durationMs}ms (success: ${trace.success})',
      'PerformanceMonitor',
    );
  }

  @override
  List<PerformanceTrace> getRecentTraces() {
    return List.unmodifiable(_traces);
  }

  @override
  Map<String, PerformanceSummary> getSummaries() {
    final Map<String, List<int>> durationsByMetric = {};

    for (final trace in _traces) {
      durationsByMetric.putIfAbsent(trace.traceName, () => []).add(trace.durationMs);
    }

    final Map<String, PerformanceSummary> summaries = {};

    durationsByMetric.forEach((name, durations) {
      if (durations.isEmpty) return;
      durations.sort();
      final count = durations.length;
      final total = durations.fold<int>(0, (sum, val) => sum + val);
      final avg = total / count;
      final min = durations.first;
      final max = durations.last;

      // 95th percentile
      final p95Index = ((count * 0.95).ceil() - 1).clamp(0, count - 1);
      final p95 = durations[p95Index];

      summaries[name] = PerformanceSummary(
        metricName: name,
        count: count,
        avgMs: double.parse(avg.toStringAsFixed(1)),
        minMs: min,
        maxMs: max,
        p95Ms: p95,
      );
    });

    return summaries;
  }

  @override
  void clearTraces() {
    _traces.clear();
    _activeStopwatches.clear();
  }
}
