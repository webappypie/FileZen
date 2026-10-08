import '../models/monetization_models.dart';

/// Abstract coordinator managing WAPCentral SDKs (Core, Ads, Notifications, Promo).
///
/// Guarantees:
/// - 100% offline-safe: failures never block local file operations.
/// - Privacy: zero PII or user files sent to WAPCentral.
/// - Ad-free respect: ads are completely disabled when ad-free status is active.
abstract class IWapCentralManager {
  /// Whether WAPCentral SDKs have completed startup initialization.
  bool get isInitialized;

  /// Active monetization and ads presentation state.
  MonetizationState get monetizationState;

  /// Stream of monetization state updates.
  Stream<MonetizationState> get monetizationStream;

  /// Initializes the WAPCentral SDK stack (Core, Ads, Notifications, Promo).
  Future<void> initialize({bool testMode = false});

  /// Validates gateway health (/api/platform/v1/health).
  Future<bool> checkPlatformHealth();

  /// Registers or refreshes the device FCM token with WAPCentral.
  Future<bool> registerDeviceToken(String fcmToken);

  /// Synchronizes remote notifications from WAPCentral into FileZen's in-app repository.
  Future<int> syncWapNotifications();

  /// Refreshes remote ad configuration from WAPCentral.
  Future<void> refreshAdConfig();

  /// Toggles or sets the user's Ad-Free purchase status.
  Future<void> setAdFreePurchased(bool purchased);

  /// Disposes background observers and resources.
  void dispose();
}
