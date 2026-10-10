import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../data/wapcentral/wap_client_provider.dart';
import '../../../../domain/models/crash_models.dart';
import '../providers/monitoring_providers.dart';

/// Diagnostics & Observability dashboard screen.
///
/// Provides complete local transparency into performance metrics, scrubbed crash reports,
/// privacy-safe telemetry events, and WAPCentral SDK ecosystem status.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportDiagnostics(BuildContext context) async {
    final crashReports = await ref.read(crashReporterProvider).getCrashReports();
    final summaries = ref.read(performanceMonitorProvider).getSummaries();
    final events = ref.read(analyticsServiceProvider).getRecentEvents();
    final wapService = ref.read(wapServiceProvider);

    final diagnosticData = {
      'exportedAt': DateTime.now().toIso8601String(),
      'app': {
        'name': AppConstants.appName,
        'version': AppConstants.appVersion,
        'packageId': AppConstants.androidPackageId,
      },
      'wapCentral': {
        'gateway': AppConstants.wapBaseUrl,
        'appId': AppConstants.wapAppId,
        'isOnline': wapService.isOnline,
      },
      'performance': summaries.map((k, v) => MapEntry(k, v.toJson())),
      'crashes': crashReports.map((c) => c.toJson()).toList(),
      'telemetryEvents': events.map((e) => e.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(diagnosticData);
    await Clipboard.setData(ClipboardData(text: jsonString));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anonymous diagnostics report copied to clipboard.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & Observability'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export Diagnostics',
            onPressed: () => _exportDiagnostics(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Ecosystem', icon: Icon(Icons.hub_outlined)),
            Tab(text: 'Performance', icon: Icon(Icons.speed_outlined)),
            Tab(text: 'Crash Logs', icon: Icon(Icons.bug_report_outlined)),
            Tab(text: 'Telemetry', icon: Icon(Icons.analytics_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEcosystemTab(),
          _buildPerformanceTab(),
          _buildCrashLogsTab(),
          _buildTelemetryTab(),
        ],
      ),
    );
  }

  Widget _buildEcosystemTab() {
    final wapService = ref.watch(wapServiceProvider);
    final monetization = ref.watch(monetizationStateProvider);

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        // Gateway Connection Status Card
        Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      wapService.isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      color: wapService.isOnline ? AppColors.success : AppColors.secondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'WAPCentral Gateway',
                      style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (wapService.isOnline ? AppColors.success : AppColors.secondary)
                            .withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        wapService.isOnline ? 'Online' : 'Local-First Mode',
                        style: AppTypography.labelSmall.copyWith(
                          color: wapService.isOnline ? AppColors.success : AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Base Gateway: ${AppConstants.wapBaseUrl}',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'App ID: ${AppConstants.wapAppId}',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Firebase Project: ${AppConstants.firebaseProjectId} (${AppConstants.firebaseProjectNumber})',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () async {
                    final healthy = await wapService.checkHealth();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            healthy
                                ? 'WAPCentral gateway reachable (online)'
                                : 'Gateway unreachable (operating locally)',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Probe Gateway Connection'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // SDK Stack Architecture Card
        Text(
          'Installed WAPCentral SDKs',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Column(
            children: const [
              ListTile(
                leading: Icon(Icons.vpn_key_outlined, color: AppColors.primary),
                title: Text('wap_core_sdk v0.1.0'),
                subtitle: Text('Connection, authentication headers, request IDs, retries.'),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.campaign_outlined, color: AppColors.accent),
                title: Text('wap_ads_sdk v0.1.0'),
                subtitle: Text('Mediation: AdMob, Meta, AppLovin, WAPAds with promo hook.'),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.notifications_active_outlined, color: AppColors.secondary),
                title: Text('wap_notifications_sdk v0.1.0'),
                subtitle: Text('FCM device registration, notification feed, unread/read state.'),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.touch_app_outlined, color: Colors.teal),
                title: Text('wap_promo_sdk v0.1.0'),
                subtitle: Text('Non-blocking cache-first self-promotions with HMAC validation.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Monetization & Ad State Card
        Text(
          'Monetization & Ad Status',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ad-Free Status:'),
                    Text(
                      monetization.isAdFreePurchased ? 'Active (Ad-Free)' : 'Inactive (Ad-Supported)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: monetization.isAdFreePurchased ? AppColors.success : AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Display Ads Active:'),
                    Text(
                      monetization.shouldDisplayAds ? 'Yes' : 'No',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: monetization.shouldDisplayAds ? AppColors.primary : AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                // Debug builds only: release builds must never expose a way to grant
                // Ad-Free without a verified Google Play purchase.
                if (kDebugMode) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.tonal(
                    onPressed: () async {
                      final newState = !monetization.isAdFreePurchased;
                      await ref.read(wapCentralManagerProvider).setAdFreePurchased(newState);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              newState
                                  ? 'Simulated Ad-Free purchase activated!'
                                  : 'Simulated Ad-Free purchase revoked.',
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(
                      monetization.isAdFreePurchased
                          ? 'Simulate Revoke Ad-Free'
                          : 'Simulate Buy Ad-Free (One-Time)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceTab() {
    final summaries = ref.watch(performanceSummariesProvider);

    if (summaries.isEmpty) {
      return const EmptyView(
        icon: Icons.speed_outlined,
        title: 'No Performance Traces',
        subtitle: 'Performance latencies will record as you navigate and perform actions.',
      );
    }

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Latency Metrics (${summaries.length})',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            TextButton.icon(
              onPressed: () {
                ref.read(performanceMonitorProvider).clearTraces();
                setState(() {});
              },
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear Traces'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...summaries.values.map(
          (summary) => Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        summary.metricName,
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${summary.avgMs} ms avg',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Samples: ${summary.count}', style: AppTypography.bodySmall),
                      Text('Min: ${summary.minMs}ms', style: AppTypography.bodySmall),
                      Text('Max: ${summary.maxMs}ms', style: AppTypography.bodySmall),
                      Text('p95: ${summary.p95Ms}ms', style: AppTypography.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCrashLogsTab() {
    final crashesAsync = ref.watch(crashReportsFutureProvider);

    return crashesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading crash reports: $e')),
      data: (reports) {
        if (reports.isEmpty) {
          return const EmptyView(
            icon: Icons.check_circle_outline_rounded,
            title: 'No Crash Reports',
            subtitle: 'Zero application errors or crashes recorded. System is healthy.',
          );
        }

        return ListView(
          padding: AppSpacing.screenPadding,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Local Crash Reports (${reports.length})',
                  style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await ref.read(crashReporterProvider).clearCrashReports();
                    ref.invalidate(crashReportsFutureProvider);
                  },
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...reports.map((report) => _buildCrashCard(report)),
          ],
        );
      },
    );
  }

  Widget _buildCrashCard(CrashReport report) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        leading: Icon(
          report.isFatal ? Icons.error_rounded : Icons.warning_amber_rounded,
          color: report.isFatal ? AppColors.error : Colors.amber,
        ),
        title: Text(
          report.errorType,
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          report.timestamp.toLocal().toString().substring(0, 19),
          style: AppTypography.bodySmall,
        ),
        childrenPadding: AppSpacing.cardPadding,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message:',
                  style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(report.message, style: AppTypography.bodySmall),
                const SizedBox(height: 8),
                if (report.stackTrace != null && report.stackTrace!.isNotEmpty) ...[
                  Text(
                    'Stack Trace (Sanitized):',
                    style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      report.stackTrace!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryTab() {
    final events = ref.watch(recentAnalyticsEventsProvider);
    final optIn = ref.watch(telemetryOptInProvider);

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        SwitchListTile(
          title: const Text('Anonymous Analytics & Telemetry'),
          subtitle: const Text('Zero personal data or file metadata is collected.'),
          value: optIn,
          onChanged: (val) async {
            ref.read(telemetryOptInProvider.notifier).state = val;
            await ref.read(analyticsServiceProvider).setEnabled(val);
            await ref.read(crashReporterProvider).setEnabled(val);
          },
        ),
        const Divider(),
        if (events.isEmpty)
          const EmptyView(
            icon: Icons.analytics_outlined,
            title: 'No Telemetry Events',
            subtitle: 'Recent anonymous actions will show here when active.',
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Events (${events.length})',
                  style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(analyticsServiceProvider).clearEvents();
                    setState(() {});
                  },
                  child: const Text('Clear Events'),
                ),
              ],
            ),
          ),
          ...events.map(
            (evt) => Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 10, color: AppColors.primary),
                title: Text(evt.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  evt.parameters.isEmpty
                      ? 'No parameters'
                      : jsonEncode(evt.parameters),
                  style: AppTypography.bodySmall,
                ),
                trailing: Text(
                  evt.timestamp.toLocal().toString().substring(11, 19),
                  style: AppTypography.labelSmall,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
