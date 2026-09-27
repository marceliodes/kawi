import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../providers/document_content_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../services/document_extractor.dart';
import '../widgets/reader_canvas.dart';
import '../widgets/toc_drawer.dart';
import '../widgets/typography_settings_sheet.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.document});

  final DocumentEntry document;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ScrollController _scrollController;
  late final PageController _pageController;

  bool _isChromeVisible = true;
  Timer? _autoHideTimer;
  Timer? _progressSaveDebounce;

  int _currentPageIndex = 0;
  double _currentScrollOffset = 0.0;
  String? _currentChapterTitle;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _pageController = PageController();

    _loadInitialProgress();
  }

  Future<void> _loadInitialProgress() async {
    try {
      final db = ref.read(databaseProvider);

      // Update lastReadAt for the document
      await db.insertOrUpdateDocument(
        widget.document
            .toCompanion(true)
            .copyWith(lastReadAt: Value(DateTime.now())),
      );

      // Retrieve saved progress
      final progress = await db.getProgressForDocument(widget.document.id);
      if (progress != null && mounted) {
        _isRestoring = true;
        setState(() {
          _currentPageIndex = progress.lastReadPageIndex.clamp(
            0,
            widget.document.pageCount > 0 ? widget.document.pageCount - 1 : 0,
          );
          _currentScrollOffset = progress.lastReadScrollOffset;
          _currentChapterTitle = progress.currentChapter;
        });

        // Restore scroll or page position after layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final settings = ref.read(readerSettingsProvider);
          if (settings.isPaginated) {
            if (_pageController.hasClients && _currentPageIndex > 0) {
              _pageController.jumpToPage(_currentPageIndex);
            }
          } else {
            if (_scrollController.hasClients && _currentScrollOffset > 0) {
              _scrollController.jumpTo(_currentScrollOffset);
            }
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _isRestoring = false;
          });
        });
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('LOAD ERROR: $e\n$st');
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _progressSaveDebounce?.cancel();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() {
      _isChromeVisible = !_isChromeVisible;
    });
  }

  void _showChrome() {
    if (!_isChromeVisible) {
      setState(() => _isChromeVisible = true);
    }
  }

  void _onPageOrScrollChanged(int pageIndex, double offset) {
    if (_isRestoring) return;

    if (_currentPageIndex != pageIndex ||
        (_currentScrollOffset - offset).abs() > 20) {
      setState(() {
        _currentPageIndex = pageIndex;
        _currentScrollOffset = offset;
      });

      _resolveChapterTitle(pageIndex);
      _debounceSaveProgress(pageIndex, offset);
    }
  }

  void _resolveChapterTitle(int pageIndex) {
    final tocAsync = ref.read(documentTocProvider(widget.document.filePath));
    tocAsync.whenData((entries) {
      String? found;
      void find(List<TocEntry> list) {
        for (final item in list) {
          if (item.pageIndex <= pageIndex) {
            found = item.title;
          }
          if (item.children.isNotEmpty) {
            find(item.children);
          }
        }
      }

      find(entries);
      if (found != null && found != _currentChapterTitle && mounted) {
        setState(() => _currentChapterTitle = found);
      }
    });
  }

  void _debounceSaveProgress(int pageIndex, double offset) {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final db = ref.read(databaseProvider);
        await db.updateProgress(
          ReadingProgressesCompanion.insert(
            documentId: widget.document.id,
            lastReadPageIndex: Value(pageIndex),
            lastReadScrollOffset: Value(offset),
            currentChapter: Value(_currentChapterTitle),
            updatedAt: DateTime.now(),
          ),
        );
      } catch (_) {}
    });
  }

  void _navigateToPage(int pageIndex) {
    final settings = ref.read(readerSettingsProvider);
    setState(() {
      _currentPageIndex = pageIndex;
      _currentScrollOffset = 0.0;
    });

    if (settings.isPaginated) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(pageIndex);
      }
    } else {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final total = widget.document.pageCount > 0
            ? widget.document.pageCount
            : 1;
        final targetOffset = (pageIndex / total) * maxScroll;
        _scrollController.jumpTo(targetOffset);
      }
    }

    _resolveChapterTitle(pageIndex);
    _debounceSaveProgress(pageIndex, _currentScrollOffset);
  }

  void _openTypographySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const TypographySettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final totalPages = widget.document.pageCount > 0
        ? widget.document.pageCount
        : 1;
    final progressPercent = (((_currentPageIndex + 1) / totalPages) * 100)
        .clamp(0, 100)
        .round();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.bgCanvas,
      drawer: TocDrawer(
        filePath: widget.document.filePath,
        currentPageIndex: _currentPageIndex,
        onSelectPage: _navigateToPage,
      ),
      body: Stack(
        children: [
          // Top edge hover detector to reveal chrome
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 32,
            child: MouseRegion(
              onHover: (_) => _showChrome(),
              child: const SizedBox.expand(),
            ),
          ),

          // Main Reading Canvas
          Positioned.fill(
            child: ReaderCanvas(
              filePath: widget.document.filePath,
              pageCount: widget.document.pageCount,
              settings: settings,
              initialPageIndex: _currentPageIndex,
              initialScrollOffset: _currentScrollOffset,
              scrollController: _scrollController,
              pageController: _pageController,
              onPageChanged: _onPageOrScrollChanged,
              onToggleChrome: _toggleChrome,
              onPlayFromHere: (sentence) {
                // Hook for Phase 5 / 6 audio dock integration
              },
            ),
          ),

          // Auto-hiding Top Navigation Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              offset: _isChromeVisible ? Offset.zero : const Offset(0, -1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isChromeVisible ? 1.0 : 0.0,
                child: _buildTopAppBar(theme),
              ),
            ),
          ),

          // Auto-hiding Bottom Progress Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              offset: _isChromeVisible ? Offset.zero : const Offset(0, 1),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isChromeVisible ? 1.0 : 0.0,
                child: _buildBottomStatus(theme, progressPercent, totalPages),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(ReaderThemeData theme) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + Spacing.xs,
        bottom: Spacing.xs,
        left: Spacing.md,
        right: Spacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.bgCard.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: theme.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back to Library Button
          IconButton(
            tooltip: 'Back to Library',
            icon: PhosphorIcon(
              PhosphorIconsLight.arrowLeft,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),

          // Table of Contents Toggle
          IconButton(
            tooltip: 'Table of Contents',
            icon: PhosphorIcon(
              PhosphorIconsLight.listBullets,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),

          const SizedBox(width: Spacing.xs),

          // Document Title and Active Chapter
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.document.title,
                  style: AppTypography.headline.copyWith(
                    color: theme.textPrimary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (_currentChapterTitle != null &&
                    _currentChapterTitle!.isNotEmpty)
                  Text(
                    _currentChapterTitle!,
                    style: AppTypography.micro.copyWith(
                      color: theme.textMuted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),

          const SizedBox(width: Spacing.xs),

          // Typography & Appearance Settings Toggle
          IconButton(
            tooltip: 'Appearance & Typography',
            icon: PhosphorIcon(
              PhosphorIconsLight.textAa,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: _openTypographySheet,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatus(
    ReaderThemeData theme,
    int progressPercent,
    int totalPages,
  ) {
    return Container(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.xs,
        bottom: MediaQuery.paddingOf(context).bottom + Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.bgCard.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: theme.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _currentChapterTitle ?? 'Reading',
            style: AppTypography.micro.copyWith(
              color: theme.textMuted,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Page ${_currentPageIndex + 1} of $totalPages ($progressPercent%)',
            style: AppTypography.micro.copyWith(
              color: theme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
