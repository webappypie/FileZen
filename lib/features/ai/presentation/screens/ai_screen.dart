import '../../../files/presentation/resolvers/file_viewer_resolver.dart';
import '../../../../core/widgets/file_thumbnail_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/models/search_result_item.dart';
import '../providers/ai_providers.dart';
import 'auto_rename_screen.dart';
import 'collection_detail_screen.dart';

/// The central AI Hub providing Ask Your Files, Smart Collections, and AI Auto-Rename.
/// Operates 100% locally on-device without cloud uploads or external accounts.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  late final TextEditingController _queryController;

  static const _quickPrompts = [
    ('📄 Latest resume', 'latest resume'),
    ('🎥 Large videos', 'large videos over 50mb'),
    ('🔐 Screenshots with OTP', 'screenshots containing otp'),
    ('🧾 Receipts & bills', 'receipts and invoices'),
    ('🕒 Recent documents', 'recently modified documents'),
  ];

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _submitPrompt(String query) {
    _queryController.text = query;
    ref.read(askYourFilesQueryTextProvider.notifier).state = query;
  }

  void _openFile(SearchResultItem item) {
    final siblings = (ref.read(askYourFilesResultsProvider).valueOrNull ?? const <SearchResultItem>[])
        .map((r) => r.file)
        .toList();
    FileViewerResolver.openFile(context, ref, item.file, siblings);
  }

  Future<void> _showRenameDialog(SearchResultItem item) async {
    final autoRename = ref.read(autoRenameServiceProvider);
    final suggestion = await autoRename.generateRenameSuggestion(item.file);

    if (!mounted) return;

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
              if (!mounted) return;
              if (success) {
                ref.read(autoRenameHistoryNotifierProvider.notifier).refresh();
                ref.invalidate(askYourFilesResultsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Renamed to ${suggestion.suggestedName}'),
                    backgroundColor: AppColors.success,
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: Colors.white,
                      onPressed: () {
                        final history = ref.read(autoRenameHistoryNotifierProvider);
                        if (history.isNotEmpty) {
                          ref.read(autoRenameHistoryNotifierProvider.notifier).undo(history.last);
                          ref.invalidate(askYourFilesResultsProvider);
                        }
                      },
                    ),
                  ),
                );
              }
            },
            child: const Text('Apply Rename'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeQuery = ref.watch(askYourFilesQueryTextProvider);
    final activeIntent = ref.watch(activeNaturalQueryIntentProvider);
    final searchResultsAsync = ref.watch(askYourFilesResultsProvider);
    final smartCollectionsAsync = ref.watch(smartCollectionsProvider);

    return Scaffold(
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // 1. Privacy Guarantee Badge
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: isDark ? 0.15 : 0.08),
              borderRadius: AppSpacing.roundedMd,
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.secondary, size: 26),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% On-Device AI Processing',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Files and OCR remain strictly on your device. Zero cloud uploads.',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 2. Ask Your Files Search Input
          Row(
            children: [
              const Icon(Icons.psychology_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Ask Your Files',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _queryController,
            decoration: InputDecoration(
              hintText: 'e.g. "latest resume", "large videos", "receipts"...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: activeQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _queryController.clear();
                        ref.read(askYourFilesQueryTextProvider.notifier).state = '';
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            onSubmitted: (val) {
              ref.read(askYourFilesQueryTextProvider.notifier).state = val.trim();
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // Quick Prompt Suggestion Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickPrompts.map((p) {
                final isSelected = activeQuery.toLowerCase() == p.$2.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(p.$1),
                    backgroundColor: isSelected ? AppColors.primary.withValues(alpha: 0.2) : null,
                    side: isSelected ? const BorderSide(color: AppColors.primary) : null,
                    onPressed: () => _submitPrompt(p.$2),
                  ),
                );
              }).toList(),
            ),
          ),

          // Active Query Interpretation Banner
          if (activeIntent != null && activeQuery.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI Interpretation: ${activeIntent.explanation}',
                      style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Ask Your Files Results Feed
          if (activeQuery.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            searchResultsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Center(
                child: Text('Error executing natural query: $err'),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        const Icon(Icons.find_in_page_outlined, size: 40, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'No files matching "$activeQuery"',
                          style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found ${results.length} matching files',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    ...results.map((res) => _buildResultFileCard(res)),
                  ],
                );
              },
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // 3. Smart Collections Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_mosaic_rounded, color: AppColors.accent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Smart Collections',
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                'Virtual Clusters',
                style: AppTypography.bodySmall.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          smartCollectionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error loading smart collections: $err'),
            data: (collections) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.3,
                ),
                itemCount: collections.length,
                itemBuilder: (context, idx) {
                  final col = collections[idx];
                  final colColor = Color(col.colorHex);

                  return InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CollectionDetailScreen(collection: col),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: colColor.withValues(alpha: isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colColor.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colColor.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  col.icon,
                                  color: colColor,
                                  size: 20,
                                ),
                              ),
                              Text(
                                '${col.fileCount} items',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colColor,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                col.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                Formatters.formatFileSize(col.totalSizeBytes),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),

          const SizedBox(height: AppSpacing.lg),

          // 4. AI Auto-Rename Studio Shortcut Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AutoRenameScreen()),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_note_rounded, color: AppColors.accent, size: 28),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Auto-Rename Studio',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Batch-rename messy camera photos, screenshots, and downloads with before/after preview.',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildResultFileCard(SearchResultItem item) {
    final entity = item.file;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _openFile(item),
        leading: FileThumbnailWidget(file: entity, size: 40),
        title: Text(
          entity.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${Formatters.formatFileSize(entity.size)}  •  ${p.dirname(entity.path)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.snippet != null && item.snippet!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  item.snippet!,
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
              tooltip: 'AI Rename',
              onPressed: () => _showRenameDialog(item),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              tooltip: 'Open',
              onPressed: () => _openFile(item),
            ),
          ],
        ),
      ),
    );
  }
}
