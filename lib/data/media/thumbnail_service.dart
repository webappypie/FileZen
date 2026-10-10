import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/file_entity.dart';

/// Writes one scaled frame of [sourcePath] as a JPEG at [outPath]; returns
/// [outPath] on success, null when no frame could be extracted.
typedef VideoFrameExtractor = Future<String?> Function(String sourcePath, String outPath, int maxSize);

/// Video-frame thumbnails for file lists.
///
/// * The platform extracts a single key frame, scaled to [maxSize]; the video is
///   never decoded into Dart memory.
/// * Results are cached on disk under `<cache>/video_thumbs/<sha1(path)>/` and
///   named after the file's size and modification time, so an edited video gets
///   a new thumbnail and the stale one is deleted.
/// * At most [maxConcurrent] extractions run at once; requests for rows that
///   scrolled away before their turn are dropped.
/// * Files that yield no frame (corrupt/unsupported) are remembered for the
///   session and fall back to the icon.
/// * [evictPath] removes a file's thumbnails (used when it moves into the Vault).
class ThumbnailService {
  ThumbnailService({
    VideoFrameExtractor? extractor,
    Future<Directory> Function()? cacheRoot,
    this.maxConcurrent = 2,
    this.maxSize = 256,
  })  : _extractor = extractor ?? (Platform.isAndroid ? _platformExtractor : null),
        _cacheRoot = cacheRoot ?? getApplicationCacheDirectory;

  final VideoFrameExtractor? _extractor;
  final Future<Directory> Function() _cacheRoot;
  final int maxConcurrent;
  final int maxSize;

  final Map<String, Future<File?>> _inFlight = {};
  final Set<String> _failed = {};
  final List<Completer<void>> _waiting = [];
  int _running = 0;

  static const _channel = MethodChannel('com.webappypie.filezen/device');

  static Future<String?> _platformExtractor(String source, String out, int maxSize) =>
      _channel.invokeMethod<String>('videoThumbnail', {
        'path': source,
        'outPath': out,
        'maxSize': maxSize,
      });

  bool get isSupported => _extractor != null;

  Future<Directory> _dirFor(String path) async {
    final root = await _cacheRoot();
    final hash = sha1.convert(utf8.encode(path)).toString();
    return Directory(p.join(root.path, 'video_thumbs', hash));
  }

  /// Cached thumbnail for [file], generating it if needed. [stillNeeded] is
  /// asked once a generation slot is free; returning false skips the work.
  Future<File?> videoThumbnail(FileEntity file, {bool Function()? stillNeeded}) async {
    final extractor = _extractor;
    if (extractor == null || file.isDirectory) return null;

    final dir = await _dirFor(file.path);
    final target = File(p.join(dir.path, '${file.size}_${file.modifiedAt.millisecondsSinceEpoch}.jpg'));
    if (await target.exists()) return target;
    if (_failed.contains(target.path)) return null;

    // Block body on purpose: `=> _inFlight.remove(...)` would return this very
    // future to whenComplete, which would then wait on itself forever.
    return _inFlight[target.path] ??= _generate(extractor, file.path, dir, target, stillNeeded)
        .whenComplete(() {
      _inFlight.remove(target.path);
    });
  }

  Future<File?> _generate(
    VideoFrameExtractor extractor,
    String source,
    Directory dir,
    File target,
    bool Function()? stillNeeded,
  ) async {
    await _acquire();
    try {
      if (stillNeeded != null && !stillNeeded()) return null;
      await dir.create(recursive: true);
      // Older versions of this file (different size/mtime) are stale.
      await for (final old in dir.list()) {
        if (old.path != target.path) await old.delete().catchError((_) => old);
      }
      final out = await extractor(source, target.path, maxSize);
      if (out != null && await target.exists() && await target.length() > 0) return target;
      _failed.add(target.path);
      return null;
    } catch (e) {
      AppLogger.debug('Video thumbnail unavailable: $e', 'Thumbnails');
      _failed.add(target.path);
      return null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future; // slot handed over by _release
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  /// Deletes every cached thumbnail of [path].
  Future<void> evictPath(String path) async {
    try {
      final dir = await _dirFor(path);
      _failed.removeWhere((key) => p.isWithin(dir.path, key));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLogger.warning('Could not evict a thumbnail: $e', 'Thumbnails');
    }
  }

  /// Keeps the cache under [maxBytes] by deleting the least recently written thumbnails.
  Future<void> trimCache({int maxBytes = 100 * 1024 * 1024}) async {
    try {
      final root = Directory(p.join((await _cacheRoot()).path, 'video_thumbs'));
      if (!await root.exists()) return;
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final e in root.list(recursive: true)) {
        if (e is File) {
          final stat = await e.stat();
          files.add((e, stat));
          total += stat.size;
        }
      }
      if (total <= maxBytes) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in files) {
        if (total <= maxBytes) break;
        await file.delete();
        total -= stat.size;
      }
    } catch (e) {
      AppLogger.warning('Thumbnail cache trim failed: $e', 'Thumbnails');
    }
  }
}
