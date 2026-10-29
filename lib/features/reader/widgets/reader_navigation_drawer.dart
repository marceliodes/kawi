import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/apple_marquee_text.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/search_models.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/document_content_provider.dart';
import '../providers/highlights_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../providers/search_provider.dart';
import '../services/document_extractor.dart';
import 'highlight_note_dialog.dart';

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
        return 'Notes';
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
    this.autoFocusSearch = false,
  });

  final String documentId;
  final String filePath;
  final int currentPageIndex;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<ReadingAnchor>? onSelectAnchor;
  final bool? isPaginated;
  final NavigationDrawerTab initialTab;
  final bool autoFocusSearch;

  @override
  ConsumerState<ReaderNavigationDrawer> createState() =>
      _ReaderNavigationDrawerState();
}

class _ReaderNavigationDrawerState
    extends ConsumerState<ReaderNavigationDrawer> {
  late NavigationDrawerTab _activeTab;
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  bool _wasEscapeHandledOnKeyDown = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    ref.read(searchControllerProvider.notifier).setDocumentFilePath(widget.filePath);

    if (widget.autoFocusSearch) {
      _searchController.text = ref.read(searchControllerProvider).query;
    }

    _searchFocusNode = FocusNode(
      debugLabel: 'ReaderNavigationDrawerSearchFocusNode',
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_searchController.text.isNotEmpty || _wasEscapeHandledOnKeyDown) {
            if (event is KeyDownEvent) {
              _wasEscapeHandledOnKeyDown = true;
              _searchController.clear();
              ref.read(searchControllerProvider.notifier).clearSearch();
              setState(() {});
            } else if (event is KeyUpEvent) {
              _wasEscapeHandledOnKeyDown = false;
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    if (widget.autoFocusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
          if (_searchController.text.isNotEmpty) {
            _searchController.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _searchController.text.length,
            );
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ReaderNavigationDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      ref.read(searchControllerProvider.notifier).setDocumentFilePath(widget.filePath);
    }
    if (widget.autoFocusSearch && !oldWidget.autoFocusSearch) {
      _searchFocusNode.requestFocus();
    }
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
    final searchState = ref.watch(searchStateProvider);
    final isQueryNotEmpty = _searchController.text.trim().isNotEmpty;

    return Drawer(
      backgroundColor: theme.bgCard,
      surfaceTintColor: Colors.transparent,
      width: 360,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Top Bar: 3 Tabs & Close Button
            _buildDrawerHeader(theme),

            const Divider(height: 1),

            // In-Book Full-Text Search Input
            _buildSearchInput(theme),

            const Divider(height: 1),

            // Drawer Content: Search Results if query non-empty, else active tab body
            Expanded(
              child: isQueryNotEmpty
                  ? _buildSearchResultsBody(theme, searchState)
                  : switch (_activeTab) {
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
        horizontal: Spacing.xs,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          // Segmented Tab Selector (3 tabs)
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    tab: NavigationDrawerTab.contents,
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildTabButton(
                    tab: NavigationDrawerTab.bookmarks,
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildTabButton(
                    tab: NavigationDrawerTab.annotations,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Close Drawer Button
          IconButton(
            tooltip: 'Close',
            icon: PhosphorIcon(
              PhosphorIconsLight.x,
              size: 20,
              color: theme.textMuted,
            ),
            padding: const EdgeInsets.all(Spacing.xs),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
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
    final isSelected = _activeTab == tab && _searchController.text.trim().isEmpty;

    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tab;
          if (_searchController.text.isNotEmpty) {
            _searchController.clear();
            ref.read(searchControllerProvider.notifier).clearSearch();
          }
        });
      },
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
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
                      : tab == NavigationDrawerTab.annotations
                          ? PhosphorIconsFill.highlighterCircle
                          : PhosphorIconsFill.listBullets)
                  : tab.icon,
              size: 15.0,
              color: isSelected ? theme.accent : theme.textMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: AppleMarqueeText(
                text: tab.label,
                style: AppTypography.headline.copyWith(
                  fontSize: 12.0,
                  color: isSelected ? theme.accent : theme.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchInput(ReaderThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: widget.autoFocusSearch,
        onChanged: (val) {
          setState(() {});
          ref.read(searchControllerProvider.notifier).onQueryChanged(val);
        },
        style: AppTypography.body.copyWith(
          color: theme.textPrimary,
          fontSize: 13,
        ),
        cursorColor: theme.accent,
        decoration: InputDecoration(
          hintText: 'Search in book...',
          hintStyle: AppTypography.body.copyWith(
            color: theme.textMuted,
            fontSize: 13,
          ),
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
                  splashRadius: 14,
                  onPressed: () {
                    _searchController.clear();
                    ref.read(searchControllerProvider.notifier).clearSearch();
                    setState(() {});
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
    );
  }

  Widget _buildContentsTab({
    required ReaderThemeData theme,
    required bool showPageNumbers,
  }) {
    final tocAsync = ref.watch(documentTocProvider(widget.filePath));

    return tocAsync.when(
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

        final flattened = _flattenToc(entries);
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
    final highlightsAsync =
        ref.watch(highlightsStreamProvider(widget.documentId));

    return highlightsAsync.when(
      loading: () => Center(
        child: Text(
          'Loading Annotations...',
          style: AppTypography.micro.copyWith(color: theme.textMuted),
        ),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(
            'Failed to load Annotations: $err',
            style: AppTypography.body.copyWith(color: theme.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (highlights) {
        if (highlights.isEmpty) {
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
                  'No Highlights or Notes Yet',
                  style: AppTypography.headline.copyWith(
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.xxs),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.xl),
                  child: Text(
                    'Select any text in the reader to highlight or add notes.',
                    style: AppTypography.micro
                        .copyWith(color: theme.textMuted),
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
          itemCount: highlights.length,
          separatorBuilder: (_, _) => const SizedBox(height: Spacing.xs),
          itemBuilder: (context, index) {
            final highlight = highlights[index];
            return _buildHighlightCard(
              theme: theme,
              highlight: highlight,
            );
          },
        );
      },
    );
  }

  Widget _buildHighlightCard({
    required ReaderThemeData theme,
    required Highlight highlight,
  }) {
    final chapterTitleAsync = ref.watch(
      documentChapterTitleProvider((
        filePath: widget.filePath,
        chapterIndex: highlight.startAnchor.chapterIndex,
      )),
    );
    final chapterTitle = chapterTitleAsync.asData?.value;

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
              widget.onSelectAnchor!(highlight.startAnchor);
            } else {
              widget.onSelectPage(highlight.startAnchor.chapterIndex);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: Color indicator, Chapter title, and Action buttons
                Row(
                  children: [
                    // Color indicator
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: highlight.isUnderline
                            ? Colors.transparent
                            : highlight.displayColor,
                        shape: BoxShape.circle,
                        border: highlight.isUnderline
                            ? Border.all(color: theme.accent, width: 1.5)
                            : Border.all(color: Colors.black26, width: 0.8),
                      ),
                      child: highlight.isUnderline
                          ? Center(
                              child: Text(
                                'U',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: theme.accent,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        chapterTitle?.isNotEmpty == true
                            ? chapterTitle!
                            : 'Chapter ${highlight.startAnchor.chapterIndex + 1}',
                        style: AppTypography.headline.copyWith(
                          fontSize: 13,
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Edit Note Button
                    IconButton(
                      tooltip:
                          highlight.note != null ? 'Edit note' : 'Add note',
                      icon: PhosphorIcon(
                        highlight.note != null
                            ? PhosphorIconsFill.chatTeardropText
                            : PhosphorIconsLight.chatTeardropText,
                        size: 16,
                        color: highlight.note != null
                            ? theme.accent
                            : theme.textMuted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        HighlightNoteDialog.show(
                          context,
                          selectedText: highlight.highlightedText,
                          initialColorHex: highlight.colorHex,
                          initialNote: highlight.note,
                          onSave: (colorHex, note) async {
                            await ref
                                .read(highlightsControllerProvider)
                                .updateNote(
                                  highlight.id,
                                  note.isNotEmpty ? note : null,
                                );
                            await ref
                                .read(highlightsControllerProvider)
                                .updateColor(
                                  highlight.id,
                                  colorHex,
                                );
                          },
                          onDelete: () async {
                            await ref
                                .read(highlightsControllerProvider)
                                .deleteHighlight(highlight.id);
                          },
                        );
                      },
                    ),
                    const SizedBox(width: Spacing.xs),
                    // Delete Highlight Button
                    IconButton(
                      tooltip: 'Delete highlight',
                      icon: PhosphorIcon(
                        PhosphorIconsLight.trash,
                        size: 16,
                        color: theme.textMuted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        ref
                            .read(highlightsControllerProvider)
                            .deleteHighlight(highlight.id);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.xxs),

                // Quoted excerpt
                Container(
                  padding: const EdgeInsets.only(left: Spacing.xs),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: highlight.displayColor,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Text(
                    '“${highlight.highlightedText}”',
                    style: AppTypography.body.copyWith(
                      fontSize: 12,
                      color: theme.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // User note bubble if present
                if (highlight.note != null && highlight.note!.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.bgCard,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: theme.borderSubtle),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PhosphorIcon(
                          PhosphorIconsFill.notePencil,
                          size: 13,
                          color: theme.accent,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Expanded(
                          child: Text(
                            highlight.note!,
                            style: AppTypography.body.copyWith(
                              fontSize: 12,
                              color: theme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: Spacing.xs),

                // Timestamp
                Text(
                  _formatDate(highlight.createdAt),
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

  Widget _buildSearchResultsBody(
    ReaderThemeData theme,
    SearchState searchState,
  ) {
    return Column(
      children: [
        // Result count or progress header
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xxs,
          ),
          alignment: Alignment.centerLeft,
          color: theme.bgCard.withValues(alpha: 0.5),
          child: Row(
            children: [
              if (searchState.isSearching) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.accent,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
              ],
              Text(
                searchState.isSearching
                    ? 'Searching (${searchState.totalMatches} found)…'
                    : '${searchState.totalMatches} ${searchState.totalMatches == 1 ? "match" : "matches"} found',
                style: AppTypography.micro.copyWith(
                  color: theme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Results list or Empty State
        Expanded(
          child: _buildSearchResultsContent(theme, searchState),
        ),
      ],
    );
  }

  Widget _buildSearchResultsContent(
    ReaderThemeData theme,
    SearchState searchState,
  ) {
    if (!searchState.isSearching && searchState.matches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsLight.magnifyingGlass,
                size: 40,
                color: theme.textMuted.withValues(alpha: 0.4),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'No Results Found',
                style: AppTypography.headline.copyWith(
                  color: theme.textPrimary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'No matches found for "${_searchController.text.trim()}". Try a different search term.',
                textAlign: TextAlign.center,
                style: AppTypography.micro.copyWith(
                  color: theme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      itemCount: searchState.groups.length,
      itemBuilder: (context, groupIdx) {
        final group = searchState.groups[groupIdx];
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Chapter header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xs,
                  vertical: Spacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.chapterTitle?.isNotEmpty == true
                            ? group.chapterTitle!
                            : 'Chapter ${group.chapterIndex + 1}',
                        style: AppTypography.headline.copyWith(
                          color: theme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${group.count}',
                        style: AppTypography.micro.copyWith(
                          color: theme.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Match cards in this chapter
              ...group.matches.map((match) {
                final isCurrentActive =
                    searchState.activeMatch?.id == match.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: InkWell(
                    onTap: () {
                      ref
                          .read(searchControllerProvider.notifier)
                          .selectMatch(match);
                      widget.onSelectAnchor?.call(match.startAnchor);
                      if (widget.onSelectAnchor == null) {
                        widget.onSelectPage(match.startAnchor.chapterIndex);
                      }
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: Container(
                      padding: const EdgeInsets.all(Spacing.xs),
                      decoration: BoxDecoration(
                        color: isCurrentActive
                            ? theme.accent.withValues(alpha: 0.10)
                            : theme.bgCard,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(
                          color: isCurrentActive
                              ? theme.accent.withValues(alpha: 0.5)
                              : (theme.isDark ? Colors.white10 : Colors.black12),
                        ),
                      ),
                      child: _buildSnippetRichText(theme, match),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSnippetRichText(ReaderThemeData theme, SearchMatch match) {
    final snippet = match.snippet;
    final start = match.snippetMatchStart.clamp(0, snippet.length);
    final end = match.snippetMatchEnd.clamp(0, snippet.length);

    if (start >= end) {
      return Text(
        snippet,
        style: AppTypography.body.copyWith(
          color: theme.textPrimary,
          fontSize: 12,
        ),
      );
    }

    final before = snippet.substring(0, start);
    final term = snippet.substring(start, end);
    final after = snippet.substring(end);

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: AppTypography.body.copyWith(
          color: theme.textMuted,
          fontSize: 12,
          height: 1.4,
        ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: term,
            style: TextStyle(
              color: theme.isDark ? Colors.white : Colors.black,
              backgroundColor: theme.isDark
                  ? const Color(0xFFFF9800).withValues(alpha: 0.5)
                  : const Color(0xFFFFD54F).withValues(alpha: 0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }

  List<_FlattenedTocItem> _flattenToc(List<TocEntry> entries) {
    final result = <_FlattenedTocItem>[];

    void traverse(List<TocEntry> list, int depth) {
      for (final entry in list) {
        result.add(_FlattenedTocItem(entry: entry, depth: depth));
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
