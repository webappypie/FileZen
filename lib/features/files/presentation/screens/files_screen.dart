import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/widgets/empty_view.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  bool _isGridView = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final storageLocations = [
      ('Internal Storage', '46 GB / 128 GB', Icons.phone_android_rounded, AppColors.primary),
      ('SD Card', 'Not inserted', Icons.sd_card_rounded, isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
      ('Downloads', '64 files • 2.4 GB', Icons.download_rounded, AppColors.secondary),
    ];

    return Scaffold(
      body: Column(
        children: [
          // Storage root locations selector
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Locations',
                  style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
                  tooltip: _isGridView ? 'Switch to list view' : 'Switch to grid view',
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: storageLocations.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final (name, subtitle, icon, color) = storageLocations[index];
                return SizedBox(
                  width: 170,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 20, color: color),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  name,
                                  style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            subtitle,
                            style: AppTypography.bodySmall.copyWith(
                              fontSize: 10,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: AppSpacing.lg),

          // File browser content area (Phase 01 baseline state)
          Expanded(
            child: EmptyView(
              icon: Icons.folder_open_rounded,
              title: 'Storage Ready',
              subtitle: 'Storage abstractions and permission handling will be configured in Phase 02.',
              actionLabel: 'Scan Storage',
              onAction: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Storage scan pipeline activates in Phase 02'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
