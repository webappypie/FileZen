import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wap_promo_sdk/wap_promo_sdk.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../providers/monitoring_providers.dart';

/// Presentation card displaying ecosystem app cross-promotions.
class FileZenPromoCard extends ConsumerWidget {
  const FileZenPromoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monetization = ref.watch(monetizationStateProvider);
    if (!monetization.shouldDisplayAds) {
      return const SizedBox.shrink();
    }

    return WapPromoBuilder(
      builder: (context, promo) {
        if (promo == null || !promo.hasContent) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: AppColors.primary.withAlpha(50),
            ),
          ),
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.apps_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promo.title ?? 'Sponsored App',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        promo.description ?? '',
                        style: AppTypography.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonal(
                  onPressed: () {
                    if (promo.campaignId != null) {
                      WapPromoSdk.recordClick(promo.campaignId!);
                    }
                  },
                  child: Text(promo.ctaText ?? 'Explore'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
