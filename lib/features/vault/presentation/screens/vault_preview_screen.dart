import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/vault_models.dart';
import '../providers/vault_providers.dart';
import '../widgets/secure_share_dialog.dart';
import '../widgets/secure_surface.dart';

/// Private, isolated in-memory viewer for Vault files with zero disk caching.
class VaultPreviewScreen extends ConsumerStatefulWidget {
  final VaultItem item;

  const VaultPreviewScreen({
    super.key,
    required this.item,
  });

  @override
  ConsumerState<VaultPreviewScreen> createState() => _VaultPreviewScreenState();
}

class _VaultPreviewScreenState extends ConsumerState<VaultPreviewScreen> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDecryptedContent();
  }

  Future<void> _loadDecryptedContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final storage = ref.read(vaultStorageServiceProvider);
    final result = await storage.getDecryptedBytes(widget.item);

    if (!mounted) return;

    if (result.isSuccess && result.dataOrNull != null) {
      setState(() {
        _decryptedBytes = result.dataOrNull;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result.errorOrNull?.message ?? 'Decryption failed';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.item.originalFileName),
          actions: [
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Securely',
              onPressed: () => _handleShare(context),
            ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Export / Restore to Storage',
              onPressed: () => _handleExport(context),
            ),
          ],
        ),
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const LoadingView(message: 'Decrypting file securely in memory...');
    }

    if (_errorMessage != null || _decryptedBytes == null) {
      return ErrorView(
        message: _errorMessage ?? 'Unable to display private content',
        onRetry: _loadDecryptedContent,
      );
    }

    final bytes = _decryptedBytes!;
    final category = widget.item.category;

    if (category == FileCategory.image) {
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Text('Unable to render image bytes'),
            ),
          ),
        ),
      );
    }

    // Text / document fallback
    try {
      final textContent = utf8.decode(bytes);
      return SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: SelectableText(
          textContent,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
    } catch (_) {
      // Binary non-image file
      return Center(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 64, color: category.color),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.item.originalFileName,
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Size: ${Formatters.formatFileSize(widget.item.fileSize)}',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Export to View in External App'),
                onPressed: () => _handleExport(context),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    final confirmed = await SecureShareDialog.show(context, widget.item);
    if (!confirmed || !context.mounted) return;

    await runSecureShare(context, ref.read(vaultShareServiceProvider), widget.item);
  }

  Future<void> _handleExport(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export File from Vault?'),
        content: Text(
          'This will decrypt "${widget.item.originalFileName}" and restore it back to your device storage.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Export Now')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final destDir = '/storage/emulated/0/Download';
    final res = await ref.read(vaultItemsProvider.notifier).exportFile(widget.item, destDir);

    if (!context.mounted) return;

    if (res.isSuccess) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${widget.item.originalFileName} successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: ${res.errorOrNull?.message}')),
      );
    }
  }
}
