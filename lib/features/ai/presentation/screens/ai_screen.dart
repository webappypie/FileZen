import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';

class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final aiCapabilities = [
      (
        'On-Device OCR & Text Extraction',
        'Extracts text from screenshots, documents, and photos entirely on-device without cloud dependence.',
        Icons.document_scanner_rounded,
        AppColors.typeDocument,
      ),
      (
        'AI Auto-Rename with Preview',
        'Intelligently suggests structured names for messy files and camera photos with collision handling and undo.',
        Icons.edit_note_rounded,
        AppColors.accent,
      ),
      (
        'Ask Your Files',
        'Query your files naturally (e.g. "latest resume", "receipts from last month", "documents with ID").',
        Icons.psychology_rounded,
        AppColors.primary,
      ),
      (
        'Smart Collections',
        'Virtual clusters organized by topic, entity, or receipt period without physically moving files.',
        Icons.auto_awesome_mosaic_rounded,
        AppColors.typeImage,
      ),
    ];

    return Scaffold(
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Local AI Privacy Guarantee Banner
          Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: AppSpacing.roundedMd,
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.secondary, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% On-Device AI Processing',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Your documents, photos, and files are understood locally. No cloud uploads, no account required.',
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
          const SizedBox(height: AppSpacing.lg),

          Text(
            'Intelligence Engines',
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),

          ...aiCapabilities.map(
            (cap) => Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cap.$4.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.roundedSm,
                      ),
                      child: Icon(cap.$3, color: cap.$4, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cap.$1,
                            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            cap.$2,
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
          ),
        ],
      ),
    );
  }
}
