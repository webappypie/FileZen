import 'dart:async';
import 'dart:io';

import 'package:filezen/data/media/thumbnail_service.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileEntity _video(String path, {int size = 100, int mtime = 1000}) => FileEntity(
      id: path,
      path: path,
      name: p.basename(path),
      extension: 'mp4',
      size: size,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(mtime),
      createdAt: DateTime.fromMillisecondsSinceEpoch(mtime),
      isDirectory: false,
      category: FileCategory.video,
    );

void main() {
  late Directory cache;
  setUp(() async => cache = await Directory.systemTemp.createTemp('filezen_thumbs_'));
  tearDown(() async => cache.delete(recursive: true));

  test('extracts once, then serves the cached frame', () async {
    final calls = <String>[];
    final service = ThumbnailService(
      cacheRoot: () async => cache,
      extractor: (src, out, max) async {
        calls.add(src);
        File(out).writeAsBytesSync([0xFF, 0xD8, 0xFF]);
        return out;
      },
    );
    final a = await service.videoThumbnail(_video('/v/a.mp4'));
    final b = await service.videoThumbnail(_video('/v/a.mp4'));
    expect(a, isNotNull);
    expect(b!.path, a!.path);
    expect(calls, ['/v/a.mp4']);
  });

  test('an edited video gets a new frame and the stale one is deleted', () async {
    final service = ThumbnailService(
      cacheRoot: () async => cache,
      extractor: (src, out, max) async {
        File(out).writeAsBytesSync([1]);
        return out;
      },
    );
    final before = await service.videoThumbnail(_video('/v/a.mp4', mtime: 1000));
    final after = await service.videoThumbnail(_video('/v/a.mp4', mtime: 2000));
    expect(after!.path, isNot(before!.path));
    expect(before.existsSync(), isFalse);
    expect(after.existsSync(), isTrue);
  });

  test('corrupt videos fall back and are not retried in the session', () async {
    var calls = 0;
    final service = ThumbnailService(
      cacheRoot: () async => cache,
      extractor: (src, out, max) async {
        calls++;
        return null;
      },
    );
    expect(await service.videoThumbnail(_video('/v/bad.mp4')), isNull);
    expect(await service.videoThumbnail(_video('/v/bad.mp4')), isNull);
    expect(calls, 1);
  });

  test('concurrency is bounded and rows scrolled away are skipped', () async {
    var running = 0;
    var peak = 0;
    final gate = Completer<void>();
    final service = ThumbnailService(
      cacheRoot: () async => cache,
      maxConcurrent: 2,
      extractor: (src, out, max) async {
        running++;
        peak = running > peak ? running : peak;
        await gate.future;
        File(out).writeAsBytesSync([1]);
        running--;
        return out;
      },
    );
    var visible = true;
    final futures = [
      for (var i = 0; i < 6; i++) service.videoThumbnail(_video('/v/$i.mp4')),
      service.videoThumbnail(_video('/v/gone.mp4'), stillNeeded: () => visible),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 50));
    visible = false;
    gate.complete();
    final results = await Future.wait(futures);
    expect(peak, 2);
    expect(results.take(6).every((f) => f != null), isTrue);
    expect(results.last, isNull);
  });

  test('evictPath removes the cached frame (Vault privacy)', () async {
    final service = ThumbnailService(
      cacheRoot: () async => cache,
      extractor: (src, out, max) async {
        File(out).writeAsBytesSync([1]);
        return out;
      },
    );
    final thumb = await service.videoThumbnail(_video('/v/private.mp4'));
    expect(thumb!.existsSync(), isTrue);
    await service.evictPath('/v/private.mp4');
    expect(thumb.existsSync(), isFalse);
  });

  test('without a platform extractor no thumbnail is claimed', () async {
    final service = ThumbnailService(cacheRoot: () async => cache, extractor: null);
    // On the test host Platform.isAndroid is false, so the default is "unsupported".
    expect(ThumbnailService(cacheRoot: () async => cache).isSupported, Platform.isAndroid);
    expect(await service.videoThumbnail(_video('/v/a.mp4')), isNull);
  });

  test('trimCache keeps the cache under the byte budget', () async {
    final service = ThumbnailService(
      cacheRoot: () async => cache,
      extractor: (src, out, max) async {
        File(out).writeAsBytesSync(List.filled(1000, 1));
        return out;
      },
    );
    for (var i = 0; i < 5; i++) {
      await service.videoThumbnail(_video('/v/$i.mp4'));
    }
    await service.trimCache(maxBytes: 2500);
    final left = Directory(p.join(cache.path, 'video_thumbs'))
        .listSync(recursive: true)
        .whereType<File>()
        .fold<int>(0, (s, f) => s + f.lengthSync());
    expect(left, lessThanOrEqualTo(2500));
  });
}
