import 'dart:io';

import 'package:filezen/core/widgets/file_thumbnail_widget.dart';
import 'package:filezen/data/media/thumbnail_provider.dart';
import 'package:filezen/data/media/thumbnail_service.dart';
import 'package:filezen/domain/models/file_category.dart';
import 'package:filezen/domain/models/file_entity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 PNG.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

FileEntity _video(String name) => FileEntity(
      id: name,
      path: '/storage/emulated/0/DCIM/$name',
      name: name,
      extension: 'mp4',
      size: 10,
      modifiedAt: DateTime(2026),
      createdAt: DateTime(2026),
      isDirectory: false,
      category: FileCategory.video,
    );

/// Service I/O is covered by thumbnail_service_test.dart; real file I/O started
/// inside testWidgets' fake-async zone never completes, so the widget tests use a
/// stub that answers immediately.
class _StubThumbnails extends ThumbnailService {
  _StubThumbnails(this.result) : super(extractor: null);
  final File? result;
  final requested = <String>[];

  @override
  Future<File?> videoThumbnail(FileEntity file, {bool Function()? stillNeeded}) {
    requested.add(file.path);
    return Future.value(result);
  }
}

void main() {
  late Directory cache;
  setUp(() async => cache = await Directory.systemTemp.createTemp('filezen_thumb_widget_'));
  tearDown(() async => cache.delete(recursive: true));

  Future<void> pumpRow(WidgetTester tester, ThumbnailService service, FileEntity file) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [thumbnailServiceProvider.overrideWithValue(service)],
      child: MaterialApp(home: Scaffold(body: FileThumbnailWidget(file: file, size: 48))),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('video rows show the extracted frame, not the generic icon', (tester) async {
    final frameFile = File('${cache.path}/frame.png')..writeAsBytesSync(_png);
    final service = _StubThumbnails(frameFile);
    await pumpRow(tester, service, _video('holiday.mp4'));

    expect(service.requested, ['/storage/emulated/0/DCIM/holiday.mp4']);
    final frame = find.byWidgetPredicate(
      (w) => w is Image && w.image is ResizeImage && ((w.image as ResizeImage).imageProvider as FileImage).file.path == frameFile.path,
    );
    expect(frame, findsOneWidget);
    expect(find.byIcon(Icons.movie_rounded), findsNothing);
    expect(find.text('MP4'), findsOneWidget);
  });

  testWidgets('unsupported or corrupt videos keep the icon fallback', (tester) async {
    await pumpRow(tester, _StubThumbnails(null), _video('broken.mp4'));
    expect(find.byIcon(Icons.movie_rounded), findsOneWidget);
  });
}
