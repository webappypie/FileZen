import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/audio_playback_models.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../documents/presentation/screens/document_viewer_screen.dart';
import '../../../documents/presentation/screens/pdf_viewer_screen.dart';
import '../../../media/presentation/providers/media_providers.dart';
import '../../../media/presentation/screens/audio_player_screen.dart';
import '../../../media/presentation/screens/image_viewer_screen.dart';
import '../../../media/presentation/screens/video_player_screen.dart';
import '../providers/ai_providers.dart';

/// Modal bottom sheet presenting related files and companion assets for a target file.
class RelatedFilesSheet extends ConsumerWidget {
  const RelatedFilesSheet({
    super.key,
    required this.targetFile,
  });

  final FileEntity targetFile;

  void _openFile(BuildContext context, WidgetRef ref, FileEntity entity) {
    Navigator.of(context).pop();
    final ext = entity.extension.toLowerCase();

    if (ext == '.pdf') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: entity.path)),
      );
      return;
    }

    switch (entity.category) {
      case FileCategory.image:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ImageViewerScreen(imagePaths: [entity.path])),
        );
        break;
      case FileCategory.video:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoPaths: [entity.path])),
        );
        break;
      case FileCategory.audio:
        final audioService = ref.read(audioPlayerServiceProvider);
        audioService.setQueue(
          [
            AudioTrack(
              id: entity.path,
              path: entity.path,
              title: entity.name,
              artist: p.dirname(entity.path),
            ),
          ],
          autoPlay: true,
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AudioPlayerScreen()),
        );
        break;
      case FileCategory.document:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DocumentViewerScreen(filePath: entity.path)),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening ${entity.name}')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relatedAsync = ref.watch(relatedFilesProvider(targetFile));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.hub_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Related to ${targetFile.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          relatedAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Center(
              child: Text('Error finding related files: $err', style: const TextStyle(color: Colors.white70)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No related files found', style: TextStyle(color: Colors.white54)),
                  ),
                );
              }

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final file = item.file;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () => _openFile(context, ref, file),
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: file.category.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(file.category.icon, color: file.category.color, size: 20),
                      ),
                      title: Text(
                        file.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.relationship,
                              style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            Formatters.formatFileSize(file.size),
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
