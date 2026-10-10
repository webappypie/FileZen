import 'dart:io';

import 'package:mime/mime.dart';

/// Which FileZen screen (or external hand-off) opens a file.
enum FileViewerKind {
  pdf,
  image,
  video,
  audio,

  /// XML / HTML structure viewer.
  markup,

  /// In-app archive browser (ZIP, TAR, GZ, TGZ).
  archive,

  /// DOC/DOCX/XLS/XLSX/PPT/PPTX: details screen + hand-off to an installed app
  /// (FileZen does not render Office documents itself).
  office,

  /// Plain text, Markdown, CSV, JSON, source code.
  text,

  /// No in-app viewer: hand off to an installed app.
  external,
}

/// Single place that decides how a file is opened.
///
/// Extension and MIME type are only hints: the first bytes of the file decide
/// when they identify a format (a PDF renamed to `.txt` opens as a PDF, a ZIP
/// named `.txt` opens as an archive), and anything that would land in the text
/// viewer but contains NUL bytes is handed off instead — binary data is never
/// shown as text.
class FileTypeResolver {
  const FileTypeResolver._();

  static const headerLength = 512;

  static const officeExtensions = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'};
  static const archiveExtensions = {'zip', 'tar', 'gz', 'tgz'};
  static const markupExtensions = {'xml', 'html', 'htm', 'xhtml'};
  static const textExtensions = {
    'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'yaml', 'yml', 'toml',
    'log', 'conf', 'ini', 'env', 'properties', 'dart', 'py', 'js', 'ts',
    'jsx', 'tsx', 'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'cs', 'sh', 'bat', 'ps1', 'sql',
    'css', 'scss', 'gradle', 'kts', 'swift', 'go', 'rs', 'rb', 'php',
  };
  static const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'};
  static const videoExtensions = {'mp4', 'mkv', 'webm', 'mov', 'avi', '3gp', 'm4v', 'ts'};
  static const audioExtensions = {'mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'opus', 'amr'};

  /// `.PDF`, `pdf`, ` .Pdf ` -> `pdf`.
  static String normalizeExtension(String ext) => ext.trim().toLowerCase().replaceAll('.', '');

  /// Resolves from an already-read [header] (first bytes; may be empty).
  static FileViewerKind resolve({
    required String extension,
    String? mimeType,
    List<int> header = const [],
  }) {
    final ext = normalizeExtension(extension);
    final mime = mimeType?.toLowerCase();

    final sniffed = _sniff(header, ext);
    if (sniffed != null) return sniffed;

    final byName = _byExtensionOrMime(ext, mime);
    if (byName == FileViewerKind.text && header.contains(0)) {
      return FileViewerKind.external;
    }
    // A typed binary format whose bytes do not match (corrupt/mislabelled) is
    // still sent to its viewer, which reports its own error; text is the only
    // viewer that would render garbage, guarded above.
    return byName;
  }

  /// Reads the first bytes of [path] and resolves.
  static Future<FileViewerKind> resolveFile(String path, {String? extension, String? mimeType}) async {
    final ext = extension ?? path.split('/').last.split('.').skip(1).lastOrNull ?? '';
    final mime = mimeType ?? lookupMimeType(path);
    var header = const <int>[];
    try {
      final raf = await File(path).open();
      try {
        header = await raf.read(headerLength);
      } finally {
        await raf.close();
      }
    } catch (_) {
      // Unreadable: decide by name; the viewer will surface the error.
    }
    return resolve(extension: ext, mimeType: mime, header: header);
  }

  static bool _startsWith(List<int> h, List<int> sig, [int offset = 0]) {
    if (h.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (h[offset + i] != sig[i]) return false;
    }
    return true;
  }

  static FileViewerKind? _sniff(List<int> h, String ext) {
    if (h.isEmpty) return null;
    if (_startsWith(h, const [0x25, 0x50, 0x44, 0x46])) return FileViewerKind.pdf; // %PDF
    if (_startsWith(h, const [0x89, 0x50, 0x4E, 0x47]) || // PNG
        _startsWith(h, const [0xFF, 0xD8, 0xFF]) || // JPEG
        _startsWith(h, const [0x47, 0x49, 0x46, 0x38]) || // GIF8
        (_startsWith(h, const [0x52, 0x49, 0x46, 0x46]) && _startsWith(h, const [0x57, 0x45, 0x42, 0x50], 8))) {
      return FileViewerKind.image;
    }
    if (_startsWith(h, const [0x50, 0x4B, 0x03, 0x04]) || _startsWith(h, const [0x50, 0x4B, 0x05, 0x06])) {
      // ZIP container: also DOCX/XLSX/PPTX, APK, JAR, EPUB, ODT ...
      if (officeExtensions.contains(ext)) return FileViewerKind.office;
      if (ext == 'zip' || textExtensions.contains(ext) || ext.isEmpty) return FileViewerKind.archive;
      return FileViewerKind.external;
    }
    if (_startsWith(h, const [0xD0, 0xCF, 0x11, 0xE0])) {
      // OLE compound file: legacy DOC/XLS/PPT (and MSG etc.)
      return officeExtensions.contains(ext) ? FileViewerKind.office : FileViewerKind.external;
    }
    if (_startsWith(h, const [0x1F, 0x8B])) return FileViewerKind.archive; // gzip
    if (_startsWith(h, const [0x66, 0x74, 0x79, 0x70], 4)) {
      // ISO-BMFF (MP4/MOV/M4A/3GP/HEIC)
      if (audioExtensions.contains(ext)) return FileViewerKind.audio;
      if (imageExtensions.contains(ext)) return FileViewerKind.image;
      return FileViewerKind.video;
    }
    if (_startsWith(h, const [0x49, 0x44, 0x33]) || // ID3 (MP3)
        _startsWith(h, const [0x66, 0x4C, 0x61, 0x43]) || // fLaC
        _startsWith(h, const [0x4F, 0x67, 0x67, 0x53])) {
      // OggS
      return FileViewerKind.audio;
    }
    return null;
  }

  static FileViewerKind _byExtensionOrMime(String ext, String? mime) {
    if (ext == 'pdf' || (mime?.contains('pdf') ?? false)) return FileViewerKind.pdf;
    // SVG is XML; Flutter's image decoders cannot render it.
    if (ext == 'svg' || mime == 'image/svg+xml') return FileViewerKind.markup;
    if (imageExtensions.contains(ext) || (mime?.startsWith('image/') ?? false)) return FileViewerKind.image;
    if (videoExtensions.contains(ext) || (mime?.startsWith('video/') ?? false)) return FileViewerKind.video;
    if (audioExtensions.contains(ext) || (mime?.startsWith('audio/') ?? false)) return FileViewerKind.audio;
    if (markupExtensions.contains(ext) ||
        mime == 'application/xml' ||
        mime == 'text/xml' ||
        mime == 'text/html' ||
        (mime?.endsWith('+xml') ?? false)) {
      return FileViewerKind.markup;
    }
    if (archiveExtensions.contains(ext)) return FileViewerKind.archive;
    if (officeExtensions.contains(ext)) return FileViewerKind.office;
    if (textExtensions.contains(ext) ||
        (mime?.startsWith('text/') ?? false) ||
        mime == 'application/json') {
      return FileViewerKind.text;
    }
    return FileViewerKind.external;
  }
}
