import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../core/widgets/permission_view.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/repositories/i_permission_service.dart';
import '../providers/storage_providers.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  bool _isGridView = false;

  @override
  Widget build(BuildContext context) {
    final permissionAsync = ref.watch(storagePermissionStateProvider);

    return Scaffold(
      body: permissionAsync.when(
        loading: () => const LoadingView(message: 'Checking storage permissions...'),
        error: (err, _) => ErrorView(
          message: 'Permission check failed',
          recoverySuggestion: err.toString(),
          onRetry: () => ref.read(storagePermissionStateProvider.notifier).refresh(),
        ),
        data: (status) {
          if (status != StoragePermissionStatus.granted) {
            return PermissionView(
              title: 'Storage Access Required',
              rationale:
                  'FileZen requires storage access to browse, search, and manage your local files.\nAll file operations remain 100% on your device.',
              buttonLabel: status == StoragePermissionStatus.permanentlyDenied
                  ? 'Open App Settings'
                  : 'Grant Storage Access',
              onGrant: () async {
                if (status == StoragePermissionStatus.permanentlyDenied) {
                  await ref.read(permissionServiceProvider).openAppSettings();
                } else {
                  await ref.read(storagePermissionStateProvider.notifier).requestPermission();
                }
              },
            );
          }

          return _buildStorageBrowser(context);
        },
      ),
    );
  }

  Widget _buildStorageBrowser(BuildContext context) {
    final locationsAsync = ref.watch(storageLocationsProvider);
    final currentPath = ref.watch(currentDirectoryPathProvider);

    return Column(
      children: [
        // Storage locations horizontal selector
        locationsAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text('Unable to read storage locations: $err'),
          ),
          data: (locations) {
            if (locations.isEmpty) return const SizedBox.shrink();

            return Container(
              height: 90,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                scrollDirection: Axis.horizontal,
                itemCount: locations.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final loc = locations[index];
                  final isSelected = currentPath == loc.path;

                  return SizedBox(
                    width: 175,
                    child: Card(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppSpacing.roundedMd,
                        side: BorderSide(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.lightBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: AppSpacing.roundedMd,
                        onTap: () {
                          ref.read(currentDirectoryPathProvider.notifier).state = loc.path;
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Icon(loc.icon, size: 20, color: AppColors.primary),
                                  const SizedBox(width: AppSpacing.xs),
                                  Expanded(
                                    child: Text(
                                      loc.name,
                                      style: AppTypography.labelSmall.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                '${Formatters.formatFileSize(loc.freeBytes)} free',
                                style: AppTypography.bodySmall.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),

        // Breadcrumb & View Mode Toggle Bar
        if (currentPath != null) _buildBreadcrumbsBar(context, currentPath),

        const Divider(height: 1),

        // Directory contents
        Expanded(
          child: currentPath == null
              ? const EmptyView(
                  icon: Icons.folder_open_rounded,
                  title: 'Select a Storage Location',
                  subtitle: 'Tap on a storage drive above to begin browsing files.',
                )
              : _buildDirectoryList(context, currentPath),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbsBar(BuildContext context, String currentPath) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            tooltip: 'Up one folder',
            onPressed: () {
              final parent = p.dirname(currentPath);
              if (parent != currentPath && parent.isNotEmpty) {
                ref.read(currentDirectoryPathProvider.notifier).state = parent;
              }
            },
          ),
          Expanded(
            child: Text(
              currentPath,
              style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 20),
            tooltip: _isGridView ? 'List View' : 'Grid View',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            tooltip: 'New Folder',
            onPressed: () => _showCreateFolderDialog(context, currentPath),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryList(BuildContext context, String path) {
    final dirAsync = ref.watch(directoryContentsProvider(path));

    return dirAsync.when(
      loading: () => const LoadingView(message: 'Loading folder contents...'),
      error: (err, _) => ErrorView(
        title: 'Unable to open folder',
        message: err.toString(),
        onRetry: () => ref.invalidate(directoryContentsProvider(path)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyView(
            icon: Icons.folder_open_outlined,
            title: 'Folder is Empty',
            subtitle: 'No files or subdirectories found in this location.',
            actionLabel: 'Create Folder',
            onAction: () => _showCreateFolderDialog(context, path),
          );
        }

        if (_isGridView) {
          return GridView.builder(
            padding: AppSpacing.screenPadding,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.9,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildGridItem(context, items[index]),
          );
        }

        return ListView.separated(
          padding: AppSpacing.screenPadding,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xxs),
          itemBuilder: (context, index) => _buildListItem(context, items[index]),
        );
      },
    );
  }

  Widget _buildListItem(BuildContext context, FileEntity entity) {
    final isDir = entity.isDirectory;

    return Card(
      child: ListTile(
        leading: Icon(
          isDir ? Icons.folder_rounded : entity.category.icon,
          color: isDir ? Colors.amber[700] : entity.category.color,
          size: 28,
        ),
        title: Text(
          entity.name,
          style: AppTypography.titleMedium.copyWith(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isDir ? 'Directory' : '${Formatters.formatFileSize(entity.size)} • ${Formatters.formatDate(entity.modifiedAt)}',
          style: AppTypography.bodySmall.copyWith(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          onSelected: (val) {
            if (val == 'details') _showDetailsDialog(context, entity);
            if (val == 'rename') _showRenameDialog(context, entity);
            if (val == 'delete') _showDeleteConfirmation(context, entity);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'details', child: Text('Properties')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
        onTap: () {
          if (isDir) {
            ref.read(currentDirectoryPathProvider.notifier).state = entity.path;
          } else {
            _showDetailsDialog(context, entity);
          }
        },
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, FileEntity entity) {
    final isDir = entity.isDirectory;

    return Card(
      child: InkWell(
        borderRadius: AppSpacing.roundedMd,
        onTap: () {
          if (isDir) {
            ref.read(currentDirectoryPathProvider.notifier).state = entity.path;
          } else {
            _showDetailsDialog(context, entity);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDir ? Icons.folder_rounded : entity.category.icon,
                color: isDir ? Colors.amber[700] : entity.category.color,
                size: 36,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                entity.name,
                style: AppTypography.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog(BuildContext context, String currentPath) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final repo = ref.read(storageRepositoryProvider);
                final res = await repo.createFolder(currentPath, name);
                if (ctx.mounted) Navigator.of(ctx).pop();
                ref.invalidate(directoryContentsProvider(currentPath));

                res.when(
                  success: (_) {},
                  failure: (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err.message)),
                      );
                    }
                  },
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, FileEntity entity) async {
    final controller = TextEditingController(text: entity.name);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != entity.name) {
                final repo = ref.read(storageRepositoryProvider);
                final res = await repo.rename(entity.path, newName);
                if (ctx.mounted) Navigator.of(ctx).pop();
                final parent = p.dirname(entity.path);
                ref.invalidate(directoryContentsProvider(parent));

                res.when(
                  success: (_) {},
                  failure: (err) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err.message)),
                      );
                    }
                  },
                );
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context, FileEntity entity) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to permanently delete:'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              entity.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Size: ${Formatters.formatFileSize(entity.size)}',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              final repo = ref.read(storageRepositoryProvider);
              final res = await repo.delete(entity.path);
              if (ctx.mounted) Navigator.of(ctx).pop();
              final parent = p.dirname(entity.path);
              ref.invalidate(directoryContentsProvider(parent));

              res.when(
                success: (_) {},
                failure: (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err.message)),
                    );
                  }
                },
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetailsDialog(BuildContext context, FileEntity entity) async {
    String? checksum;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(entity.name),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Path', entity.path),
                _detailRow('Size', Formatters.formatFileSize(entity.size)),
                _detailRow('Category', entity.category.displayName),
                _detailRow('Modified', Formatters.formatDate(entity.modifiedAt)),
                if (checksum != null)
                  _detailRow('MD5 Checksum', checksum!)
                else if (!entity.isDirectory) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.fingerprint_rounded, size: 18),
                    label: const Text('Compute MD5 Checksum'),
                    onPressed: () async {
                      final repo = ref.read(storageRepositoryProvider);
                      final sum = await repo.calculateChecksum(entity.path);
                      setDialogState(() => checksum = sum);
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          SelectableText(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
