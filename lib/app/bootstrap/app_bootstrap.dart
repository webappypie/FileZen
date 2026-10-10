import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_constants.dart';
import '../navigation/navigation_shell.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../data/monitoring/crash_reporter.dart';
import '../../data/monitoring/performance_monitor.dart';
import '../../features/monitoring/presentation/providers/monitoring_providers.dart';
import '../../features/vault/presentation/providers/vault_lifecycle_guard.dart';

/// Bootstrap coordinator for FileZen application startup.
class AppBootstrap {
  /// Initializes services, locks portrait orientation, and returns root widget.
  static Future<Widget> createRootWidget({
    CrashReporter? customCrashReporter,
    PerformanceMonitor? customPerfMonitor,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();

    final crashReporter = customCrashReporter ?? CrashReporter();
    final perfMonitor = customPerfMonitor ?? PerformanceMonitor();

    // Measure app startup latency
    perfMonitor.startTrace('app_startup');

    // Register global error and crash hooks
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      crashReporter.recordFlutterError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      crashReporter.recordError(error, stack, isFatal: true);
      return true;
    };

    AppLogger.info('Bootstrapping ${AppConstants.appName} v${AppConstants.appVersion}', 'Bootstrap');

    // System Chrome setup
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    perfMonitor.stopTrace('app_startup');

    return ProviderScope(
      overrides: [
        crashReporterProvider.overrideWithValue(crashReporter),
        performanceMonitorProvider.overrideWithValue(perfMonitor),
      ],
      child: const FileZenApp(),
    );
  }
}

/// Root Application Widget.
class FileZenApp extends ConsumerStatefulWidget {
  const FileZenApp({super.key});

  @override
  ConsumerState<FileZenApp> createState() => _FileZenAppState();
}

class _FileZenAppState extends ConsumerState<FileZenApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(wapCentralManagerProvider).initialize();
      // Starts the app-wide Vault auto-lock observer.
      ref.read(vaultLifecycleGuardProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const NavigationShell(),
    );
  }
}
