import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/empty_view.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0;

  final _filters = ['All', 'Images', 'Documents', 'Videos', 'Audio', 'Archives'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search files, OCR text, tags...',
            border: InputBorder.none,
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              fontSize: 16,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: (val) => setState(() {}),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                final isSelected = _selectedFilterIndex == index;
                return ChoiceChip(
                  label: Text(_filters[index]),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedFilterIndex = index);
                  },
                );
              },
            ),
          ),
          const Divider(),

          // Search Content / Empty State
          Expanded(
            child: _searchController.text.isEmpty
                ? const EmptyView(
                    icon: Icons.search_rounded,
                    title: 'Universal Search',
                    subtitle: 'Search across filenames, paths, OCR extracted text, documents, and smart metadata.',
                  )
                : EmptyView(
                    icon: Icons.find_in_page_outlined,
                    title: 'No indexed results yet',
                    subtitle: 'Full-text FTS5 database and incremental scanning activate in Phase 03.',
                  ),
          ),
        ],
      ),
    );
  }
}
