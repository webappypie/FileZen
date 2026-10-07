import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/config/app_config.dart';
import '../../domain/repositories/i_wap_service.dart';
import 'wap_client_service.dart';

/// Provider for runtime AppConfig.
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

/// Provider for IWapService.
final wapServiceProvider = Provider<IWapService>((ref) {
  final config = ref.watch(appConfigProvider);
  final service = WapClientService(config: config);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Async notifier for WAPCentral connection health.
final wapHealthNotifierProvider = AsyncNotifierProvider<WapHealthNotifier, bool>(WapHealthNotifier.new);

class WapHealthNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final service = ref.watch(wapServiceProvider);
    return await service.checkHealth();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(wapServiceProvider);
      return await service.checkHealth();
    });
  }
}
