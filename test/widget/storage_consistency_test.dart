import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/database/database_provider.dart';
import 'package:filezen/data/storage/device_storage_service.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/storage_intelligence_models.dart';
import 'package:filezen/features/clean/presentation/screens/storage_analysis_screen.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;

class _FixedDeviceStorage implements IDeviceStorageService {
  _FixedDeviceStorage(this.stats);
  final DeviceStorageStats? stats;
  int calls = 0;

  @override
  Future<DeviceStorageStats?> getStats() async {
    calls++;
    return stats;
  }
}

/// Regression for the "Home 35% vs Storage Intelligence 50%" report.
///
/// Root cause: neither number was measured. Home hard-coded 46 GB of 128 GB
/// (35.9% truncated to "35%"); Storage Intelligence summed the "Internal" and
/// "Downloads" locations — two folders on one volume, each carrying a nominal
/// 128 GB / 64 GB free — giving 256 GB / 128 GB free = "50.0%".
/// Lets real database I/O (drift runs outside the fake test clock) complete.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget app(Widget home, IDeviceStorageService device) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceStorageServiceProvider.overrideWithValue(device),
        ],
        child: MaterialApp(home: home),
      );

  testWidgets('Home and Storage Intelligence show the same measured percentage', (tester) async {
    final device = _FixedDeviceStorage(DeviceStorageStats(
      totalBytes: 128 * _gb,
      freeBytes: 82 * _gb, // 46 GB used = 35.9%
      measuredAt: DateTime(2026, 10, 10),
    ));

    await tester.pumpWidget(app(const HomeScreen(), device));
    await _settle(tester);

    // One rounding rule everywhere: 35.9% -> 36%.
    expect(find.text('36%'), findsOneWidget);
    expect(find.text('35%'), findsNothing);
    expect(find.textContaining('used of 128 GB'), findsOneWidget);

    await tester.tap(find.text('Internal Storage'));
    await _settle(tester);

    expect(find.byType(StorageAnalysisScreen), findsOneWidget);
    expect(find.text('36%'), findsOneWidget);
    expect(find.text('50%'), findsNothing);
    expect(find.textContaining('50.0%'), findsNothing);
    expect(find.text('used of 128 GB'), findsOneWidget);
    // Both screens consumed one measurement.
    expect(device.calls, 1);
  });

  testWidgets('Unmeasurable device storage is shown as unavailable, never invented', (tester) async {
    final device = _FixedDeviceStorage(null);

    await tester.pumpWidget(app(const HomeScreen(), device));
    await _settle(tester);
    expect(find.text('Device storage unavailable'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    await tester.tap(find.text('Internal Storage'));
    await _settle(tester);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Device capacity could not be measured'), findsOneWidget);
    expect(find.textContaining('128'), findsNothing);
  });

  test('Locations on one volume are not scanned or counted twice', () {
    expect(
      FilesystemStorageRepository.distinctRoots(
        ['/storage/emulated/0/Download', '/storage/emulated/0', '/storage/emulated/0/'],
      ),
      ['/storage/emulated/0'],
    );
    expect(
      FilesystemStorageRepository.distinctRoots(['/a/b', '/a/bc']),
      ['/a/b', '/a/bc'],
    );
  });

  test('Percent label rounding is shared by every metric', () {
    final stats = DeviceStorageStats(totalBytes: 128 * _gb, freeBytes: 82 * _gb, measuredAt: DateTime(2026));
    const overview = StorageOverview(
      totalBytes: 128 * _gb,
      usedBytes: 46 * _gb,
      freeBytes: 82 * _gb,
      categorySizes: {},
      categoryCounts: {},
    );
    expect(stats.usedPercentLabel, 36);
    expect(overview.usedPercentLabel, stats.usedPercentLabel);
    expect(DeviceStorageStats.percentLabel(0.004), 0);
    expect(DeviceStorageStats.percentLabel(1.2), 100);
  });

  test('DeviceStorageService reads StatFs values and rejects nonsense', () async {
    const channel = MethodChannel('test/device');
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'storageStats');
      return {'path': '/storage/emulated/0', 'totalBytes': 1000, 'availableBytes': 250};
    });
    final ok = await DeviceStorageService(channel: channel, isAndroid: true).getStats();
    expect(ok!.usedBytes, 750);

    messenger.setMockMethodCallHandler(channel, (call) async => {'totalBytes': 10, 'availableBytes': 20});
    expect(await DeviceStorageService(channel: channel, isAndroid: true).getStats(), isNull);

    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'X'));
    expect(await DeviceStorageService(channel: channel, isAndroid: true).getStats(), isNull);

    expect(await DeviceStorageService(channel: channel, isAndroid: false).getStats(), isNull);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
