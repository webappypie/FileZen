import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/config/app_constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/theme/theme_provider.dart';
import '../../../../data/wapcentral/wap_client_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final wapService = ref.watch(wapServiceProvider);
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
            child: Padding(
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
              leading: const Icon(Icons.star_outline_rounded, color: AppColors.primary),
              title: const Text('Remove Ads (One-Time Purchase)'),
              subtitle: const Text('Non-intrusive ads; never requires recurring subscriptions.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('In-app purchase flow integrates in Phase 12')),
                );
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
