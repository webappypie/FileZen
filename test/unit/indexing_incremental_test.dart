import 'dart:io';

import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/indexing/indexing_service.dart';
import 'package:filezen/data/indexing/text_extractor.dart';
import 'package:filezen/data/search/search_repository.dart';
import 'package:filezen/data/storage/filesystem_storage_repository.dart';
import 'package:filezen/domain/models/ai_models.dart';
import 'package:filezen/domain/models/search_query.dart';
import 'package:filezen/domain/repositories/i_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Stands in for ML Kit: returns fixed text per file name, counts calls.
class _CountingOcr implements IOcrService {
  final Map<String, String> textByName;
  final List<String> processed = [];
  _CountingOcr(this.textByName);

  @override
  Future<bool> isOcrAvailable() async => true;

  @override
  Future<OcrExtractionResult> extractTextFromImage(String imagePath) async {
    processed.add(p.basename(imagePath));
    return OcrExtractionResult(
      filePath: imagePath,
      extractedText: textByName[p.basename(imagePath)] ?? '',
      confidence: 0.9,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late SearchRepository search;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    search = SearchRepository(db);
    tempDir = await Directory.systemTemp.createTemp('filezen_incremental_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  IndexingService indexer({IOcrService? ocr, Future<bool> Function()? heavyWorkAllowed}) => IndexingService(
        db: db,
        storageRepo: FilesystemStorageRepository(),
        textExtractor: TextExtractor(ocrService: ocr),
        heavyWorkAllowed: heavyWorkAllowed,
      );

  Future<List<String>> indexedPaths() async =>
      (await db.select(db.fileRecords).get()).map((r) => r.path).toList()..sort();

  Future<List<String>> searchNames(String text) async =>
      (await search.search(SearchQuery(text: text))).dataOrNull!.map((r) => r.file.name).toList();

  test('files deleted outside FileZen are pruned from the index and search', () async {
    final keep = File(p.join(tempDir.path, 'keep.txt'))..writeAsStringSync('alpha');
    final gone = File(p.join(tempDir.path, 'gone.txt'))..writeAsStringSync('bravo');
    await indexer().runIndexScan(targetPaths: [tempDir.path]);
    expect(await searchNames('bravo'), ['gone.txt']);

    gone.deleteSync();
    final res = await indexer().runIndexScan(targetPaths: [tempDir.path]);

    expect(res.dataOrNull!.removedCount, 1);
    expect(await indexedPaths(), [keep.path]);
    expect(await searchNames('bravo'), isEmpty);
  });

  test('new files created outside FileZen are picked up; unchanged files are skipped', () async {
    File(p.join(tempDir.path, 'a.txt')).writeAsStringSync('one');
    await indexer().runIndexScan(targetPaths: [tempDir.path]);

    File(p.join(tempDir.path, 'b.txt')).writeAsStringSync('two');
    final res = (await indexer().runIndexScan(targetPaths: [tempDir.path])).dataOrNull!;
    expect(res.indexedCount, 1);
    expect(res.skippedCount, 1);
    expect(await searchNames('two'), ['b.txt']);
  });

  test('a folder that cannot be read does not cause its entries to be pruned', () async {
    if (Platform.isWindows) return;
    final locked = Directory(p.join(tempDir.path, 'locked'))..createSync();
    final inside = File(p.join(locked.path, 'secret.txt'))..writeAsStringSync('charlie');
    await indexer().runIndexScan(targetPaths: [tempDir.path]);
    expect(await indexedPaths(), [inside.path]);

    await Process.run('chmod', ['000', locked.path]);
    addTearDown(() => Process.run('chmod', ['755', locked.path]));
    // Running as root bypasses permissions; only assert when the folder is really unreadable.
    final readable = await locked.list().toList().then((_) => true, onError: (_) => false);
    if (readable) return;

    final res = (await indexer().runIndexScan(targetPaths: [tempDir.path])).dataOrNull!;
    expect(res.removedCount, 0);
    expect(await indexedPaths(), [inside.path]);
  });

  test('OCR runs once per image version and its text becomes searchable', () async {
    final ocr = _CountingOcr({'receipt.jpg': 'Total paid 42 EUR grocery'});
    final img = File(p.join(tempDir.path, 'receipt.jpg'))..writeAsBytesSync([1, 2, 3]);

    final first = (await indexer(ocr: ocr).runIndexScan(targetPaths: [tempDir.path])).dataOrNull!;
    expect(first.pendingOcrCount, 0);
    expect(ocr.processed, ['receipt.jpg']);
    expect(await searchNames('grocery'), ['receipt.jpg']);

    await indexer(ocr: ocr).runIndexScan(targetPaths: [tempDir.path]);
    expect(ocr.processed, ['receipt.jpg'], reason: 'unchanged image must not be OCR\'d again');

    img.writeAsBytesSync([1, 2, 3, 4]);
    ocr.textByName['receipt.jpg'] = 'Updated invoice';
    await indexer(ocr: ocr).runIndexScan(targetPaths: [tempDir.path]);
    expect(ocr.processed, ['receipt.jpg', 'receipt.jpg']);
    expect(await searchNames('grocery'), isEmpty);
    expect(await searchNames('invoice'), ['receipt.jpg']);
  });

  test('OCR is deferred, not dropped, while heavy work is not allowed', () async {
    final ocr = _CountingOcr({'scan.png': 'passport number'});
    File(p.join(tempDir.path, 'scan.png')).writeAsBytesSync([9, 9]);

    final deferred = (await indexer(ocr: ocr, heavyWorkAllowed: () async => false)
            .runIndexScan(targetPaths: [tempDir.path]))
        .dataOrNull!;
    expect(deferred.pendingOcrCount, 1);
    expect(ocr.processed, isEmpty);
    // The file itself is indexed (by name) even while OCR waits.
    expect(await searchNames('scan'), ['scan.png']);

    final later = (await indexer(ocr: ocr, heavyWorkAllowed: () async => true)
            .runIndexScan(targetPaths: [tempDir.path]))
        .dataOrNull!;
    expect(later.pendingOcrCount, 0);
    expect(await searchNames('passport'), ['scan.png']);
  });

  test('nested roots (Downloads inside Internal Storage) are walked once', () async {
    final downloads = Directory(p.join(tempDir.path, 'Download'))..createSync();
    File(p.join(downloads.path, 'file.pdf')).writeAsStringSync('%PDF-1.4');

    final res = (await indexer().runIndexScan(targetPaths: [tempDir.path, downloads.path])).dataOrNull!;
    expect(res.totalFilesDiscovered, 1);
  });

  test('a large library indexes and re-scans within budget', () async {
    for (var d = 0; d < 20; d++) {
      final dir = Directory(p.join(tempDir.path, 'dir$d'))..createSync();
      for (var f = 0; f < 100; f++) {
        File(p.join(dir.path, 'file_${d}_$f.bin')).writeAsBytesSync([d, f]);
      }
    }
    final sw = Stopwatch()..start();
    final first = (await indexer().runIndexScan(targetPaths: [tempDir.path])).dataOrNull!;
    final firstMs = sw.elapsedMilliseconds;
    sw.reset();
    final second = (await indexer().runIndexScan(targetPaths: [tempDir.path])).dataOrNull!;
    final secondMs = sw.elapsedMilliseconds;

    expect(first.indexedCount, 2000);
    expect(second.skippedCount, 2000);
    expect(second.indexedCount, 0);
    // ignore: avoid_print
    print('2,000 files: first scan ${firstMs}ms, unchanged re-scan ${secondMs}ms');
    expect(secondMs, lessThan(firstMs), reason: 'unchanged files must not be re-processed');
  });
}
