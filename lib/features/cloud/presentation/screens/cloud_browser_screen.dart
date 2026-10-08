import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/cloud_models.dart';
import '../../../../domain/models/network_models.dart';
import '../../../transfer/presentation/providers/network_providers.dart';
import '../providers/cloud_providers.dart';

/// Screen for browsing files within a connected cloud drive, downloading files,
/// and uploading local files on explicit user request.
class CloudBrowserScreen extends ConsumerStatefulWidget {
  final CloudAccount account;

  const CloudBrowserScreen({super.key, required this.account});

  @override
  ConsumerState<CloudBrowserScreen> createState() => _CloudBrowserScreenState();
}

class _CloudBrowserScreenState extends ConsumerState<CloudBrowserScreen> {
  String _currentFolderId = 'root';
  String _currentFolderPath = '/';
  List<RemoteFileItem>? _files;
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final repo = ref.read(cloudProviderRepositoryProvider);
    final result = await repo.listCloudFiles(
      widget.account,
      folderId: _currentFolderId,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _files = result.dataOrNull;
      } else {
        _errorMessage = result.errorOrNull?.message ?? 'Failed to load cloud files';
      }
    });
  }

  void _navigateToFolder(RemoteFileItem folder) {
    setState(() {
      _currentFolderId = folder.id;
      _currentFolderPath = folder.remotePath;
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentFolderPath == '/' || _currentFolderPath.isEmpty) return;
    setState(() {
      _currentFolderId = 'root';
      _currentFolderPath = '/';
    });
    _loadFiles();
  }

  Future<void> _downloadFile(RemoteFileItem file) async {
    final destPath = '/storage/emulated/0/Download/${file.name}';
    final result = await ref
        .read(networkTransferControllerProvider.notifier)
        .enqueueTransfer(
          fileName: file.name,
          direction: TransferDirection.download,
          sourcePath: file.remotePath,
          destinationPath: destPath,
          cloudProvider: widget.account.provider.name,
          totalBytes: file.size,
        );

    if (!mounted) return;

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${file.name} from ${widget.account.displayName}...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _uploadDemoFile() async {
    // Allows user to push an on-demand file to cloud
    final fileName = 'filezen_export_${DateTime.now().millisecondsSinceEpoch}.txt';
    final localPath = '/storage/emulated/0/Documents/$fileName';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Uploading $fileName to ${widget.account.displayName}...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final result = await ref
        .read(networkTransferControllerProvider.notifier)
        .enqueueTransfer(
          fileName: fileName,
          direction: TransferDirection.upload,
          sourcePath: localPath,
          destinationPath: '$_currentFolderPath/$fileName',
          cloudProvider: widget.account.provider.name,
          totalBytes: 1024 * 512, // 512 KB
        );

    if (mounted && result.isSuccess) {
      await _loadFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.account.displayName),
            Text(
              '${widget.account.provider.displayName} • ${widget.account.accountEmail}',
              style: AppTypography.labelSmall.copyWith(
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadFiles,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Upload File to Cloud',
            onPressed: _uploadDemoFile,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Breadcrumb Bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            color: isDark ? Colors.grey[900] : Colors.grey[100],
            child: Column(
              children: [
                // Search bar
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search cloud files...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                ),
                const SizedBox(height: 6),
                // Breadcrumbs
                Row(
                  children: [
                    if (_currentFolderPath != '/')
                      IconButton(
                        icon: const Icon(Icons.arrow_upward, size: 18),
                        tooltip: 'Parent Folder',
                        onPressed: _navigateUp,
                      ),
                    const Icon(Icons.cloud_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _currentFolderPath,
                        style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingView(message: 'Loading cloud files...');
    }

    if (_errorMessage != null) {
      return ErrorView(
        message: 'Could not load cloud files',
        recoverySuggestion: _errorMessage!,
        onRetry: _loadFiles,
      );
    }

    final allFiles = _files ?? [];
    final filtered = _searchQuery.isEmpty
        ? allFiles
        : allFiles.where((f) => f.name.toLowerCase().contains(_searchQuery)).toList();

    if (filtered.isEmpty) {
      return const EmptyView(
        title: 'No Cloud Files Found',
        subtitle: 'Folder is empty or search returned no matches.',
        icon: Icons.cloud_queue_rounded,
      );
    }

    return ListView.separated(
      padding: AppSpacing.screenPadding,
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = filtered[index];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: item.isDirectory
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
              color: item.isDirectory ? AppColors.primary : null,
              size: 22,
            ),
          ),
          title: Text(
            item.name,
            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            item.isDirectory
                ? 'Cloud Folder'
                : '${Formatters.formatFileSize(item.size)} • ${Formatters.formatDate(item.modifiedAt)}',
            style: AppTypography.bodySmall,
          ),
          trailing: item.isDirectory
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  icon: const Icon(Icons.download_rounded, color: AppColors.primary),
                  tooltip: 'Download to Device',
                  onPressed: () => _downloadFile(item),
                ),
          onTap: () {
            if (item.isDirectory) {
              _navigateToFolder(item);
            } else {
              _downloadFile(item);
            }
          },
        );
      },
    );
  }
}
