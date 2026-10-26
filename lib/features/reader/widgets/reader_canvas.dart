import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../constants/reader_layout_constants.dart';
import '../models/document_models.dart';
import '../models/reader_settings.dart';
import '../providers/document_content_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../../tts/models/tts_models.dart';
import '../../tts/providers/tts_provider.dart';
import '../../tts/services/tts_text_normalizer.dart';

class ReaderCanvas extends ConsumerStatefulWidget {
  const ReaderCanvas({
    super.key,
    required this.filePath,
    required this.pageCount,
    required this.settings,
    required this.initialPageIndex,
    this.initialChapterIndex,
    required this.initialScrollOffset,
    this.scrollController,
    this.itemScrollController,
    this.itemPositionsListener,
    required this.pageController,
    required this.onPageChanged,
    required this.onToggleChrome,
    this.onPlayFromHere,
    this.epubChunks,
    this.epubNodes,
    this.isEpub,
    this.chapterIndex,
    this.pageIndexInChapter,
    this.onNextChapter,
    this.onPreviousChapter,
    this.onEpubPageChanged,
    this.onChapterChanged,
    this.isUserDesyncedFromTts = false,
    this.onUserNavigated,
    this.onSpeakingPageDiscovered,
    this.onToggleTts,
    this.isTtsBarVisible = false,
  });

  final String filePath;
  final int pageCount;
  final ReaderSettings settings;
  final int initialPageIndex;
  final int? initialChapterIndex;
  final double initialScrollOffset;
  final ScrollController? scrollController;
  final ItemScrollController? itemScrollController;
  final ItemPositionsListener? itemPositionsListener;
  final PageController pageController;
  final void Function(int pageIndex, double offset) onPageChanged;
  final VoidCallback onToggleChrome;
  final ValueChanged<String>? onPlayFromHere;
  final VoidCallback? onToggleTts;
  final bool isTtsBarVisible;

  // EPUB Reflow Engine integration properties
  final List<PageChunk>? epubChunks;
  final List<DocumentNode>? epubNodes;
  final bool? isEpub;
  final int? chapterIndex;
  final int? pageIndexInChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onPreviousChapter;
  final void Function(int chapterIndex, int pageIndexInChapter)? onEpubPageChanged;
  final ValueChanged<int>? onChapterChanged;

  // Decoupled TTS & Navigation properties
  final bool isUserDesyncedFromTts;
  final VoidCallback? onUserNavigated;
  final void Function(int chapterIndex, int pageIndexInChapter)?
      onSpeakingPageDiscovered;

  @override
  ConsumerState<ReaderCanvas> createState() => ReaderCanvasState();
}

class ReaderCanvasState extends ConsumerState<ReaderCanvas> {
  final FocusNode _focusNode = FocusNode();
  ItemScrollController? _internalItemScrollController;
  ItemPositionsListener? _internalItemPositionsListener;

  bool get _isEpub =>
      widget.isEpub == true || widget.filePath.toLowerCase().endsWith('.epub');

  PageController? _epubPageController;
  Timer? _oldControllerDisposalTimer;
  PageController? _pendingDisposalController;
  int? _lastPageSentinelConsumedForChapter;
  int? _paginatedChapterIndex;

  int get _currentEpubPage =>
      _currentPageIndexInChapter >= 0 ? _currentPageIndexInChapter : 0;

  bool get _shouldUseInternalEpubPageController =>
      widget.onNextChapter != null ||
      widget.pageCount > 1 ||
      widget.epubChunks == null;

  PageController get _effectiveEpubPageController =>
      _shouldUseInternalEpubPageController
          ? (_epubPageController ?? widget.pageController)
          : widget.pageController;

  PageController? get epubPageController => _effectiveEpubPageController;

  bool get _isEpubPageControllerReady =>
      _effectiveEpubPageController.hasClients &&
      _effectiveEpubPageController.positions.length == 1;

  bool get isEpubPageControllerReady => _isEpubPageControllerReady;

  bool get _isPageControllerReady =>
      widget.pageController.hasClients &&
      widget.pageController.positions.length == 1;

  static const double _kTrackpadSwipeThreshold = 50.0;
  static const Duration _kTrackpadCooldown = Duration(milliseconds: 380);

  double _accumulatedTrackpadDelta = 0.0;
  bool _isPanGestureActive = false;
  bool _isPanLatched = false;
  bool _isScrollLatched = false;
  Timer? _scrollLatchResetTimer;
  DateTime _lastTrackpadPageTurnTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOverscrollNavTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _resetGestureLatch() {
    _isPanGestureActive = false;
    _isPanLatched = false;
    _isScrollLatched = false;
    _scrollLatchResetTimer?.cancel();
    _scrollLatchResetTimer = null;
    _accumulatedTrackpadDelta = 0.0;
  }

  void _handleTrackpadDelta(double delta, {bool isPanZoom = false}) {
    if (!widget.settings.isPaginated) return;
    if (delta == 0) return;

    final now = clock.now();

    // 1. Momentum latch / cooldown immediately after triggering a page turn
    // (absorb subsequent inertial scroll events to prevent inertia flinging on desktop).
    if (isPanZoom) {
      if (_isPanGestureActive && _isPanLatched) {
        _accumulatedTrackpadDelta = 0.0;
        return;
      }
    } else {
      if (_isScrollLatched ||
          now.difference(_lastTrackpadPageTurnTime) < _kTrackpadCooldown) {
        _accumulatedTrackpadDelta = 0.0;
        if (delta.abs() < 1.0 &&
            now.difference(_lastTrackpadPageTurnTime) >=
                const Duration(milliseconds: 150)) {
          _isScrollLatched = false;
        }
        return;
      }
    }

    // 2. Clear accumulated delta on direction change
    if ((_accumulatedTrackpadDelta > 0 && delta < 0) ||
        (_accumulatedTrackpadDelta < 0 && delta > 0)) {
      _accumulatedTrackpadDelta = 0.0;
    }

    // 3. Accumulate delta
    _accumulatedTrackpadDelta += delta;

    // 4. Check threshold
    if (_accumulatedTrackpadDelta >= _kTrackpadSwipeThreshold) {
      // Swipe left (scrollDelta > 0 or panDelta < 0) navigates to the next page
      _accumulatedTrackpadDelta = 0.0;
      _lastTrackpadPageTurnTime = now;
      if (isPanZoom) {
        _isPanLatched = true;
      } else {
        _isScrollLatched = true;
        _scrollLatchResetTimer?.cancel();
        _scrollLatchResetTimer = Timer(_kTrackpadCooldown, () {
          if (mounted) {
            _isScrollLatched = false;
          }
        });
      }
      widget.onUserNavigated?.call();
      goToNextPage();
    } else if (_accumulatedTrackpadDelta <= -_kTrackpadSwipeThreshold) {
      // Swipe right (scrollDelta < 0 or panDelta > 0) navigates to the previous page
      _accumulatedTrackpadDelta = 0.0;
      _lastTrackpadPageTurnTime = now;
      if (isPanZoom) {
        _isPanLatched = true;
      } else {
        _isScrollLatched = true;
        _scrollLatchResetTimer?.cancel();
        _scrollLatchResetTimer = Timer(_kTrackpadCooldown, () {
          if (mounted) {
            _isScrollLatched = false;
          }
        });
      }
      widget.onUserNavigated?.call();
      goToPreviousPage();
    }
  }

