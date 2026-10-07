import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:filezen/data/database/app_database.dart';
import 'package:filezen/data/search/search_repository.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SearchRepository searchRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    searchRepo = SearchRepository(db);

    final now = DateTime.now();

    // Seed file 1: PDF Document
    await db.into(db.fileRecords).insert(
          FileRecordsCompanion.insert(
            id: 'doc_1',
            path: '/storage/emulated/0/Download/Quarterly_Report_2026.pdf',
            name: 'Quarterly_Report_2026.pdf',
            extension: '.pdf',
            size: BigInt.from(500 * 1024),
            modifiedAt: now.subtract(const Duration(days: 2)),
            createdAt: now.subtract(const Duration(days: 5)),
            mimeType: const Value('application/pdf'),
            isFavorite: const Value(true),
            category: const Value('Documents'),
            indexedAt: Value(now),
          ),
        );
    await db.insertSearchDocument(
      'doc_1',
      'Quarterly_Report_2026.pdf',
      '/storage/emulated/0/Download/Quarterly_Report_2026.pdf',
      'Executive financial summary revenue growth and budget planning for Q1 2026',
      'finance,report',
      'Documents',
    );

    // Seed file 2: JPEG Image
    await db.into(db.fileRecords).insert(
          FileRecordsCompanion.insert(
            id: 'img_1',
            path: '/storage/emulated/0/DCIM/Camera/sunset_vacation.jpg',
            name: 'sunset_vacation.jpg',
            extension: '.jpg',
            size: BigInt.from(2 * 1024 * 1024),
            modifiedAt: now.subtract(const Duration(days: 10)),
            createdAt: now.subtract(const Duration(days: 10)),
            mimeType: const Value('image/jpeg'),
            category: const Value('Images'),
            indexedAt: Value(now),
          ),
        );
    await db.insertSearchDocument(
      'img_1',
      'sunset_vacation.jpg',
      '/storage/emulated/0/DCIM/Camera/sunset_vacation.jpg',
      'sunset vacation beach holiday scenery gold hour',
      'travel,photo',
      'Images',
    );

    // Seed file 3: TXT Code/Notes
    await db.into(db.fileRecords).insert(
          FileRecordsCompanion.insert(
            id: 'txt_1',
            path: '/storage/emulated/0/Documents/passwords_backup.txt',
            name: 'passwords_backup.txt',
            extension: '.txt',
            size: BigInt.from(4 * 1024),
            modifiedAt: now,
            createdAt: now,
            mimeType: const Value('text/plain'),
            category: const Value('Documents'),
            indexedAt: Value(now),
          ),
        );
    await db.insertSearchDocument(
      'txt_1',
      'passwords_backup.txt',
      '/storage/emulated/0/Documents/passwords_backup.txt',
      'Important private credentials and server database keys',
      'private,notes',
      'Documents',
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('SearchRepository FTS5 Universal Search', () {
    test('searches across filenames and content with snippet highlighting', () async {
      final res = await searchRepo.search(const SearchQuery(text: 'revenue'));
      expect(res.isSuccess, isTrue);

      final items = res.dataOrNull!;
      expect(items.length, 1);
      expect(items.first.file.id, 'doc_1');
      expect(items.first.file.name, 'Quarterly_Report_2026.pdf');
      expect(items.first.snippet, contains('[match]revenue[/match]'));
    });

    test('supports prefix queries for responsive search as you type', () async {
      // Searching prefix 'vacat' matches 'vacation'
      final res = await searchRepo.search(const SearchQuery(text: 'vacat'));
      expect(res.isSuccess, isTrue);

      final items = res.dataOrNull!;
      expect(items.length, 1);
      expect(items.first.file.id, 'img_1');
    });

    test('filters search results by category', () async {
      // 'passwords' is in Documents
      final docRes = await searchRepo.search(
        const SearchQuery(text: 'passwords', category: FileCategory.document),
      );
      expect(docRes.dataOrNull!.length, 1);

      // 'passwords' searched in Images should yield no results
      final imgRes = await searchRepo.search(
        const SearchQuery(text: 'passwords', category: FileCategory.image),
      );
      expect(imgRes.dataOrNull!.isEmpty, isTrue);
    });

    test('browses by category when text query is empty', () async {
      final res = await searchRepo.search(const SearchQuery(text: '', category: FileCategory.document));
      expect(res.isSuccess, isTrue);

      final items = res.dataOrNull!;
      expect(items.length, 2); // doc_1 and txt_1
    });

    test('applies secondary filters: size, extension, and favorite', () async {
      // Size filter: only files > 1MB
      final largeRes = await searchRepo.search(
        const SearchQuery(text: 'vacation', minSize: 1024 * 1024),
      );
      expect(largeRes.dataOrNull!.length, 1);

      final smallRes = await searchRepo.search(
        const SearchQuery(text: 'vacation', maxSize: 500 * 1024),
      );
      expect(smallRes.dataOrNull!.isEmpty, isTrue);

      // Favorite filter
      final favRes = await searchRepo.search(
        const SearchQuery(text: 'report', isFavoriteOnly: true),
      );
      expect(favRes.dataOrNull!.length, 1);
    });

    test('reports accurate indexed count and clears index cleanly', () async {
      final countRes = await searchRepo.getIndexedDocumentCount();
      expect(countRes.dataOrNull, 3);

      await searchRepo.clearIndex();

      final afterClearCount = await searchRepo.getIndexedDocumentCount();
      expect(afterClearCount.dataOrNull, 0);

      final searchAfterClear = await searchRepo.search(const SearchQuery(text: 'revenue'));
      expect(searchAfterClear.dataOrNull!.isEmpty, isTrue);
    });
  });
}
