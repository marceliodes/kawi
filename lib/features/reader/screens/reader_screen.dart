import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
import '../widgets/tts_control_bar.dart';
import '../../tts/models/tts_models.dart';
import '../../tts/providers/tts_provider.dart';
import '../../tts/providers/voice_manager_provider.dart';
import '../../tts/screens/voice_manager_screen.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.document});

  final DocumentEntry document;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ReaderCanvasState> _canvasKey =
      GlobalKey<ReaderCanvasState>();
  late final ScrollController _scrollController;
  late final PageController _pageController;
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _itemPositionsListener;

  bool _isChromeVisible = true;
  bool _isTtsBarVisible = false;
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
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();

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
          _canvasKey.currentState?.scrollToPage(_currentPageIndex);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _isRestoring = false;
          });
        });
      }
    } catch (_) {
      // Ignored: fallback to initial page
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

    final pageChanged = _currentPageIndex != pageIndex;
    final offsetChanged = (_currentScrollOffset - offset).abs() > 0.05;

    if (pageChanged) {
      setState(() {
        _currentPageIndex = pageIndex;
        _currentScrollOffset = offset;
      });

      _resolveChapterTitle(pageIndex);
      _debounceSaveProgress(pageIndex, offset);
    } else if (offsetChanged) {
      _currentScrollOffset = offset;
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
    if (pageIndex < 0) return;
    final total = widget.document.pageCount > 0 ? widget.document.pageCount : 1;
    final clampedPage = pageIndex.clamp(0, total - 1);

    setState(() {
      _currentPageIndex = clampedPage;
      _currentScrollOffset = 0.0;
    });

    final settings = ref.read(readerSettingsProvider);
    if (settings.isPaginated) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(clampedPage);
      }
    } else {
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: clampedPage);
      } else {
        _canvasKey.currentState?.scrollToPage(clampedPage);
      }
    }

    _resolveChapterTitle(clampedPage);
    _debounceSaveProgress(clampedPage, _currentScrollOffset);
  }

  void _openTypographySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const TypographySettingsSheet(),
    );
  }

  Future<void> _startTts({String? fromSentence}) async {
    try {
      final pageContent = await ref.read(
        documentPageContentProvider((
          filePath: widget.document.filePath,
          pageIndex: _currentPageIndex,
        )).future,
      );

      if (pageContent.plainText.trim().isEmpty) return;

      var textToRead = pageContent.plainText;
      if (fromSentence != null && fromSentence.trim().isNotEmpty) {
        final idx = textToRead.indexOf(fromSentence.trim());
        if (idx != -1) {
          textToRead = textToRead.substring(idx);
        }
      }

      final ttsNotifier = ref.read(ttsStateProvider.notifier);
      ttsNotifier.loadText(textToRead);

      setState(() {
        _isTtsBarVisible = true;
      });

      ttsNotifier.play();
    } catch (e) {
      debugPrint('Error starting TTS: $e');
    }
  }

  void _toggleTts() {
    final hasInstalledModels = ref.read(hasInstalledTtsModelsProvider);
    if (!hasInstalledModels) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No TTS engine downloaded.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.isPlaying) {
      ref.read(ttsStateProvider.notifier).pause();
    } else if (ttsState.isPaused) {
      ref.read(ttsStateProvider.notifier).play();
      setState(() => _isTtsBarVisible = true);
    } else {
      if (_isTtsBarVisible) {
        setState(() => _isTtsBarVisible = false);
      } else {
        _startTts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final ttsState = ref.watch(ttsStateProvider);
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
        isPaginated: settings.isPaginated,
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
              key: _canvasKey,
              filePath: widget.document.filePath,
              pageCount: widget.document.pageCount,
              settings: settings,
              initialPageIndex: _currentPageIndex,
              initialScrollOffset: _currentScrollOffset,
              scrollController: _scrollController,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              pageController: _pageController,
              onPageChanged: _onPageOrScrollChanged,
              onToggleChrome: _toggleChrome,
              onPlayFromHere: (sentence) {
                _startTts(fromSentence: sentence);
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
                child: _buildTopAppBar(theme, ttsState),
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

          // Floating Media Control Bar for TTS
          if (_isTtsBarVisible || ttsState.isPlaying || ttsState.isPaused)
            Positioned(
              bottom: Spacing.xl + MediaQuery.paddingOf(context).bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: TtsControlBar(
                  onClose: () {
                    setState(() => _isTtsBarVisible = false);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(ReaderThemeData theme, TtsState ttsState) {
    final hasInstalledModels = ref.watch(hasInstalledTtsModelsProvider);

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

          // Read Aloud (TTS) Toggle
          IconButton(
            tooltip: hasInstalledModels
                ? 'Read Aloud (TTS)'
                : 'No TTS engine downloaded.',
            icon: PhosphorIcon(
              _isTtsBarVisible || ttsState.isPlaying
                  ? PhosphorIconsFill.speakerHigh
                  : PhosphorIconsLight.speakerHigh,
              size: 20,
              color: !hasInstalledModels
                  ? theme.textMuted.withValues(alpha: 0.35)
                  : (_isTtsBarVisible || ttsState.isPlaying
                      ? theme.accent
                      : theme.textPrimary),
            ),
            onPressed: hasInstalledModels ? _toggleTts : null,
          ),

          // Voice Manager / TTS Voices Settings
          IconButton(
            tooltip: 'Voice Settings',
            icon: PhosphorIcon(
              PhosphorIconsLight.waveform,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: () => VoiceManagerScreen.show(context),
          ),

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

/// Alias for [ReaderScreen] to support both naming conventions.
typedef DocumentViewerScreen = ReaderScreen;
