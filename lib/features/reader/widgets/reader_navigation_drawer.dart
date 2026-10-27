import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../models/bookmark.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/document_content_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../services/document_extractor.dart';

enum NavigationDrawerTab {
  contents,
  bookmarks,
  annotations;

  String get label {
    switch (this) {
      case NavigationDrawerTab.contents:
        return 'Contents';
      case NavigationDrawerTab.bookmarks:
        return 'Bookmarks';
      case NavigationDrawerTab.annotations:
        return 'Notes & Highlights';
    }
  }

  PhosphorIconData get icon {
    switch (this) {
      case NavigationDrawerTab.contents:
        return PhosphorIconsLight.listBullets;
      case NavigationDrawerTab.bookmarks:
        return PhosphorIconsLight.bookmarkSimple;
      case NavigationDrawerTab.annotations:
        return PhosphorIconsLight.highlighterCircle;
    }
  }
}

class ReaderNavigationDrawer extends ConsumerStatefulWidget {
  const ReaderNavigationDrawer({
    super.key,
    required this.documentId,
    required this.filePath,
    required this.currentPageIndex,
    required this.onSelectPage,
    this.onSelectAnchor,
    this.isPaginated,
    this.initialTab = NavigationDrawerTab.contents,
  });

  final String documentId;
  final String filePath;
  final int currentPageIndex;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<ReadingAnchor>? onSelectAnchor;
  final bool? isPaginated;
  final NavigationDrawerTab initialTab;

  @override
  ConsumerState<ReaderNavigationDrawer> createState() =>
      _ReaderNavigationDrawerState();
}

