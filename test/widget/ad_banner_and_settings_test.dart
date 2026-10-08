import 'dart:async';
import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/domain/models/monetization_models.dart';
import 'package:filezen/domain/repositories/i_wap_central_manager.dart';
import 'package:filezen/features/monitoring/presentation/providers/monitoring_providers.dart';
import 'package:filezen/features/monitoring/presentation/widgets/filezen_ad_banner.dart';
import 'package:filezen/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWapCentralManager implements IWapCentralManager {
  MonetizationState _state;
  final _controller = StreamController<MonetizationState>.broadcast();

  FakeWapCentralManager({this._state = const MonetizationState()});

  @override
  bool get isInitialized => true;

  @override
  MonetizationState get monetizationState => _state;

  @override
  Stream<MonetizationState> get monetizationStream => _controller.stream;

  @override
  Future<void> initialize({bool testMode = false}) async {}

  @override
  Future<bool> checkPlatformHealth() async => true;

  @override
  Future<bool> registerDeviceToken(String fcmToken) async => true;

  @override
  Future<int> syncWapNotifications() async => 0;

  @override
  Future<void> refreshAdConfig() async {}

  @override
  Future<void> setAdFreePurchased(bool purchased) async {
    _state = _state.copyWith(isAdFreePurchased: purchased);
    _controller.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  group('AdBanner and SettingsScreen Widget Tests', () {
    testWidgets('FileZenAdBanner collapses completely when Ad-Free is purchased', (tester) async {
      final fakeManager = FakeWapCentralManager(
        state: const MonetizationState(isAdFreePurchased: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wapCentralManagerProvider.overrideWithValue(fakeManager),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FileZenAdBanner(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // When ad-free, banner collapses to SizedBox.shrink()
      expect(find.byType(FileZenAdBanner), findsOneWidget);
      final sizedBoxFinder = find.descendant(
        of: find.byType(FileZenAdBanner),
        matching: find.byType(SizedBox),
      );
      expect(sizedBoxFinder, findsOneWidget);
      final SizedBox sizedBox = tester.widget(sizedBoxFinder);
      expect(sizedBox.width, equals(0.0));
      expect(sizedBox.height, equals(0.0));
    });

    testWidgets('SettingsScreen renders diagnostics and ad-free controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeManager = FakeWapCentralManager(
        state: const MonetizationState(isAdFreePurchased: false),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wapCentralManagerProvider.overrideWithValue(fakeManager),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Privacy & Processing section has Diagnostics
      expect(find.text('Anonymous Diagnostics & Crash Monitoring'), findsOneWidget);
      expect(find.text('Diagnostics & Observability Dashboard'), findsOneWidget);

      // Check Monetization section has Ad-Free Pro
      expect(find.text('Ad-Free Pro (One-Time Purchase)'), findsOneWidget);
      expect(find.text('Non-intrusive ads active. Tap to remove ads permanently.'), findsOneWidget);

      // Tap Ad-Free purchase button
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify state updated to ACTIVE chip and active subtitle
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Active — All advertising is completely disabled.'), findsOneWidget);
    });
  });
}
