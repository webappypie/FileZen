import 'package:filezen/data/monitoring/performance_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerformanceMonitor Unit Tests', () {
    late PerformanceMonitor monitor;

    setUp(() {
      monitor = PerformanceMonitor();
    });

    test('measures async closure duration and records trace', () async {
      final result = await monitor.measure<int>('db_query', () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 42;
      });

      expect(result, equals(42));
      final traces = monitor.getRecentTraces();
      expect(traces.length, equals(1));
      expect(traces.first.traceName, equals('db_query'));
      expect(traces.first.durationMs, greaterThanOrEqualTo(10));
      expect(traces.first.success, isTrue);
    });

    test('records failed measurement on exception without swallowing error', () async {
      await expectLater(
        monitor.measure<void>('faulty_op', () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          throw const FormatException('Malformed payload');
        }),
        throwsA(isA<FormatException>()),
      );

      final traces = monitor.getRecentTraces();
      expect(traces.length, equals(1));
      expect(traces.first.traceName, equals('faulty_op'));
      expect(traces.first.success, isFalse);
    });

    test('calculates accurate aggregate statistics and percentiles', () {
      // Simulate trace samples manually by starting and stopping
      monitor.startTrace('fts_search');
      monitor.stopTrace('fts_search');

      monitor.startTrace('fts_search');
      monitor.stopTrace('fts_search');

      final summaries = monitor.getSummaries();
      expect(summaries.containsKey('fts_search'), isTrue);
      final summary = summaries['fts_search']!;

      expect(summary.count, equals(2));
      expect(summary.minMs, greaterThanOrEqualTo(0));
      expect(summary.maxMs, greaterThanOrEqualTo(summary.minMs));
      expect(summary.avgMs, greaterThanOrEqualTo(0.0));
      expect(summary.p95Ms, greaterThanOrEqualTo(0));
    });

    test('clears active and recorded traces', () {
      monitor.startTrace('op_1');
      monitor.stopTrace('op_1');

      expect(monitor.getRecentTraces().length, equals(1));

      monitor.clearTraces();
      expect(monitor.getRecentTraces(), isEmpty);
      expect(monitor.getSummaries(), isEmpty);
    });
  });
}
