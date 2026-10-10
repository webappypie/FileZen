import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/vault_models.dart';
import '../../../files/presentation/screens/category_files_screen.dart';
import '../providers/vault_providers.dart';
import 'vault_preview_screen.dart';
import 'vault_settings_screen.dart';
import '../widgets/secure_share_dialog.dart';

/// Secure Vault Screen with hardware-backed encryption, PIN/biometrics,
/// auto-lock on app minimize, private in-memory previews, and screenshot safeguards.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final TextEditingController _pinController = TextEditingController();
  String? _errorMessage;

  // Auto-lock on background is handled app-wide by VaultLifecycleGuard so it
  // honors the configured timeout and works from any screen.
  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUnlocked = ref.watch(vaultSessionProvider);

    if (!isUnlocked) {
      return _buildLockedView(context, isDark);
    }

    return _buildUnlockedView(context, isDark);
  }

  Widget _buildLockedView(BuildContext context, bool isDark) {
    final configAsync = ref.watch(vaultSecurityConfigProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.typeVault.withValues(alpha: isDark ? 0.15 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 56,
                  color: AppColors.typeVault,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Vault is Locked',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Hardware-backed AES-256-GCM encryption with Biometric/PIN protection.\nThumbnails and previews never leak outside.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              configAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (config) {
                  if (config.isLockedOut) {
                    return Container(
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: AppSpacing.roundedSm,
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Text(
                        'Too many failed attempts. Locked out for ${config.remainingLockoutSeconds} seconds.',
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final isPinConfigured = config.isPinConfigured;

                  return Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: TextField(
                          controller: _pinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, letterSpacing: 8),
                          decoration: InputDecoration(
                            hintText: '••••',
                            hintStyle: const TextStyle(letterSpacing: 8),
                            helperText: isPinConfigured
                                ? 'Enter 4-6 digit PIN'
                                : 'Set a new 4-6 digit PIN',
                          ),
                          onSubmitted: (_) => _handleUnlockOrSetup(isPinConfigured),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton.icon(
                        onPressed: () => _handleUnlockOrSetup(isPinConfigured),
                        icon: const Icon(Icons.fingerprint_rounded, size: 22),
                        label: Text(
                          isPinConfigured
                              ? 'Unlock with Biometrics / PIN'
                              : 'Create Master PIN',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleUnlockOrSetup(bool isConfigured) async {
    final pin = _pinController.text.trim();

    if (!isConfigured) {
      if (pin.length < 4) {
        setState(() => _errorMessage = 'PIN must be at least 4 digits');
        return;
      }
      final success = await ref.read(vaultSessionProvider.notifier).setupInitialPin(pin);
      if (success) {
        _pinController.clear();
        setState(() => _errorMessage = null);
      }
    } else {
      if (pin.isEmpty) {
        // Attempt biometric unlock if PIN text is empty
        final res = await ref.read(vaultSessionProvider.notifier).unlockWithBiometrics();
        if (!res.success) {
          setState(() => _errorMessage = res.errorMessage ?? 'Authentication failed');
        } else {
          _pinController.clear();
          setState(() => _errorMessage = null);
        }
        return;
      }

      final res = await ref.read(vaultSessionProvider.notifier).unlockWithPin(pin);
      if (!res.success) {
        setState(() => _errorMessage = res.errorMessage);
      } else {
        _pinController.clear();
        setState(() => _errorMessage = null);
      }
    }
  }

  Widget _buildUnlockedView(BuildContext context, bool isDark) {
    final itemsAsync = ref.watch(vaultItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Vault Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VaultSettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            tooltip: 'Lock Vault Now',
            onPressed: () {
              ref.read(vaultSessionProvider.notifier).lock();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Security Safeguards Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: AppColors.typeVault.withValues(alpha: isDark ? 0.15 : 0.08),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, color: AppColors.typeVault, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hardware-Backed Security Active',
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.typeVault,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Auto-locks when minimized. Private previews decrypted strictly in memory.',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items Content
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyView(
                    title: 'Your Vault is Empty',
                    subtitle: 'No private files locked yet. Tap the button below to encrypt sensitive documents, photos, or recordings.',
                    icon: Icons.lock_open_rounded,
                    actionLabel: 'Add Files Now',
                    onAction: () => _showAddFileDialog(context),
                  );
                }

                return ListView.separated(
                  padding: AppSpacing.screenPadding,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: item.category.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(item.category.icon, color: item.category.color, size: 22),
                      ),
                      title: Text(
                        item.originalFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Encrypted ${item.encryptedAt.month}/${item.encryptedAt.day}/${item.encryptedAt.year} • ${Formatters.formatFileSize(item.fileSize)}',
                        style: AppTypography.labelSmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          fontSize: 10,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => _handleItemAction(context, item, action),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'view',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('View In Memory'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'export',
                            child: Row(
                              children: [
                                Icon(Icons.file_upload_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Export to Storage'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'share',
                            child: Row(
                              children: [
                                Icon(Icons.share_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Share Securely'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_forever_rounded, size: 18, color: AppColors.error),
                                SizedBox(width: 8),
                                Text('Delete Permanently', style: TextStyle(color: AppColors.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VaultPreviewScreen(item: item),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_moderator_rounded),
        label: const Text('Add Files to Vault'),
        onPressed: () => _showAddFileDialog(context),
      ),
    );
  }

  Future<void> _handleItemAction(
    BuildContext context,
    VaultItem item,
    String action,
  ) async {
    if (action == 'view') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VaultPreviewScreen(item: item)),
      );
    } else if (action == 'export') {
      final destDir = '/storage/emulated/0/Download';
      final res = await ref.read(vaultItemsProvider.notifier).exportFile(item, destDir);
      if (!context.mounted) return;
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored ${item.originalFileName} to $destDir')),
        );
      }
    } else if (action == 'share') {
      final confirmed = await SecureShareDialog.show(context, item);
      if (confirmed && context.mounted) {
        await runSecureShare(context, ref.read(vaultShareServiceProvider), item);
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Permanently Delete from Vault?'),
          content: Text('Are you sure you want to delete "${item.originalFileName}" forever? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete Forever'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(vaultItemsProvider.notifier).deleteItem(item);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted ${item.originalFileName}')),
          );
        }
      }
    }
  }

  Future<void> _showAddFileDialog(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.typeVault.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_moderator_rounded, color: AppColors.typeVault),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add Files to Vault', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            'Select a category to pick and lock files with hardware-grade AES-256',
                            style: AppTypography.bodySmall.copyWith(color: AppColors.lightTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                _buildCategoryTile(
                  sheetCtx,
                  category: FileCategory.image,
                  title: 'Photos & Images',
                  subtitle: 'Private photos, sensitive ID cards, screenshots',
                ),
                _buildCategoryTile(
                  sheetCtx,
                  category: FileCategory.document,
                  title: 'Documents & PDFs',
                  subtitle: 'Contracts, tax returns, bank statements',
                ),
                _buildCategoryTile(
                  sheetCtx,
                  category: FileCategory.video,
                  title: 'Videos',
                  subtitle: 'Private recordings, personal clips',
                ),
                _buildCategoryTile(
                  sheetCtx,
                  category: FileCategory.audio,
                  title: 'Audio & Voice Recordings',
                  subtitle: 'Voice memos, private interviews',
                ),
                _buildCategoryTile(
                  sheetCtx,
                  category: null,
                  isDownloads: true,
                  title: 'Downloads',
                  subtitle: 'Downloaded statements and attachments',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTile(
    BuildContext sheetCtx, {
    required FileCategory? category,
    bool isDownloads = false,
    required String title,
    required String subtitle,
  }) {
    final icon = isDownloads ? Icons.download_rounded : (category?.icon ?? Icons.folder_rounded);
    final color = isDownloads ? AppColors.typeArchive : (category?.color ?? AppColors.primary);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: AppTypography.bodySmall.copyWith(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () {
        Navigator.of(sheetCtx).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CategoryFilesScreen(
              category: category,
              isDownloads: isDownloads,
              categoryTitle: title,
            ),
          ),
        );
      },
    );
  }
}
