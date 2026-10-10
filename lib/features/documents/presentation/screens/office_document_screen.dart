import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/file_entity.dart';

/// Screen for Microsoft Office and complex binary documents (DOC, DOCX, XLS, XLSX, PPT, PPTX).
/// Provides file metadata preview and secure handoff to installed Android document viewers.
class OfficeDocumentScreen extends StatelessWidget {
  const OfficeDocumentScreen({
    super.key,
    required this.file,
  });

  final FileEntity file;

  Future<void> _openWithExternalApp(BuildContext context) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (!context.mounted) return;

      if (result.type == ResultType.noAppToOpen) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No Compatible Viewer'),
            content: Text(
              'No app on your device is currently installed to open "${file.name}".\n\n'
              'Please install an office viewer such as Google Docs, Google Sheets, or Microsoft Office from Google Play.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else if (result.type == ResultType.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open document: ${result.message}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to launch viewer: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ext = file.extension.toLowerCase().replaceAll('.', '');

    final (formatName, iconData, brandColor, suiteType) = switch (ext) {
      'doc' || 'docx' => ('Microsoft Word Document', Icons.article_rounded, Colors.blueAccent, 'Word Processing'),
      'xls' || 'xlsx' => ('Microsoft Excel Spreadsheet', Icons.table_chart_rounded, Colors.green, 'Spreadsheet'),
      'ppt' || 'pptx' => ('Microsoft PowerPoint Presentation', Icons.slideshow_rounded, Colors.deepOrange, 'Presentation'),
      _ => ('Office Document', Icons.description_rounded, AppColors.typeDocument, 'Document'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: brandColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(iconData, size: 48, color: brandColor),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                file.name,
                style: AppTypography.headlineMedium.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatName,
                style: AppTypography.bodySmall.copyWith(
                  color: brandColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      _buildInfoRow('Type', suiteType),
                      const Divider(height: 16),
                      _buildInfoRow('Format', '.${ext.toUpperCase()}'),
                      const Divider(height: 16),
                      _buildInfoRow('Size', Formatters.formatFileSize(file.size)),
                      const Divider(height: 16),
                      _buildInfoRow('Modified', Formatters.formatDate(file.modifiedAt)),
                      const Divider(height: 16),
                      _buildInfoRow('Path', file.path, isMonospace: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open in Compatible App'),
                  style: FilledButton.styleFrom(
                    backgroundColor: brandColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => _openWithExternalApp(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Uses Android Secure Intent handoff to display full formatted document in your installed office suite.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}
