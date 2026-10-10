import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/empty_view.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../../../domain/models/network_models.dart';
import '../providers/network_providers.dart';
import 'add_server_dialog.dart';
import 'remote_browser_screen.dart';

/// Central Hub for LAN Web Sharing, Network Storage Servers, and Transfers Queue.
class NetworkHubScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const NetworkHubScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<NetworkHubScreen> createState() => _NetworkHubScreenState();
}

class _NetworkHubScreenState extends ConsumerState<NetworkHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTransfersCount = ref.watch(activeTransfersCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network & Transfer'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(
              icon: Icon(Icons.wifi_tethering_rounded),
              text: 'Wi-Fi Share',
            ),
            const Tab(
              icon: Icon(Icons.dns_rounded),
              text: 'Network Storage',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: activeTransfersCount > 0,
                label: Text(activeTransfersCount.toString()),
                child: const Icon(Icons.swap_vert_rounded),
              ),
              text: 'Transfers',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _LanShareTab(),
          _NetworkServersTab(),
          _TransfersTab(),
        ],
      ),
    );
  }
}

// ==================== Tab 1: Wi-Fi Web Share ====================

class _LanShareTab extends ConsumerWidget {
  const _LanShareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(lanSessionStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return sessionAsync.when(
      loading: () => const LoadingView(message: 'Initializing Wi-Fi share...'),
      error: (e, _) => ErrorView(
        message: 'LAN Share Error',
        recoverySuggestion: e.toString(),
      ),
      data: (session) {
        final isActive = session.isActive;

        return ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // Header Hero Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.roundedLg,
                side: BorderSide(
                  color: isActive ? AppColors.success : Colors.transparent,
                  width: isActive ? 1.5 : 0,
                ),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (isActive ? AppColors.success : AppColors.primary)
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isActive ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                        size: 40,
                        color: isActive ? AppColors.success : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      isActive ? 'Web Share is Live' : 'Wi-Fi Web Share',
                      style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      isActive
                          ? 'Visit the URL below on any browser on your Wi-Fi network.'
                          : 'Share files with any laptop, iPhone, or PC on your local Wi-Fi without cables or cloud accounts.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isActive ? AppColors.error : AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final controller = ref.read(networkTransferControllerProvider.notifier);
                          if (isActive) {
                            await controller.stopLanServer();
                          } else {
                            await controller.startLanServer();
                          }
                        },
                        icon: Icon(isActive ? Icons.stop_rounded : Icons.play_arrow_rounded),
                        label: Text(
                          isActive ? 'Stop Web Share' : 'Start Web Share',
                          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (isActive) ...[
              // Connection Details Card
              Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Browser Access Details',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // URL Box
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.grey[100],
                          borderRadius: AppSpacing.roundedSm,
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link_rounded, color: AppColors.primary),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: SelectableText(
                                session.displayUrl,
                                style: AppTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 20),
                              tooltip: 'Copy URL',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: session.displayUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URL copied to clipboard'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Security PIN Box
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Security PIN',
                                style: AppTypography.labelLarge.copyWith(
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Required to connect',
                                style: AppTypography.bodySmall.copyWith(
                                  color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: AppSpacing.roundedSm,
                              border: Border.all(color: AppColors.accent),
                            ),
                            child: Text(
                              session.accessPin,
                              style: AppTypography.titleLarge.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 4,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Divider(),
                      const SizedBox(height: AppSpacing.sm),

                      // QR Pairing Visual Matrix
                      Row(
                        children: [
                          _buildQrVisualMatrix(session.accessPin, isDark),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pairing Code Matrix',
                                  style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Clients: ${session.connectedClientsCount} connected',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: session.connectedClientsCount > 0 ? AppColors.success : null,
                                    fontWeight: session.connectedClientsCount > 0 ? FontWeight.w600 : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Feature Highlights / Privacy
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: AppColors.secondary, size: 20),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Local-First Privacy Principle',
                          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'All transfers remain 100% on your local Wi-Fi network. No files are routed through external servers or third-party cloud infrastructure.',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQrVisualMatrix(String pin, bool isDark) {
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white : Colors.black,
        borderRadius: AppSpacing.roundedSm,
      ),
      child: Center(
        child: Icon(
          Icons.qr_code_2_rounded,
          size: 60,
          color: isDark ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

// ==================== Tab 2: Network Storage Servers ====================

class _NetworkServersTab extends ConsumerWidget {
  const _NetworkServersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(networkServersStreamProvider);

    return serversAsync.when(
      loading: () => const LoadingView(message: 'Loading servers...'),
      error: (e, _) => ErrorView(
        message: 'Failed to load servers',
        recoverySuggestion: e.toString(),
      ),
      data: (servers) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const AddServerDialog(),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Storage'),
          ),
          body: servers.isEmpty
              ? EmptyView(
                  title: 'No Network Servers',
                  subtitle: 'Add a WebDAV server to browse and transfer remote files.',
                  icon: Icons.dns_rounded,
                  actionLabel: 'Add Server',
                  onAction: () {
                    showDialog(
                      context: context,
                      builder: (_) => const AddServerDialog(),
                    );
                  },
                )
              : ListView.builder(
                  padding: AppSpacing.screenPadding,
                  itemCount: servers.length,
                  itemBuilder: (context, index) {
                    final server = servers[index];
                    return _ServerCard(server: server);
                  },
                ),
        );
      },
    );
  }
}

class _ServerCard extends ConsumerWidget {
  final NetworkServerConfig server;

  const _ServerCard({required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (server.status) {
      ServerStatus.connected => AppColors.success,
      ServerStatus.connecting => AppColors.info,
      ServerStatus.error => AppColors.error,
      ServerStatus.disconnected => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.dns_rounded, color: AppColors.primary),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: AppSpacing.roundedSm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    server.status.displayName,
                    style: AppTypography.labelSmall.copyWith(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(server.displayUri, style: AppTypography.bodySmall),
            if (server.lastError != null)
              Text(
                server.lastError!,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) async {
            if (action == 'test') {
              final result = await ref
                  .read(networkTransferControllerProvider.notifier)
                  .testConnection(server);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.isSuccess
                        ? 'Connection successful!'
                        : 'Connection failed: ${result.errorOrNull?.message}'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } else if (action == 'edit') {
              showDialog(
                context: context,
                builder: (_) => AddServerDialog(existingServer: server),
              );
            } else if (action == 'delete') {
              await ref
                  .read(networkTransferControllerProvider.notifier)
                  .deleteServer(server.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'test', child: Text('Test Connection')),
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RemoteBrowserScreen(server: server),
            ),
          );
        },
      ),
    );
  }
}

// ==================== Tab 3: Transfers Queue ====================

class _TransfersTab extends ConsumerWidget {
  const _TransfersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfersAsync = ref.watch(transfersStreamProvider);

    return transfersAsync.when(
      loading: () => const LoadingView(message: 'Loading transfers...'),
      error: (e, _) => ErrorView(
        message: 'Transfers Error',
        recoverySuggestion: e.toString(),
      ),
      data: (tasks) {
        if (tasks.isEmpty) {
          return const EmptyView(
            title: 'No Transfers',
            subtitle: 'Queued and active network or cloud transfers will appear here.',
            icon: Icons.swap_vert_rounded,
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${tasks.length} total tasks',
                    style: AppTypography.bodySmall,
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ref
                          .read(networkTransferControllerProvider.notifier)
                          .clearCompletedTransfers();
                    },
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Clear Completed'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: AppSpacing.screenPadding,
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return _TransferTaskCard(task: task);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransferTaskCard extends ConsumerWidget {
  final NetworkTransferTask task;

  const _TransferTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpload = task.direction == TransferDirection.upload;
    final isTransferring = task.status == TransferStatus.transferring;
    final isDone = task.status == TransferStatus.completed;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUpload ? Icons.upload_rounded : Icons.download_rounded,
                  color: isUpload ? AppColors.accent : AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    task.fileName,
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isDone && task.status != TransferStatus.cancelled)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Cancel',
                    onPressed: () {
                      ref
                          .read(networkTransferControllerProvider.notifier)
                          .cancelTransfer(task.id);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: AppSpacing.roundedSm,
              child: LinearProgressIndicator(
                value: isDone ? 1.0 : task.progress,
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDone ? AppColors.success : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Formatters.formatFileSize(task.bytesTransferred)} of ${Formatters.formatFileSize(task.totalBytes)}',
                  style: AppTypography.bodySmall,
                ),
                Text(
                  isTransferring
                      ? '${Formatters.formatFileSize(task.speedBytesPerSec.toInt())}/s'
                      : task.status.displayName,
                  style: AppTypography.labelSmall.copyWith(
                    color: isDone ? AppColors.success : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
