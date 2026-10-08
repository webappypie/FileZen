/// State representation for monetization and ads presentation.
class MonetizationState {
  final bool isAdFreePurchased;
  final bool isAdsEnabledByPlatform;
  final List<String> activeNetworks;
  final DateTime? lastConfigRefresh;

  const MonetizationState({
    this.isAdFreePurchased = false,
    this.isAdsEnabledByPlatform = true,
    this.activeNetworks = const ['admob', 'meta', 'applovin', 'wapads'],
    this.lastConfigRefresh,
  });

  /// Effective flag determining whether client widgets should display ads.
  /// If the user has purchased Ad-Free, ads are strictly disabled.
  bool get shouldDisplayAds => !isAdFreePurchased && isAdsEnabledByPlatform;

  MonetizationState copyWith({
    bool? isAdFreePurchased,
    bool? isAdsEnabledByPlatform,
    List<String>? activeNetworks,
    DateTime? lastConfigRefresh,
  }) {
    return MonetizationState(
      isAdFreePurchased: isAdFreePurchased ?? this.isAdFreePurchased,
      isAdsEnabledByPlatform: isAdsEnabledByPlatform ?? this.isAdsEnabledByPlatform,
      activeNetworks: activeNetworks ?? this.activeNetworks,
      lastConfigRefresh: lastConfigRefresh ?? this.lastConfigRefresh,
    );
  }

  Map<String, dynamic> toJson() => {
        'isAdFreePurchased': isAdFreePurchased,
        'isAdsEnabledByPlatform': isAdsEnabledByPlatform,
        'activeNetworks': activeNetworks,
        'lastConfigRefresh': lastConfigRefresh?.toIso8601String(),
      };

  factory MonetizationState.fromJson(Map<String, dynamic> json) {
    return MonetizationState(
      isAdFreePurchased: json['isAdFreePurchased'] as bool? ?? false,
      isAdsEnabledByPlatform: json['isAdsEnabledByPlatform'] as bool? ?? true,
      activeNetworks: (json['activeNetworks'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['admob', 'meta', 'applovin', 'wapads'],
      lastConfigRefresh: json['lastConfigRefresh'] != null
          ? DateTime.tryParse(json['lastConfigRefresh'] as String)
          : null,
    );
  }
}
