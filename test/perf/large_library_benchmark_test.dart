import 'dart:io';

import 'package:drift/native.dart';
import 'package:filezen/data/cleanup/storage_hygiene_service.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/indexing/indexing_service.dart';
import 'package:filezen/data/search/search_repository.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/search_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Opt-in benchmark on real files: `FILEZEN_BENCH=100000 flutter test test/perf`.
/// Host numbers (desktop SSD); phones are slower — use them to compare builds,
/// not as device timings.
void main() {
  final count = int.tryParse(Platform.environment['FILEZEN_BENCH'] ?? '');

  test('large library: index, re-scan, search, storage aggregates', () async {
    final n = count!;
    final tempDir = await Directory.systemTemp.createTemp('filezen_bench_');
    final dbFile = File(p.join(tempDir.path, 'bench.sqlite'));
    final root = Directory(p.join(tempDir.path, 'storage'))..createSync();
    final exts = ['jpg', 'mp4', 'pdf', 'txt', 'zip', 'mp3', 'docx', 'bin'];
    for (var i = 0; i < n; i++) {
      final dir = Directory(p.join(root.path, 'folder_${i ~/ 500}'));
      if (i % 500 == 0) dir.createSync();
      File(p.join(dir.path, 'item_$i.${exts[i % exts.length]}'))
          .writeAsStringSync(i % 8 == 3 ? 'invoice number $i' : 'x');
    }

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final indexer = IndexingService(db: db, storageRepo: FilesystemStorageRepository());
    final search = SearchRepository(db);
    final hygiene = StorageHygieneService(
      db: db,
      storageRepo: FilesystemStorageRepository(),
      customTrendFilePath: p.join(tempDir.path, 't.json'),
    );

    Future<int> time(Future<void> Function() body) async {
      final sw = Stopwatch()..start();
      await body();
      return sw.elapsedMilliseconds;
    }

    final firstMs = await time(() => indexer.runIndexScan(targetPaths: [root.path]));
    final rescanMs = await time(() => indexer.runIndexScan(targetPaths: [root.path]));
    File(p.join(root.path, 'folder_0', 'item_0.jpg')).deleteSync();
    File(p.join(root.path, 'folder_0', 'new.txt')).writeAsStringSync('fresh');
    final deltaMs = await time(() => indexer.runIndexScan(targetPaths: [root.path]));
    late int hits;
    final searchMs = await time(() async {
      hits = (await search.search(const SearchQuery(text: 'invoice'))).dataOrNull!.length;
    });
    final prefixMs = await time(() => search.search(const SearchQuery(text: 'i')));
    final overviewMs = await time(() => hygiene.getStorageOverview());
    final foldersMs = await time(() => hygiene.getTopFolders());
    final largestMs = await time(() => hygiene.getLargestFiles());
    final countsMs = await time(() => db.getCategoryCounts());

    // ignore: avoid_print
    print('''
$n files
  first index          ${firstMs}ms
  unchanged re-scan    ${rescanMs}ms
  1 deleted + 1 new    ${deltaMs}ms
  FTS "invoice"        ${searchMs}ms ($hits results, capped at ${SearchRepository.maxResults})
  FTS prefix "i*"      ${prefixMs}ms
  storage overview     ${overviewMs}ms
  top folders          ${foldersMs}ms
  largest files        ${largestMs}ms
  category counts      ${countsMs}ms''');

    expect(hits, SearchRepository.maxResults);
    await db.close();
    await tempDir.delete(recursive: true);
  }, skip: count == null ? 'set FILEZEN_BENCH=<file count> to run' : false, timeout: Timeout.none);
}
