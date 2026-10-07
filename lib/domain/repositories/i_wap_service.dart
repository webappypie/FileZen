enum WapServiceStatus {
  unconfigured,
  checking,
  online,
  offline,
  error,
}

/// Abstract domain contract for WAPCentral Platform client.
///
/// Ensures the application layer never couples directly to concrete network implementations.
abstract class IWapService {
  WapServiceStatus get status;
  bool get isConfigured;
  bool get isOnline;

  /// Checks platform API gateway health (/api/platform/v1/health).
  Future<bool> checkHealth();

  /// Disposes resources and clients.
  void dispose();
}
