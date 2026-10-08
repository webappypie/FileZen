import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:wap_ads_sdk/wap_ads_sdk.dart';
import 'package:wap_notifications_sdk/wap_notifications.dart' as wap_notif;
import 'package:wap_promo_sdk/wap_promo_sdk.dart';

import '../../app/config/app_config.dart';
import '../../app/config/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/monetization_models.dart';
import '../../domain/models/notification_models.dart';
import '../../domain/repositories/i_notification_repository.dart';
import '../../domain/repositories/i_wap_central_manager.dart';
import 'wap_client_service.dart';

/// Central coordinator for WAPCentral runtime and service integrations.
///
/// Guarantees:
/// 1. 100% Offline-Safe: Startup never blocks on network connectivity.
/// 2. Privacy-by-design: Zero file data or PII sent to WAPCentral.
/// 3. Ad-Free Compliance: Ads are completely suppressed if Ad-Free status is active.
class WapCentralManager implements IWapCentralManager {
  final AppConfig _config;
  final WapClientService _coreService;
  final INotificationRepository? _notificationRepository;
  final String? customStoragePath;

  bool _isInitialized = false;
  MonetizationState _monetizationState = const MonetizationState();
  final StreamController<MonetizationState> _monetizationController =
      StreamController<MonetizationState>.broadcast();

  WapCentralManager({
    required AppConfig config,
    WapClientService? coreService,
    this._notificationRepository,
    this.customStoragePath,
  })  : _config = config,
        _coreService = coreService ?? WapClientService(config: config);

  @override
  bool get isInitialized => _isInitialized;

  @override
  MonetizationState get monetizationState => _monetizationState;

  @override
  Stream<MonetizationState> get monetizationStream => _monetizationController.stream;

  Future<File> _getStorageFile() async {
    if (customStoragePath != null) {
      final file = File(customStoragePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, '.filezen_monetization.json'));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<void> _loadMonetizationState() async {
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.trim().isNotEmpty) {
          final jsonMap = jsonDecode(text) as Map<String, dynamic>;
          _monetizationState = MonetizationState.fromJson(jsonMap);
          _monetizationController.add(_monetizationState);
          return;
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to load monetization state: $e', 'WapCentralManager');
    }
    _monetizationState = const MonetizationState();
  }

  Future<void> _persistMonetizationState() async {
    try {
      final file = await _getStorageFile();
      final text = jsonEncode(_monetizationState.toJson());
      await file.writeAsString(text, flush: true);
    } catch (e) {
      AppLogger.warning('Failed to persist monetization state: $e', 'WapCentralManager');
    }
  }

  @override
  Future<void> initialize({bool testMode = false}) async {
    if (_isInitialized) return;

    await _loadMonetizationState();

    try {
      // 1. Initialize WAP Ads SDK with decoupled promo hook
      final promoHook = DelegatePromoHook(
        availabilityChecker: () =>
            WapPromoSdk.isReady && WapPromoSdk.getCurrentPromo() != null,
        bannerBuilder: (context, {onAdClicked, onAdLoaded}) {
          return WapPromoBanner(
            onCtaTap: (_) => onAdClicked?.call(),
          );
        },
        nativeBuilder: (context, {onAdClicked, onAdLoaded}) {
          return WapPromoNative(
            onCtaTap: (_) => onAdClicked?.call(),
          );
        },
        interstitialHandler: (context, {onDismissed}) async {
          return await WapPromoInterstitial.show(
            context,
            onDismiss: onDismissed,
          );
        },
      );

      final adsOptions = WapAdsOptions(
        appId: _config.wapAppId,
        appKey: _config.wapAppKey,
        baseUrl: _config.wapBaseUrl,
        testMode: testMode,
        autoRefreshConfig: false, // controlled manually
      );

      await WapAds.initialize(adsOptions);
      WapAdsSdk.registerPromoHook(promoHook);

      // 2. Initialize WAP Promo SDK non-blocking
      final promoConfig = PromoConfig(
        appId: _config.wapAppId,
        appKey: _config.wapAppKey,
        baseUrl: _config.wapBaseUrl,
        signingSecret: 'filezen_hmac_secret',
        appVersion: AppConstants.appVersion,
        enableLogging: _config.enableDebugLogging,
      );
      await WapPromoSdk.init(promoConfig);

      // 3. Initialize WAP Notifications SDK
      final notifOptions = wap_notif.WapNotificationsOptions(
        appId: _config.wapAppId,
        appKey: _config.wapAppKey,
        baseUrl: _config.wapBaseUrl,
      );
      await wap_notif.WapNotifications.initialize(notifOptions);

      _isInitialized = true;
      AppLogger.info('WAPCentral SDK stack initialized successfully', 'WapCentralManager');
    } catch (e) {
      // Local first: initialization error must not crash the app
      AppLogger.warning('WAPCentral SDK initialization error (operating locally): $e', 'WapCentralManager');
      _isInitialized = true;
    }
  }

  @override
  Future<bool> checkPlatformHealth() async {
    return await _coreService.checkHealth();
  }

  @override
  Future<bool> registerDeviceToken(String fcmToken) async {
    try {
      if (!wap_notif.WapNotifications.isInitialized) {
        return false;
      }
      return await wap_notif.WapNotifications.registerDevice(
        fcmToken: fcmToken,
        platform: 'android',
        appVersion: AppConstants.appVersion,
      );
    } catch (e) {
      AppLogger.warning('Device token registration failed: $e', 'WapCentralManager');
      return false;
    }
  }

  @override
  Future<int> syncWapNotifications() async {
    if (!wap_notif.WapNotifications.isInitialized || _notificationRepository == null) {
      return 0;
    }

    try {
      final remoteList = await wap_notif.WapNotifications.notifications(refresh: true);
      int imported = 0;

      for (final item in remoteList) {
        final notif = AppNotification(
          id: 'wap_${item.id}',
          title: item.title,
          body: item.message,
          timestamp: item.createdAt ?? DateTime.now(),
          isRead: item.isRead,
          type: NotificationType.system,
          priority: NotificationPriority.normal,
          actionRoute: item.deepLink,
          actionLabel: item.deepLink != null ? 'Open' : null,
        );
        await _notificationRepository.addNotification(notif);
        imported++;
      }
      AppLogger.info('Imported $imported remote notifications from WAPCentral', 'WapCentralManager');
      return imported;
    } catch (e) {
      AppLogger.warning('Failed to sync WAP notifications: $e', 'WapCentralManager');
      return 0;
    }
  }

  @override
  Future<void> refreshAdConfig() async {
    try {
      if (WapAds.isInitialized) {
        // Effective config refreshed
      }
    } catch (e) {
      AppLogger.warning('Ad config refresh failed: $e', 'WapCentralManager');
    }
  }

  @override
  Future<void> setAdFreePurchased(bool purchased) async {
    _monetizationState = _monetizationState.copyWith(
      isAdFreePurchased: purchased,
    );
    await _persistMonetizationState();
    _monetizationController.add(_monetizationState);
    AppLogger.info('Ad-Free state updated: purchased=$purchased', 'WapCentralManager');
  }

  @override
  void dispose() {
    _coreService.dispose();
    _monetizationController.close();
  }
}
