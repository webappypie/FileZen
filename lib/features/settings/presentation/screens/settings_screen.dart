import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/app_constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/theme_provider.dart';
import '../../../../data/wapcentral/wap_client_provider.dart';
import '../../../cloud/presentation/screens/cloud_sources_screen.dart';
import '../../../monitoring/presentation/providers/monitoring_providers.dart';
import '../../../monitoring/presentation/screens/diagnostics_screen.dart';
import '../../../transfer/presentation/screens/network_hub_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final wapService = ref.watch(wapServiceProvider);
    final monetization = ref.watch(monetizationStateProvider);
    final telemetryOptIn = ref.watch(telemetryOptInProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Appearance Section
          Text(
            'Appearance',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.settings_suggest_outlined),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (newSelection) {
                    ref.read(themeModeProvider.notifier).state = newSelection.first;
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Privacy & Local-First Philosophy
          Text(
            'Privacy & Processing',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, color: AppColors.secondary),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Local-First Guarantee',
                            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'All indexing, OCR, file operations, and vault encryption run strictly on your device. FileZen does not silently upload or sync your files.',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.analytics_outlined, color: AppColors.primary),
                  title: const Text('Anonymous Diagnostics & Crash Monitoring'),
                  subtitle: const Text('Strictly zero file names, contents, or personal information.'),
                  value: telemetryOptIn,
                  onChanged: (val) async {
                    ref.read(telemetryOptInProvider.notifier).state = val;
                    await ref.read(analyticsServiceProvider).setEnabled(val);
                    await ref.read(crashReporterProvider).setEnabled(val);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.insights_rounded, color: AppColors.secondary),
                  title: const Text('Diagnostics & Observability Dashboard'),
                  subtitle: const Text('Inspect local performance traces, crash logs, and WAPCentral SDK status.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Network & Cloud Sources
          Text(
            'Network & Cloud Sources',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wifi_tethering_rounded, color: AppColors.primary),
                  title: const Text('Wi-Fi Web Share & LAN Transfer'),
                  subtitle: const Text('Direct browser transfer, SMB, FTP, SFTP, and WebDAV.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NetworkHubScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cloud_queue_rounded, color: AppColors.accent),
                  title: const Text('Cloud Storage Accounts'),
                  subtitle: const Text('Google Drive, OneDrive, Dropbox, and Box.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CloudSourcesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Monetization Architecture
          Text(
            'Monetization',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.star_rounded,
                color: monetization.isAdFreePurchased ? AppColors.success : AppColors.primary,
              ),
              title: const Text('Ad-Free Pro (One-Time Purchase)'),
              subtitle: Text(
                monetization.isAdFreePurchased
                    ? 'Active — All advertising is completely disabled.'
                    : 'Non-intrusive ads active. Tap to remove ads permanently.',
              ),
              trailing: monetization.isAdFreePurchased
                  ? const Chip(
                      label: Text('ACTIVE'),
                      backgroundColor: Color(0x2210B981),
                      side: BorderSide.none,
                    )
                  : FilledButton.tonal(
                      onPressed: () async {
                        await ref.read(monetizationStateProvider.notifier).setAdFreePurchased(true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ad-Free Pro activated! Ads are now suppressed.'),
                            ),
                          );
                        }
                      },
                      child: const Text('Remove'),
                    ),
              onTap: () async {
                final newState = !monetization.isAdFreePurchased;
                await ref.read(monetizationStateProvider.notifier).setAdFreePurchased(newState);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        newState
                            ? 'Ad-Free Pro activated! Ads are suppressed.'
                            : 'Ad-Free revoked. Ad-supported mode active.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // About FileZen
          Text(
            'About',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Application'),
                  trailing: Text(
                    '${AppConstants.appName} v${AppConstants.appVersion}',
                    style: AppTypography.labelLarge,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Package'),
                  trailing: Text(
                    AppConstants.androidPackageId,
                    style: AppTypography.bodySmall,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('WAPCentral Gateway'),
                  subtitle: Text(
                    wapService.isOnline ? 'Online' : 'Operating in local-first mode',
                    style: AppTypography.bodySmall.copyWith(
                      color: wapService.isOnline ? AppColors.success : AppColors.secondary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Check Gateway Connection',
                    onPressed: () async {
                      final isHealthy = await wapService.checkHealth();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isHealthy
                                  ? 'WAPCentral gateway reachable'
                                  : 'WAPCentral offline (Operating locally)',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
