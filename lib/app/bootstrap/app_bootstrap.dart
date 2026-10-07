import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_constants.dart';
import '../navigation/navigation_shell.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../../core/logging/app_logger.dart';

/// Bootstrap coordinator for FileZen application startup.
class AppBootstrap {
  /// Initializes services, locks portrait orientation, and returns root widget.
  static Future<Widget> createRootWidget() async {
    WidgetsFlutterBinding.ensureInitialized();

    AppLogger.info('Bootstrapping ${AppConstants.appName} v${AppConstants.appVersion}', 'Bootstrap');

    // System Chrome setup
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    return const ProviderScope(
      child: FileZenApp(),
    );
  }
}

/// Root Application Widget.
class FileZenApp extends ConsumerWidget {
  const FileZenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
