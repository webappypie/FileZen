import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/file_entity.dart';
import '../../../../domain/models/file_sort_criteria.dart';
import '../../../vault/presentation/services/vault_action_coordinator.dart';
import '../providers/category_files_providers.dart';
import '../resolvers/file_viewer_resolver.dart';

/// Generic category result screen displaying indexed files for a given category.
/// Operates directly on SQLite indexed metadata with zero unnecessary filesystem scanning.
class CategoryFilesScreen extends ConsumerStatefulWidget {
  const CategoryFilesScreen({
    super.key,
    this.category,
    required this.categoryTitle,
    this.isDownloads = false,
  });

  final FileCategory? category;
  final String categoryTitle;
  final bool isDownloads;

  @override
  ConsumerState<CategoryFilesScreen> createState() => _CategoryFilesScreenState();
}

class _CategoryFilesScreenState extends ConsumerState<CategoryFilesScreen> {
  bool _isGridView = false;
  FileSortField _sortField = FileSortField.date;
  bool _sortAscending = false;
  String _searchFilter = '';
  final Set<String> _selectedPaths = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FileEntity> _applySortingAndFiltering(List<FileEntity> source) {
    var filtered = source;
    if (_searchFilter.isNotEmpty) {
      final q = _searchFilter.toLowerCase();
      filtered = filtered.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    filtered.sort((a, b) {
      int cmp = 0;
      switch (_sortField) {
        case FileSortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case FileSortField.date:
          cmp = a.modifiedAt.compareTo(b.modifiedAt);
          break;
        case FileSortField.size:
          cmp = a.size.compareTo(b.size);
          break;
        case FileSortField.type:
          cmp = a.extension.compareTo(b.extension);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final query = (category: widget.category, isDownloads: widget.isDownloads);
    final filesAsync = ref.watch(categoryFilesListProvider(query));
    final isSelectionMode = _selectedPaths.isNotEmpty;

    return Scaffold(
      appBar: isSelectionMode
          ? _buildSelectionAppBar(context, filesAsync.valueOrNull ?? [])
          : _buildStandardAppBar(context, filesAsync.valueOrNull?.length ?? 0),
      body: filesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error loading ${widget.categoryTitle}: $err'),
        ),
        data: (allFiles) {
          final files = _applySortingAndFiltering(allFiles);

          if (files.isEmpty) {
            return EmptyView(
              icon: widget.category?.icon ?? Icons.folder_open_rounded,
              title: _searchFilter.isNotEmpty
                  ? 'No matching files'
                  : 'No ${widget.categoryTitle} found',
              subtitle: _searchFilter.isNotEmpty
                  ? 'Try searching with a different keyword.'
                  : 'Files belonging to this category will automatically appear here once indexed.',
            );
          }

          return _isGridView
              ? _buildGridView(context, files, allFiles)
              : _buildListView(context, files, allFiles);
        },
      ),
    );
  }

  PreferredSizeWidget _buildStandardAppBar(BuildContext context, int totalCount) {
    return AppBar(
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Filter ${widget.categoryTitle}...',
                border: InputBorder.none,
              ),
              onChanged: (val) => setState(() => _searchFilter = val.trim()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.categoryTitle),
                Text(
                  '$totalCount files',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
      actions: [
        IconButton(
          icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
          tooltip: _isSearching ? 'Close search' : 'Filter files',
          onPressed: () {
            setState(() {
              if (_isSearching) {
                _isSearching = false;
                _searchFilter = '';
                _searchController.clear();
              } else {
                _isSearching = true;
              }
            });
          },
        ),
        IconButton(
          icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
          tooltip: _isGridView ? 'List view' : 'Grid view',
          onPressed: () => setState(() => _isGridView = !_isGridView),
        ),
        PopupMenuButton<FileSortField>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort by',
          onSelected: (field) {
            setState(() {
              if (_sortField == field) {
                _sortAscending = !_sortAscending;
              } else {
                _sortField = field;
                _sortAscending = false;
              }
            });
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: FileSortField.date, child: Text('Date Modified')),
            const PopupMenuItem(value: FileSortField.name, child: Text('Name')),
            const PopupMenuItem(value: FileSortField.size, child: Text('Size')),
            const PopupMenuItem(value: FileSortField.type, child: Text('Extension')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(BuildContext context, List<FileEntity> allFiles) {
    final selectedFiles = allFiles.where((f) => _selectedPaths.contains(f.path)).toList();
    final totalBytes = selectedFiles.fold<int>(0, (acc, f) => acc + f.size);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close selection',
        onPressed: () => setState(() => _selectedPaths.clear()),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_selectedPaths.length} selected'),
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
            setState(() {
              _selectedPaths.addAll(allFiles.map((f) => f.path));
            });
          },
        ),
        IconButton(
          icon: const Icon(Icons.lock_rounded, color: AppColors.typeVault),
          tooltip: 'Move to Vault',
          onPressed: () async {
            await VaultActionCoordinator.moveFilesToVault(
              context,
              ref,
              selectedFiles,
              onSuccess: () {
                setState(() => _selectedPaths.clear());
                final query = (category: widget.category, isDownloads: widget.isDownloads);
                ref.invalidate(categoryFilesListProvider(query));
                ref.invalidate(categoryFileCountsProvider);
              },
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          tooltip: 'Delete',
          onPressed: () => _confirmBatchDelete(context, selectedFiles),
        ),
      ],
    );
  }

  Widget _buildListView(BuildContext context, List<FileEntity> files, List<FileEntity> allFiles) {
    final isSelectionMode = _selectedPaths.isNotEmpty;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = _selectedPaths.contains(file.path);

        return ListTile(
          selected: isSelected,
          leading: FileThumbnailWidget(file: file, size: 44),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${Formatters.formatFileSize(file.size)}  •  ${Formatters.formatDate(file.modifiedAt)}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelect(file.path),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (action) => _handleAction(context, file, action, allFiles),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'open', child: Text('Open')),
                    const PopupMenuItem(
                      value: 'vault',
                      child: Row(
                        children: [
                          Icon(Icons.lock_rounded, size: 18, color: AppColors.typeVault),
                          SizedBox(width: 8),
                          Text('Move to Vault', style: TextStyle(color: AppColors.typeVault)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(value: 'details', child: Text('Properties')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
          onTap: () {
            if (isSelectionMode) {
              _toggleSelect(file.path);
            } else {
              FileViewerResolver.openFile(context, ref, file, allFiles);
            }
          },
          onLongPress: () => _toggleSelect(file.path),
        );
      },
    );
  }

  Widget _buildGridView(BuildContext context, List<FileEntity> files, List<FileEntity> allFiles) {
    final isSelectionMode = _selectedPaths.isNotEmpty;

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = _selectedPaths.contains(file.path);

        return Card(
          elevation: 0,
          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.lightBorder.withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (isSelectionMode) {
                _toggleSelect(file.path);
              } else {
                FileViewerResolver.openFile(context, ref, file, allFiles);
              }
            },
            onLongPress: () => _toggleSelect(file.path),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: FileThumbnailWidget(file: file, size: 70),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    Formatters.formatFileSize(file.size),
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  Future<void> _handleAction(
    BuildContext context,
    FileEntity file,
    String action,
    List<FileEntity> allFiles,
  ) async {
    switch (action) {
      case 'open':
        FileViewerResolver.openFile(context, ref, file, allFiles);
        break;
      case 'vault':
        await VaultActionCoordinator.moveFilesToVault(
          context,
          ref,
          [file],
          onSuccess: () {
            final query = (category: widget.category, isDownloads: widget.isDownloads);
            ref.invalidate(categoryFilesListProvider(query));
            ref.invalidate(categoryFileCountsProvider);
          },
        );
        break;
      case 'details':
        _showPropertiesDialog(context, file);
        break;
      case 'delete':
        _confirmBatchDelete(context, [file]);
        break;
    }
  }

  void _showPropertiesDialog(BuildContext context, FileEntity file) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('File Properties'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${file.name}'),
            const SizedBox(height: 6),
            Text('Size: ${Formatters.formatFileSize(file.size)}'),
            const SizedBox(height: 6),
            Text('Type: ${file.category.displayName} (${file.extension})'),
            const SizedBox(height: 6),
            Text('Modified: ${Formatters.formatDate(file.modifiedAt)}'),
            const SizedBox(height: 6),
            Text('Path: ${file.path}', style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBatchDelete(BuildContext context, List<FileEntity> files) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${files.length} file(s)?'),
        content: const Text('This action will delete the selected files from storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final f in files) {
        try {
          final file = File(f.path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      setState(() => _selectedPaths.clear());
      final query = (category: widget.category, isDownloads: widget.isDownloads);
      ref.invalidate(categoryFilesListProvider(query));
      ref.invalidate(categoryFileCountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${files.length} item(s)')),
        );
      }
    }
  }
}
