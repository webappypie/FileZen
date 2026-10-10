import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../domain/models/audio_playback_models.dart';
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
import 'file_type_resolver.dart';

/// Centralized file-type, extension, and MIME resolver for opening files
/// with the appropriate native FileZen viewer or secure external handoff.
class FileViewerResolver {
  const FileViewerResolver._();

  static bool _isKind(FileEntity f, FileViewerKind kind) =>
      FileTypeResolver.resolve(extension: f.extension, mimeType: f.mimeType) == kind;

  /// Dispatches the file to the appropriate viewer. Every screen that opens a
  /// file goes through here; the type decision is [FileTypeResolver]'s.
  static Future<void> openFile(
    BuildContext context,
    WidgetRef ref,
    FileEntity file, [
    List<FileEntity>? allFiles,
  ]) async {
    final kind = await FileTypeResolver.resolveFile(
      file.path,
      extension: file.extension,
      mimeType: file.mimeType,
    );
    if (!context.mounted) return;

    switch (kind) {
      case FileViewerKind.pdf:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PdfViewerScreen(filePath: file.path)),
        );
      case FileViewerKind.image:
        // Gallery paging over the other images of the same list.
        final images = (allFiles ?? [file])
            .where((f) => f.path == file.path || _isKind(f, FileViewerKind.image))
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
      case FileViewerKind.video:
        final videos = (allFiles ?? [file])
            .where((f) => f.path == file.path || _isKind(f, FileViewerKind.video))
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
      case FileViewerKind.audio:
        final audioFiles = (allFiles ?? [file])
            .where((f) => f.path == file.path || _isKind(f, FileViewerKind.audio))
            .toList();
        final tracks = (audioFiles.isNotEmpty ? audioFiles : [file])
            .map((f) => AudioTrack(id: f.path, path: f.path, title: f.name))
            .toList();
        final index = tracks.indexWhere((t) => t.path == file.path);
        final player = ref.read(audioPlayerServiceProvider);
        player.setQueue(tracks, initialIndex: index >= 0 ? index : 0, autoPlay: true);
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AudioPlayerScreen()),
        );
      case FileViewerKind.markup:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => XmlViewerScreen(filePath: file.path)),
        );
      case FileViewerKind.archive:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ArchiveViewerScreen(filePath: file.path)),
        );
      case FileViewerKind.office:
        // Details + hand-off; FileZen does not render Office formats itself.
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => OfficeDocumentScreen(file: file)),
        );
      case FileViewerKind.text:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => DocumentViewerScreen(filePath: file.path)),
        );
      case FileViewerKind.external:
        await _openExternally(context, file);
    }
  }

  static Future<void> _openExternally(BuildContext context, FileEntity file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (!context.mounted) return;
      if (result.type == ResultType.noAppToOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No installed app can open ${file.name}')),
        );
      } else if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${file.name}: ${result.message}')),
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
