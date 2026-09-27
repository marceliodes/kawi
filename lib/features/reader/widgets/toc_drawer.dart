import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../providers/document_content_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../services/document_extractor.dart';

class TocDrawer extends ConsumerStatefulWidget {
  const TocDrawer({
    super.key,
    required this.filePath,
    required this.currentPageIndex,
    required this.onSelectPage,
    this.isPaginated,
  });

  final String filePath;
  final int currentPageIndex;
  final ValueChanged<int> onSelectPage;
  final bool? isPaginated;

  @override
  ConsumerState<TocDrawer> createState() => _TocDrawerState();
}

class _TocDrawerState extends ConsumerState<TocDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final tocAsync = ref.watch(documentTocProvider(widget.filePath));
    final settings = ref.watch(readerSettingsProvider);
    final showPageNumbers = widget.isPaginated ?? settings.isPaginated;

    return Drawer(
      backgroundColor: theme.bgCard,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Table of Contents',
                      style: AppTypography.headline.copyWith(
                        color: theme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: PhosphorIcon(
                      PhosphorIconsLight.x,
                      size: 20,
                      color: theme.textMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search filter
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.xs,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _filterQuery = val.trim()),
                style: AppTypography.body.copyWith(color: theme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Filter chapters...',
                  hintStyle: AppTypography.body.copyWith(
                    color: theme.textMuted,
                  ),
                  prefixIcon: PhosphorIcon(
                    PhosphorIconsLight.magnifyingGlass,
                    size: 16,
                    color: theme.textMuted,
                  ),
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          icon: PhosphorIcon(
                            PhosphorIconsLight.xCircle,
                            size: 16,
                            color: theme.textMuted,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filterQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: theme.bgCanvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: theme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: theme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: theme.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                ),
              ),
            ),
            const Divider(height: Spacing.md),

            // TOC List
            Expanded(
              child: tocAsync.when(
                loading: () => Center(
                  child: Text(
                    'Loading Table of Contents...',
                    style: AppTypography.micro.copyWith(color: theme.textMuted),
                  ),
                ),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Text(
                      'Failed to load Table of Contents: $err',
                      style: AppTypography.body.copyWith(
                        color: theme.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PhosphorIcon(
                            PhosphorIconsLight.bookBookmark,
                            size: 48,
                            color: theme.textMuted,
                          ),
                          const SizedBox(height: Spacing.sm),
                          Text(
                            'No Table of Contents',
                            style: AppTypography.headline.copyWith(
                              color: theme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: Spacing.xxs),
                          Text(
                            'This document does not contain outline markers.',
                            style: AppTypography.micro.copyWith(
                              color: theme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final flattened = _flattenAndFilter(entries, _filterQuery);
                  if (flattened.isEmpty) {
                    return Center(
                      child: Text(
                        'No matching chapters found.',
                        style: AppTypography.body.copyWith(
                          color: theme.textMuted,
                        ),
                      ),
                    );
                  }

                  _FlattenedTocItem? currentItem;
                  for (final it in flattened) {
                    if (it.entry.pageIndex >= 0 &&
                        it.entry.pageIndex <= widget.currentPageIndex) {
                      currentItem = it;
                    }
                  }

                  return ListView.builder(
                    itemCount: flattened.length,
                    itemBuilder: (context, index) {
                      final item = flattened[index];
                      final isCurrent = item == currentItem;

                      return _buildTocRow(
                        theme: theme,
                        item: item,
                        isCurrent: isCurrent,
                        showPageNumbers: showPageNumbers,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTocRow({
    required ReaderThemeData theme,
    required _FlattenedTocItem item,
    required bool isCurrent,
    required bool showPageNumbers,
  }) {
    return InkWell(
      onTap: () {
        if (item.entry.pageIndex >= 0) {
          widget.onSelectPage(item.entry.pageIndex);
        }
        Navigator.of(context).pop();
      },
      child: Container(
        padding: EdgeInsets.only(
          left: Spacing.md + (item.depth * 16.0),
          right: Spacing.md,
          top: Spacing.xs,
          bottom: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: isCurrent ? theme.accent.withValues(alpha: 0.12) : null,
          border: isCurrent
              ? Border(left: BorderSide(color: theme.accent, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.entry.title.isNotEmpty
                    ? item.entry.title
                    : (item.entry.pageIndex >= 0
                          ? 'Chapter ${item.entry.pageIndex + 1}'
                          : 'Section'),
                style: AppTypography.body.copyWith(
                  color: isCurrent ? theme.accent : theme.textPrimary,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showPageNumbers && item.entry.pageIndex >= 0) ...[
              const SizedBox(width: Spacing.xs),
              Text(
                '${item.entry.pageIndex + 1}',
                style: AppTypography.micro.copyWith(
                  color: isCurrent ? theme.accent : theme.textMuted,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_FlattenedTocItem> _flattenAndFilter(
    List<TocEntry> entries,
    String query,
  ) {
    final result = <_FlattenedTocItem>[];

    void traverse(List<TocEntry> list, int depth) {
      for (final entry in list) {
        final matches =
            query.isEmpty ||
            entry.title.toLowerCase().contains(query.toLowerCase());
        if (matches) {
          result.add(_FlattenedTocItem(entry: entry, depth: depth));
        }
        if (entry.children.isNotEmpty) {
          traverse(entry.children, depth + 1);
        }
      }
    }

    traverse(entries, 0);
    return result;
  }
}

class _FlattenedTocItem {
  const _FlattenedTocItem({required this.entry, required this.depth});
  final TocEntry entry;
  final int depth;
}
