import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/file_category.dart';
import '../../../../domain/models/indexing_progress.dart';
import '../../../../domain/models/search_result_item.dart';
import '../../../files/presentation/resolvers/file_viewer_resolver.dart';
import '../../../vault/presentation/services/vault_action_coordinator.dart';
import '../providers/search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryTextProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    ref.read(searchQueryTextProvider.notifier).state = value;
  }

  void _onQuerySubmitted(String value) {
    if (value.trim().isNotEmpty) {
      ref.read(searchHistoryProvider.notifier).addQuery(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedCategory = ref.watch(searchCategoryFilterProvider);
    final indexingProgress = ref.watch(indexingProgressProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final indexedCountAsync = ref.watch(indexedCountProvider);
    final searchHistory = ref.watch(searchHistoryProvider);
    final currentText = ref.watch(searchQueryTextProvider);

    final isSearching = currentText.trim().isNotEmpty || selectedCategory != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search files, OCR, documents...',
            border: InputBorder.none,
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              fontSize: 16,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: _onQueryChanged,
          onSubmitted: _onQuerySubmitted,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              tooltip: 'Clear search',
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Indexing Status Banner
          _buildIndexingBanner(context, indexingProgress, indexedCountAsync),

          // Category Filter Chips Bar
          _buildFilterChips(context, selectedCategory),

          const Divider(height: 1),

          // Main Content
          Expanded(
            child: isSearching
                ? _buildSearchResults(context, searchResultsAsync)
                : _buildEmptyOrHistoryState(context, searchHistory),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexingBanner(
    BuildContext context,
    IndexingProgress progress,
    AsyncValue<int> countAsync,
  ) {
    final theme = Theme.of(context);

    if (progress.isRunning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    switch (progress.status) {
                      IndexingStatus.scanning => 'Scanning storage for files...',
                      IndexingStatus.paused => 'Indexing paused',
                      _ when progress.pendingOcrCount > 0 =>
                        'Reading text in images (${progress.pendingOcrCount} left)...',
                      _ =>
                        'Indexing (${progress.indexedCount + progress.skippedCount}/${progress.totalFilesDiscovered})...',
                    },
                    style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(indexingProgressProvider.notifier).cancelIndexing(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
            if (progress.totalFilesDiscovered > 0) ...[
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: progress.progressFraction,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          ],
        ),
      );
    }

    final countText = countAsync.maybeWhen(
      data: (cnt) => progress.pendingOcrCount > 0
          ? '$cnt files indexed • ${progress.pendingOcrCount} images waiting for text recognition'
          : '$cnt files indexed in catalog',
      orElse: () => 'Database catalog ready',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.storage_rounded, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              countText,
              style: AppTypography.bodySmall.copyWith(fontSize: 12),
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 0),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Scan Storage', style: TextStyle(fontSize: 11)),
            onPressed: () => ref.read(indexingProgressProvider.notifier).startIndexing(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, FileCategory? selectedCategory) {
    final categories = [
      null,
      FileCategory.document,
      FileCategory.image,
      FileCategory.video,
      FileCategory.audio,
      FileCategory.archive,
      FileCategory.apk,
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = selectedCategory == cat;
          final label = cat == null ? 'All' : cat.displayName;

          return ChoiceChip(
            label: Text(label),
            avatar: cat != null
                ? Icon(cat.icon, size: 16, color: isSelected ? null : cat.color)
                : null,
            selected: isSelected,
            onSelected: (selected) {
              ref.read(searchCategoryFilterProvider.notifier).state = selected ? cat : null;
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    AsyncValue<List<SearchResultItem>> resultsAsync,
  ) {
    return resultsAsync.when(
      loading: () => const LoadingView(message: 'Searching indexed database...'),
      error: (err, _) => ErrorView(
        message: 'Search Query Failed',
        recoverySuggestion: err.toString(),
        onRetry: () => ref.refresh(searchResultsProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyView(
            icon: Icons.search_off_rounded,
            title: 'No Matching Files Found',
            subtitle: 'Try searching with different keywords or indexing more folders.',
            actionLabel: 'Index Storage',
            onAction: () => ref.read(indexingProgressProvider.notifier).startIndexing(),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
              child: Text(
                '${items.length} ${items.length == 1 ? 'file' : 'files'} found',
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  return _buildResultCard(context, items[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultCard(BuildContext context, SearchResultItem result) {
    final file = result.file;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.roundedMd,
        side: BorderSide(color: AppColors.lightBorder.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: AppSpacing.roundedMd,
        onTap: () => FileViewerResolver.openFile(
          context,
          ref,
          file,
          (ref.read(searchResultsProvider).valueOrNull ?? const []).map((r) => r.file).toList(),
        ),
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FileThumbnailWidget(file: file, size: 40),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          p.dirname(file.path),
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'File actions',
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onSelected: (action) {
                      switch (action) {
                        case 'open':
                          FileViewerResolver.openFile(context, ref, file);
                        case 'details':
                          _showFileDetailsDialog(context, result);
                        case 'vault':
                          VaultActionCoordinator.moveFileToVault(
                            context,
                            ref,
                            file,
                            onSuccess: () => ref.invalidate(searchResultsProvider),
                          );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Open')),
                      PopupMenuItem(value: 'details', child: Text('Details')),
                      PopupMenuItem(value: 'vault', child: Text('Move to Vault')),
                    ],
                  ),
                ],
              ),
              if (result.snippet != null && result.snippet!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: AppSpacing.roundedSm,
                  ),
                  child: RichText(
                    text: _buildSnippetTextSpan(result.snippet!, theme),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Text(
                    Formatters.formatFileSize(file.size),
                    style: AppTypography.bodySmall.copyWith(fontSize: 11),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '•  ${Formatters.formatDate(file.modifiedAt)}',
                    style: AppTypography.bodySmall.copyWith(fontSize: 11),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: file.category.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      file.category.displayName,
                      style: TextStyle(fontSize: 10, color: file.category.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextSpan _buildSnippetTextSpan(String snippet, ThemeData theme) {
    final spans = <TextSpan>[];
    final parts = snippet.split('[match]');

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i == 0) {
        if (part.isNotEmpty) {
          spans.add(TextSpan(text: part, style: AppTypography.bodySmall.copyWith(fontSize: 11)));
        }
      } else {
        final subparts = part.split('[/match]');
        final matchedWord = subparts[0];
        spans.add(
          TextSpan(
            text: matchedWord,
            style: AppTypography.bodySmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
        );
        if (subparts.length > 1 && subparts[1].isNotEmpty) {
          spans.add(TextSpan(text: subparts[1], style: AppTypography.bodySmall.copyWith(fontSize: 11)));
        }
      }
    }

    return TextSpan(children: spans);
  }

  Widget _buildEmptyOrHistoryState(BuildContext context, List<String> history) {
    if (history.isEmpty) {
      return const EmptyView(
        icon: Icons.search_rounded,
        title: 'Universal Full-Text Search',
        subtitle: 'Search across filenames, documents, extracted text, and local file metadata with instant FTS5 indexing.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: () => ref.read(searchHistoryProvider.notifier).clearHistory(),
                child: const Text('Clear all', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: history.map((q) {
              return InputChip(
                label: Text(q),
                avatar: const Icon(Icons.history_rounded, size: 14),
                onPressed: () {
                  _controller.text = q;
                  _onQueryChanged(q);
                },
                onDeleted: () => ref.read(searchHistoryProvider.notifier).removeQuery(q),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
          const EmptyView(
            icon: Icons.search_rounded,
            title: 'Universal Full-Text Search',
            subtitle: 'Powered by SQLite FTS5 on-device indexing.',
          ),
        ],
      ),
    );
  }

  void _showFileDetailsDialog(BuildContext context, SearchResultItem item) {
    final file = item.file;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(file.category.icon, color: file.category.color, size: 22),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Path', file.path),
            _buildDetailRow('Size', Formatters.formatFileSize(file.size)),
            _buildDetailRow('Category', file.category.displayName),
            _buildDetailRow('Modified', Formatters.formatDate(file.modifiedAt)),
            if (item.snippet != null && item.snippet!.isNotEmpty)
              _buildDetailRow('Match Excerpt', item.snippet!.replaceAll('[match]', '').replaceAll('[/match]', '')),
          ],
        ),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open'),
            onPressed: () {
              Navigator.of(ctx).pop();
              FileViewerResolver.openFile(context, ref, file);
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
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
}
