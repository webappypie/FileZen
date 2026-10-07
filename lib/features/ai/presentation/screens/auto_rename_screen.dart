import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/models/ai_models.dart';
import '../../../files/presentation/providers/storage_providers.dart';
import '../providers/ai_providers.dart';

/// Screen providing AI-assisted batch file rename suggestions, side-by-side preview,
/// collision prevention, and instant undo capabilities.
class AutoRenameScreen extends ConsumerStatefulWidget {
  const AutoRenameScreen({super.key});

  @override
  ConsumerState<AutoRenameScreen> createState() => _AutoRenameScreenState();
}

class _AutoRenameScreenState extends ConsumerState<AutoRenameScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final TextEditingController _folderPathController;

  bool _isScanning = false;
  List<AutoRenameSuggestion> _suggestions = [];
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _folderPathController = TextEditingController(text: '/storage/emulated/0/Download');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _folderPathController.dispose();
    super.dispose();
  }

  Future<void> _scanFolderForRenames() async {
    final targetPath = _folderPathController.text.trim();
    if (targetPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a directory path to scan')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _suggestions = [];
      _selectedPaths.clear();
    });

    try {
      final storageRepo = ref.read(storageRepositoryProvider);
      final autoRename = ref.read(autoRenameServiceProvider);

      final files = await storageRepo.listDirectory(targetPath);
      final fileEntities = files.where((f) => !f.isDirectory).toList();

      if (fileEntities.isEmpty) {
        if (mounted) {
          setState(() => _isScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No files found in directory')),
          );
        }
        return;
      }

      final proposed = await autoRename.generateBatchRenameSuggestions(fileEntities);

      // Filter to suggestions that actually suggest a name change
      final changed = proposed.where((s) => !s.isSameName).toList();

      if (mounted) {
        setState(() {
          _isScanning = false;
          _suggestions = changed;
          _selectedPaths.addAll(changed.map((s) => s.originalPath));
        });

        if (changed.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All files already have optimal names!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  Future<void> _applySelectedRenames() async {
    final selectedSuggestions = _suggestions.where((s) => _selectedPaths.contains(s.originalPath)).toList();
    if (selectedSuggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files selected for rename')),
      );
      return;
    }

    final autoRename = ref.read(autoRenameServiceProvider);
    var appliedCount = 0;

    for (final suggestion in selectedSuggestions) {
      final success = await autoRename.applyRename(suggestion);
      if (success) appliedCount++;
    }

    ref.read(autoRenameHistoryNotifierProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully renamed $appliedCount files'),
          backgroundColor: AppColors.success,
          action: SnackBarAction(
            label: 'View History',
            textColor: Colors.white,
            onPressed: () {
              _tabController.animateTo(1);
            },
          ),
        ),
      );

      // Re-scan after rename
      _scanFolderForRenames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = ref.watch(autoRenameHistoryNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Auto-Rename Studio'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Proposals (${_suggestions.length})'),
            Tab(text: 'History (${history.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Rename Proposals
          _buildProposalsTab(isDark),

          // Tab 2: Undo History
          _buildHistoryTab(history),
        ],
      ),
      bottomNavigationBar: _suggestions.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
              ),
              child: SafeArea(
                child: FilledButton.icon(
                  onPressed: _selectedPaths.isEmpty ? null : _applySelectedRenames,
                  icon: const Icon(Icons.check_rounded),
                  label: Text('Apply Rename to ${_selectedPaths.length} Files'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildProposalsTab(bool isDark) {
    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        // Directory Input
        TextField(
          controller: _folderPathController,
          decoration: InputDecoration(
            labelText: 'Target Directory Path',
            hintText: '/storage/emulated/0/Download',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Scan for Messy Names',
              onPressed: _isScanning ? null : _scanFolderForRenames,
            ),
          ),
        ),
        const SizedBox(height: 12),

        FilledButton.tonalIcon(
          onPressed: _isScanning ? null : _scanFolderForRenames,
          icon: _isScanning
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(_isScanning ? 'Analyzing Files with AI...' : 'Scan & Propose Renames'),
        ),
        const SizedBox(height: 16),

        if (_suggestions.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Proposed Renames (${_suggestions.length})',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedPaths.length == _suggestions.length) {
                      _selectedPaths.clear();
                    } else {
                      _selectedPaths.addAll(_suggestions.map((s) => s.originalPath));
                    }
                  });
                },
                child: Text(_selectedPaths.length == _suggestions.length ? 'Deselect All' : 'Select All'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          ..._suggestions.map((s) {
            final isChecked = _selectedPaths.contains(s.originalPath);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isChecked ? const BorderSide(color: AppColors.primary, width: 1.5) : BorderSide.none,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedPaths.add(s.originalPath);
                          } else {
                            _selectedPaths.remove(s.originalPath);
                          }
                        });
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  s.originalName,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, decoration: TextDecoration.lineThrough),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  s.suggestedName,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  s.reason,
                                  style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (s.hasCollision) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Collision Resolved',
                                    style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ] else if (!_isScanning) ...[
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Icon(Icons.edit_note_rounded, size: 56, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                const Text(
                  'Enter a folder path and tap "Scan & Propose Renames"\nto generate intelligent AI file names.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryTab(List<AutoRenameHistoryItem> history) {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 56, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'No recent rename operations to undo.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: AppSpacing.screenPadding,
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final item = history[history.length - 1 - index]; // latest first

        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.renamedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text('Previously: ${item.originalName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          trailing: TextButton.icon(
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: const Text('Undo'),
            onPressed: () async {
              final success = await ref.read(autoRenameHistoryNotifierProvider.notifier).undo(item);
              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Reverted ${item.renamedName} back to ${item.originalName}'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to undo rename'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }
}