class _ReaderNavigationDrawerState
    extends ConsumerState<ReaderNavigationDrawer> {
  late NavigationDrawerTab _activeTab;
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  String _filterQuery = '';
  bool _wasEscapeHandledOnKeyDown = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _searchFocusNode = FocusNode(
      debugLabel: 'ReaderNavigationDrawerSearchFocusNode',
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_searchController.text.isNotEmpty || _wasEscapeHandledOnKeyDown) {
            if (event is KeyDownEvent) {
              _wasEscapeHandledOnKeyDown = true;
              _searchController.clear();
              setState(() => _filterQuery = '');
            } else if (event is KeyUpEvent) {
              _wasEscapeHandledOnKeyDown = false;
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final showPageNumbers = widget.isPaginated ?? settings.isPaginated;

    return Drawer(
      backgroundColor: theme.bgCard,
      surfaceTintColor: Colors.transparent,
      width: 360,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Top Bar: Tabs & Close Button
            _buildDrawerHeader(theme),

            const Divider(height: 1),

            // Drawer Content based on active tab
            Expanded(
              child: switch (_activeTab) {
                NavigationDrawerTab.contents => _buildContentsTab(
                  theme: theme,
                  showPageNumbers: showPageNumbers,
                ),
                NavigationDrawerTab.bookmarks => _buildBookmarksTab(theme),
                NavigationDrawerTab.annotations => _buildAnnotationsTab(theme),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(ReaderThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          // Segmented Tab Selector
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    tab: NavigationDrawerTab.contents,
                    theme: theme,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: _buildTabButton(
                    tab: NavigationDrawerTab.bookmarks,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),

          // Close Drawer Button
          IconButton(
            tooltip: 'Close',
            icon: PhosphorIcon(
              PhosphorIconsLight.x,
              size: 20,
              color: theme.textMuted,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required NavigationDrawerTab tab,
    required ReaderThemeData theme,
  }) {
    final isSelected = _activeTab == tab;

    return InkWell(
      onTap: () {
        if (_activeTab != tab) {
          setState(() => _activeTab = tab);
        }
      },
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PhosphorIcon(
              isSelected
                  ? (tab == NavigationDrawerTab.bookmarks
                      ? PhosphorIconsFill.bookmarkSimple
                      : PhosphorIconsFill.listBullets)
                  : tab.icon,
              size: 16,
              color: isSelected ? theme.accent : theme.textMuted,
            ),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                tab.label,
                style: AppTypography.headline.copyWith(
                  fontSize: 13,
                  color: isSelected ? theme.accent : theme.textMuted,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentsTab({
    required ReaderThemeData theme,
    required bool showPageNumbers,
  }) {
    final tocAsync = ref.watch(documentTocProvider(widget.filePath));

    return Column(
      children: [
        // Search Filter Input
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs,
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (val) => setState(() => _filterQuery = val.trim()),
            style: AppTypography.body.copyWith(color: theme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search chapters...',
              hintStyle: AppTypography.body.copyWith(color: theme.textMuted),
              prefixIcon: PhosphorIcon(
                PhosphorIconsLight.magnifyingGlass,
                size: 16,
                color: theme.textMuted,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: PhosphorIcon(
                        PhosphorIconsLight.x,
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
        const Divider(height: Spacing.xs),

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
                  style: AppTypography.body.copyWith(color: theme.textMuted),
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
                    style: AppTypography.body.copyWith(color: theme.textMuted),
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
          if (widget.onSelectAnchor != null) {
            widget.onSelectAnchor!(ReadingAnchor(
              chapterIndex: item.entry.pageIndex,
              paragraphIndex: 0,
              charOffset: 0,
            ));
          } else {
            widget.onSelectPage(item.entry.pageIndex);
          }
        }
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

  Widget _buildBookmarksTab(ReaderThemeData theme) {
    final bookmarksAsync = ref.watch(bookmarksStreamProvider(widget.documentId));

    return bookmarksAsync.when(
      loading: () => Center(
        child: Text(
          'Loading Bookmarks...',
          style: AppTypography.micro.copyWith(color: theme.textMuted),
        ),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(
            'Failed to load Bookmarks: $err',
            style: AppTypography.body.copyWith(color: theme.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (bookmarks) {
        if (bookmarks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  PhosphorIconsLight.bookmarkSimple,
                  size: 48,
                  color: theme.textMuted,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'No Bookmarks Yet',
                  style: AppTypography.headline.copyWith(
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
                  child: Text(
                    'Press Ctrl+D or tap the bookmark icon in the top bar to save your position.',
                    style: AppTypography.micro.copyWith(color: theme.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          itemCount: bookmarks.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.xs),
          itemBuilder: (context, index) {
            final bookmark = bookmarks[index];
            return _buildBookmarkCard(
              theme: theme,
              bookmark: bookmark,
            );
          },
        );
      },
    );
  }

  Widget _buildBookmarkCard({
    required ReaderThemeData theme,
    required Bookmark bookmark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () {
            if (widget.onSelectAnchor != null) {
              widget.onSelectAnchor!(bookmark.anchor);
            } else {
              widget.onSelectPage(bookmark.anchor.chapterIndex);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: Chapter title & Delete button
                Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsFill.bookmarkSimple,
                      size: 14,
                      color: theme.accent,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        bookmark.chapterTitle?.isNotEmpty == true
                            ? bookmark.chapterTitle!
                            : 'Chapter ${bookmark.anchor.chapterIndex + 1}',
                        style: AppTypography.headline.copyWith(
                          fontSize: 13,
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete bookmark',
                      icon: PhosphorIcon(
                        PhosphorIconsLight.trash,
                        size: 16,
                        color: theme.textMuted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        ref
                            .read(bookmarksControllerProvider)
                            .removeBookmark(bookmark.id);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.xxs),

                // Snippet text preview
                Text(
                  bookmark.snippet,
                  style: AppTypography.body.copyWith(
                    fontSize: 12,
                    color: theme.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.xs),

                // Timestamp
                Text(
                  _formatDate(bookmark.createdAt),
                  style: AppTypography.micro.copyWith(
                    color: theme.textMuted.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnotationsTab(ReaderThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            PhosphorIconsLight.highlighterCircle,
            size: 48,
            color: theme.textMuted,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Notes & Highlights',
            style: AppTypography.headline.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            'Coming soon in a future update.',
            style: AppTypography.micro.copyWith(color: theme.textMuted),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:$minute $ampm';
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
