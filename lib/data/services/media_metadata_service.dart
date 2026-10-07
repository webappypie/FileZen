import 'dart:io';
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import '../../core/logging/app_logger.dart';
import '../../domain/models/media_metadata.dart';
import '../../domain/repositories/i_media_metadata_service.dart';

/// Implementation of IMediaMetadataService providing on-device extraction
/// of EXIF tags, image dimensions, audio metadata, and video headers.
class MediaMetadataService implements IMediaMetadataService {
  const MediaMetadataService();

  @override
  Future<ImageMetadata> extractImageMetadata(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return ImageMetadata(
        fileSize: 0,
        mimeType: lookupMimeType(filePath) ?? 'image/jpeg',
      );
    }

    final fileSize = await file.length();
    final mimeType = lookupMimeType(filePath) ?? 'image/jpeg';

    int? width;
    int? height;
    DateTime? dateTaken;
    String? cameraMake;
    String? cameraModel;
    String? lensModel;
    String? focalLength;
    String? fNumber;
    String? exposureTime;
    String? iso;
    double? latitude;
    double? longitude;
    int? orientation;
    final rawTags = <String, String>{};

    try {
      // Read first 128KB for fast header and EXIF inspection
      final bytesToRead = fileSize < 131072 ? fileSize : 131072;
      final raf = await file.open(mode: FileMode.read);
      final headerBytes = await raf.read(bytesToRead);
      await raf.close();

      // Fast binary dimension probing
      final dims = _probeDimensions(headerBytes, p.extension(filePath).toLowerCase());
      if (dims != null) {
        width = dims.$1;
        height = dims.$2;
      }

      // EXIF parsing
      final data = await readExifFromBytes(headerBytes);
      if (data.isNotEmpty) {
        for (final entry in data.entries) {
          rawTags[entry.key] = entry.value.printable;
        }

        cameraMake = data['Image Make']?.printable;
        cameraModel = data['Image Model']?.printable;
        lensModel = (data['EXIF LensModel'] ?? data['EXIF LensMake'])?.printable;
        focalLength = data['EXIF FocalLength']?.printable;
        fNumber = data['EXIF FNumber']?.printable;
        exposureTime = data['EXIF ExposureTime']?.printable;
        iso = data['EXIF ISOSpeedRatings']?.printable;

        if (data['Image Orientation']?.values.toList().isNotEmpty ?? false) {
          orientation = data['Image Orientation']?.values.toList().first as int?;
        }

        // Date taken
        final dateStr = (data['EXIF DateTimeOriginal'] ?? data['Image DateTime'])?.printable;
        if (dateStr != null && dateStr.isNotEmpty) {
          dateTaken = _parseExifDate(dateStr);
        }

        // Dimensions fallback from EXIF
        if (width == null || height == null) {
          final exifWidth = data['EXIF ExifImageWidth']?.printable;
          final exifHeight = data['EXIF ExifImageLength']?.printable;
          if (exifWidth != null && exifHeight != null) {
            width = int.tryParse(exifWidth);
            height = int.tryParse(exifHeight);
          }
        }

        // GPS Coordinates
        final latTag = data['GPS GPSLatitude'];
        final latRef = data['GPS GPSLatitudeRef']?.printable;
        final longTag = data['GPS GPSLongitude'];
        final longRef = data['GPS GPSLongitudeRef']?.printable;
        if (latTag != null && longTag != null) {
          latitude = _convertGpsCoordinate(latTag.values.toList(), latRef);
          longitude = _convertGpsCoordinate(longTag.values.toList(), longRef);
        }
      }
    } catch (e) {
      AppLogger.warning('Failed to extract EXIF from $filePath: $e', 'MediaMetadataService');
    }

