import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wap_ads_sdk/wap_ads.dart';
import 'package:wap_promo_sdk/wap_promo_sdk.dart';

import '../providers/monitoring_providers.dart';

/// Non-intrusive advertisement and promotional banner widget.
///
/// Guaranteed properties:
/// 1. Ad-Free Compliance: If the user has purchased Ad-Free, collapses to zero height.
/// 2. Graceful degradation: If no ad network fills and no promo is active, collapses cleanly.
/// 3. Offline resilience: Never displays broken placeholders or loading spinners when offline.
class FileZenAdBanner extends ConsumerStatefulWidget {
  final String placementId;

  const FileZenAdBanner({
    super.key,
    this.placementId = 'default_banner',
  });

  @override
  ConsumerState<FileZenAdBanner> createState() => _FileZenAdBannerState();
}

class _FileZenAdBannerState extends ConsumerState<FileZenAdBanner> {
  bool _adAvailable = true;

  @override
  Widget build(BuildContext context) {
    final monetization = ref.watch(monetizationStateProvider);

    // If Ad-Free is purchased or platform disabled ads, completely collapse
    if (!monetization.shouldDisplayAds || !_adAvailable) {
      return const SizedBox.shrink();
    }

    // If WapAds is not ready, check if WapPromoSdk is ready
    if (!WapAds.isInitialized) {
      if (WapPromoSdk.isReady && WapPromoSdk.getCurrentPromo() != null) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const WapPromoBanner(),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: const BoxConstraints(minHeight: 50, maxHeight: 60),
      child: WapAds.banner(
        placementKey: widget.placementId,
        onFailed: (error) {
          if (mounted) {
            setState(() {
              _adAvailable = false;
            });
          }
        },
      ),
    );
  }
}
