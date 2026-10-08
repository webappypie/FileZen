/// Data model representing a latency or resource performance measurement.
///
/// Designed to measure execution metrics without storing personal or file data.
class PerformanceTrace {
  final String traceName;
  final DateTime startTime;
  final int durationMs;
  final bool success;
  final Map<String, dynamic> metadata;

  const PerformanceTrace({
    required this.traceName,
    required this.startTime,
    required this.durationMs,
    this.success = true,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'traceName': traceName,
        'startTime': startTime.toIso8601String(),
        'durationMs': durationMs,
        'success': success,
        'metadata': metadata,
      };

  factory PerformanceTrace.fromJson(Map<String, dynamic> json) {
    return PerformanceTrace(
      traceName: json['traceName'] as String? ?? 'unknown',
      startTime: json['startTime'] != null
          ? DateTime.tryParse(json['startTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      durationMs: json['durationMs'] as int? ?? 0,
      success: json['success'] as bool? ?? true,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// Aggregated statistical summary for a performance metric.
class PerformanceSummary {
  final String metricName;
  final int count;
  final double avgMs;
  final int minMs;
  final int maxMs;
  final int p95Ms;

  const PerformanceSummary({
    required this.metricName,
    required this.count,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.p95Ms,
  });

  Map<String, dynamic> toJson() => {
        'metricName': metricName,
        'count': count,
        'avgMs': avgMs,
        'minMs': minMs,
        'maxMs': maxMs,
        'p95Ms': p95Ms,
      };
}
