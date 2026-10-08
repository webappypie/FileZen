import 'app_constants.dart';

/// Runtime environment configuration for FileZen.
class AppConfig {
  final String environment;
  final String wapAppId;
  final String wapAppKey;
  final String wapBaseUrl;
  final String wapPromoSecret;
  final bool preferLocal;
  final bool enableDebugLogging;

  const AppConfig({
    required this.environment,
    required this.wapAppId,
    required this.wapAppKey,
    required this.wapBaseUrl,
    this.wapPromoSecret = '',
    this.preferLocal = true,
    this.enableDebugLogging = false,
  });

  /// Factory creating configuration with values sourced securely via dart-define or runtime overrides.
  /// Never hardcodes production secret keys in source control.
  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'production');
    const customBaseUrl = String.fromEnvironment('WAP_BASE_URL', defaultValue: AppConstants.wapBaseUrl);
    // Secret keys injected via build environment / CI / secure config
    const key = String.fromEnvironment('WAP_APP_KEY', defaultValue: '');
    const promoSecret = String.fromEnvironment('WAP_PROMO_SECRET', defaultValue: '');
    const isDebug = bool.fromEnvironment('DEBUG_LOGS', defaultValue: false);

    return const AppConfig(
      environment: env,
      wapAppId: AppConstants.wapAppId,
      wapAppKey: key,
      wapBaseUrl: customBaseUrl,
      wapPromoSecret: promoSecret,
      preferLocal: true,
      enableDebugLogging: isDebug,
    );
  }

  bool get hasValidWapKey => wapAppKey.isNotEmpty;
}
