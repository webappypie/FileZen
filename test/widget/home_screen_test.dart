import 'dart:io';

import 'package:drift/native.dart';
import 'package:filezen/app/navigation/navigation_provider.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/database/database_provider.dart';
import 'package:filezen/data/indexing/indexing_service.dart';
import 'package:filezen/data/storage/device_storage_service.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/storage_intelligence_models.dart';
import 'package:filezen/features/files/presentation/providers/storage_providers.dart';
import 'package:filezen/features/files/presentation/screens/category_files_screen.dart';
import 'package:filezen/features/home/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _NoDeviceStats implements IDeviceStorageService {
  @override
  Future<DeviceStorageStats?> getStats() async => null;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Home is driven by the real index: categories, Recent, Favorites and the
/// receipts collection all come from files indexed from disk.
void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('filezen_home_');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceStorageServiceProvider.overrideWithValue(_NoDeviceStats()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await _settle(tester);
  }

  testWidgets('categories, recent files, favorites and receipts reflect indexed files', (tester) async {
    await tester.runAsync(() async {
      Directory(p.join(dir.path, 'Download')).createSync();
      File(p.join(dir.path, 'Download', 'tax_invoice_2026.pdf')).writeAsStringSync('%PDF-1.4 invoice');
      File(p.join(dir.path, 'holiday.mp4')).writeAsBytesSync([0, 0, 0, 1]);
      final notes = File(p.join(dir.path, 'notes.txt'))..writeAsStringSync('hello');
      await IndexingService(db: db, storageRepo: FilesystemStorageRepository())
          .runIndexScan(targetPaths: [dir.path]);
      await db.setFavorite(notes.path, true);
    });

    await pumpHome(tester);

    expect(find.text('Recent Files'), findsOneWidget);
    expect(find.text('holiday.mp4'), findsOneWidget);
    // notes.txt is both recent and a favorite.
    expect(find.text('notes.txt'), findsNWidgets(2));
    expect(find.text('2 items'), findsOneWidget); // Documents: pdf + txt
    expect(find.text('1 item'), findsWidgets); // Videos, Downloads
    expect(find.text('tax_invoice_2026.pdf'), findsWidgets);
    expect(find.textContaining('1 document'), findsOneWidget);

    // Category card opens the real list.
    await tester.tap(find.text('Videos'));
    await _settle(tester);
    expect(find.byType(CategoryFilesScreen), findsOneWidget);
    expect(find.text('holiday.mp4'), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);

    // "See all" on Favorites opens the full favorites list.
    await tester.tap(find.text('See all').last);
    await _settle(tester);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('holiday.mp4'), findsNothing);
  });

  testWidgets('empty index shows honest empty states; Ask Your Files opens the AI tab', (tester) async {
    late ProviderContainer container;
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceStorageServiceProvider.overrideWithValue(_NoDeviceStats()),
      ],
      child: MaterialApp(home: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return const HomeScreen();
      })),
    ));
    await _settle(tester);

    expect(find.text('Files appear here as FileZen indexes your storage.'), findsOneWidget);
    expect(find.textContaining('Add to Favorites'), findsOneWidget);
    expect(find.text('See all'), findsNothing);

    await tester.tap(find.text('Ask Your Files'));
    await tester.pump();
    expect(container.read(currentTabProvider), 2);
  });
}