  void _toggleTtsPlayback() {
    if (widget.onToggleTts != null) {
      widget.onToggleTts!();
      return;
    }
    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.isPlaying) {
      ref.read(ttsStateProvider.notifier).pause();
    } else if (ttsState.isPaused) {
      ref.read(ttsStateProvider.notifier).play();
    } else {
      final snippet = getFirstVisibleTextSnippet();
      widget.onPlayFromHere?.call(snippet ?? '');
    }
  }

  void _seekForwardTts() {
    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.totalSentences > 0) {
      ref.read(ttsStateProvider.notifier).nextSentence();
    }
  }

  void _seekBackwardTts() {
    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.totalSentences > 0) {
      final isUnderway = ttsState.isPlaying &&
          (ttsState.activeWordStart > 0 || ttsState.currentWord.isNotEmpty);
      if (isUnderway) {
        ref.read(ttsStateProvider.notifier).seekSentence(ttsState.currentSentenceIndex);
      } else {
        ref.read(ttsStateProvider.notifier).previousSentence();
      }
    }
  }

  bool _onOverscroll(OverscrollNotification notification, int pageCount) {
    if (notification.dragDetails == null) return false;
    final now = clock.now();
    if (now.difference(_lastOverscrollNavTime).inMilliseconds < 500) return false;

    if (notification.overscroll < -5.0 && _currentEpubPage == 0) {
      _lastOverscrollNavTime = now;
      goToPreviousPage();
      return true;
    } else if (notification.overscroll > 5.0 && _currentEpubPage >= pageCount - 1) {
      _lastOverscrollNavTime = now;
      goToNextPage();
      return true;
    }
    return false;
  }

  void _recreateEpubPageController(int initialPage, [int? maxPages]) {
    final effectiveMax = maxPages ??
        ((_paginatedChapterIndex == _currentChapterIndex &&
                _effectivePages.isNotEmpty)
            ? _effectivePages.length
            : null);
    final clamped = (effectiveMax != null && effectiveMax > 0)
        ? initialPage.clamp(0, effectiveMax - 1)
        : (initialPage < 0 ? 0 : initialPage);
    final oldController = _epubPageController;
    _epubPageController = PageController(initialPage: clamped);
    if (oldController != null) {
      _oldControllerDisposalTimer?.cancel();
      _pendingDisposalController?.dispose();
      _pendingDisposalController = oldController;
      _oldControllerDisposalTimer = Timer(const Duration(milliseconds: 250), () {
        _pendingDisposalController?.dispose();
        _pendingDisposalController = null;
        _oldControllerDisposalTimer = null;
      });
    }
  }

  double? _safeGetPage(PageController? controller) {
    if (controller == null || !controller.hasClients || controller.positions.length != 1) {
      return null;
    }
    try {
      final pos = controller.position;
      if (pos.hasPixels && pos.hasViewportDimension && pos.hasContentDimensions) {
        return controller.page;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  double? safeGetEpubPage() => _safeGetPage(_effectiveEpubPageController);
  double? safeGetPage() => _safeGetPage(widget.pageController);

  void requestFocus() {
    _focusNode.requestFocus();
  }

  FocusNode get focusNode => _focusNode;

  void animateToPageInChapter(
    int pageIndex, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeInOut,
  }) {
    if (!mounted) return;
    _focusNode.requestFocus();
    _currentPageIndexInChapter = pageIndex;
    final controller = _isEpub ? _effectiveEpubPageController : widget.pageController;
    final isReady = _isEpub ? _isEpubPageControllerReady : _isPageControllerReady;
    final curPage = _safeGetPage(controller);
    if (isReady && curPage?.round() != pageIndex) {
      controller.animateToPage(pageIndex, duration: duration, curve: curve);
    }
  }

  void jumpToPageInChapter(int pageIndex) {
    if (!mounted) return;
    _focusNode.requestFocus();
    final pages = _effectivePages;
    final int resolved;
    if (pageIndex == -1) {
      resolved = pages.isNotEmpty ? pages.length - 1 : -1;
      _lastPageSentinelConsumedForChapter = _currentChapterIndex;
    } else if (pages.isEmpty) {
      resolved = pageIndex;
    } else {
      resolved = pageIndex.clamp(0, pages.length - 1);
    }
    _currentPageIndexInChapter = resolved;
    final controller = _isEpub ? _effectiveEpubPageController : widget.pageController;
    final isReady = _isEpub ? _isEpubPageControllerReady : _isPageControllerReady;
    final curPage = _safeGetPage(controller);
    if (isReady && resolved >= 0) {
      if (curPage?.round() != resolved) {
        controller.jumpToPage(resolved);
      }
    } else if (_isEpub && resolved >= 0) {
      _recreateEpubPageController(
        resolved,
        pages.isNotEmpty ? pages.length : null,
      );
    }
  }

  int _currentChapterIndex = 0;
  int _currentPageIndexInChapter = 0;
  List<PageChunk> _currentChapterPages = const [];
  PaginationParams? _lastPaginationParams;

  List<PageChunk> get _effectivePages {
    if (_currentChapterPages.isNotEmpty) return _currentChapterPages;
    if (widget.epubChunks != null && widget.epubChunks!.isNotEmpty) {
      return widget.epubChunks!;
    }
    return const [];
  }

  bool _isProgrammaticNavigation = false;
  bool _isProgrammaticReanchoring = false;
  bool _isUserScrolling = false;
  Timer? _userScrollDebounceTimer;
  Timer? _continuousAnchorDebounceTimer;
  ReadingAnchor? _pendingContinuousScrollAnchor;
  int _lastSentenceIndexDuringUserScroll = -1;
  Timer? _prewarmTimer;

  void _onUserScrollStarted() {
    _isUserScrolling = true;
    _userScrollDebounceTimer?.cancel();
    final ttsState = ref.read(ttsStateProvider);
    _lastSentenceIndexDuringUserScroll = ttsState.currentSentenceIndex;
  }

  void _scheduleUserScrollEnded() {
    _userScrollDebounceTimer?.cancel();
    _userScrollDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _isUserScrolling = false;
      }
    });
  }

  void _onUserScrollEnded() {
    _scheduleUserScrollEnded();
  }

  bool get isAutoScrollSuspendedByUser {
    if (_isUserScrolling) return true;
    final ttsState = ref.read(ttsStateProvider);
    return _lastSentenceIndexDuringUserScroll != -1 &&
        _lastSentenceIndexDuringUserScroll == ttsState.currentSentenceIndex;
  }

  ItemScrollController get _effectiveItemScrollController =>
      widget.itemScrollController ??
      (_internalItemScrollController ??= ItemScrollController());

  ItemPositionsListener get _effectiveItemPositionsListener =>
      widget.itemPositionsListener ??
      (_internalItemPositionsListener ??= ItemPositionsListener.create());

  void _schedulePrewarmAdjacentChapters() {
    _prewarmTimer?.cancel();
    _prewarmTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _prewarmAdjacentChapters();
      }
    });
  }

  void _setProgrammaticScroll(bool isProg) {
    _isProgrammaticNavigation = isProg;
  }

  final Set<_EpubScopedNodeWidgetState> _activeNodeStates = {};

  void _registerNodeState(_EpubScopedNodeWidgetState state) {
    _activeNodeStates.add(state);
    if (_pendingContinuousScrollAnchor != null &&
        state.widget.chapterIndex == _pendingContinuousScrollAnchor!.chapterIndex &&
        state.widget.paragraphIndex == _pendingContinuousScrollAnchor!.paragraphIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pendingContinuousScrollAnchor != null) {
          final scrolled = _scrollToAnchorNode(_pendingContinuousScrollAnchor!);
          if (scrolled) {
            _pendingContinuousScrollAnchor = null;
          }
        }
      });
    }
  }

  void _unregisterNodeState(_EpubScopedNodeWidgetState state) {
    _activeNodeStates.remove(state);
  }

  bool _scrollToAnchorNode(ReadingAnchor anchor, {bool jump = true}) {
    if (!mounted) return false;

    _EpubScopedNodeWidgetState? targetState;
    for (final state in _activeNodeStates) {
      if (!state.mounted) continue;
      if (state.widget.chapterIndex == anchor.chapterIndex &&
          state.widget.paragraphIndex == anchor.paragraphIndex) {
        targetState = state;
        break;
      }
    }

    if (targetState == null) return false;

    final box = targetState.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;

    final scrollable = Scrollable.maybeOf(targetState.context);
    if (scrollable == null || !scrollable.position.hasPixels) return false;

    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null || !scrollableBox.hasSize) return false;

    final localTopLeft =
        scrollableBox.globalToLocal(box.localToGlobal(Offset.zero));
    double nodeDy = localTopLeft.dy;
    final double nodeHeight = box.size.height;
    final text = targetState.widget.node.toPlainText();

    if (text.isNotEmpty && anchor.charOffset > 0 && nodeHeight > 0) {
      final fraction = (anchor.charOffset / text.length).clamp(0.0, 1.0);
      nodeDy += nodeHeight * fraction;
    }

    const readingLine = 80.0;
    final scrollDelta = nodeDy - readingLine;
    final targetOffset = (scrollable.position.pixels + scrollDelta).clamp(
      scrollable.position.minScrollExtent,
      scrollable.position.maxScrollExtent,
    );

    _isProgrammaticNavigation = true;
    _isProgrammaticReanchoring = true;

    if (jump || (targetOffset - scrollable.position.pixels).abs() < 1.0) {
      scrollable.position.jumpTo(targetOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _isProgrammaticNavigation = false;
          _isProgrammaticReanchoring = false;
        }
      });
    } else {
      scrollable.position.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      ).then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _isProgrammaticNavigation = false;
            _isProgrammaticReanchoring = false;
          }
        });
      }).catchError((_) {
        if (mounted) {
          _isProgrammaticNavigation = false;
          _isProgrammaticReanchoring = false;
        }
      });
    }

    return true;
  }

  ReadingAnchor? computeLeadingContinuousAnchor() {
    if (_activeNodeStates.isEmpty) return null;

    RenderBox? scrollableBox;
    for (final state in _activeNodeStates) {
      if (!state.mounted) continue;
      final s = Scrollable.maybeOf(state.context);
      final sb = s?.context.findRenderObject() as RenderBox?;
      if (sb != null && sb.hasSize) {
        scrollableBox = sb;
        break;
      }
    }
    if (scrollableBox == null) return null;

    const readingLine = 80.0;
    final candidates = <({
      _EpubScopedNodeWidgetState state,
      double dy,
      double bottomDy,
      int chapterIndex,
      int paragraphIndex,
    })>[];

    for (final state in _activeNodeStates) {
      if (!state.mounted) continue;
      final ch = state.widget.chapterIndex;
      final p = state.widget.paragraphIndex;
      if (ch == null || p == null) continue;

      final box = state.context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;

      try {
        final localTopLeft =
            scrollableBox.globalToLocal(box.localToGlobal(Offset.zero));
        final dy = localTopLeft.dy;
        final bottomDy = dy + box.size.height;
        if (bottomDy > 0.0) {
          candidates.add((
            state: state,
            dy: dy,
            bottomDy: bottomDy,
            chapterIndex: ch,
            paragraphIndex: p,
          ));
        }
      } catch (_) {}
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final chCmp = a.chapterIndex.compareTo(b.chapterIndex);
      if (chCmp != 0) return chCmp;
      return a.paragraphIndex.compareTo(b.paragraphIndex);
    });

    final straddling = candidates.where(
      (c) => c.dy <= readingLine && c.bottomDy > readingLine,
    ).toList();

    final active = straddling.isNotEmpty
        ? straddling.first
        : candidates.firstWhere(
            (c) => c.dy >= readingLine,
            orElse: () => candidates.last,
          );

    final nodeHeight = active.bottomDy - active.dy;
    final text = active.state.widget.node.toPlainText();
    int charOffset = 0;
    if (text.isNotEmpty && nodeHeight > 0 && active.dy < readingLine) {
      final hiddenAboveReadingLine = readingLine - active.dy;
      final fraction = (hiddenAboveReadingLine / nodeHeight).clamp(0.0, 1.0);
      charOffset = (fraction * text.length).round().clamp(0, text.length);
    }

    return ReadingAnchor(
      chapterIndex: active.chapterIndex,
      paragraphIndex: active.paragraphIndex,
      charOffset: charOffset,
    );
  }

  void _recordLeadingVisibleContinuousAnchor() {
    if (!mounted || widget.settings.isPaginated) return;
    if (_isProgrammaticNavigation || _isProgrammaticReanchoring) return;

    final anchor = computeLeadingContinuousAnchor();
    if (anchor != null) {
      if (_currentChapterIndex != anchor.chapterIndex) {
        _currentChapterIndex = anchor.chapterIndex;
        _schedulePrewarmAdjacentChapters();
        widget.onChapterChanged?.call(anchor.chapterIndex);
        widget.onPageChanged(anchor.chapterIndex, 0.0);
      }
      ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
            chapterIndex: anchor.chapterIndex,
            paragraphIndex: anchor.paragraphIndex,
            charOffset: anchor.charOffset,
          );
    }
  }

  void _scheduleContinuousAnchorDebounce() {
    _continuousAnchorDebounceTimer?.cancel();
    _continuousAnchorDebounceTimer =
        Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        _recordLeadingVisibleContinuousAnchor();
      }
    });
  }

  void _scheduleContinuousAnchorCommit() {
    _continuousAnchorDebounceTimer?.cancel();
    _continuousAnchorDebounceTimer =
        Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        _recordLeadingVisibleContinuousAnchor();
      }
    });
  }

  /// Returns the first visible sentence or text snippet on screen for TTS initialization.
  String? getFirstVisibleTextSnippet() {
    if (widget.settings.isPaginated) {
      final pages = _effectivePages;
      if (pages.isEmpty) return null;
      final controller = _isEpub ? _effectiveEpubPageController : widget.pageController;
      final curPage = _safeGetPage(controller);
      final activePage = curPage != null
          ? curPage.round()
          : (widget.pageIndexInChapter ?? _currentPageIndexInChapter);
      final startPage = activePage.clamp(
        0,
        pages.length - 1,
      );
      for (var pageIdx = startPage; pageIdx < pages.length; pageIdx++) {
        final chunk = pages[pageIdx];
        for (final node in chunk.nodes) {
          if (node is ParagraphNode || node is HeadingNode) {
            final text = node.toPlainText().trim();
            if (text.isNotEmpty && TtsTextNormalizer.hasAlphanumeric(text)) {
              final sentences = TtsTextNormalizer.extractSanitizedSentenceList(text);
              return sentences.isNotEmpty ? sentences.first : text;
            }
          }
        }
      }
      return null;
    } else {
      // Continuous Mode: Inspect rendered _EpubScopedNodeWidgets
      final visibleCandidates =
          <({_EpubScopedNodeWidgetState state, double dy, double bottomDy})>[];

      for (final nodeState in _activeNodeStates) {
        if (!nodeState.mounted) continue;
        if (nodeState.widget.chapterIndex != null &&
            nodeState.widget.chapterIndex != _currentChapterIndex) {
          continue;
        }
        final node = nodeState.widget.node;
        if (node is! ParagraphNode && node is! HeadingNode) continue;
        final renderBox = nodeState.context.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) continue;
        try {
          final dy = renderBox.localToGlobal(Offset.zero).dy;
          final bottomDy = dy + renderBox.size.height;
          if (bottomDy >= 60.0) {
            visibleCandidates.add((state: nodeState, dy: dy, bottomDy: bottomDy));
          }
        } catch (_) {}
      }

      if (visibleCandidates.isEmpty) {
        for (final nodeState in _activeNodeStates) {
          if (!nodeState.mounted) continue;
          final node = nodeState.widget.node;
          if (node is! ParagraphNode && node is! HeadingNode) continue;
          final renderBox = nodeState.context.findRenderObject() as RenderBox?;
          if (renderBox == null || !renderBox.hasSize) continue;
          try {
            final dy = renderBox.localToGlobal(Offset.zero).dy;
            final bottomDy = dy + renderBox.size.height;
            if (bottomDy >= 60.0) {
              visibleCandidates.add((state: nodeState, dy: dy, bottomDy: bottomDy));
            }
          } catch (_) {}
        }
      }

      if (visibleCandidates.isEmpty) {
        if (widget.epubNodes != null && widget.epubNodes!.isNotEmpty) {
          for (final node in widget.epubNodes!) {
            if (node is ParagraphNode || node is HeadingNode) {
              final text = node.toPlainText().trim();
              if (text.isNotEmpty && TtsTextNormalizer.hasAlphanumeric(text)) {
                final sentences =
                    TtsTextNormalizer.extractSanitizedSentenceList(text);
                return sentences.isNotEmpty ? sentences.first : text;
              }
            }
          }
        }
        return null;
      }

      visibleCandidates.sort((a, b) => a.dy.compareTo(b.dy));

      // Find first readable node: either starting below the top bar (dy >= 60.0)
      // or straddling the top bar with substantial visible height (bottomDy >= 100.0).
      final matching = visibleCandidates.firstWhere(
        (c) => (c.dy >= 60.0) || (c.dy < 60.0 && c.bottomDy >= 100.0),
        orElse: () => visibleCandidates.first,
      );

      final text = matching.state.widget.node.toPlainText().trim();
      if (text.isEmpty || !TtsTextNormalizer.hasAlphanumeric(text)) return null;

      final sentences = TtsTextNormalizer.extractSanitizedSentenceList(text);
      if (sentences.isEmpty) return text;

      // If the node starts above the top bar (dy < 60.0), calculate which sentence
      // is actually visible in the viewport instead of starting from the hidden top sentence.
      if (matching.dy < 60.0 && sentences.length > 1) {
        final totalHeight = matching.bottomDy - matching.dy;
        if (totalHeight > 0) {
          final hiddenHeight = 60.0 - matching.dy;
          final fraction = (hiddenHeight / totalHeight).clamp(0.0, 1.0);
          final sentenceIdx =
              (sentences.length * fraction).floor().clamp(0, sentences.length - 1);
          return sentences[sentenceIdx];
        }
      }

      return sentences.first;
    }
  }

  @override
  void initState() {
    super.initState();
    final anchor = ref.read(activeReadingAnchorProvider);
    if (anchor != null) {
      _currentChapterIndex = anchor.chapterIndex;
      if (!widget.settings.isPaginated) {
        _pendingContinuousScrollAnchor = anchor;
        _isProgrammaticReanchoring = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_pendingContinuousScrollAnchor != null) {
            final scrolled =
                _scrollToAnchorNode(_pendingContinuousScrollAnchor!);
            if (scrolled) {
              _pendingContinuousScrollAnchor = null;
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _pendingContinuousScrollAnchor != null) {
                  final secondAttempt =
                      _scrollToAnchorNode(_pendingContinuousScrollAnchor!);
                  _pendingContinuousScrollAnchor = null;
                  if (!secondAttempt) {
                    _isProgrammaticReanchoring = false;
                  }
                }
              });
            }
          } else {
            _isProgrammaticReanchoring = false;
          }
        });
      }
    } else {
      _currentChapterIndex = widget.initialChapterIndex ??
          widget.chapterIndex ??
          widget.initialPageIndex.clamp(
            0,
            widget.pageCount > 0 ? widget.pageCount - 1 : 0,
          );
    }
    _currentPageIndexInChapter = widget.pageIndexInChapter ?? 0;

    if (_isEpub) {
      _epubPageController = PageController(
        initialPage: _currentPageIndexInChapter,
      );
    }

    _effectiveItemPositionsListener.itemPositions.addListener(
      _onPositionsChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _schedulePrewarmAdjacentChapters();
    });
  }

  void _prewarmAdjacentChapters() {
    if (!_isEpub) return;
    final totalChapters = widget.pageCount > 0 ? widget.pageCount : 1;
    prewarmAdjacentChapters(
      ref,
      filePath: widget.filePath,
      chapterIndex: _currentChapterIndex,
      totalChapters: totalChapters,
    );
  }

  @override
  void didUpdateWidget(covariant ReaderCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldListener =
        oldWidget.itemPositionsListener ?? _internalItemPositionsListener;
    final newListener =
        widget.itemPositionsListener ?? _internalItemPositionsListener;
    if (oldListener != newListener) {
      oldListener?.itemPositions.removeListener(_onPositionsChanged);
      newListener?.itemPositions.addListener(_onPositionsChanged);
    }

    final bool chapterChanged = _isEpub &&
        widget.chapterIndex != null &&
        (widget.chapterIndex != oldWidget.chapterIndex ||
            widget.chapterIndex != _currentChapterIndex);

    if (chapterChanged) {
      final newIndex = widget.chapterIndex!;
      _currentChapterIndex = newIndex;
      _paginatedChapterIndex = null;
      _lastPageSentinelConsumedForChapter = null;
      final targetInitialPage = (widget.pageIndexInChapter == -1)
          ? -1
          : (widget.pageIndexInChapter ?? 0);
      _currentPageIndexInChapter = targetInitialPage;
      _schedulePrewarmAdjacentChapters();
      if (widget.settings.isPaginated) {
        if (_isEpub) {
          final maxP = (_paginatedChapterIndex == newIndex &&
                  _currentChapterPages.isNotEmpty)
              ? _currentChapterPages.length
              : null;
          _recreateEpubPageController(
            targetInitialPage == -1 ? 0 : targetInitialPage,
            maxP,
          );
        } else {
          if (_isPageControllerReady) {
            widget.pageController.jumpToPage(0);
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _isPageControllerReady) {
                widget.pageController.jumpToPage(0);
              }
            });
          }
        }
      } else {
        if (_effectiveItemScrollController.isAttached) {
          _effectiveItemScrollController.jumpTo(index: newIndex);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _effectiveItemScrollController.isAttached) {
              _effectiveItemScrollController.jumpTo(index: newIndex);
            }
          });
        }
      }
    } else if (widget.pageIndexInChapter != null &&
        widget.pageIndexInChapter != oldWidget.pageIndexInChapter) {
      if (widget.pageIndexInChapter == -1) {
        if (_lastPageSentinelConsumedForChapter != _currentChapterIndex) {
          jumpToPageInChapter(-1);
        }
      } else if (widget.pageIndexInChapter != _currentPageIndexInChapter) {
        _currentPageIndexInChapter = widget.pageIndexInChapter!;
        _lastPageSentinelConsumedForChapter = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_isEpub && _isEpubPageControllerReady) {
            final curPage = _safeGetPage(_effectiveEpubPageController);
            if (curPage?.round() != _currentPageIndexInChapter) {
              _effectiveEpubPageController.jumpToPage(_currentPageIndexInChapter);
            }
          }
        });
      }
    } else if (widget.initialPageIndex != oldWidget.initialPageIndex) {
      _currentChapterIndex = widget.initialPageIndex.clamp(
        0,
        widget.pageCount > 0 ? widget.pageCount - 1 : 0,
      );
      _paginatedChapterIndex = null;
      _currentPageIndexInChapter = 0;
      _schedulePrewarmAdjacentChapters();
      if (widget.settings.isPaginated) {
        if (_isEpub) {
          final maxP = (_paginatedChapterIndex == _currentChapterIndex &&
                  _currentChapterPages.isNotEmpty)
              ? _currentChapterPages.length
              : null;
          _recreateEpubPageController(0, maxP);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isPageControllerReady) {
              final target = widget.initialPageIndex.clamp(
                0,
                widget.pageCount > 0 ? widget.pageCount - 1 : 0,
              );
              if (widget.pageController.page?.round() != target) {
                widget.pageController.jumpToPage(target);
              }
            }
          });
        }
      }
    }

    if (!oldWidget.settings.isPaginated && widget.settings.isPaginated) {
      _isProgrammaticReanchoring = true;
      final anchor = ref.read(activeReadingAnchorProvider);
      if (anchor != null) {
        _currentChapterIndex = anchor.chapterIndex;
        _paginatedChapterIndex = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_isEpub && _isEpubPageControllerReady) {
            final pages = _effectivePages;
            final resolved = ref
                .read(activeReadingAnchorProvider.notifier)
                .resolvePageForCurrentAnchor(pages);
            _currentPageIndexInChapter = resolved;
            final curPage = _safeGetPage(_effectiveEpubPageController);
            if (curPage?.round() != resolved) {
              _isProgrammaticReanchoring = true;
              _effectiveEpubPageController.jumpToPage(resolved);
            }
          } else if (!_isEpub && _isPageControllerReady) {
            widget.pageController.jumpToPage(_currentPageIndexInChapter);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isProgrammaticReanchoring = false;
            }
          });
        }
      });
    } else if (oldWidget.settings.isPaginated && !widget.settings.isPaginated) {
      _isProgrammaticReanchoring = true;
      final anchor = ref.read(activeReadingAnchorProvider);
      if (anchor != null) {
        _currentChapterIndex = anchor.chapterIndex;
        _pendingContinuousScrollAnchor = anchor;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_effectiveItemScrollController.isAttached) {
          _effectiveItemScrollController.jumpTo(index: _currentChapterIndex);
        }
        if (_pendingContinuousScrollAnchor != null) {
          final scrolled =
              _scrollToAnchorNode(_pendingContinuousScrollAnchor!);
          if (scrolled) {
            _pendingContinuousScrollAnchor = null;
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _pendingContinuousScrollAnchor != null) {
                final secondAttempt =
                    _scrollToAnchorNode(_pendingContinuousScrollAnchor!);
                _pendingContinuousScrollAnchor = null;
                if (!secondAttempt) {
                  _isProgrammaticReanchoring = false;
                }
              }
            });
          }
        } else {
          _isProgrammaticReanchoring = false;
        }
      });
    }

    if (oldWidget.isUserDesyncedFromTts && !widget.isUserDesyncedFromTts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) scrollSpeakingSentenceIntoView();
      });
    }
  }

  @override
  void dispose() {
    _scrollLatchResetTimer?.cancel();
    _prewarmTimer?.cancel();
    _userScrollDebounceTimer?.cancel();
    _continuousAnchorDebounceTimer?.cancel();
    _oldControllerDisposalTimer?.cancel();
    _pendingDisposalController?.dispose();
    _pendingDisposalController = null;
    _effectiveItemPositionsListener.itemPositions.removeListener(
      _onPositionsChanged,
    );
    _epubPageController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPositionsChanged() {
    if (!mounted || widget.settings.isPaginated) return;

    if (_isEpub) {
      _handleEpubContinuousPositions();
      return;
    }

    final positions = _effectiveItemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final visible = positions
        .where((pos) => pos.itemTrailingEdge > 0.0 && pos.itemLeadingEdge < 1.0)
        .toList();
    if (visible.isEmpty) return;

    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));

    ItemPosition active = visible.first;
    if (visible.length > 1 && active.itemTrailingEdge < 0.15) {
      active = visible[1];
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onPageChanged(active.index, active.itemLeadingEdge);
    });
  }

  void _handleEpubContinuousPositions() {
    final positions = _effectiveItemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // In EPUB continuous mode, each item is an entire chapter.
    // Determine visibleChapterIndex by finding the chapter item that straddles the
    // upper viewport reading line (e.g., pos.itemLeadingEdge <= 0.3 && pos.itemTrailingEdge > 0.1),
    // falling back to the item with the smallest non-negative itemLeadingEdge if none straddles 0.1.
    final straddling = positions
        .where((pos) => pos.itemLeadingEdge <= 0.3 && pos.itemTrailingEdge > 0.1)
        .toList();

    ItemPosition activePos;
    if (straddling.isNotEmpty) {
      final straddlingReadingLine = straddling.where(
        (pos) => pos.itemLeadingEdge <= 0.1 && pos.itemTrailingEdge > 0.1,
      ).toList();
      if (straddlingReadingLine.isNotEmpty) {
        activePos = straddlingReadingLine.first;
      } else {
        straddling.sort((a, b) => b.itemLeadingEdge.compareTo(a.itemLeadingEdge));
        activePos = straddling.first;
      }
    } else {
      final nonNegative = positions
          .where((pos) => pos.itemLeadingEdge >= 0.0)
          .toList()
        ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
      if (nonNegative.isNotEmpty) {
        activePos = nonNegative.first;
      } else {
        final sorted = positions.toList()
          ..sort((a, b) => b.itemTrailingEdge.compareTo(a.itemTrailingEdge));
        activePos = sorted.first;
      }
    }

    final visibleChapterIndex = activePos.index;

    if (visibleChapterIndex != _currentChapterIndex) {
      _currentChapterIndex = visibleChapterIndex;
      _schedulePrewarmAdjacentChapters();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onChapterChanged?.call(visibleChapterIndex);
        widget.onPageChanged(visibleChapterIndex, 0.0);
      });
    }
  }

  void scrollSpeakingSentenceIntoView() {
    if (!mounted) return;
    if (widget.settings.isPaginated) {
      final controller = _isEpub ? _effectiveEpubPageController : widget.pageController;
      final isReady = _isEpub ? _isEpubPageControllerReady : _isPageControllerReady;
      final curPage = _safeGetPage(controller);
      if (isReady &&
          curPage?.round() != _currentPageIndexInChapter) {
        _isProgrammaticNavigation = true;
        controller.animateToPage(
          _currentPageIndexInChapter,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        ).then((_) {
          _isProgrammaticNavigation = false;
        });
      }
    } else {
      _isUserScrolling = false;
      _lastSentenceIndexDuringUserScroll = -1;
      _userScrollDebounceTimer?.cancel();

      final ttsState = ref.read(ttsStateProvider);
      final activeSentence = ttsState.currentSentenceText.trim();
      _EpubScopedNodeWidgetState? matchedState;
      if (activeSentence.isNotEmpty) {
        for (final nodeState in _activeNodeStates) {
          if (!nodeState.mounted) continue;
          final plain = nodeState.widget.node.toPlainText().trim();
          if (plain.contains(activeSentence) ||
              plain.replaceAll(RegExp(r'\s+'), ' ').toLowerCase().contains(
                  activeSentence.replaceAll(RegExp(r'\s+'), ' ').toLowerCase())) {
            matchedState = nodeState;
            break;
          }
        }
      }

      if (matchedState != null) {
        matchedState.scrollNodeIntoView(force: true);
      } else if (_effectiveItemScrollController.isAttached) {
        _isProgrammaticNavigation = true;
        _effectiveItemScrollController.scrollTo(
          index: _currentChapterIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        ).then((_) {
          _isProgrammaticNavigation = false;
        });
      }
    }
  }

  void scrollToPage(int targetPageIndex) {
    if (_isEpub) {
      final target = targetPageIndex.clamp(
        0,
        widget.pageCount > 0 ? widget.pageCount - 1 : 0,
      );
      setState(() {
        _currentChapterIndex = target;
        _paginatedChapterIndex = null;
        _lastPageSentinelConsumedForChapter = null;
        _currentPageIndexInChapter = 0;
      });
      _schedulePrewarmAdjacentChapters();
      if (widget.settings.isPaginated) {
        final maxP = (_paginatedChapterIndex == target &&
                _currentChapterPages.isNotEmpty)
            ? _currentChapterPages.length
            : null;
        _recreateEpubPageController(0, maxP);
      } else {
        if (_effectiveItemScrollController.isAttached) {
          _effectiveItemScrollController.jumpTo(index: target);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _effectiveItemScrollController.isAttached) {
              _effectiveItemScrollController.jumpTo(index: target);
            }
          });
        }
      }
      widget.onPageChanged(target, 0.0);
      widget.onEpubPageChanged?.call(target, 0);
      return;
    }

    final total = widget.pageCount > 0 ? widget.pageCount : 1;
    final clampedIndex = targetPageIndex.clamp(0, total - 1);
    if (widget.settings.isPaginated) {
      if (_isPageControllerReady) {
        widget.pageController.jumpToPage(clampedIndex);
      }
      return;
    }

    final controller = _effectiveItemScrollController;
    if (controller.isAttached) {
      controller.jumpTo(index: clampedIndex);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.isAttached) {
          controller.jumpTo(index: clampedIndex);
        }
      });
    }
  }

  void goToNextPage({bool animate = true}) {
    _focusNode.requestFocus();
    if (_isEpub) {
      final pages = _effectivePages;
      if (pages.isEmpty) return;
      final totalPages = pages.length;
      final activePage =
          _safeGetPage(_effectiveEpubPageController)?.round() ??
              _currentPageIndexInChapter;
      final curPage = activePage.clamp(0, totalPages - 1);
      if (curPage < totalPages - 1) {
        final nextPage = curPage + 1;
        _currentPageIndexInChapter = nextPage;
        if (nextPage < pages.length) {
          final chunk = pages[nextPage];
          ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
                chapterIndex: _currentChapterIndex,
                paragraphIndex: chunk.startParagraphIndex,
                charOffset: chunk.startCharOffset,
              );
        }
        widget.onEpubPageChanged?.call(_currentChapterIndex, nextPage);
        if (!_isProgrammaticNavigation) {
          widget.onUserNavigated?.call();
        }
        if (animate && _isEpubPageControllerReady) {
          _effectiveEpubPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _effectiveEpubPageController.jumpToPage(nextPage);
        }
        return;
      }
      if (!_isProgrammaticNavigation) {
        widget.onUserNavigated?.call();
      }
      if (widget.onNextChapter != null) {
        widget.onNextChapter!();
      } else if (_currentChapterIndex < widget.pageCount - 1) {
        setState(() {
          _currentChapterIndex++;
          _paginatedChapterIndex = null;
          _lastPageSentinelConsumedForChapter = null;
          _currentPageIndexInChapter = 0;
        });
        _schedulePrewarmAdjacentChapters();
        final maxP = (_paginatedChapterIndex == _currentChapterIndex &&
                _effectivePages.isNotEmpty)
            ? _effectivePages.length
            : null;
        _recreateEpubPageController(0, maxP);
        widget.onPageChanged(_currentChapterIndex, 0.0);
        widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
      }
      return;
    }

    final total = widget.pageCount > 0 ? widget.pageCount : 1;
    final curPage = _safeGetPage(widget.pageController)?.round() ??
        (widget.pageController.hasClients ? widget.pageController.page?.round() ?? widget.initialPageIndex : widget.initialPageIndex);
    final clamped = curPage.clamp(0, total - 1);
    if (clamped < total - 1) {
      if (!_isProgrammaticNavigation) {
        widget.onUserNavigated?.call();
      }
      final nextPage = clamped + 1;
      if (_isPageControllerReady) {
        if (animate) {
          widget.pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        } else {
          widget.pageController.jumpToPage(nextPage);
        }
      }
    }
  }

  void goToPreviousPage({bool animate = true}) {
    _focusNode.requestFocus();
    if (_isEpub) {
      final pages = _effectivePages;
      if (pages.isEmpty) return;
      final totalPages = pages.length;
      final activePage =
          _safeGetPage(_effectiveEpubPageController)?.round() ??
              _currentPageIndexInChapter;
      final curPage = activePage.clamp(0, totalPages - 1);
      if (curPage > 0) {
        final prevPage = curPage - 1;
        _currentPageIndexInChapter = prevPage;
        if (prevPage < pages.length) {
          final chunk = pages[prevPage];
          ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
                chapterIndex: _currentChapterIndex,
                paragraphIndex: chunk.startParagraphIndex,
                charOffset: chunk.startCharOffset,
              );
        }
        widget.onEpubPageChanged?.call(_currentChapterIndex, prevPage);
        if (!_isProgrammaticNavigation) {
          widget.onUserNavigated?.call();
        }
        if (animate && _isEpubPageControllerReady) {
          _effectiveEpubPageController.animateToPage(
            prevPage,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _effectiveEpubPageController.jumpToPage(prevPage);
        }
        return;
      }
      if (!_isProgrammaticNavigation) {
        widget.onUserNavigated?.call();
      }
      if (widget.onPreviousChapter != null) {
        widget.onPreviousChapter!();
      } else if (_currentChapterIndex > 0) {
        setState(() {
          _currentChapterIndex--;
          _paginatedChapterIndex = null;
          _lastPageSentinelConsumedForChapter = null;
          _currentPageIndexInChapter = -1;
        });
        _schedulePrewarmAdjacentChapters();
        final maxP = (_paginatedChapterIndex == _currentChapterIndex &&
                _effectivePages.isNotEmpty)
            ? _effectivePages.length
            : null;
        _recreateEpubPageController(0, maxP);
        widget.onPageChanged(_currentChapterIndex, 0.0);
        widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
      }
      return;
    }

    final total = widget.pageCount > 0 ? widget.pageCount : 1;
    final curPage = _safeGetPage(widget.pageController)?.round() ??
        (widget.pageController.hasClients ? widget.pageController.page?.round() ?? widget.initialPageIndex : widget.initialPageIndex);
    final clamped = curPage.clamp(0, total - 1);
    if (clamped > 0) {
      if (!_isProgrammaticNavigation) {
        widget.onUserNavigated?.call();
      }
      final prevPage = clamped - 1;
      if (_isPageControllerReady) {
        if (animate) {
          widget.pageController.animateToPage(
            prevPage,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        } else {
          widget.pageController.jumpToPage(prevPage);
        }
      }
    }
  }

  void goToFirstPage({bool animate = true}) {
    _focusNode.requestFocus();
    if (_isEpub) {
      scrollToPage(0);
      return;
    }
    final total = widget.pageCount > 0 ? widget.pageCount : 1;
    final curPage = _safeGetPage(widget.pageController)?.round() ??
        (widget.pageController.hasClients ? widget.pageController.page?.round() ?? widget.initialPageIndex : widget.initialPageIndex);
    final clamped = curPage.clamp(0, total - 1);
    if (clamped > 0) {
      if (!_isProgrammaticNavigation) {
        widget.onUserNavigated?.call();
      }
      if (widget.settings.isPaginated && _isPageControllerReady) {
        if (animate) {
          widget.pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        } else {
          widget.pageController.jumpToPage(0);
        }
      } else {
        scrollToPage(0);
      }
    }
  }

  void goToLastPage({bool animate = true}) {
    _focusNode.requestFocus();
    final total = widget.pageCount > 0 ? widget.pageCount : 1;
    final lastPageIndex = total - 1;
    if (_isEpub) {
      final totalChapters = widget.pageCount > 0 ? widget.pageCount : 1;
      final target = (widget.pageCount > 0 ? widget.pageCount - 1 : 0).clamp(0, totalChapters - 1);
      setState(() {
        _currentChapterIndex = target;
        _paginatedChapterIndex = null;
        _lastPageSentinelConsumedForChapter = null;
        _currentPageIndexInChapter = -1;
      });
      _schedulePrewarmAdjacentChapters();
      if (widget.settings.isPaginated) {
        final maxP = (_paginatedChapterIndex == target &&
                _currentChapterPages.isNotEmpty)
            ? _currentChapterPages.length
            : null;
        _recreateEpubPageController(0, maxP);
      } else {
        if (_effectiveItemScrollController.isAttached) {
          _effectiveItemScrollController.jumpTo(index: target);
        }
      }
      widget.onPageChanged(target, 0.0);
      widget.onEpubPageChanged?.call(target, -1);
      return;
    }
    final curPage = _safeGetPage(widget.pageController)?.round() ??
        (widget.pageController.hasClients ? widget.pageController.page?.round() ?? widget.initialPageIndex : widget.initialPageIndex);
    final clamped = curPage.clamp(0, total - 1);
    if (clamped < lastPageIndex) {
      if (!_isProgrammaticNavigation) {
        widget.onUserNavigated?.call();
      }
      if (widget.settings.isPaginated && _isPageControllerReady) {
        if (animate) {
          widget.pageController.animateToPage(
            lastPageIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        } else {
          widget.pageController.jumpToPage(lastPageIndex);
        }
      } else {
        scrollToPage(lastPageIndex);
      }
    }
  }

  int _findTargetPageIndex(List<PageChunk> pages, String currentSentence) {
    final sentence = currentSentence.trim();
    if (sentence.isEmpty) return -1;
    final lowerSentence = sentence.toLowerCase();

    // 1. Direct contains check across all pages
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].plainText.toLowerCase().contains(lowerSentence)) {
        return i;
      }
    }

    // 2. Normalized check (collapsing whitespace, quotes, curly apostrophes)
    final normSentence = sentence
        .replaceAll(RegExp(r'[’‘]'), "'")
        .replaceAll(RegExp(r'[“”]'), '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();

    for (var i = 0; i < pages.length; i++) {
      final normPage = pages[i].plainText
          .replaceAll(RegExp(r'[’‘]'), "'")
          .replaceAll(RegExp(r'[“”]'), '"')
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      if (normPage.contains(normSentence)) {
        return i;
      }
    }

    // 3. Word sequence match (first few significant words)
    final words = normSentence.split(' ').where((w) => w.length > 2).toList();
    if (words.length >= 2) {
      final pattern = RegExp(
        words.take(5).map(RegExp.escape).join(r'\s+'),
        caseSensitive: false,
      );
      for (var i = 0; i < pages.length; i++) {
        if (pattern.hasMatch(pages[i].plainText)) {
          return i;
        }
      }
    }

    // 4. Split sentence check across adjacent page boundaries
    for (var i = 0; i < pages.length - 1; i++) {
      final pageA = pages[i].plainText.toLowerCase();
      final pageB = pages[i + 1].plainText.toLowerCase();
      final combined = '$pageA $pageB';
      if (combined.contains(lowerSentence)) {
        final bTrim = pageB.trim();
        if (bTrim.isNotEmpty &&
            lowerSentence.contains(bTrim.substring(0, bTrim.length.clamp(0, 15)))) {
          return i + 1;
        }
        return i;
      }
    }

    return -1;
  }

  void _checkAutoPageTurn(List<PageChunk> pages, TtsState ttsState) {
    if (!widget.settings.isPaginated || pages.isEmpty || !ttsState.isPlaying) {
      return;
    }

    final readerSettings = ref.read(readerSettingsProvider);
    if (widget.isUserDesyncedFromTts || !readerSettings.ttsAutoAdvance) {
      return;
    }

    final currentSentence = ttsState.currentSentenceText.trim();
    if (currentSentence.isEmpty) return;

    final targetPageIndex = _findTargetPageIndex(pages, currentSentence);
    if (targetPageIndex < 0 || targetPageIndex >= pages.length) {
      return;
    }

    widget.onSpeakingPageDiscovered?.call(_currentChapterIndex, targetPageIndex);

    // If targetPageIndex is not current page, animate directly to targetPageIndex,
    // skipping right over any intermediate image-only pages!
    if (targetPageIndex != _currentPageIndexInChapter &&
        !widget.isUserDesyncedFromTts) {
      final controller = _isEpub ? _effectiveEpubPageController : widget.pageController;
      final isControllerReady = _isEpub ? _isEpubPageControllerReady : _isPageControllerReady;
      final curPage = _safeGetPage(controller);
      if (isControllerReady &&
          curPage?.round() != targetPageIndex) {
        setState(() {
          _currentPageIndexInChapter = targetPageIndex;
        });
        _setProgrammaticScroll(true);
        controller.animateToPage(
          targetPageIndex,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        ).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _setProgrammaticScroll(false);
            }
          });
        }).catchError((_) {
          if (mounted) {
            _setProgrammaticScroll(false);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final isPaginated = widget.settings.isPaginated;

    // Auto-turn check on TTS progress in paginated mode without full rebuild
    ref.listen<TtsState>(ttsStateProvider, (previous, next) {
      if (next.isPlaying) {
        if (next.currentSentenceIndex != previous?.currentSentenceIndex) {
          if (!_isUserScrolling) {
            _lastSentenceIndexDuringUserScroll = -1;
          }
        }
        if (widget.settings.isPaginated) {
          final pages = _effectivePages;
          _checkAutoPageTurn(pages, next);
        }
      }
    });

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy.abs() > 1.0) {
            if (!widget.settings.isPaginated) {
              _onUserScrollStarted();
              _scheduleUserScrollEnded();
            } else {
              widget.onUserNavigated?.call();
            }
          }
          if (widget.settings.isPaginated && event.scrollDelta.dx != 0) {
            _handleTrackpadDelta(event.scrollDelta.dx);
          }
        }
      },
      onPointerPanZoomStart: (_) {
        _isPanGestureActive = true;
        _isPanLatched = false;
        _accumulatedTrackpadDelta = 0.0;
      },
      onPointerPanZoomUpdate: (event) {
        if (widget.settings.isPaginated) {
          final double delta;
          if (event.panDelta.dx.abs() >= event.panDelta.dy.abs()) {
            delta = -event.panDelta.dx;
          } else {
            delta = -event.panDelta.dy;
          }
          if (delta != 0) {
            _handleTrackpadDelta(delta, isPanZoom: true);
          }
        }
      },
      onPointerPanZoomEnd: (_) {
        _isPanGestureActive = false;
        _isPanLatched = false;
        _accumulatedTrackpadDelta = 0.0;
      },
      onPointerDown: (_) {
        _resetGestureLatch();
        _focusNode.requestFocus();
      },
      onPointerUp: (_) {
        _resetGestureLatch();
      },
      onPointerCancel: (_) {
        _resetGestureLatch();
      },
      onPointerMove: (event) {
        if (event.buttons != 0 || event.kind == PointerDeviceKind.touch) {
          if (!widget.settings.isPaginated) {
            _onUserScrollStarted();
            _scheduleUserScrollEnded();
          } else {
            widget.onUserNavigated?.call();
          }
        }
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final isAlt = HardwareKeyboard.instance.isAltPressed;
          final isControl = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          final isShift = HardwareKeyboard.instance.isShiftPressed;

          // Toggle TTS Playback: Ctrl + Space, mediaPlayPause, mediaPlay, mediaPause
          if (isControl && event.logicalKey == LogicalKeyboardKey.space) {
            _toggleTtsPlayback();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
              event.logicalKey == LogicalKeyboardKey.mediaPlay ||
              event.logicalKey == LogicalKeyboardKey.mediaPause) {
            _toggleTtsPlayback();
            return KeyEventResult.handled;
          }

          // Seek / Skip TTS: Alt + Right Arrow (forward), Alt + Left Arrow (backward)
          if (isAlt && event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _seekForwardTts();
            return KeyEventResult.handled;
          }
          if (isAlt && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _seekBackwardTts();
            return KeyEventResult.handled;
          }

          // Shift + Space: navigate to previous page
          if (!isAlt && !isControl && isShift && event.logicalKey == LogicalKeyboardKey.space) {
            goToPreviousPage();
            return KeyEventResult.handled;
          }

          // Standard page turns without Alt, Ctrl, or Shift
          if (!isAlt && !isControl && !isShift) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.pageUp) {
              goToPreviousPage();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.pageDown ||
                event.logicalKey == LogicalKeyboardKey.space) {
              goToNextPage();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.home) {
              goToFirstPage();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.end) {
              goToLastPage();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _focusNode.requestFocus();
          widget.onToggleChrome();
        },
        child: _isEpub
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final columnWidth = EpubPaginationMetrics.computeColumnWidth(
                    viewportWidth: constraints.maxWidth,
                    horizontalPadding: widget.settings.horizontalPadding,
                    maxContentWidth: widget.settings.contentMaxWidth,
                  );
                  final columnHeight = EpubPaginationMetrics.computeColumnHeight(
                    constraints.maxHeight,
                  );

                  return isPaginated
                      ? _buildEpubPaginatedView(
                          theme,
                          columnWidth,
                          columnHeight,
                          widget.settings.horizontalPadding,
                        )
                      : _buildEpubContinuousView(
                          theme,
                          columnWidth,
                          columnHeight,
                          widget.settings.horizontalPadding,
                        );
                },
              )
            : (isPaginated
                ? _buildPaginatedView(theme)
                : _buildContinuousView(theme)),
      ),
    ),
  );
}

  Widget _buildEpubPaginatedView(
    ReaderThemeData theme,
    double columnWidth,
    double columnHeight,
    double horizontalPadding,
  ) {
    final textStyle = TextStyle(
      fontFamily: widget.settings.fontFamily,
      fontSize: widget.settings.fontSize,
      height: widget.settings.lineHeight,
      color: theme.textPrimary,
    );

    final activeChapterIndex = widget.chapterIndex ?? _currentChapterIndex;

    final params = PaginationParams(
      filePath: widget.filePath,
      chapterIndex: activeChapterIndex,
      maxWidth: columnWidth,
      maxHeight: columnHeight,
      textStyle: textStyle,
      paragraphSpacing: widget.settings.paragraphSpacing,
    );

    final pagesAsync = ref.watch(chapterPagesProvider(params));

    final hasNewPages = pagesAsync.asData != null ||
        (widget.epubChunks != null &&
            widget.epubChunks!.isNotEmpty &&
            widget.epubChunks!.first.chapterIndex == activeChapterIndex);

    final pages = pagesAsync.asData?.value ??
        ((widget.epubChunks != null &&
                widget.epubChunks!.isNotEmpty &&
                widget.epubChunks!.first.chapterIndex == activeChapterIndex)
            ? widget.epubChunks
            : (_currentChapterPages.isNotEmpty &&
                    _currentChapterPages.first.chapterIndex == activeChapterIndex
                ? _currentChapterPages
                : null));

    final effectiveParams = hasNewPages ? params : _lastPaginationParams;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: pages != null
          ? KeyedSubtree(
              key: ValueKey('paginated_pages_$activeChapterIndex'),
              child: _buildEpubPagesStack(
                theme,
                pages,
                columnWidth,
                columnHeight,
                horizontalPadding,
                textStyle,
                params: effectiveParams,
              ),
            )
          : pagesAsync.when(
              loading: () => Center(
                key: const ValueKey('paginated_loading'),
                child: CircularProgressIndicator(color: theme.accent),
              ),
              error: (err, _) => Center(
                key: const ValueKey('paginated_error'),
                child: Text(
                  'Error paginating chapter: $err',
                  style: AppTypography.body.copyWith(color: theme.textMuted),
                ),
              ),
              data: (p) => const SizedBox.shrink(),
            ),
    );
  }

  Widget _buildEpubPagesStack(
    ReaderThemeData theme,
    List<PageChunk> pages,
    double columnWidth,
    double columnHeight,
    double horizontalPadding,
    TextStyle textStyle, {
    PaginationParams? params,
  }) {
    _currentChapterPages = pages;

    if (_paginatedChapterIndex != _currentChapterIndex) {
      _paginatedChapterIndex = _currentChapterIndex;
      final bool landingOnLastPage = (widget.pageIndexInChapter == -1 ||
              _currentPageIndexInChapter == -1) &&
          (_lastPageSentinelConsumedForChapter != _currentChapterIndex);

      if (landingOnLastPage) {
        _currentPageIndexInChapter = pages.isNotEmpty ? pages.length - 1 : 0;
        _lastPageSentinelConsumedForChapter = _currentChapterIndex;
      } else {
        final anchor = ref.read(activeReadingAnchorProvider);
        int resolvedAnchorPage = -1;
        if (anchor != null && anchor.chapterIndex == _currentChapterIndex) {
          resolvedAnchorPage = ref
              .read(activeReadingAnchorProvider.notifier)
              .resolvePageForCurrentAnchor(pages);
        }
        if (resolvedAnchorPage >= 0 && resolvedAnchorPage < pages.length) {
          _currentPageIndexInChapter = resolvedAnchorPage;
        } else {
          _currentPageIndexInChapter = _currentPageIndexInChapter.clamp(
            0,
            pages.isNotEmpty ? pages.length - 1 : 0,
          );
        }
      }

      if (_shouldUseInternalEpubPageController) {
        _isProgrammaticReanchoring = true;
        _recreateEpubPageController(_currentPageIndexInChapter, pages.length);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _isProgrammaticReanchoring = false;
          }
        });
      }

      final targetPage = _currentPageIndexInChapter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onEpubPageChanged?.call(_currentChapterIndex, targetPage);
        final currentAnchor = ref.read(activeReadingAnchorProvider);
        if (currentAnchor == null ||
            currentAnchor.chapterIndex != _currentChapterIndex) {
          if (targetPage < pages.length) {
            final chunk = pages[targetPage];
            ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
                  chapterIndex: _currentChapterIndex,
                  paragraphIndex: chunk.startParagraphIndex,
                  charOffset: chunk.startCharOffset,
                );
          }
        }
      });
    } else {
      // Resolve anchor position for this chapter
      final ttsState = ref.read(ttsStateProvider);
      final hasTtsSentence = (ttsState.isPlaying || ttsState.isPaused) &&
          ttsState.currentSentenceText.trim().isNotEmpty &&
          !widget.isUserDesyncedFromTts;
      int resolvedPage = -1;
      if (hasTtsSentence) {
        resolvedPage = _findTargetPageIndex(pages, ttsState.currentSentenceText);
      }
      if (resolvedPage < 0 || resolvedPage >= pages.length) {
        resolvedPage = ref
            .read(activeReadingAnchorProvider.notifier)
            .resolvePageForCurrentAnchor(pages);
      }
      resolvedPage =
          resolvedPage.clamp(0, pages.isNotEmpty ? pages.length - 1 : 0);

      final hasNoPositions = !_effectiveEpubPageController.hasClients ||
          _effectiveEpubPageController.positions.isEmpty;

      if (_shouldUseInternalEpubPageController) {
        if (_epubPageController == null ||
            (hasNoPositions &&
                _epubPageController!.initialPage != resolvedPage)) {
          _isProgrammaticReanchoring = true;
          _recreateEpubPageController(resolvedPage, pages.length);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isProgrammaticReanchoring = false;
            }
          });
        }
      }

      // Settings reactivity: if layout changed within the same chapter, preserve anchor position
      if (params != null &&
          _lastPaginationParams != null &&
          _lastPaginationParams!.chapterIndex == params.chapterIndex &&
          _lastPaginationParams != params) {
        _isProgrammaticReanchoring = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _currentPageIndexInChapter = resolvedPage;
          if (_isEpubPageControllerReady) {
            final curPage = _safeGetPage(_effectiveEpubPageController);
            if (curPage?.round() != resolvedPage) {
              _isProgrammaticReanchoring = true;
              _effectiveEpubPageController.jumpToPage(resolvedPage);
            }
          }
          widget.onEpubPageChanged?.call(_currentChapterIndex, resolvedPage);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isProgrammaticReanchoring = false;
            }
          });
        });
      }
    }

    if (params != null) {
      _lastPaginationParams = params;
    }

    final effectivePageCount = pages.isNotEmpty ? pages.length : 1;

    return Stack(
      children: [
        NotificationListener<OverscrollNotification>(
          onNotification: (notification) =>
              _onOverscroll(notification, pages.length),
          child: PageView.builder(
            key: ValueKey('epub_pageview_${widget.chapterIndex ?? _currentChapterIndex}'),
            controller: _effectiveEpubPageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: effectivePageCount,
            onPageChanged: (pageIndex) {
              _currentPageIndexInChapter = pageIndex;
              if (!_isProgrammaticReanchoring) {
                if (pageIndex < pages.length) {
                  final chunk = pages[pageIndex];
                  ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
                        chapterIndex: _currentChapterIndex,
                        paragraphIndex: chunk.startParagraphIndex,
                        charOffset: chunk.startCharOffset,
                      );
                }
              }
              widget.onEpubPageChanged?.call(_currentChapterIndex, pageIndex);
              _focusNode.requestFocus();
            },
          itemBuilder: (context, pageIndex) {
            if (pages.isEmpty) {
              return const SizedBox.shrink();
            }
            final chunk = pages[pageIndex];

            if (chunk.nodes.length == 1 && chunk.nodes.first is ImageNode) {
              return LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: Image.memory(
                    (chunk.nodes.first as ImageNode).bytes,
                    fit: BoxFit.contain,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                ),
              );
            }

            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: columnWidth,
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: EpubPaginationMetrics.topPadding,
                    bottom: EpubPaginationMetrics.bottomPadding,
                  ),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0.0,
                      maxHeight: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Page Header Info (Chapter & Page in Chapter)
                          SizedBox(
                            height: EpubPaginationMetrics.pageHeaderHeight,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: Spacing.sm),
                              child: Row(
                                children: [
                                  Text(
                                    'Page ${pageIndex + 1} of ${pages.length}',
                                    style: AppTypography.micro.copyWith(
                                      color: theme.textMuted,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: Spacing.sm),
                                      child: Divider(height: 1),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          for (final node in chunk.nodes)
                            Padding(
                              padding: EdgeInsets.only(
                                  bottom: ref.watch(readerSettingsProvider).paragraphSpacing),
                              child: _buildNodeWidget(
                                node,
                                textStyle,
                                theme,
                                viewportHeight: columnHeight,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),

        // Left hover/click arrow
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 60,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              excludeFromSemantics: true,
              onTap: goToPreviousPage,
              hoverColor: theme.textPrimary.withValues(alpha: 0.03),
              child: Center(
                child: PhosphorIcon(
                  PhosphorIconsLight.caretLeft,
                  size: 24,
                  color: theme.textMuted.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),

        // Right hover/click arrow
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 60,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              excludeFromSemantics: true,
              onTap: goToNextPage,
              hoverColor: theme.textPrimary.withValues(alpha: 0.03),
              child: Center(
                child: PhosphorIcon(
                  PhosphorIconsLight.caretRight,
                  size: 24,
                  color: theme.textMuted.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),

        // Default Page Progress Footer in Paginated Mode (smoothly cross-fades when TTS transport bar is visible)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: EpubPaginationMetrics.bottomHeadroom,
          child: AnimatedOpacity(
            opacity: (widget.isTtsBarVisible ||
                    ref.watch(ttsStateProvider.select((s) => s.isPlaying)))
                ? 0.0
                : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: IgnorePointer(
              ignoring: widget.isTtsBarVisible ||
                  ref.watch(ttsStateProvider.select((s) => s.isPlaying)),
              child: Center(
                child: Text(
                  '${_currentPageIndexInChapter + 1} / ${pages.length}',
                  key: const ValueKey('paginated_page_progress_footer'),
                  style: AppTypography.micro.copyWith(
                    color: theme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEpubContinuousView(
    ReaderThemeData theme,
    double columnWidth,
    double columnHeight,
    double horizontalPadding,
  ) {
    final totalChapters = widget.pageCount > 0 ? widget.pageCount : 1;
    final initialIndex = _currentChapterIndex.clamp(0, totalChapters - 1);

    final baseStyle = TextStyle(
      fontFamily: widget.settings.fontFamily,
      fontSize: widget.settings.fontSize,
      height: widget.settings.lineHeight,
      color: theme.textPrimary,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!_isProgrammaticNavigation && !_isProgrammaticReanchoring) {
          if (notification is ScrollStartNotification) {
            if (notification.dragDetails != null) {
              _onUserScrollStarted();
            }
          } else if (notification is ScrollUpdateNotification) {
            if (notification.dragDetails != null) {
              _onUserScrollStarted();
              _scheduleUserScrollEnded();
            }
            _scheduleContinuousAnchorDebounce();
          } else if (notification is ScrollEndNotification) {
            _onUserScrollEnded();
            _scheduleContinuousAnchorCommit();
          } else if (notification is UserScrollNotification) {
            if (notification.direction != ScrollDirection.idle) {
              _onUserScrollStarted();
            } else {
              _onUserScrollEnded();
              _scheduleContinuousAnchorCommit();
            }
          }
        }
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: _effectiveItemScrollController,
        itemPositionsListener: _effectiveItemPositionsListener,
        initialScrollIndex: initialIndex,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: horizontalPadding,
          right: horizontalPadding,
          top: Spacing.xl + 40.0,
          bottom: 96.0,
        ),
        itemCount: totalChapters,
        itemBuilder: (context, chapterIdx) {
          return _ContinuousChapterSectionWidget(
            filePath: widget.filePath,
            chapterIndex: chapterIdx,
            initialNodes: (chapterIdx == widget.chapterIndex &&
                    widget.epubNodes != null &&
                    widget.epubNodes!.isNotEmpty)
                ? widget.epubNodes
                : null,
            columnWidth: columnWidth,
            columnHeight: columnHeight,
            theme: theme,
            baseStyle: baseStyle,
            onPlayFromHere: widget.onPlayFromHere,
            isUserDesynced: widget.isUserDesyncedFromTts,
            onProgrammaticScroll: _setProgrammaticScroll,
          );
        },
      ),
    );
  }

  Widget _buildNodeWidget(
    DocumentNode node,
    TextStyle baseStyle,
    ReaderThemeData theme, {
    double? viewportHeight,
    int? paragraphIndex,
  }) {
    return _EpubScopedNodeWidget(
      node: node,
      chapterIndex: _currentChapterIndex,
      paragraphIndex: paragraphIndex,
      baseStyle: baseStyle,
      theme: theme,
      viewportHeight: viewportHeight,
      isUserDesynced: widget.isUserDesyncedFromTts,
      onProgrammaticScroll: _setProgrammaticScroll,
      isContinuous: !widget.settings.isPaginated,
      contextMenuBuilder: (context, editableTextState) {
        return _buildContextMenu(
          context,
          editableTextState,
          theme,
          nodeText: node.toPlainText(),
        );
      },
    );
  }

  // --- PDF Native/Fixed-Layout Fallback View Builders ---

  Widget _buildContinuousView(ReaderThemeData theme) {
    final effectivePageCount = widget.pageCount > 0 ? widget.pageCount : 1;

    return ScrollablePositionedList.builder(
      itemScrollController: _effectiveItemScrollController,
      itemPositionsListener: _effectiveItemPositionsListener,
      initialScrollIndex: widget.initialPageIndex.clamp(
        0,
        effectivePageCount - 1,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: widget.settings.horizontalPadding,
        vertical: Spacing.xl + 40.0,
      ),
      itemCount: effectivePageCount,
      itemBuilder: (context, index) {
        return Center(
          key: ValueKey('page_$index'),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: widget.settings.contentMaxWidth,
            ),
            child: _PageContentWidget(
              filePath: widget.filePath,
              pageIndex: index,
              settings: widget.settings,
              onPlayFromHere: widget.onPlayFromHere,
              isUserDesynced: widget.isUserDesyncedFromTts,
              onProgrammaticScroll: _setProgrammaticScroll,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaginatedView(ReaderThemeData theme) {
    final effectivePageCount = widget.pageCount > 0 ? widget.pageCount : 1;

    return Stack(
      children: [
        PageView.builder(
          controller: widget.pageController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: effectivePageCount,
          onPageChanged: (index) {
            _focusNode.requestFocus();
            widget.onPageChanged(index, 0.0);
          },
          itemBuilder: (context, index) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _focusNode.requestFocus();
                widget.onToggleChrome();
              },
              child: Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: widget.settings.contentMaxWidth,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.settings.horizontalPadding,
                    vertical: Spacing.xl + 40.0,
                  ),
                  child: SingleChildScrollView(
                    child: _PageContentWidget(
                      filePath: widget.filePath,
                      pageIndex: index,
                      settings: widget.settings,
                      onPlayFromHere: widget.onPlayFromHere,
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        // Left / Right page flip hover controls
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 60,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              excludeFromSemantics: true,
              onTap: goToPreviousPage,
              hoverColor: theme.textPrimary.withValues(alpha: 0.03),
              child: Center(
                child: PhosphorIcon(
                  PhosphorIconsLight.caretLeft,
                  size: 24,
                  color: theme.textMuted.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 60,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              excludeFromSemantics: true,
              onTap: goToNextPage,
              hoverColor: theme.textPrimary.withValues(alpha: 0.03),
              child: Center(
                child: PhosphorIcon(
                  PhosphorIconsLight.caretRight,
                  size: 24,
                  color: theme.textMuted.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),

        // Default Page Progress Footer for PDF/paginated mode (smoothly cross-fades when TTS transport bar is visible)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: EpubPaginationMetrics.bottomHeadroom,
          child: AnimatedOpacity(
            opacity: (widget.isTtsBarVisible ||
                    ref.watch(ttsStateProvider.select((s) => s.isPlaying)))
                ? 0.0
                : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: IgnorePointer(
              ignoring: widget.isTtsBarVisible ||
                  ref.watch(ttsStateProvider.select((s) => s.isPlaying)),
              child: Center(
                child: Text(
                  '${(_safeGetPage(widget.pageController)?.round() ?? widget.initialPageIndex) + 1} / $effectivePageCount',
                  key: const ValueKey('pdf_paginated_page_progress_footer'),
                  style: AppTypography.micro.copyWith(
                    color: theme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState state,
    ReaderThemeData theme, {
    String? nodeText,
  }) {
    return _buildReaderContextMenu(
      context,
      state,
      theme,
      onPlayFromHere: widget.onPlayFromHere,
      nodeText: nodeText,
    );
  }
}

class _PageContentWidget extends ConsumerStatefulWidget {
  const _PageContentWidget({
    required this.filePath,
    required this.pageIndex,
    required this.settings,
    this.onPlayFromHere,
    this.isUserDesynced = false,
    this.onProgrammaticScroll,
  });

  final String filePath;
  final int pageIndex;
  final ReaderSettings settings;
  final ValueChanged<String>? onPlayFromHere;
  final bool isUserDesynced;
  final void Function(bool isProgrammatic)? onProgrammaticScroll;

  @override
  ConsumerState<_PageContentWidget> createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends ConsumerState<_PageContentWidget> {
  void _scrollIntoMiddleThird() {
    if (!mounted || widget.isUserDesynced || widget.settings.isPaginated) return;
    final ttsState = ref.read(ttsStateProvider);
    if (!ttsState.isPlaying) return;

    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.hasSize) return;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;

    final viewportBox = scrollable.context.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return;

    final viewportHeight = viewportBox.size.height;
    final nodePos = renderBox.localToGlobal(Offset.zero, ancestor: viewportBox);
    final topInViewport = nodePos.dy;
    final bottomInViewport = topInViewport + renderBox.size.height;

    if (topInViewport > viewportHeight * 0.55 ||
        bottomInViewport < viewportHeight * 0.20) {
      widget.onProgrammaticScroll?.call(true);
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      ).then((_) {
        widget.onProgrammaticScroll?.call(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final pageAsync = ref.watch(
      documentPageContentProvider(
          (filePath: widget.filePath, pageIndex: widget.pageIndex)),
    );

    return pageAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        child: Center(
          child: Text(
            'Loading page ${widget.pageIndex + 1}...',
            style: AppTypography.micro.copyWith(color: theme.textMuted),
          ),
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text(
          'Error loading page ${widget.pageIndex + 1}: $err',
          style: AppTypography.body.copyWith(color: theme.textMuted),
        ),
      ),
      data: (content) {
        final text = TtsTextNormalizer.flattenSoftLineBreaks(content.plainText);
        final isPaginated = widget.settings.isPaginated;

        final isMatched = ref.watch(
          ttsStateProvider.select((s) {
            if (!s.isPlaying && !s.isPaused) return false;
            final sentence = s.currentSentenceText.trim();
            if (sentence.isEmpty || text.isEmpty) return false;
            return text.toLowerCase().contains(sentence.toLowerCase());
          }),
        );

        if (isMatched && !widget.isUserDesynced && !isPaginated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || widget.isUserDesynced) return;
            _scrollIntoMiddleThird();
          });
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: isPaginated ? Spacing.xl : Spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isPaginated)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Row(
                    children: [
                      Text(
                        'Page ${widget.pageIndex + 1}',
                        style: AppTypography.micro.copyWith(
                          color: theme.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: Spacing.sm),
                          child: Divider(height: 1),
                        ),
                      ),
                    ],
                  ),
                ),

              if (text.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  child: Text(
                    '[Non-text or image content]',
                    style: AppTypography.body.copyWith(
                      color: theme.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                SelectableText.rich(
                  _buildHighlightedTextSpan(
                    text: text,
                    baseStyle: TextStyle(
                      fontFamily: widget.settings.fontFamily,
                      fontSize: widget.settings.fontSize,
                      height: widget.settings.lineHeight,
                      color: theme.textPrimary,
                    ),
                    theme: theme,
                    ttsState: ref.watch(ttsStateProvider),
                  ),
                  textAlign: TextAlign.start,
                  onTap: () {
                    context.findAncestorStateOfType<ReaderCanvasState>()?.requestFocus();
                  },
                  contextMenuBuilder: (context, editableTextState) {
                    return _buildReaderContextMenu(
                      context,
                      editableTextState,
                      theme,
                      onPlayFromHere: widget.onPlayFromHere,
                      nodeText: text,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  TextSpan _buildHighlightedTextSpan({
    required String text,
    required TextStyle baseStyle,
    required ReaderThemeData theme,
    required TtsState ttsState,
  }) {
    final isTtsActive =
        (ttsState.isPlaying || ttsState.isPaused) &&
        ttsState.currentSentenceText.trim().isNotEmpty;

    final settings = ref.read(readerSettingsProvider);
    final sentenceHighlightStyle =
        settings.ttsHighlightStyle == TtsHighlightStyle.underline
            ? baseStyle.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: theme.accent,
                decorationThickness: 2.0,
              )
            : baseStyle.copyWith(
                backgroundColor: theme.ttsHighlight,
              );

    final paragraphRegex = RegExp(r'(?:\r?\n){2,}');
    final sentenceDelimiter = RegExp(
      r'''(?<!\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|e\.g|i\.e)\.["'”’]?)(?<=[.!?]["'”’]?)\s+(?=[A-Z0-9“"‘'])''',
    );

    final paragraphs = text
        .split(paragraphRegex)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final children = <InlineSpan>[];
    bool hasHighlighted = false;

    for (var pIdx = 0; pIdx < paragraphs.length; pIdx++) {
      if (pIdx > 0) {
        children.add(const TextSpan(text: '\n\n'));
      }

      final p = paragraphs[pIdx];
      final sentences = p
          .split(sentenceDelimiter)
          .map((s) => s.replaceFirst(RegExp(r'''^[”’»\)\]]+\s*'''), '').trim())
          .where((s) => s.isNotEmpty && RegExp(r'[a-zA-Z0-9]').hasMatch(s))
          .toList();

      if (sentences.isEmpty) {
        children.add(TextSpan(text: p, style: baseStyle));
        continue;
      }

      for (var sIdx = 0; sIdx < sentences.length; sIdx++) {
        if (sIdx > 0) {
          children.add(const TextSpan(text: ' '));
        }

        final sentence = sentences[sIdx];
        final bool isMatch = isTtsActive &&
            !hasHighlighted &&
            _isSentenceMatch(sentence, ttsState.currentSentenceText);

        if (isMatch) {
          hasHighlighted = true;
          children.add(
            TextSpan(text: sentence, style: sentenceHighlightStyle),
          );
        } else {
          children.add(TextSpan(text: sentence, style: baseStyle));
        }
      }
    }

    return TextSpan(
      style: baseStyle,
      children: children,
    );
  }

  bool _isSentenceMatch(String uiSentence, String ttsSentence) {
    final ui = uiSentence.trim();
    final tts = ttsSentence.trim();
    if (ui.isEmpty || tts.isEmpty) return false;
    if (ui == tts) return true;
    if (TtsTextNormalizer.normalizeAllCaps(ui) == tts) return true;
    return ui.toLowerCase() == tts.toLowerCase();
  }
}

String _extractSentenceAtOffset(String fullText, int offset) {
  if (fullText.trim().isEmpty) return '';
  final clamped = offset.clamp(0, fullText.length);

  // Look backward from clamped for sentence boundary
  var start = 0;
  for (var i = clamped - 1; i >= 0; i--) {
    final char = fullText[i];
    if (char == '\n') {
      start = i + 1;
      break;
    }
    if ((char == '.' || char == '!' || char == '?') && i + 1 < fullText.length) {
      var nextIdx = i + 1;
      while (nextIdx < fullText.length &&
          (fullText[nextIdx] == '"' ||
              fullText[nextIdx] == '”' ||
              fullText[nextIdx] == "'" ||
              fullText[nextIdx] == '’')) {
        nextIdx++;
      }
      if (nextIdx < fullText.length && RegExp(r'\s').hasMatch(fullText[nextIdx])) {
        start = nextIdx;
        while (start < fullText.length && RegExp(r'\s').hasMatch(fullText[start])) {
          start++;
        }
        break;
      }
    }
  }

  // Look forward from clamped for sentence boundary
  var end = fullText.length;
  for (var i = clamped; i < fullText.length; i++) {
    final char = fullText[i];
    if (char == '\n') {
      end = i;
      break;
    }
    if (char == '.' || char == '!' || char == '?') {
      var nextIdx = i + 1;
      while (nextIdx < fullText.length &&
          (fullText[nextIdx] == '"' ||
              fullText[nextIdx] == '”' ||
              fullText[nextIdx] == "'" ||
              fullText[nextIdx] == '’')) {
        nextIdx++;
      }
      end = nextIdx;
      break;
    }
  }

  if (start >= end) return fullText.trim();
  final extracted = fullText.substring(start, end).trim();
  return extracted.isNotEmpty ? extracted : fullText.trim();
}

Widget _buildReaderContextMenu(
  BuildContext context,
  EditableTextState state,
  ReaderThemeData theme, {
  ValueChanged<String>? onPlayFromHere,
  String? nodeText,
}) {
  final selectedText = state.textEditingValue.selection.textInside(
    state.textEditingValue.text,
  );
  final fullText = (nodeText != null && nodeText.isNotEmpty)
      ? nodeText
      : state.textEditingValue.text;
  final selectionStart = state.textEditingValue.selection.start;

  final items = <ContextMenuButtonItem>[
    if (selectedText.isNotEmpty && onPlayFromHere != null)
      ContextMenuButtonItem(
        label: 'Play from here',
        onPressed: () {
          final sentence = _extractSentenceAtOffset(
            fullText,
            selectionStart >= 0 ? selectionStart : 0,
          );
          onPlayFromHere(sentence.isNotEmpty ? sentence : selectedText);
          ContextMenuController.removeAny();
        },
      ),
    if (selectedText.isNotEmpty)
      ContextMenuButtonItem(
        label: 'Search Web',
        onPressed: () {
          _searchWeb(selectedText);
          ContextMenuController.removeAny();
        },
      ),
    ContextMenuButtonItem(
      label: 'Copy',
      onPressed: () {
        Clipboard.setData(ClipboardData(text: selectedText));
        ContextMenuController.removeAny();
      },
    ),
  ];

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: items,
  );
}

void _searchWeb(String query) {
  try {
    final encoded = Uri.encodeComponent(query.trim());
    final url = 'https://duckduckgo.com/?q=$encoded';
    if (Platform.isLinux) {
      Process.run('xdg-open', [url]);
    } else if (Platform.isMacOS) {
      Process.run('open', [url]);
    } else if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', url]);
    }
  } catch (_) {}
}

class _ContinuousChapterSectionWidget extends ConsumerWidget {
  final String filePath;
  final int chapterIndex;
  final List<DocumentNode>? initialNodes;
  final double columnWidth;
  final double columnHeight;
  final ReaderThemeData theme;
  final TextStyle baseStyle;
  final ValueChanged<String>? onPlayFromHere;
  final bool isUserDesynced;
  final void Function(bool isProgrammatic)? onProgrammaticScroll;

  const _ContinuousChapterSectionWidget({
    required this.filePath,
    required this.chapterIndex,
    this.initialNodes,
    required this.columnWidth,
    required this.columnHeight,
    required this.theme,
    required this.baseStyle,
    this.onPlayFromHere,
    this.isUserDesynced = false,
    this.onProgrammaticScroll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child;
    if (initialNodes != null && initialNodes!.isNotEmpty) {
      child = _buildContent(context, initialNodes!);
    } else {
      final nodesAsync = ref.watch(documentChapterNodesProvider((
        filePath: filePath,
        chapterIndex: chapterIndex,
      )));

      child = nodesAsync.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChapterHeaderWidget(
              filePath: filePath,
              chapterIndex: chapterIndex,
              columnWidth: columnWidth,
              theme: theme,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.xl),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
        ),
        error: (err, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChapterHeaderWidget(
              filePath: filePath,
              chapterIndex: chapterIndex,
              columnWidth: columnWidth,
              theme: theme,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
              child: Center(
                child: Text(
                  'Error loading chapter: $err',
                  style: AppTypography.micro.copyWith(color: theme.textMuted),
                ),
              ),
            ),
          ],
        ),
        data: (nodes) => _buildContent(context, nodes),
      );
    }

    return RepaintBoundary(child: child);
  }

  Widget _buildContent(BuildContext context, List<DocumentNode> nodes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChapterHeaderWidget(
          filePath: filePath,
          chapterIndex: chapterIndex,
          columnWidth: columnWidth,
          theme: theme,
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < nodes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: _EpubScopedNodeWidget(
                      node: nodes[i],
                      chapterIndex: chapterIndex,
                      paragraphIndex: i,
                      baseStyle: baseStyle,
                      theme: theme,
                      viewportHeight: columnHeight,
                      isUserDesynced: isUserDesynced,
                      onProgrammaticScroll: onProgrammaticScroll,
                      isContinuous: true,
                      contextMenuBuilder: (ctx, editableTextState) =>
                          _buildReaderContextMenu(
                        ctx,
                        editableTextState,
                        theme,
                        onPlayFromHere: onPlayFromHere,
                        nodeText: nodes[i].toPlainText(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterHeaderWidget extends ConsumerWidget {
  final String filePath;
  final int chapterIndex;
  final double columnWidth;
  final ReaderThemeData theme;

  const _ChapterHeaderWidget({
    required this.filePath,
    required this.chapterIndex,
    required this.columnWidth,
    required this.theme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleAsync = ref.watch(documentChapterTitleProvider((
      filePath: filePath,
      chapterIndex: chapterIndex,
    )));

    final title = titleAsync.asData?.value?.trim();
    final String label;
    if (title != null && title.isNotEmpty) {
      label = title;
    } else {
      label = 'Chapter ${chapterIndex + 1}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: columnWidth),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: Text(
                  label,
                  style: AppTypography.micro.copyWith(
                    color: theme.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
      ),
    );
  }
}

extension DocumentNodePlainTextX on DocumentNode {
  String toPlainText() {
    if (this is ParagraphNode) return (this as ParagraphNode).plainText;
    if (this is HeadingNode) return (this as HeadingNode).plainText;
    return '';
  }
}

List<InlineSpan> _buildDefaultSpans(DocumentNode node, TextStyle textStyle) {
  final List<TextSegment> segments = node is ParagraphNode
      ? node.segments
      : (node is HeadingNode ? node.segments : const []);
  return [
    for (final s in segments)
      TextSpan(
        text: s.text,
        style: textStyle.copyWith(
          fontWeight: s.isBold ? FontWeight.bold : null,
          fontStyle: s.isItalic ? FontStyle.italic : null,
        ),
      ),
  ];
}

class _EpubScopedNodeWidget extends ConsumerStatefulWidget {
  final DocumentNode node;
  final int? chapterIndex;
  final int? paragraphIndex;
  final TextStyle baseStyle;
  final ReaderThemeData theme;
  final double? viewportHeight;
  final Widget Function(BuildContext, EditableTextState)? contextMenuBuilder;
  final bool isUserDesynced;
  final void Function(bool isProgrammatic)? onProgrammaticScroll;
  final bool isContinuous;

  const _EpubScopedNodeWidget({
    required this.node,
    this.chapterIndex,
    this.paragraphIndex,
    required this.baseStyle,
    required this.theme,
    this.viewportHeight,
    this.contextMenuBuilder,
    this.isUserDesynced = false,
    this.onProgrammaticScroll,
    this.isContinuous = false,
  });

  @override
  ConsumerState<_EpubScopedNodeWidget> createState() =>
      _EpubScopedNodeWidgetState();
}

class _EpubScopedNodeWidgetState extends ConsumerState<_EpubScopedNodeWidget> {
  bool _wasMatched = false;
  int _lastSentenceIndex = -1;
  ReaderCanvasState? _parentCanvasState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final canvas = context.findAncestorStateOfType<ReaderCanvasState>();
    if (canvas != _parentCanvasState) {
      _parentCanvasState?._unregisterNodeState(this);
      _parentCanvasState = canvas;
      _parentCanvasState?._registerNodeState(this);
    }
  }

  @override
  void dispose() {
    _parentCanvasState?._unregisterNodeState(this);
    _parentCanvasState = null;
    super.dispose();
  }

  void scrollNodeIntoView({bool force = false}) {
    final readerSettings = ref.read(readerSettingsProvider);
    if (!mounted || !widget.isContinuous || !readerSettings.ttsAutoAdvance) return;
    if (widget.isUserDesynced) return;
    if (!force && _parentCanvasState?.isAutoScrollSuspendedByUser == true) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.position.hasPixels) return;

    final scrollableBox = scrollable.context.findRenderObject() as RenderBox?;
    if (scrollableBox == null || !scrollableBox.hasSize) return;

    // Viewport-relative coordinates (immune to chrome / window positioning):
    final localTopLeft =
        scrollableBox.globalToLocal(box.localToGlobal(Offset.zero));
    final double nodeDy = localTopLeft.dy;
    final double nodeHeight = box.size.height;
    final double viewportHeight = scrollableBox.size.height;

    // Approximate vertical offset of the active sentence within this node:
    final ttsState = ref.read(ttsStateProvider);
    final paragraphText = widget.node.toPlainText();
    final activeSentence = ttsState.currentSentenceText.trim();

    double sentenceDy = nodeDy;
    double sentenceBottomDy = nodeDy + nodeHeight;
    if (paragraphText.isNotEmpty && activeSentence.isNotEmpty) {
      final idx = paragraphText.indexOf(activeSentence);
      if (idx >= 0) {
        final fraction = idx / paragraphText.length;
        final lenFraction =
            (activeSentence.length / paragraphText.length).clamp(0.05, 1.0);
        sentenceDy = nodeDy + (nodeHeight * fraction);
        sentenceBottomDy = sentenceDy + (nodeHeight * lenFraction);
      }
    }

    // Dead-zone check:
    // Only scroll if nearing lower threshold (or bottom > viewport - 96.0),
    // or off-screen top (< 70px)
    const double bottomInset = 96.0;
    final double effectiveViewportHeight =
        (viewportHeight - bottomInset).clamp(100.0, viewportHeight);
    final bool isNearBottom = sentenceDy > effectiveViewportHeight * 0.65 ||
        sentenceBottomDy > viewportHeight - bottomInset;
    final bool isOffscreenTop = sentenceDy < 70.0;

    if (force || isNearBottom || isOffscreenTop) {
      // Bring active sentence into upper-middle third (around 35% from the top of effective viewport):
      final targetDyInViewport = effectiveViewportHeight * 0.35;
      final scrollDelta = sentenceDy - targetDyInViewport;
      final targetOffset = (scrollable.position.pixels + scrollDelta).clamp(
        scrollable.position.minScrollExtent,
        scrollable.position.maxScrollExtent,
      );

      if ((targetOffset - scrollable.position.pixels).abs() < 1.0) return;

      AppLogger.d(
          '>>> [TTS AUTO-SCROLL] Scrolling to matched node (dy: $sentenceDy -> targetOffset: $targetOffset, clamped: ${scrollable.position.minScrollExtent}..${scrollable.position.maxScrollExtent})');

      widget.onProgrammaticScroll?.call(true);
      _parentCanvasState?._setProgrammaticScroll(true);
      scrollable.position.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      ).then((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onProgrammaticScroll?.call(false);
            _parentCanvasState?._setProgrammaticScroll(false);
          }
        });
      }).catchError((_) {
        if (mounted) {
          widget.onProgrammaticScroll?.call(false);
          _parentCanvasState?._setProgrammaticScroll(false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.node is ImageNode) {
      final img = widget.node as ImageNode;
      Widget imageWidget = Image.memory(
        img.bytes,
        fit: BoxFit.contain,
        semanticLabel: img.altText,
      );

      if (widget.viewportHeight != null) {
        imageWidget = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.viewportHeight!),
          child: imageWidget,
        );
      }

      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: imageWidget,
        ),
      );
    }

    final paragraphText = widget.node.toPlainText();
    final ttsState = ref.watch(ttsStateProvider);
    final isTtsActive = ttsState.isPlaying || ttsState.isPaused;
    final currentSentenceIndex = ttsState.currentSentenceIndex;

    final isMatched = isTtsActive && (() {
      final sentence = ttsState.currentSentenceText.trim();
      if (sentence.isEmpty) return false;
      final plain = paragraphText.trim();
      if (plain.isEmpty) return false;
      if (plain.contains(sentence)) return true;

      final normPlain = plain.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      final normSentence =
          sentence.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (normPlain == normSentence) return true;
      if (normPlain.contains(normSentence) ||
          normSentence.contains(normPlain)) {
        return true;
      }
      return false;
    })();

    if (isMatched && !widget.isUserDesynced && widget.isContinuous) {
      final bool transitionToMatched = !_wasMatched;
      final bool sentenceIndexChanged = currentSentenceIndex != _lastSentenceIndex;
      if (transitionToMatched || sentenceIndexChanged) {
        _wasMatched = true;
        _lastSentenceIndex = currentSentenceIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollNodeIntoView();
        });
      }
    } else if (!isMatched) {
      _wasMatched = false;
      _lastSentenceIndex = -1;
    }

    TextStyle effectiveStyle = widget.baseStyle;
    if (widget.node is HeadingNode) {
      final scale =
          (1.6 - ((widget.node as HeadingNode).level * 0.1)).clamp(1.15, 1.6);
      effectiveStyle = widget.baseStyle.copyWith(
        fontSize: (widget.baseStyle.fontSize ?? 16.0) * scale,
        fontWeight: FontWeight.bold,
      );
    }

    final strutStyle = EpubPaginationMetrics.strutStyleFor(effectiveStyle);

    if (!isMatched) {
      return SelectableText.rich(
        TextSpan(
          style: effectiveStyle,
          children: _buildDefaultSpans(widget.node, effectiveStyle),
        ),
        textAlign: TextAlign.start,
        strutStyle: strutStyle,
        textScaler: TextScaler.noScaling,
        contextMenuBuilder: widget.contextMenuBuilder,
      );
    }

    return SelectableText.rich(
      _buildHighlightedNodeSpan(
        node: widget.node,
        textStyle: effectiveStyle,
        theme: widget.theme,
        ttsState: ttsState,
        highlightStyle: ref.watch(readerSettingsProvider).ttsHighlightStyle,
      ),
      textAlign: TextAlign.start,
      strutStyle: strutStyle,
      textScaler: TextScaler.noScaling,
      contextMenuBuilder: widget.contextMenuBuilder,
    );
  }
}


TextSpan _buildHighlightedNodeSpan({
  required DocumentNode node,
  required TextStyle textStyle,
  required ReaderThemeData theme,
  required TtsState ttsState,
  TtsHighlightStyle highlightStyle = TtsHighlightStyle.background,
}) {
  if (!ttsState.isPlaying && !ttsState.isPaused) {
    return TextSpan(children: _buildDefaultSpans(node, textStyle));
  }

  final paragraphText = node.toPlainText();
  final activeSentenceText = ttsState.currentSentenceText;

  final normNode = paragraphText.replaceAll(RegExp(r'\s+'), ' ').trim();
  final normSentence =
      activeSentenceText.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (normNode.isEmpty || normSentence.isEmpty) {
    return TextSpan(children: _buildDefaultSpans(node, textStyle));
  }

  final highlightedStyle = highlightStyle == TtsHighlightStyle.underline
      ? textStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: theme.accent,
          decorationThickness: 2.0,
        )
      : textStyle.copyWith(backgroundColor: theme.ttsHighlight);

  // Normalize whitespace and trim string comparison between node.toPlainText()
  // and ttsState.currentSentenceText so title sentences like "Chapter 3: Resolve"
  // match and highlight immediately on speech start.
  final isFullMatch = normNode.toLowerCase() == normSentence.toLowerCase() ||
      normSentence.toLowerCase().startsWith(normNode.toLowerCase());

  if (isFullMatch) {
    final spans = _buildDefaultSpans(
      node,
      highlightedStyle,
    );
    if (spans.isNotEmpty) {
      return TextSpan(
        style: highlightedStyle,
        children: spans,
      );
    }
    return TextSpan(
      text: paragraphText,
      style: highlightedStyle,
    );
  }

  int startIndex = -1;
  int endIndex = -1;

  if (paragraphText.contains(activeSentenceText)) {
    startIndex = paragraphText.indexOf(activeSentenceText);
    endIndex = startIndex + activeSentenceText.length;
  } else if (activeSentenceText.trim().isNotEmpty &&
      paragraphText.contains(activeSentenceText.trim())) {
    final trimmed = activeSentenceText.trim();
    startIndex = paragraphText.indexOf(trimmed);
    endIndex = startIndex + trimmed.length;
  } else {
    final words = normSentence.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty) {
      final pattern = RegExp(
        words.map(RegExp.escape).join(r'\s+'),
        caseSensitive: false,
      );
      final match = pattern.firstMatch(paragraphText);
      if (match != null) {
        startIndex = match.start;
        endIndex = match.end;
      }
    }
  }

  if (startIndex < 0 || endIndex <= startIndex) {
    return TextSpan(children: _buildDefaultSpans(node, textStyle));
  }

  return TextSpan(children: [
    if (startIndex > 0)
      TextSpan(text: paragraphText.substring(0, startIndex), style: textStyle),
    TextSpan(
      text: paragraphText.substring(startIndex, endIndex),
      style: highlightedStyle,
    ),
    if (endIndex < paragraphText.length)
      TextSpan(text: paragraphText.substring(endIndex), style: textStyle),
  ]);
}
