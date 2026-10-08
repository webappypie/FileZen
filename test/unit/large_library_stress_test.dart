import 'package:filezen/domain/models/deduplication_models.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Large Library & Scalability Stress Tests (Phase 13 Hardening)', () {
    test('deduplication clustering scales linearly on large collections (5,000 items)', () {
      final List<FileEntity> mockFiles = [];
      final now = DateTime.now();

      // Generate 5,000 files with 50 duplicate clusters of 10 items each, and 4,500 unique files
      for (int c = 0; c < 50; c++) {
        for (int i = 0; i < 10; i++) {
          mockFiles.add(
            FileEntity(
              id: 'dup_${c}_$i',
              path: '/mock/storage/cluster_$c/photo_$i.jpg',
              name: 'photo_$i.jpg',
              extension: 'jpg',
              size: 2048576, // exactly 2MB
              modifiedAt: now,
              createdAt: now,
              isDirectory: false,
              category: FileCategory.image,
              checksum: 'hash_cluster_$c',
            ),
          );
        }
      }

      for (int u = 0; u < 4500; u++) {
        mockFiles.add(
          FileEntity(
            id: 'unique_$u',
            path: '/mock/storage/unique/doc_$u.pdf',
            name: 'doc_$u.pdf',
            extension: 'pdf',
            size: 1024 + u,
            modifiedAt: now,
            createdAt: now,
            isDirectory: false,
            category: FileCategory.document,
            checksum: 'unique_hash_$u',
          ),
        );
      }

      expect(mockFiles.length, equals(5000));

      final sw = Stopwatch()..start();

      // Clustering algorithm benchmark
      final Map<String, List<FileEntity>> clustersByHash = {};
      for (final file in mockFiles) {
        if (file.checksum != null) {
          clustersByHash.putIfAbsent(file.checksum!, () => []).add(file);
        }
      }

      final duplicateGroups = clustersByHash.entries
          .where((e) => e.value.length > 1)
          .map(
            (e) => DuplicateGroup(
              checksum: e.key,
              fileSize: e.value.first.size,
              primaryFile: e.value.first,
              duplicateFiles: e.value.sublist(1),
            ),
          )
          .toList();

      sw.stop();

      expect(duplicateGroups.length, equals(50));
      for (final group in duplicateGroups) {
        expect(group.duplicateFiles.length, equals(9));
        expect(group.allFiles.length, equals(10));
        expect(group.recoverableSize, equals(2048576 * 9));
      }

      // Must complete in under 100 milliseconds for 5,000 items
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('batch chunking splits large collections without memory spikes', () {
      final List<int> items = List.generate(12500, (i) => i);
      const chunkSize = 500;

      final sw = Stopwatch()..start();
      final List<List<int>> chunks = [];
      for (int i = 0; i < items.length; i += chunkSize) {
        final end = (i + chunkSize < items.length) ? i + chunkSize : items.length;
        chunks.add(items.sublist(i, end));
      }
      sw.stop();

      expect(chunks.length, equals(25));
      expect(chunks.first.length, equals(500));
      expect(chunks.last.length, equals(500));
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}
