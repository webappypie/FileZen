import '../../../files/presentation/resolvers/file_viewer_resolver.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/file_entity.dart';
import '../providers/ai_providers.dart';

/// Modal bottom sheet presenting related files and companion assets for a target file.
class RelatedFilesSheet extends ConsumerWidget {
  const RelatedFilesSheet({
    super.key,
    required this.targetFile,
  });

  final FileEntity targetFile;

  void _openFile(BuildContext context, WidgetRef ref, FileEntity entity) {
    // The navigator's context outlives this sheet, which closes first.
    final hostContext = Navigator.of(context).context;
    Navigator.of(context).pop();
    FileViewerResolver.openFile(hostContext, ref, entity);
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
                      leading: FileThumbnailWidget(file: file, size: 36),
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
