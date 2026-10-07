import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:filezen/data/services/media_metadata_service.dart';

void main() {
  late Directory tempDir;
  late MediaMetadataService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('filezen_media_test_');
    service = const MediaMetadataService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaMetadataService - Image Metadata', () {
    test('returns empty metadata gracefully for non-existent image', () async {
      final meta = await service.extractImageMetadata('/non/existent/image.jpg');
      expect(meta.fileSize, 0);
      expect(meta.width, isNull);
      expect(meta.height, isNull);
      expect(meta.cameraString, 'Unknown');
      expect(meta.hasGps, isFalse);
    });

    test('extracts PNG dimensions correctly from synthetic binary header', () async {
      final pngFile = File('${tempDir.path}/test_image.png');
      // Create a valid PNG signature + IHDR chunk (width=1920, height=1080)
      final bytes = Uint8List(33);
      // PNG Signature
      bytes.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      // IHDR Length = 13 (bytes 8-11)
      bytes[11] = 13;
      // IHDR Type
      bytes[12] = 0x49; // 'I'
      bytes[13] = 0x48; // 'H'
      bytes[14] = 0x44; // 'D'
      bytes[15] = 0x52; // 'R'
      // Width = 1920 (0x00000780)
      final bd = ByteData.sublistView(bytes);
      bd.setUint32(16, 1920, Endian.big);
      // Height = 1080 (0x00000438)
      bd.setUint32(20, 1080, Endian.big);

      await pngFile.writeAsBytes(bytes);

      final meta = await service.extractImageMetadata(pngFile.path);
      expect(meta.width, 1920);
      expect(meta.height, 1080);
      expect(meta.resolutionString, '1920 × 1080');
      expect(meta.fileSize, 33);
      expect(meta.mimeType, 'image/png');
    });

    test('extracts BMP dimensions correctly from synthetic binary header', () async {
      final bmpFile = File('${tempDir.path}/test_image.bmp');
      final bytes = Uint8List(30);
      // BMP Magic: 'BM'
      bytes[0] = 0x42;
      bytes[1] = 0x4D;
      // DIB Header width = 640, height = 480 (little endian at offsets 18, 22)
      final bd = ByteData.sublistView(bytes);
      bd.setInt32(18, 640, Endian.little);
      bd.setInt32(22, 480, Endian.little);

      await bmpFile.writeAsBytes(bytes);

      final meta = await service.extractImageMetadata(bmpFile.path);
      expect(meta.width, 640);
      expect(meta.height, 480);
      expect(meta.resolutionString, '640 × 480');
      expect(meta.mimeType, 'image/bmp');
    });

    test('extracts GIF dimensions correctly from synthetic binary header', () async {
      final gifFile = File('${tempDir.path}/test_image.gif');
      final bytes = Uint8List(16);
      // GIF Magic: 'GIF89a'
      bytes.setRange(0, 6, [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      // Screen width = 800, height = 600 (little endian at offsets 6, 8)
      final bd = ByteData.sublistView(bytes);
      bd.setUint16(6, 800, Endian.little);
      bd.setUint16(8, 600, Endian.little);

      await gifFile.writeAsBytes(bytes);

      final meta = await service.extractImageMetadata(gifFile.path);
      expect(meta.width, 800);
      expect(meta.height, 600);
      expect(meta.resolutionString, '800 × 600');
      expect(meta.mimeType, 'image/gif');
    });
  });

  group('MediaMetadataService - Video Metadata', () {
    test('returns empty video metadata gracefully for non-existent video', () async {
      final meta = await service.extractVideoMetadata('/non/existent/video.mp4');
      expect(meta.fileSize, 0);
      expect(meta.format, 'MP4');
      expect(meta.duration, Duration.zero);
      expect(meta.resolutionString, 'Unknown');
    });

    test('extracts basic video container metadata for empty mp4 file', () async {
      final videoFile = File('${tempDir.path}/clip.mp4');
      await videoFile.writeAsBytes(List.filled(100, 0));

      final meta = await service.extractVideoMetadata(videoFile.path);
      expect(meta.fileSize, 100);
      expect(meta.format, 'MP4');
    });
  });

  group('MediaMetadataService - Audio Metadata', () {
    test('returns filename title for non-existent audio', () async {
      final meta = await service.extractAudioMetadata('/music/summer_breeze.mp3');
      expect(meta.title, 'summer_breeze');
      expect(meta.format, 'MP3');
      expect(meta.artistOrUnknown, 'Unknown Artist');
      expect(meta.albumOrUnknown, 'Unknown Album');
    });

    test('parses ID3v1 tags from audio file tail', () async {
      final audioFile = File('${tempDir.path}/song.mp3');
      // Create file of 256 bytes with ID3v1 tag in last 128 bytes
      final bytes = Uint8List(256);
      final tagOffset = 128;
      // 'TAG' identifier
      bytes[tagOffset] = 0x54; // 'T'
      bytes[tagOffset + 1] = 0x41; // 'A'
      bytes[tagOffset + 2] = 0x47; // 'G'

      // Title: "Sunset Horizon"
      final title = 'Sunset Horizon';
      for (var i = 0; i < title.length; i++) {
        bytes[tagOffset + 3 + i] = title.codeUnitAt(i);
      }

      // Artist: "Zen Master"
      final artist = 'Zen Master';
      for (var i = 0; i < artist.length; i++) {
        bytes[tagOffset + 33 + i] = artist.codeUnitAt(i);
      }

      // Album: "Serenity"
      final album = 'Serenity';
      for (var i = 0; i < album.length; i++) {
        bytes[tagOffset + 63 + i] = album.codeUnitAt(i);
      }

      await audioFile.writeAsBytes(bytes);

      final meta = await service.extractAudioMetadata(audioFile.path);
      expect(meta.title, 'Sunset Horizon');
      expect(meta.artist, 'Zen Master');
      expect(meta.album, 'Serenity');
      expect(meta.format, 'MP3');
      expect(meta.fileSize, 256);
    });
  });
}