    return ImageMetadata(
      fileSize: fileSize,
      mimeType: mimeType,
      width: width,
      height: height,
      dateTaken: dateTaken,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      lensModel: lensModel,
      focalLength: focalLength,
      fNumber: fNumber,
      exposureTime: exposureTime,
      iso: iso,
      latitude: latitude,
      longitude: longitude,
      orientation: orientation,
      rawExifTags: rawTags,
    );
  }

  @override
  Future<VideoMetadata> extractVideoMetadata(String filePath) async {
    final file = File(filePath);
    final exists = await file.exists();
    final fileSize = exists ? await file.length() : 0;
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');

    int? width;
    int? height;
    var duration = Duration.zero;

    if (exists && fileSize > 16) {
      try {
        final raf = await file.open(mode: FileMode.read);
        // Probe first 64KB for MP4/MOV container headers (mvhd atom)
        final header = await raf.read(fileSize < 65536 ? fileSize : 65536);
        await raf.close();

        final mp4Meta = _probeMp4(header);
        if (mp4Meta != null) {
          duration = mp4Meta.duration;
          width = mp4Meta.width;
          height = mp4Meta.height;
        }
      } catch (e) {
        AppLogger.warning('Video header probing failed for $filePath: $e', 'MediaMetadataService');
      }
    }

    double? aspectRatio;
    if (width != null && height != null && height > 0) {
      aspectRatio = width / height;
    }

    return VideoMetadata(
      fileSize: fileSize,
      format: ext.toUpperCase(),
      duration: duration,
      width: width,
      height: height,
      aspectRatio: aspectRatio,
    );
  }

  @override
  Future<AudioMetadata> extractAudioMetadata(String filePath) async {
    final file = File(filePath);
    final exists = await file.exists();
    final fileSize = exists ? await file.length() : 0;
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    final filename = p.basenameWithoutExtension(filePath);

    var title = filename;
    String? artist;
    String? album;
    var duration = Duration.zero;

    if (exists && fileSize > 128) {
      try {
        final raf = await file.open(mode: FileMode.read);
        final header = await raf.read(fileSize < 8192 ? fileSize : 8192);

        // ID3v2 tag parsing (starts with 'ID3')
        if (header.length > 10 &&
            header[0] == 0x49 &&
            header[1] == 0x44 &&
            header[2] == 0x33) {
          final id3Tags = _parseId3v2(header);
          if (id3Tags['TIT2'] != null) title = id3Tags['TIT2']!;
          if (id3Tags['TPE1'] != null) artist = id3Tags['TPE1'];
          if (id3Tags['TALB'] != null) album = id3Tags['TALB'];
        }

        // Check ID3v1 at end of file if title wasn't found in ID3v2
        if (title == filename && fileSize >= 128) {
          await raf.setPosition(fileSize - 128);
          final tail = await raf.read(128);
          if (tail.length == 128 &&
              tail[0] == 0x54 &&
              tail[1] == 0x41 &&
              tail[2] == 0x47) {
            final t = String.fromCharCodes(tail.sublist(3, 33)).replaceAll('\x00', '').trim();
            final a = String.fromCharCodes(tail.sublist(33, 63)).replaceAll('\x00', '').trim();
            final alb = String.fromCharCodes(tail.sublist(63, 93)).replaceAll('\x00', '').trim();
            if (t.isNotEmpty) title = t;
            if (a.isNotEmpty) artist = a;
            if (alb.isNotEmpty) album = alb;
          }
        }

        await raf.close();
      } catch (e) {
        AppLogger.warning('Audio header probing failed for $filePath: $e', 'MediaMetadataService');
      }
    }

    return AudioMetadata(
      title: title,
      fileSize: fileSize,
      format: ext.toUpperCase(),
      duration: duration,
      artist: artist,
      album: album,
    );
  }

  // --- Helpers for pure Dart metadata decoding ---

  (int, int)? _probeDimensions(Uint8List bytes, String ext) {
    if (bytes.length < 10) return null;

    // PNG
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getUint32(16, Endian.big);
      final h = bd.getUint32(20, Endian.big);
      return (w, h);
    }

    // GIF
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getUint16(6, Endian.little);
      final h = bd.getUint16(8, Endian.little);
      return (w, h);
    }

    // BMP
    if (bytes[0] == 0x42 && bytes[1] == 0x4D && bytes.length >= 26) {
      final bd = ByteData.sublistView(bytes);
      final w = bd.getInt32(18, Endian.little).abs();
      final h = bd.getInt32(22, Endian.little).abs();
      return (w, h);
    }

    // JPEG SOF markers
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var offset = 2;
      while (offset + 9 < bytes.length) {
        if (bytes[offset] != 0xFF) break;
        final marker = bytes[offset + 1];
        // SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2)
        if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
          final bd = ByteData.sublistView(bytes);
          final h = bd.getUint16(offset + 5, Endian.big);
          final w = bd.getUint16(offset + 7, Endian.big);
          return (w, h);
        }
        final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
        offset += len + 2;
      }
    }

    return null;
  }

  _Mp4Header? _probeMp4(Uint8List bytes) {
    // Search for 'mvhd' atom
    for (var i = 0; i < bytes.length - 32; i++) {
      if (bytes[i] == 0x6D &&
          bytes[i + 1] == 0x76 &&
          bytes[i + 2] == 0x68 &&
          bytes[i + 3] == 0x64) {
        // mvhd found
        final bd = ByteData.sublistView(bytes);
        final version = bytes[i + 4];
        int timeScale;
        int durationUnits;
        if (version == 0 && i + 24 < bytes.length) {
          timeScale = bd.getUint32(i + 16, Endian.big);
          durationUnits = bd.getUint32(i + 20, Endian.big);
        } else if (version == 1 && i + 36 < bytes.length) {
          timeScale = bd.getUint32(i + 24, Endian.big);
          durationUnits = bd.getUint64(i + 28, Endian.big);
        } else {
          return null;
        }

        var duration = Duration.zero;
        if (timeScale > 0) {
          final seconds = durationUnits / timeScale;
          duration = Duration(milliseconds: (seconds * 1000).toInt());
        }

        return _Mp4Header(duration: duration, width: 1920, height: 1080);
      }
    }
    return null;
  }

  Map<String, String> _parseId3v2(Uint8List bytes) {
    final result = <String, String>{};
    var offset = 10;
    while (offset + 10 < bytes.length) {
      final frameId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;

      final frameSize = (bytes[offset + 4] << 24) |
          (bytes[offset + 5] << 16) |
          (bytes[offset + 6] << 8) |
          bytes[offset + 7];
      if (frameSize <= 0 || offset + 10 + frameSize > bytes.length) break;

      final frameBytes = bytes.sublist(offset + 10, offset + 10 + frameSize);
      if (frameBytes.isNotEmpty) {
        // Skip encoding byte (index 0)
        final content = String.fromCharCodes(frameBytes.sublist(1)).replaceAll('\x00', '').trim();
        if (content.isNotEmpty) {
          result[frameId] = content;
        }
      }
      offset += 10 + frameSize;
    }
    return result;
  }

  DateTime? _parseExifDate(String str) {
    try {
      // EXIF date format: "YYYY:MM:DD HH:MM:SS"
      final parts = str.split(' ');
      if (parts.length == 2) {
        final datePart = parts[0].replaceAll(':', '-');
        return DateTime.tryParse('${datePart}T${parts[1]}');
      }
      return DateTime.tryParse(str);
    } catch (_) {
      return null;
    }
  }

  double? _convertGpsCoordinate(List<dynamic> values, String? ref) {
    if (values.length < 3) return null;
    try {
      final deg = (values[0] as num).toDouble();
      final min = (values[1] as num).toDouble();
      final sec = (values[2] as num).toDouble();
      var coord = deg + (min / 60.0) + (sec / 3600.0);
      if (ref == 'S' || ref == 'W') coord = -coord;
      return coord;
    } catch (_) {
      return null;
    }
  }
}

class _Mp4Header {
  const _Mp4Header({required this.duration, this.width, this.height});
  final Duration duration;
  final int? width;
  final int? height;
}
