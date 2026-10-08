import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/cloud_models.dart';
import '../providers/cloud_providers.dart';
import 'cloud_browser_screen.dart';

/// Screen managing connected cloud storage sources (Google Drive, OneDrive, Dropbox, Box).
class CloudSourcesScreen extends ConsumerWidget {
  const CloudSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(cloudAccountsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sources'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showConnectDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
      body: accountsAsync.when(
        loading: () => const LoadingView(message: 'Loading cloud accounts...'),
        error: (e, _) => ErrorView(
          message: 'Failed to load cloud accounts',
          recoverySuggestion: e.toString(),
        ),
        data: (accounts) {
          return ListView(
            padding: AppSpacing.screenPadding,
            children: [
              // Privacy Guarantee Card
              Card(
                color: isDark ? Colors.grey[900] : Colors.blue[50],
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.roundedMd,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Local-First Cloud Architecture',
                              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cloud accounts are optional external file sources. FileZen does not silently back up or upload local files. All cloud transfers occur only on explicit user request.',
                              style: AppTypography.bodySmall.copyWith(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              if (accounts.isEmpty)
                EmptyView(
                  title: 'No Cloud Accounts Connected',
                  subtitle: 'Connect Google Drive, OneDrive, Dropbox, or Box to browse your remote files.',
                  icon: Icons.cloud_queue_rounded,
                  actionLabel: 'Connect Account',
                  onAction: () => _showConnectDialog(context, ref),
                )
              else
                ...accounts.map((acc) => _buildAccountCard(context, ref, acc, isDark)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    WidgetRef ref,
    CloudAccount account,
    bool isDark,
  ) {
    final usedRatio = account.usedPercentage;
    final (icon, color) = switch (account.provider) {
      CloudProviderType.googleDrive => (Icons.add_to_drive_rounded, Colors.amber[700]!),
      CloudProviderType.oneDrive => (Icons.cloud_rounded, Colors.blue[600]!),
      CloudProviderType.dropbox => (Icons.archive_outlined, Colors.indigo[500]!),
      CloudProviderType.box => (Icons.inventory_2_outlined, Colors.cyan[600]!),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName,
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${account.provider.displayName} • ${account.accountEmail}',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (action) async {
                    if (action == 'refresh') {
                      await ref.read(cloudControllerProvider.notifier).refreshQuota(account);
                    } else if (action == 'disconnect') {
                      await ref.read(cloudControllerProvider.notifier).disconnectAccount(account.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'refresh', child: Text('Refresh Quota')),
                    PopupMenuItem(value: 'disconnect', child: Text('Disconnect Account')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Storage quota progress
            ClipRRect(
              borderRadius: AppSpacing.roundedSm,
              child: LinearProgressIndicator(
                value: usedRatio,
                minHeight: 8,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Formatters.formatFileSize(account.usedStorageBytes)} used of ${Formatters.formatFileSize(account.totalStorageBytes)}',
                  style: AppTypography.bodySmall,
                ),
                Text(
                  '${(usedRatio * 100).toInt()}%',
                  style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Action: Browse Files
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CloudBrowserScreen(account: account),
                    ),
                  );
                },
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Browse Files'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _ConnectAccountDialog(),
    );
  }
}

class _ConnectAccountDialog extends ConsumerStatefulWidget {
  const _ConnectAccountDialog();

  @override
  ConsumerState<_ConnectAccountDialog> createState() => _ConnectAccountDialogState();
}

class _ConnectAccountDialogState extends ConsumerState<_ConnectAccountDialog> {
  CloudProviderType _selectedProvider = CloudProviderType.googleDrive;
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.roundedLg),
      title: const Text('Connect Cloud Storage'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Provider',
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CloudProviderType.values.map((p) {
                final isSelected = _selectedProvider == p;
                return ChoiceChip(
                  label: Text(p.shortName),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedProvider = p),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Account Display Name',
                hintText: 'e.g. My ${_selectedProvider.displayName}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Account Email',
                hintText: 'name@example.com',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final email = _emailController.text.trim().isEmpty
                ? 'account@example.com'
                : _emailController.text.trim();
            final name = _nameController.text.trim().isEmpty
                ? 'My ${_selectedProvider.displayName}'
                : _nameController.text.trim();

            await ref.read(cloudControllerProvider.notifier).connectAccount(
                  _selectedProvider,
                  email: email,
                  displayName: name,
                );

            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
