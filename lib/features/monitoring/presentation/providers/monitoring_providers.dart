import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/monitoring/analytics_service.dart';
import '../../../../data/monitoring/crash_reporter.dart';
import '../../../../data/monitoring/performance_monitor.dart';
import '../../../../data/wapcentral/wap_central_manager.dart';
import '../../../../data/wapcentral/wap_client_provider.dart';
import '../../../../domain/models/analytics_models.dart';
import '../../../../domain/models/crash_models.dart';
import '../../../../domain/models/monetization_models.dart';
import '../../../../domain/models/performance_models.dart';
import '../../../../domain/repositories/i_analytics_service.dart';
import '../../../../domain/repositories/i_crash_reporter.dart';
import '../../../../domain/repositories/i_performance_monitor.dart';
import '../../../../domain/repositories/i_wap_central_manager.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';

/// Singleton CrashReporter provider.
final crashReporterProvider = Provider<ICrashReporter>((ref) {
  return CrashReporter();
});

/// Singleton PerformanceMonitor provider.
final performanceMonitorProvider = Provider<IPerformanceMonitor>((ref) {
  return PerformanceMonitor();
});

/// Singleton AnalyticsService provider.
final analyticsServiceProvider = Provider<IAnalyticsService>((ref) {
  return AnalyticsService();
});

/// Coordinator provider for WAPCentral stack.
final wapCentralManagerProvider = Provider<IWapCentralManager>((ref) {
  final config = ref.watch(appConfigProvider);
  final notifRepo = ref.watch(notificationRepositoryProvider);
  final manager = WapCentralManager(
    config: config,
    notificationRepository: notifRepo,
  );
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Reactive notifier managing MonetizationState.
class MonetizationNotifier extends StateNotifier<MonetizationState> {
  final IWapCentralManager _manager;

  MonetizationNotifier(this._manager) : super(_manager.monetizationState) {
    _manager.monetizationStream.listen((newState) {
      if (mounted) {
        state = newState;
      }
    });
  }

  Future<void> setAdFreePurchased(bool purchased) async {
    await _manager.setAdFreePurchased(purchased);
    if (mounted) {
      state = _manager.monetizationState;
    }
  }
}

/// Reactive active monetization state provider.
final monetizationStateProvider =
    StateNotifierProvider<MonetizationNotifier, MonetizationState>((ref) {
  final manager = ref.watch(wapCentralManagerProvider);
  return MonetizationNotifier(manager);
});

/// Provider for user telemetry and crash reporting opt-in status.
final telemetryOptInProvider = StateProvider<bool>((ref) => true);

/// FutureProvider loading local crash reports.
final crashReportsFutureProvider = FutureProvider.autoDispose<List<CrashReport>>((ref) async {
  final reporter = ref.watch(crashReporterProvider);
  return await reporter.getCrashReports();
});

/// Provider exposing calculated performance summaries.
final performanceSummariesProvider = Provider.autoDispose<Map<String, PerformanceSummary>>((ref) {
  final monitor = ref.watch(performanceMonitorProvider);
  return monitor.getSummaries();
});

/// Provider exposing recent privacy-sanitized analytics events.
final recentAnalyticsEventsProvider = Provider.autoDispose<List<AnalyticsEvent>>((ref) {
  final analytics = ref.watch(analyticsServiceProvider);
  return analytics.getRecentEvents();
});
