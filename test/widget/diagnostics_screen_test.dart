import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/data/monitoring/analytics_service.dart';
import 'package:filezen/data/monitoring/crash_reporter.dart';
import 'package:filezen/data/monitoring/performance_monitor.dart';
import 'package:filezen/domain/models/crash_models.dart';
import 'package:filezen/features/monitoring/presentation/providers/monitoring_providers.dart';
import 'package:filezen/features/monitoring/presentation/screens/diagnostics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticsScreen Widget Tests', () {
    late CrashReporter crashReporter;
    late PerformanceMonitor perfMonitor;
    late AnalyticsService analyticsService;

    setUp(() {
      crashReporter = CrashReporter();
      perfMonitor = PerformanceMonitor();
      analyticsService = AnalyticsService();
    });

    Widget createTestWidget({List<CrashReport>? reports}) {
      return ProviderScope(
        overrides: [
          crashReporterProvider.overrideWithValue(crashReporter),
          performanceMonitorProvider.overrideWithValue(perfMonitor),
          analyticsServiceProvider.overrideWithValue(analyticsService),
          crashReportsFutureProvider.overrideWith((ref) => Future.value(reports ?? [])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const DiagnosticsScreen(),
        ),
      );
    }

    testWidgets('renders all 4 tabs and ecosystem gateway info', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Diagnostics & Observability'), findsOneWidget);
      expect(find.text('Ecosystem'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Crash Logs'), findsOneWidget);
      expect(find.text('Telemetry'), findsOneWidget);

      // Verify Ecosystem contents
      expect(find.text('WAPCentral Gateway'), findsOneWidget);
      expect(find.text('Installed WAPCentral SDKs'), findsOneWidget);
      expect(find.text('wap_core_sdk v0.1.0'), findsOneWidget);
      expect(find.text('wap_ads_sdk v0.1.0'), findsOneWidget);
      expect(find.text('wap_notifications_sdk v0.1.0'), findsOneWidget);
      expect(find.text('wap_promo_sdk v0.1.0'), findsOneWidget);
    });

    testWidgets('switches to Performance tab and shows empty state or metrics', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap Performance tab
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();

      expect(find.text('No Performance Traces'), findsOneWidget);
    });

    testWidgets('switches to Crash Logs tab and shows empty healthy state', (tester) async {
      await tester.pumpWidget(createTestWidget(reports: []));
      await tester.pumpAndSettle();

      // Tap Crash Logs tab
      await tester.tap(find.text('Crash Logs'));
      await tester.pumpAndSettle();

      expect(find.text('No Crash Reports'), findsOneWidget);
    });

    testWidgets('switches to Telemetry tab and toggles opt-in switch', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap Telemetry tab
      await tester.tap(find.text('Telemetry'));
      await tester.pumpAndSettle();

      expect(find.text('Anonymous Analytics & Telemetry'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);

      // Toggle switch
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
    });
  });
}
