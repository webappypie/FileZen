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
import '../../../../domain/models/network_models.dart';
import '../providers/network_providers.dart';

/// Screen for browsing directories and downloading files from a remote network server.
class RemoteBrowserScreen extends ConsumerStatefulWidget {
  final NetworkServerConfig server;

  const RemoteBrowserScreen({super.key, required this.server});

  @override
  ConsumerState<RemoteBrowserScreen> createState() =>
      _RemoteBrowserScreenState();
}

class _RemoteBrowserScreenState extends ConsumerState<RemoteBrowserScreen> {
  String _currentPath = '/';
  List<RemoteFileItem>? _files;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.server.path.isEmpty ? '/' : widget.server.path;
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final repo = ref.read(networkTransferRepositoryProvider);
    final result = await repo.listRemoteFiles(
      widget.server,
      path: _currentPath,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _files = result.dataOrNull;
      } else {
        _errorMessage = result.errorOrNull?.message ?? 'Failed to load remote directory';
      }
    });
  }

  void _navigateToFolder(String folderPath) {
    setState(() {
      _currentPath = folderPath;
    });
    _loadDirectory();
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final parent = p.posix.dirname(_currentPath);
    setState(() {
      _currentPath = parent;
    });
    _loadDirectory();
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
          protocol: widget.server.protocol,
          serverId: widget.server.id,
          totalBytes: file.size,
        );

    if (!mounted) return;

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${file.name} to device...'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
            Text(widget.server.name),
            Text(
              '${widget.server.protocol.shortName} • ${widget.server.host}',
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
            onPressed: _loadDirectory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Path Breadcrumb Bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            color: isDark ? Colors.grey[900] : Colors.grey[100],
            child: Row(
              children: [
                if (_currentPath != '/' && _currentPath.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    tooltip: 'Parent Folder',
                    onPressed: _navigateUp,
                  ),
                const Icon(Icons.folder_open, size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Main View
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingView(message: 'Loading remote files...');
    }

    if (_errorMessage != null) {
      return ErrorView(
        message: 'Unable to access remote directory',
        recoverySuggestion: _errorMessage!,
        onRetry: _loadDirectory,
      );
    }

    final files = _files ?? [];
    if (files.isEmpty) {
      return const EmptyView(
        title: 'Empty Folder',
        subtitle: 'No files or subdirectories found at this location.',
        icon: Icons.folder_open,
      );
    }

    return ListView.separated(
      padding: AppSpacing.screenPadding,
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = files[index];
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
                ? 'Directory'
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
              _navigateToFolder(item.remotePath);
            } else {
              _downloadFile(item);
            }
          },
        );
      },
    );
  }
}
