import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:filezen/domain/models/file_sort_criteria.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final folderA = FileEntity(
    id: 'f_a',
    path: '/mock/folder_a',
    name: 'Folder Zebra',
    extension: '',
    size: 0,
    modifiedAt: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    isDirectory: true,
    category: FileCategory.other,
  );

  final fileB = FileEntity(
    id: 'f_b',
    path: '/mock/alpha.txt',
    name: 'alpha.txt',
    extension: '.txt',
    size: 100,
    modifiedAt: DateTime(2026, 3, 1),
    createdAt: DateTime(2026, 3, 1),
    isDirectory: false,
    category: FileCategory.document,
  );

  final fileC = FileEntity(
    id: 'f_c',
    path: '/mock/beta.pdf',
    name: 'beta.pdf',
    extension: '.pdf',
    size: 5000,
    modifiedAt: DateTime(2026, 2, 1),
    createdAt: DateTime(2026, 2, 1),
    isDirectory: false,
    category: FileCategory.document,
  );

  group('FileSortCriteria Sorting Logic', () {
    test('keeps folders first when foldersFirst is enabled', () {
      const criteria = FileSortCriteria(
        field: FileSortField.name,
        direction: SortDirection.ascending,
        foldersFirst: true,
      );

      final sorted = criteria.apply([fileB, folderA, fileC]);
      expect(sorted.first.name, 'Folder Zebra'); // folder comes first despite 'Z'
      expect(sorted[1].name, 'alpha.txt');
      expect(sorted[2].name, 'beta.pdf');
    });

    test('sorts by size descending', () {
      const criteria = FileSortCriteria(
        field: FileSortField.size,
        direction: SortDirection.descending,
        foldersFirst: false,
      );

      final sorted = criteria.apply([fileB, folderA, fileC]);
      expect(sorted.first.name, 'beta.pdf'); // 5000 bytes
      expect(sorted[1].name, 'alpha.txt'); // 100 bytes
      expect(sorted[2].name, 'Folder Zebra'); // 0 bytes
    });

    test('sorts by date ascending', () {
      const criteria = FileSortCriteria(
        field: FileSortField.date,
        direction: SortDirection.ascending,
        foldersFirst: false,
      );

      final sorted = criteria.apply([fileB, folderA, fileC]);
      expect(sorted.first.name, 'Folder Zebra'); // Jan 2026
      expect(sorted[1].name, 'beta.pdf'); // Feb 2026
      expect(sorted[2].name, 'alpha.txt'); // Mar 2026
    });
  });
}
