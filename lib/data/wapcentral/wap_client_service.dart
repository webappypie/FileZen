import 'package:wap_core_sdk/wap_core_sdk.dart';
import '../../app/config/app_config.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/repositories/i_wap_service.dart';

/// Concrete implementation of IWapService utilizing wap_core_sdk.
///
/// Guaranteed properties:
/// 1. Non-blocking & graceful degradation: Local file operations NEVER depend on WAPCentral.
/// 2. Privacy safe: Secrets and user data are never logged.
/// 3. Offline resilience: Safe offline state when network is unavailable.
class WapClientService implements IWapService {
  final AppConfig _config;
  final WapClient? _client;
  WapServiceStatus _status = WapServiceStatus.unconfigured;

  WapClientService({
    required AppConfig config,
    WapClient? client,
  })  : _config = config,
        _client = client ??
            (config.hasValidWapKey
                ? WapClient(
                    config: WapConfig(
                      appId: config.wapAppId,
                      appKey: config.wapAppKey,
                      baseUrl: config.wapBaseUrl,
                      preferLocal: config.preferLocal,
                    ),
                  )
                : null) {
    if (_client != null) {
      _status = WapServiceStatus.offline;
    }
  }

  @override
  WapServiceStatus get status => _status;

  @override
  bool get isConfigured => _client != null && _config.hasValidWapKey;

  @override
  bool get isOnline => _status == WapServiceStatus.online;

  @override
  Future<bool> checkHealth() async {
    if (!isConfigured || _client == null) {
      _status = WapServiceStatus.unconfigured;
      AppLogger.debug('WAPCentral client is unconfigured or missing API key', 'WapService');
      return false;
    }

    _status = WapServiceStatus.checking;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        path: '/health',
        dataParser: (data) => (data is Map<String, dynamic>) ? data : {},
      );

      if (response.success) {
        _status = WapServiceStatus.online;
        AppLogger.info('WAPCentral connection healthy (requestId: ${response.requestId})', 'WapService');
        return true;
      } else {
        _status = WapServiceStatus.offline;
        return false;
      }
    } on WapNetworkException catch (e) {
      _status = WapServiceStatus.offline;
      AppLogger.debug('WAPCentral unreachable (operating in local-first mode): $e', 'WapService');
      return false;
    } on WapException catch (e) {
      _status = WapServiceStatus.error;
      AppLogger.warning('WAPCentral error (${e.code}): ${e.message}', 'WapService');
      return false;
    } catch (e) {
      _status = WapServiceStatus.error;
      AppLogger.warning('Unexpected WAPCentral exception: $e', 'WapService');
      return false;
    }
  }

  @override
  void dispose() {
    _client?.close();
  }
}
