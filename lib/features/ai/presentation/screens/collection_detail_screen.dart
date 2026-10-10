import '../../../files/presentation/resolvers/file_viewer_resolver.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/ai_models.dart';
import '../../../../domain/models/file_entity.dart';
import '../providers/ai_providers.dart';
import '../widgets/related_files_sheet.dart';

/// Screen displaying the files belonging to a virtual Smart Collection.
class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collection,
  });

  final SmartCollection collection;

  void _openFile(BuildContext context, WidgetRef ref, FileEntity entity, List<FileEntity> all) {
    FileViewerResolver.openFile(context, ref, entity, all);
  }

  void _showRelatedFiles(BuildContext context, FileEntity file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => RelatedFilesSheet(targetFile: file),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(collectionFilesProvider(collection.id));
    final colColor = Color(collection.colorHex);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              collection.icon,
              color: colColor,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(collection.title, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
      body: filesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading collection: $err')),
        data: (files) {
          if (files.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    collection.icon,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No files found for "${collection.title}"',
                    style: AppTypography.titleMedium.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      collection.description,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            );
          }

          final totalBytes = files.fold<int>(0, (acc, f) => acc + f.size);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: colColor.withValues(alpha: 0.08),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${files.length} items',
                      style: TextStyle(fontWeight: FontWeight.bold, color: colColor, fontSize: 13),
                    ),
                    Text(
                      Formatters.formatFileSize(totalBytes),
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                  itemBuilder: (context, index) {
                    final file = files[index];

                    return ListTile(
                      onTap: () => _openFile(context, ref, file, files),
                      leading: FileThumbnailWidget(file: file, size: 40),
                      title: Text(
                        file.name,
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${Formatters.formatFileSize(file.size)}  •  ${Formatters.formatDate(file.modifiedAt)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.hub_outlined, size: 20),
                        tooltip: 'Related Files',
                        onPressed: () => _showRelatedFiles(context, file),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
