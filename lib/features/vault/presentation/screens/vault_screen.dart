import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/vault_models.dart';
import '../../../files/presentation/providers/category_files_providers.dart';
import '../../../files/presentation/screens/category_files_screen.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../providers/vault_providers.dart';
import 'vault_preview_screen.dart';
import 'vault_setup_screen.dart';
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

                  if (!config.isPinConfigured) {
                    return Column(
                      children: [
                        Text(
                          'Move private photos, documents and recordings here to encrypt them on this phone.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.typeVault),
                          onPressed: () => VaultSetupScreen.show(context),
                          icon: const Icon(Icons.shield_rounded),
                          label: const Text('Set Up Vault'),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: TextField(
                          controller: _pinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, letterSpacing: 8),
                          decoration: const InputDecoration(
                            hintText: '••••',
                            hintStyle: TextStyle(letterSpacing: 8),
                            helperText: 'Enter your Vault PIN',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _unlockWithPin(),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton.icon(
                        onPressed: _unlockWithPin,
                        icon: const Icon(Icons.lock_open_rounded, size: 22),
                        label: const Text('Unlock Vault'),
                      ),
                      if (config.isBiometricEnabled) ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: _unlockWithBiometrics,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Use fingerprint / face'),
                        ),
                      ],
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

  Future<void> _unlockWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'Enter your PIN');
      return;
    }
    final res = await ref.read(vaultSessionProvider.notifier).unlockWithPin(pin);
    if (!mounted) return;
    _pinController.clear();
    // A wrong PIN may have started a lockout; reload it.
    ref.invalidate(vaultSecurityConfigProvider);
    setState(() => _errorMessage = res.success ? null : res.errorMessage);
  }

  Future<void> _unlockWithBiometrics() async {
    final res = await ref.read(vaultSessionProvider.notifier).unlockWithBiometrics();
    if (!mounted) return;
    ref.invalidate(vaultSecurityConfigProvider);
    setState(() => _errorMessage = res.success ? null : (res.errorMessage ?? 'Authentication failed'));
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
                                Icon(Icons.lock_open_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Move out of Vault'),
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
      await _moveOutOfVault(context, item);
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

  /// Decrypts [item] back to its original folder (Downloads if that folder no
  /// longer exists) and removes it from the Vault once the copy is verified.
  Future<void> _moveOutOfVault(BuildContext context, VaultItem item) async {
    final originalDir = p.dirname(item.originalPath);
    final destDir = (item.originalPath.isNotEmpty && await Directory(originalDir).exists())
        ? originalDir
        : '/storage/emulated/0/Download';
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move out of Vault?'),
        content: Text(
          '"${item.originalFileName}" will be decrypted to $destDir and removed from the Vault. '
          'It will be visible to other apps and in FileZen search again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Move out')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final res = await ref.read(vaultItemsProvider.notifier).exportFile(item, destDir);
    if (!context.mounted) return;
    final restored = res.dataOrNull;
    if (restored != null) {
      await ref.read(indexingServiceProvider).indexSingleFile(restored);
      ref.invalidate(categoryFileCountsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored to ${restored.path}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.error,
        content: Text('Could not move "${item.originalFileName}" out of the Vault: '
            '${res.errorOrNull?.message ?? 'unknown error'}. It is still in the Vault.'),
      ));
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
