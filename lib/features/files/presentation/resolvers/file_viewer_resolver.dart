import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../domain/models/audio_playback_models.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../documents/presentation/screens/archive_viewer_screen.dart';
import '../../../documents/presentation/screens/document_viewer_screen.dart';
import '../../../documents/presentation/screens/office_document_screen.dart';
import '../../../documents/presentation/screens/pdf_viewer_screen.dart';
import '../../../documents/presentation/screens/xml_viewer_screen.dart';
import '../../../media/presentation/providers/media_providers.dart';
import '../../../media/presentation/screens/audio_player_screen.dart';
import '../../../media/presentation/screens/image_viewer_screen.dart';
import '../../../media/presentation/screens/video_player_screen.dart';

/// Centralized file-type, extension, and MIME resolver for opening files
/// with the appropriate native FileZen viewer or secure external handoff.
class FileViewerResolver {
  const FileViewerResolver._();

  static const _officeExtensions = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'};
  // Formats the in-app archive viewer can actually decode; other archives (7z,
  // rar, bz2, ...) fall through to the external-app handoff.
  static const _archiveExtensions = {'zip', 'tar', 'gz', 'tgz'};
  static const _xmlExtensions = {'xml', 'html', 'htm', 'xhtml'};
  static const _textExtensions = {
    'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'yaml', 'yml', 'toml',
    'log', 'conf', 'ini', 'env', 'properties', 'dart', 'py', 'js', 'ts',
    'jsx', 'tsx', 'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'cs', 'sh', 'bat', 'ps1', 'sql'
  };

  /// Dispatches the file to the appropriate viewer.
  static Future<void> openFile(
    BuildContext context,
    WidgetRef ref,
    FileEntity file, [
    List<FileEntity>? allFiles,
  ]) async {
    final cleanExt = file.extension.toLowerCase().replaceAll('.', '').trim();

    // 1. PDF Documents
    if (cleanExt == 'pdf' || (file.mimeType?.contains('pdf') ?? false)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(filePath: file.path),
        ),
      );
      return;
    }

    // 2. Images (with gallery paging if allFiles provided)
    if (file.category == FileCategory.image || (file.mimeType?.startsWith('image/') ?? false)) {
      final images = (allFiles ?? [file])
          .where((f) => f.category == FileCategory.image || (f.mimeType?.startsWith('image/') ?? false))
          .map((f) => f.path)
          .toList();
      final index = images.indexOf(file.path);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewerScreen(
            imagePaths: images.isNotEmpty ? images : [file.path],
            initialIndex: index >= 0 ? index : 0,
          ),
        ),
      );
      return;
    }

    // 3. Videos (with playlist paging if allFiles provided)
    if (file.category == FileCategory.video || (file.mimeType?.startsWith('video/') ?? false)) {
      final videos = (allFiles ?? [file])
          .where((f) => f.category == FileCategory.video || (f.mimeType?.startsWith('video/') ?? false))
          .map((f) => f.path)
          .toList();
      final index = videos.indexOf(file.path);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            videoPaths: videos.isNotEmpty ? videos : [file.path],
            initialIndex: index >= 0 ? index : 0,
          ),
        ),
      );
      return;
    }

    // 4. Audio
    if (file.category == FileCategory.audio || (file.mimeType?.startsWith('audio/') ?? false)) {
      final audioFiles = (allFiles ?? [file])
          .where((f) => f.category == FileCategory.audio || (f.mimeType?.startsWith('audio/') ?? false))
          .toList();
      final tracks = (audioFiles.isNotEmpty ? audioFiles : [file]).map((f) {
        return AudioTrack(
          id: f.path,
          path: f.path,
          title: f.name,
        );
      }).toList();
      final index = tracks.indexWhere((t) => t.path == file.path);
      final player = ref.read(audioPlayerServiceProvider);
      player.setQueue(tracks, initialIndex: index >= 0 ? index : 0, autoPlay: true);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AudioPlayerScreen(),
        ),
      );
      return;
    }

    // 5. XML / HTML Structured Markup
    if (_xmlExtensions.contains(cleanExt) ||
        (file.mimeType?.contains('xml') ?? false) ||
        (file.mimeType?.contains('html') ?? false)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => XmlViewerScreen(filePath: file.path),
        ),
      );
      return;
    }

    // 6. Archives the in-app viewer supports (ZIP, TAR, GZ, TGZ)
    if (_archiveExtensions.contains(cleanExt)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArchiveViewerScreen(filePath: file.path),
        ),
      );
      return;
    }

    // 7. Microsoft Office Formats (DOC, DOCX, XLS, XLSX, PPT, PPTX)
    if (_officeExtensions.contains(cleanExt)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfficeDocumentScreen(file: file),
        ),
      );
      return;
    }

    // 8. Markdown, Plain Text, Code, CSV, JSON
    if (_textExtensions.contains(cleanExt) ||
        file.category == FileCategory.document ||
        (file.mimeType?.startsWith('text/') ?? false)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DocumentViewerScreen(filePath: file.path),
        ),
      );
      return;
    }

    // 9. Fallback External App Handoff via OpenFile
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type == ResultType.noAppToOpen && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No installed app can open ${file.name}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${file.name}: $e')),
        );
      }
    }
  }
}
