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
import '../../../../domain/models/file_clipboard.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/models/file_operation_models.dart';
import '../../../../domain/models/file_sort_criteria.dart';
import '../../../../domain/repositories/i_permission_service.dart';
import '../../../documents/presentation/screens/pdf_studio_screen.dart';
import '../../../media/presentation/widgets/mini_audio_player_bar.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../../ai/presentation/providers/ai_providers.dart';
import '../../../ai/presentation/widgets/related_files_sheet.dart';
import '../../../transfer/presentation/providers/network_providers.dart';
import '../../../transfer/presentation/screens/network_hub_screen.dart';
import '../../../vault/presentation/services/vault_action_coordinator.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import '../resolvers/file_viewer_resolver.dart';
import '../services/file_deletion.dart';
import '../providers/file_management_providers.dart';
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
    final selectedPaths = ref.watch(selectedFilePathsProvider);

    return Scaffold(
      appBar: selectedPaths.isNotEmpty ? _buildSelectionAppBar(context, selectedPaths) : null,
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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniAudioPlayerBar(),
          if (_buildClipboardBar(context) != null) _buildClipboardBar(context)!,
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(BuildContext context, Set<String> selectedPaths) {
    final currentPath = ref.watch(currentDirectoryPathProvider);
    final contents = currentPath != null
        ? ref.watch(sortedDirectoryContentsProvider(currentPath)).valueOrNull ?? []
        : <FileEntity>[];

    final selectedFiles = contents.where((f) => selectedPaths.contains(f.path)).toList();
    final totalBytes = selectedFiles.fold<int>(0, (acc, f) => acc + f.size);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close selection',
        onPressed: () => ref.read(selectedFilePathsProvider.notifier).clear(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${selectedPaths.length} selected'),
          if (totalBytes > 0)
            Text(
              Formatters.formatFileSize(totalBytes),
              style: AppTypography.bodySmall.copyWith(fontSize: 11),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all_rounded),
          tooltip: 'Select all',
          onPressed: () {
            ref.read(selectedFilePathsProvider.notifier).selectAll(contents.map((f) => f.path));
          },
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded),
          tooltip: 'Copy',
          onPressed: () {
            ref.read(fileClipboardProvider.notifier).state = FileClipboard(
              mode: ClipboardMode.copy,
              items: selectedFiles,
            );
            ref.read(selectedFilePathsProvider.notifier).clear();
            _showSnackBar(context, '${selectedFiles.length} items copied to clipboard');
          },
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_move_outlined),
          tooltip: 'Move (Cut)',
          onPressed: () {
            ref.read(fileClipboardProvider.notifier).state = FileClipboard(
              mode: ClipboardMode.cut,
              items: selectedFiles,
            );
            ref.read(selectedFilePathsProvider.notifier).clear();
            _showSnackBar(context, '${selectedFiles.length} items cut to clipboard');
          },
        ),
        IconButton(
          icon: const Icon(Icons.archive_outlined),
          tooltip: 'Compress (ZIP)',
          onPressed: () => _showZipDialog(context, selectedFiles),
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_rename_outline_rounded),
          tooltip: 'Batch Rename',
          onPressed: () => _showBatchRenameDialog(context, selectedFiles),
        ),
        IconButton(
          icon: const Icon(Icons.wifi_tethering_rounded),
          tooltip: 'Share via Wi-Fi Web Share',
          onPressed: () {
            ref
                .read(networkTransferControllerProvider.notifier)
                .setSharedFiles(selectedFiles.map((f) => f.path).toList());
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NetworkHubScreen(initialTabIndex: 0),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.lock_outline_rounded),
          tooltip: 'Move to Vault',
          onPressed: () async {
            final nonDirs = selectedFiles.where((f) => !f.isDirectory).toList();
            if (nonDirs.isEmpty) {
              _showSnackBar(context, 'Cannot move folders to Vault');
              return;
            }
            final parentDirs = nonDirs.map((f) => p.dirname(f.path)).toSet();
            await VaultActionCoordinator.moveMultipleToVault(
              context,
              ref,
              nonDirs,
              // Refresh the listing so moved files disappear immediately.
              onSuccess: () {
                for (final dir in parentDirs) {
                  ref.invalidate(directoryContentsProvider(dir));
                }
              },
            );
            ref.read(selectedFilePathsProvider.notifier).clear();
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          tooltip: 'Delete',
          onPressed: () => _showBatchDeleteDialog(context, selectedFiles),
        ),
      ],
    );
  }

  Widget? _buildClipboardBar(BuildContext context) {
    final clipboard = ref.watch(fileClipboardProvider);
    final currentPath = ref.watch(currentDirectoryPathProvider);

    if (clipboard == null || currentPath == null) return null;

    final isCut = clipboard.mode == ClipboardMode.cut;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: AppColors.lightBorder.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Icon(isCut ? Icons.drive_file_move_rounded : Icons.copy_rounded, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${clipboard.count} items (${isCut ? 'Move' : 'Copy'})\n${Formatters.formatFileSize(clipboard.totalBytes)}',
                style: AppTypography.bodySmall.copyWith(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(fileClipboardProvider.notifier).state = null,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton.icon(
              icon: const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text('Paste Here'),
              onPressed: () => _executePaste(context, clipboard, currentPath),
            ),
          ],
        ),
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
                          ref.read(selectedFilePathsProvider.notifier).clear();
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
                                loc.totalBytes > 0
                                    ? '${Formatters.formatFileSize(loc.freeBytes)} free'
                                    : 'Tap to browse',
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
    final showHidden = ref.watch(showHiddenFilesProvider);

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
                ref.read(selectedFilePathsProvider.notifier).clear();
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
            icon: const Icon(Icons.sort_rounded, size: 20),
            tooltip: 'Sort files',
            onPressed: () => _showSortModal(context),
          ),
          IconButton(
            icon: Icon(
              showHidden ? Icons.visibility_rounded : Icons.visibility_off_outlined,
              size: 20,
              color: showHidden ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: showHidden ? 'Hide hidden files' : 'Show hidden files',
            onPressed: () {
              ref.read(showHiddenFilesProvider.notifier).state = !showHidden;
            },
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 20),
            tooltip: _isGridView ? 'List View' : 'Grid View',
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
            tooltip: 'PDF Studio',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const PdfStudioScreen(),
                ),
              );
            },
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
    final contentsAsync = ref.watch(sortedDirectoryContentsProvider(path));
    final selectedPaths = ref.watch(selectedFilePathsProvider);

    return contentsAsync.when(
      loading: () => const LoadingView(message: 'Loading directory...'),
      error: (err, _) => ErrorView(
        message: 'Could not open folder',
        recoverySuggestion: err.toString(),
        onRetry: () => ref.invalidate(directoryContentsProvider(path)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyView(
            icon: Icons.folder_open_outlined,
            title: 'Folder is empty',
            subtitle: 'No files found in this location.',
            actionLabel: 'New Folder',
            onAction: () => _showCreateFolderDialog(context, path),
          );
        }

        if (_isGridView) {
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.85,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = selectedPaths.contains(item.path);
              return _buildGridItem(context, item, isSelected, items);
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            final item = items[index];
            final isSelected = selectedPaths.contains(item.path);
            return _buildListItem(context, item, isSelected, items);
          },
        );
      },
    );
  }

  Widget _buildListItem(BuildContext context, FileEntity file, bool isSelected, List<FileEntity> allItems) {
    final isSelectionMode = ref.watch(selectedFilePathsProvider).isNotEmpty;

    return ListTile(
      selected: isSelected,
      leading: isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => ref.read(selectedFilePathsProvider.notifier).toggle(file.path),
            )
          : FileThumbnailWidget(file: file, size: 40),
      title: Text(
        file.name,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        file.isDirectory
            ? Formatters.formatDate(file.modifiedAt)
            : '${Formatters.formatFileSize(file.size)}  •  ${Formatters.formatDate(file.modifiedAt)}',
        style: AppTypography.bodySmall.copyWith(fontSize: 11),
      ),
      trailing: isSelectionMode
          ? null
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (action) => _handleFileAction(context, file, action, allItems),
              itemBuilder: (ctx) => [
                if (!file.isDirectory)
                  const PopupMenuItem(value: 'open_media', child: Text('Open')),
                if (!file.isDirectory)
                  const PopupMenuItem(
                    value: 'vault',
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Move to Vault'),
                      ],
                    ),
                  ),
                const PopupMenuItem(value: 'details', child: Text('Properties')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                if (!file.isDirectory)
                  const PopupMenuItem(value: 'ai_rename', child: Text('AI Auto-Rename')),
                if (!file.isDirectory)
                  const PopupMenuItem(value: 'related', child: Text('Related Files')),
                const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                const PopupMenuItem(value: 'cut', child: Text('Move (Cut)')),
                if (file.extension.toLowerCase() == '.zip')
                  const PopupMenuItem(value: 'extract', child: Text('Extract Archive')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
      onTap: () {
        if (isSelectionMode) {
          ref.read(selectedFilePathsProvider.notifier).toggle(file.path);
        } else if (file.isDirectory) {
          ref.read(currentDirectoryPathProvider.notifier).state = file.path;
        } else {
          _handleFileTap(context, file, allItems);
        }
      },
      onLongPress: () {
        ref.read(selectedFilePathsProvider.notifier).toggle(file.path);
      },
    );
  }

  Widget _buildGridItem(BuildContext context, FileEntity file, bool isSelected, List<FileEntity> allItems) {
    final isSelectionMode = ref.watch(selectedFilePathsProvider).isNotEmpty;

    return Card(
      elevation: 0,
      color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : null,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.roundedMd,
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : AppColors.lightBorder.withValues(alpha: 0.5),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: AppSpacing.roundedMd,
        onTap: () {
          if (isSelectionMode) {
            ref.read(selectedFilePathsProvider.notifier).toggle(file.path);
          } else if (file.isDirectory) {
            ref.read(currentDirectoryPathProvider.notifier).state = file.path;
          } else {
            _handleFileTap(context, file, allItems);
          }
        },
        onLongPress: () {
          ref.read(selectedFilePathsProvider.notifier).toggle(file.path);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FileThumbnailWidget(file: file, size: 48),
              const SizedBox(height: AppSpacing.xs),
              Text(
                file.name,
                style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                file.isDirectory ? 'Folder' : Formatters.formatFileSize(file.size),
                style: AppTypography.bodySmall.copyWith(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleFileTap(BuildContext context, FileEntity file, List<FileEntity> allFiles) {
    FileViewerResolver.openFile(context, ref, file, allFiles);
  }

  void _handleFileAction(BuildContext context, FileEntity file, String action, [List<FileEntity>? allItems]) {
    switch (action) {
      case 'open_media':
        _handleFileTap(context, file, allItems ?? [file]);
        break;
      case 'vault':
        VaultActionCoordinator.moveFileToVault(
          context,
          ref,
          file,
          onSuccess: () => ref.invalidate(directoryContentsProvider(p.dirname(file.path))),
        );
        break;
      case 'details':
        _showPropertiesDialog(context, file);
        break;
      case 'rename':
        _showRenameDialog(context, file);
        break;
      case 'ai_rename':
        _showAiRenameDialog(context, file);
        break;
      case 'related':
        _showRelatedFiles(context, file);
        break;
      case 'duplicate':
        _executeDuplicate(context, file);
        break;
      case 'copy':
        ref.read(fileClipboardProvider.notifier).state = FileClipboard(
          mode: ClipboardMode.copy,
          items: [file],
        );
        _showSnackBar(context, 'Copied "${file.name}" to clipboard');
        break;
      case 'cut':
        ref.read(fileClipboardProvider.notifier).state = FileClipboard(
          mode: ClipboardMode.cut,
          items: [file],
        );
        _showSnackBar(context, 'Cut "${file.name}" to clipboard');
        break;
      case 'extract':
        _showExtractDialog(context, file);
        break;
      case 'delete':
        _showDeleteConfirmationDialog(context, file);
        break;
    }
  }

  Future<void> _executeDuplicate(BuildContext context, FileEntity file) async {
    final repo = ref.read(storageRepositoryProvider);
    final res = await repo.duplicate(file.path);
    res.when(
      success: (duplicated) {
        ref.invalidate(directoryContentsProvider(p.dirname(file.path)));
        ref.read(indexingServiceProvider).indexSingleFile(duplicated);
        _showSnackBar(context, 'Duplicated as "${duplicated.name}"');
      },
      failure: (e) => _showSnackBar(context, 'Failed to duplicate: ${e.message}'),
    );
  }

  Future<void> _executePaste(
    BuildContext context,
    FileClipboard clipboard,
    String targetDirectory,
  ) async {
    final repo = ref.read(storageRepositoryProvider);
    final indexService = ref.read(indexingServiceProvider);
    final paths = clipboard.paths;

    final progressController = ref.read(activeOperationProgressProvider.notifier);
    final token = CancellationToken();

    final isCut = clipboard.mode == ClipboardMode.cut;

    final res = isCut
        ? await repo.batchMove(
            paths,
            targetDirectory,
            cancellationToken: token,
            onProgress: (p) => progressController.state = p,
          )
        : await repo.batchCopy(
            paths,
            targetDirectory,
            cancellationToken: token,
            onProgress: (p) => progressController.state = p,
          );

    progressController.state = null;

    res.when(
      success: (items) async {
        ref.read(fileClipboardProvider.notifier).state = null;
        ref.invalidate(directoryContentsProvider(targetDirectory));
        for (final item in items) {
          await indexService.indexSingleFile(item);
        }
        if (!context.mounted) return;
        _showSnackBar(context, 'Pasted ${items.length} items successfully');
      },
      failure: (e) {
        if (!context.mounted) return;
        _showSnackBar(context, 'Paste operation failed: ${e.message}');
      },
    );
  }

  void _showSortModal(BuildContext context) {
    final current = ref.read(fileSortCriteriaProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sort Files', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: FileSortField.values.map((f) {
                    final isSel = current.field == f;
                    return ChoiceChip(
                      label: Text(f.name.toUpperCase()),
                      selected: isSel,
                      onSelected: (sel) {
                        if (sel) {
                          final updated = current.copyWith(field: f);
                          ref.read(fileSortCriteriaProvider.notifier).state = updated;
                          Navigator.pop(ctx);
                        }
                      },
                    );
                  }).toList(),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Direction'),
                  trailing: TextButton.icon(
                    icon: Icon(
                      current.direction == SortDirection.ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 18,
                    ),
                    label: Text(current.direction == SortDirection.ascending ? 'Ascending' : 'Descending'),
                    onPressed: () {
                      final updated = current.copyWith(
                        direction: current.direction == SortDirection.ascending
                            ? SortDirection.descending
                            : SortDirection.ascending,
                      );
                      ref.read(fileSortCriteriaProvider.notifier).state = updated;
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                SwitchListTile(
                  title: const Text('Keep Folders on Top'),
                  value: current.foldersFirst,
                  onChanged: (val) {
                    final updated = current.copyWith(foldersFirst: val);
                    ref.read(fileSortCriteriaProvider.notifier).state = updated;
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showZipDialog(BuildContext context, List<FileEntity> files) {
    final textController = TextEditingController(text: 'Archive.zip');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create ZIP Archive'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Compressing ${files.length} items into ZIP archive:'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Archive Name', hintText: 'Archive.zip'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final parentDir = p.dirname(files.first.path);
              var zipName = textController.text.trim();
              if (!zipName.endsWith('.zip')) zipName += '.zip';
              final targetZip = p.join(parentDir, zipName);

              final archiveService = ref.read(archiveServiceProvider);
              final res = await archiveService.createZipArchive(
                sourcePaths: files.map((f) => f.path).toList(),
                targetZipPath: targetZip,
              );

              res.when(
                success: (path) async {
                  ref.read(selectedFilePathsProvider.notifier).clear();
                  ref.invalidate(directoryContentsProvider(parentDir));
                  final repo = ref.read(storageRepositoryProvider);
                  final details = await repo.getFileDetails(path);
                  ref.read(indexingServiceProvider).indexSingleFile(details);
                  if (!context.mounted) return;
                  _showSnackBar(context, 'Archive created: $zipName');
                },
                failure: (e) {
                  if (!context.mounted) return;
                  _showSnackBar(context, 'Failed creating archive: ${e.message}');
                },
              );
            },
            child: const Text('Compress'),
          ),
        ],
      ),
    );
  }

  void _showExtractDialog(BuildContext context, FileEntity zipFile) {
    final destDir = p.join(p.dirname(zipFile.path), p.basenameWithoutExtension(zipFile.path));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extract Archive'),
        content: Text('Extract "${zipFile.name}" into folder:\n\n$destDir?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final archiveService = ref.read(archiveServiceProvider);
              final res = await archiveService.extractZipArchive(
                zipFilePath: zipFile.path,
                destinationDirectory: destDir,
              );

              res.when(
                success: (extractedDir) {
                  ref.invalidate(directoryContentsProvider(p.dirname(zipFile.path)));
                  _showSnackBar(context, 'Archive extracted to ${p.basename(extractedDir)}');
                },
                failure: (e) => _showSnackBar(context, 'Extraction failed: ${e.message}'),
              );
            },
            child: const Text('Extract'),
          ),
        ],
      ),
    );
  }

  void _showBatchRenameDialog(BuildContext context, List<FileEntity> files) {
    final prefixController = TextEditingController(text: 'File_');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batch Rename'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rename ${files.length} items sequentially with prefix:'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: prefixController,
              decoration: const InputDecoration(labelText: 'Prefix', hintText: 'e.g. Photo_'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final prefix = prefixController.text.trim();
              final renameMap = <String, String>{};

              for (var i = 0; i < files.length; i++) {
                final file = files[i];
                final ext = file.extension;
                renameMap[file.path] = '$prefix${i + 1}$ext';
              }

              final repo = ref.read(storageRepositoryProvider);
              final res = await repo.batchRename(renameMap);

              res.when(
                success: (renamedList) {
                  ref.read(selectedFilePathsProvider.notifier).clear();
                  ref.invalidate(directoryContentsProvider(p.dirname(files.first.path)));
                  _showSnackBar(context, 'Renamed ${renamedList.length} files');
                },
                failure: (e) => _showSnackBar(context, 'Batch rename failed: ${e.message}'),
              );
            },
            child: const Text('Rename All'),
          ),
        ],
      ),
    );
  }

  void _showBatchDeleteDialog(BuildContext context, List<FileEntity> files) {
    final totalSize = files.fold<int>(0, (acc, f) => acc + f.size);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: AppSpacing.xs),
            Text('Confirm Deletion'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete ${files.length} selected items?\n\nEstimated size: ${Formatters.formatFileSize(totalSize)}\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              final parentDir = p.dirname(files.first.path);
              final result = await FileDeletion.deleteFiles(ref, files);
              ref.read(selectedFilePathsProvider.notifier).clear();
              ref.invalidate(directoryContentsProvider(parentDir));
              if (!context.mounted) return;
              _showSnackBar(context, result.summary());
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, FileEntity file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: AppSpacing.xs),
            Text('Delete File'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${file.name}"?\n\nSize: ${Formatters.formatFileSize(file.size)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await FileDeletion.deleteFiles(ref, [file]);
              ref.invalidate(directoryContentsProvider(p.dirname(file.path)));
              if (!context.mounted) return;
              _showSnackBar(
                context,
                result.allDeleted ? 'Deleted "${file.name}"' : 'Could not delete "${file.name}"',
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context, String currentPath) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder Name', hintText: 'Enter folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final repo = ref.read(storageRepositoryProvider);
              final res = await repo.createFolder(currentPath, name);
              res.when(
                success: (folder) {
                  ref.invalidate(directoryContentsProvider(currentPath));
                  _showSnackBar(context, 'Created folder "${folder.name}"');
                },
                failure: (e) => _showSnackBar(context, 'Failed to create folder: ${e.message}'),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, FileEntity file) {
    final controller = TextEditingController(text: file.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == file.name) return;
              Navigator.pop(ctx);

              final repo = ref.read(storageRepositoryProvider);
              final res = await repo.rename(file.path, newName);
              res.when(
                success: (renamed) {
                  ref.invalidate(directoryContentsProvider(p.dirname(file.path)));
                  ref.read(indexingServiceProvider).indexSingleFile(renamed);
                  _showSnackBar(context, 'Renamed to "${renamed.name}"');
                },
                failure: (e) => _showSnackBar(context, 'Rename failed: ${e.message}'),
              );
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showPropertiesDialog(BuildContext context, FileEntity file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(file.isDirectory ? Icons.folder_rounded : file.category.icon, color: file.category.color),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                file.name,
                style: AppTypography.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Path', file.path),
              _buildDetailRow('Size', Formatters.formatFileSize(file.size)),
              _buildDetailRow('Category', file.category.displayName),
              _buildDetailRow('Modified', Formatters.formatDate(file.modifiedAt)),
              _buildDetailRow('Created', Formatters.formatDate(file.createdAt)),
              if (file.mimeType != null) _buildDetailRow('MIME Type', file.mimeType!),
              const Divider(),
              FutureBuilder<String>(
                future: file.isDirectory
                    ? Future.value('N/A (directory)')
                    : ref.read(storageRepositoryProvider).calculateChecksum(file.path),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('Calculating MD5 checksum...', style: TextStyle(fontSize: 11)),
                    );
                  }
                  return _buildDetailRow('MD5 Checksum', snapshot.data ?? 'Error');
                },
              ),
            ],
          ),
        ),
        actions: [
          if (!file.isDirectory)
            TextButton.icon(
              icon: const Icon(Icons.hub_outlined, size: 16),
              label: const Text('Related Files'),
              onPressed: () {
                Navigator.pop(ctx);
                _showRelatedFiles(context, file);
              },
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
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

  Future<void> _showAiRenameDialog(BuildContext context, FileEntity file) async {
    final autoRename = ref.read(autoRenameServiceProvider);
    final suggestion = await autoRename.generateRenameSuggestion(file);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: AppColors.accent),
            SizedBox(width: 8),
            Text('AI Auto-Rename', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Original Name:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(suggestion.originalName, style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            const Text('Suggested Name:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              suggestion.suggestedName,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Reason: ${suggestion.reason}',
                style: const TextStyle(fontSize: 11, color: AppColors.primary),
              ),
            ),
            if (suggestion.hasCollision) ...[
              const SizedBox(height: 8),
              const Text(
                'Notice: Filename collision detected. Suffix appended.',
                style: TextStyle(fontSize: 11, color: AppColors.warning),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await autoRename.applyRename(suggestion);
              if (!context.mounted) return;
              if (success) {
                ref.read(autoRenameHistoryNotifierProvider.notifier).refresh();
                ref.invalidate(directoryContentsProvider(p.dirname(file.path)));
                _showSnackBar(context, 'Renamed to ${suggestion.suggestedName}');
              } else {
                _showSnackBar(context, 'Failed to rename file');
              }
            },
            child: const Text('Apply Rename'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.lightTextSecondary)),
          SelectableText(value, style: AppTypography.bodySmall),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
