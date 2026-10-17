import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../constants/reader_layout_constants.dart';
import '../models/document_models.dart';
import '../models/reader_settings.dart';
import '../providers/document_content_provider.dart';
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

  DateTime _lastHorizontalSwipeTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOverscrollNavTime = DateTime.fromMillisecondsSinceEpoch(0);

  void _handleHorizontalScrollDelta(double dx, int pageCount) {
    final now = DateTime.now();
    if (now.difference(_lastHorizontalSwipeTime).inMilliseconds < 400) return;

    if (dx > 25.0) {
      _lastHorizontalSwipeTime = now;
      goToNextPage();
    } else if (dx < -25.0) {
      _lastHorizontalSwipeTime = now;
      goToPreviousPage();
    }
  }

  bool _onOverscroll(OverscrollNotification notification, int pageCount) {
    if (notification.dragDetails == null) return false;
    final now = DateTime.now();
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
      resolved = pages.isNotEmpty ? pages.length - 1 : 0;
      _lastPageSentinelConsumedForChapter = _currentChapterIndex;
    } else {
      resolved = pageIndex.clamp(0, pages.isNotEmpty ? pages.length - 1 : 0);
    }
    _currentPageIndexInChapter = resolved;
    final controller = _isEpub ? _effectiveEpubPageController : widget.pageController;
    final isReady = _isEpub ? _isEpubPageControllerReady : _isPageControllerReady;
    final curPage = _safeGetPage(controller);
    if (isReady) {
      if (curPage?.round() != resolved) {
        controller.jumpToPage(resolved);
      }
    } else if (_isEpub) {
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
  Timer? _prewarmTimer;

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
  }

  void _unregisterNodeState(_EpubScopedNodeWidgetState state) {
    _activeNodeStates.remove(state);
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
    _currentChapterIndex = widget.initialChapterIndex ??
        widget.chapterIndex ??
        widget.initialPageIndex.clamp(
          0,
          widget.pageCount > 0 ? widget.pageCount - 1 : 0,
        );
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

    final bool chapterChanged = widget.chapterIndex != null &&
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
        } else if (_isPageControllerReady) {
          widget.pageController.jumpToPage(0);
        }
      }
    }

    if (!oldWidget.settings.isPaginated && widget.settings.isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_isEpub && _isEpubPageControllerReady) {
            _epubPageController!.jumpToPage(_currentPageIndexInChapter);
          } else if (!_isEpub && _isPageControllerReady) {
            widget.pageController.jumpToPage(_currentPageIndexInChapter);
          }
        }
      });
    } else if (oldWidget.settings.isPaginated && !widget.settings.isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _effectiveItemScrollController.isAttached) {
          _effectiveItemScrollController.jumpTo(index: _currentChapterIndex);
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
    _prewarmTimer?.cancel();
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
      if (_effectiveItemScrollController.isAttached) {
        _isProgrammaticNavigation = true;
        _effectiveItemScrollController.scrollTo(
          index: _currentChapterIndex,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
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

    if (widget.settings.isPaginated) {
      if (_isPageControllerReady) {
        widget.pageController.jumpToPage(targetPageIndex);
      }
      return;
    }

    final controller = _effectiveItemScrollController;
    if (controller.isAttached) {
      controller.jumpTo(index: targetPageIndex);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.isAttached) {
          controller.jumpTo(index: targetPageIndex);
        }
      });
    }
  }

  void goToNextPage() {
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
        if (_isEpubPageControllerReady) {
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

    if (!_isProgrammaticNavigation) {
      widget.onUserNavigated?.call();
    }
    if (_isPageControllerReady) {
      widget.pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void goToPreviousPage() {
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
        if (_isEpubPageControllerReady) {
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

    if (!_isProgrammaticNavigation) {
      widget.onUserNavigated?.call();
    }
    if (_isPageControllerReady) {
      widget.pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
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

    if (widget.isUserDesyncedFromTts) {
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
      if (next.isPlaying && widget.settings.isPaginated) {
        final pages = _effectivePages;
        _checkAutoPageTurn(pages, next);
      }
    });

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          if (event.scrollDelta.dy.abs() > 1.0) {
            widget.onUserNavigated?.call();
          }
          if (widget.settings.isPaginated && event.scrollDelta.dx.abs() > 15.0) {
            widget.onUserNavigated?.call();
            final pages = _effectivePages;
            _handleHorizontalScrollDelta(event.scrollDelta.dx, pages.length);
          }
        }
      },
      onPointerMove: (event) {
        if (event.buttons != 0 || event.kind == PointerDeviceKind.touch) {
          widget.onUserNavigated?.call();
        }
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            goToPreviousPage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.space) {
            goToNextPage();
            return KeyEventResult.handled;
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
      paragraphSpacing: EpubPaginationMetrics.paragraphSpacing,
    );

    final pagesAsync = ref.watch(chapterPagesProvider(params));

    final pages = pagesAsync.asData?.value ??
        ((widget.epubChunks != null &&
                widget.epubChunks!.isNotEmpty &&
                widget.epubChunks!.first.chapterIndex == activeChapterIndex)
            ? widget.epubChunks
            : null);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: pages != null
          ? KeyedSubtree(
              key: ValueKey('paginated_pages_${activeChapterIndex}_${pages.length}'),
              child: _buildEpubPagesStack(
                theme,
                pages,
                columnWidth,
                columnHeight,
                horizontalPadding,
                textStyle,
                params: params,
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
        _currentPageIndexInChapter = _currentPageIndexInChapter.clamp(
          0,
          pages.isNotEmpty ? pages.length - 1 : 0,
        );
      }

      if (_shouldUseInternalEpubPageController) {
        _recreateEpubPageController(_currentPageIndexInChapter, pages.length);
      }

      final targetPage = _currentPageIndexInChapter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onEpubPageChanged?.call(_currentChapterIndex, targetPage);
        if (targetPage < pages.length) {
          final chunk = pages[targetPage];
          ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
                chapterIndex: _currentChapterIndex,
                paragraphIndex: chunk.startParagraphIndex,
                charOffset: chunk.startCharOffset,
              );
        }
      });
    } else {
      if (_shouldUseInternalEpubPageController && _epubPageController == null) {
        _recreateEpubPageController(_currentPageIndexInChapter, pages.length);
      }

      // Settings reactivity: if layout changed within the same chapter, preserve anchor position
      if (params != null &&
          _lastPaginationParams != null &&
          _lastPaginationParams!.chapterIndex == params.chapterIndex &&
          _lastPaginationParams != params) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final resolvedPage = ref
              .read(activeReadingAnchorProvider.notifier)
              .resolvePageForCurrentAnchor(pages);

          _currentPageIndexInChapter = resolvedPage;
          if (_isEpubPageControllerReady) {
            final curPage = _safeGetPage(_effectiveEpubPageController);
            if (curPage?.round() != resolvedPage) {
              _effectiveEpubPageController.jumpToPage(resolvedPage);
            }
          }
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
            itemCount: effectivePageCount,
            onPageChanged: (pageIndex) {
              _currentPageIndexInChapter = pageIndex;
              if (pageIndex < pages.length) {
                final chunk = pages[pageIndex];
                ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
                      chapterIndex: _currentChapterIndex,
                      paragraphIndex: chunk.startParagraphIndex,
                      charOffset: chunk.startCharOffset,
                    );
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
                              padding: const EdgeInsets.only(
                                  bottom: EpubPaginationMetrics.paragraphSpacing),
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

    return ScrollablePositionedList.builder(
      itemScrollController: _effectiveItemScrollController,
      itemPositionsListener: _effectiveItemPositionsListener,
      initialScrollIndex: initialIndex,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: Spacing.xl + 40.0,
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
    );
  }

  Widget _buildNodeWidget(
    DocumentNode node,
    TextStyle baseStyle,
    ReaderThemeData theme, {
    double? viewportHeight,
  }) {
    return _EpubScopedNodeWidget(
      node: node,
      chapterIndex: _currentChapterIndex,
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
          itemCount: effectivePageCount,
          onPageChanged: (index) {
            widget.onPageChanged(index, 0.0);
          },
          itemBuilder: (context, index) {
            return Center(
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

    final sentenceHighlightStyle = baseStyle.copyWith(
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
                for (final node in nodes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: _EpubScopedNodeWidget(
                      node: node,
                      chapterIndex: chapterIndex,
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
                        nodeText: node.toPlainText(),
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

  void _scrollToFollowHighlight() {
    if (!mounted || widget.isUserDesynced || !widget.isContinuous) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final viewportHeight = MediaQuery.maybeOf(context)?.size.height ??
        widget.viewportHeight ??
        800.0;

    double dy;
    try {
      dy = box.localToGlobal(Offset.zero).dy;
    } catch (_) {
      return;
    }
    final bottomDy = dy + box.size.height;

    // Calculate the approximate vertical offset of the active sentence within this node
    final ttsState = ref.read(ttsStateProvider);
    final paragraphText = widget.node.toPlainText();
    final activeSentence = ttsState.currentSentenceText.trim();

    double sentenceDy = dy;
    double sentenceBottomDy = bottomDy;
    if (paragraphText.isNotEmpty && activeSentence.isNotEmpty) {
      final idx = paragraphText.indexOf(activeSentence);
      if (idx >= 0) {
        final fraction = idx / paragraphText.length;
        final lenFraction =
            (activeSentence.length / paragraphText.length).clamp(0.05, 1.0);
        sentenceDy = dy + (box.size.height * fraction);
        sentenceBottomDy = sentenceDy + (box.size.height * lenFraction);
      }
    }

    if (sentenceDy > viewportHeight * 0.65 ||
        sentenceBottomDy > viewportHeight - 80 ||
        sentenceDy < 70) {
      final scrollable = Scrollable.maybeOf(context);
      if (scrollable != null && scrollable.position.hasPixels) {
        final targetOffset = (scrollable.position.pixels +
                (sentenceDy - viewportHeight * 0.30))
            .clamp(
          scrollable.position.minScrollExtent,
          scrollable.position.maxScrollExtent,
        );
        debugPrint(
            '>>> [TTS AUTO-SCROLL] Scrolling to matched node (dy: $sentenceDy -> targetOffset:$targetOffset)');
        widget.onProgrammaticScroll?.call(true);
        scrollable.position.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onProgrammaticScroll?.call(false);
            }
          });
        }).catchError((_) {
          if (mounted) {
            widget.onProgrammaticScroll?.call(false);
          }
        });
      } else {
        widget.onProgrammaticScroll?.call(true);
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onProgrammaticScroll?.call(false);
            }
          });
        }).catchError((_) {
          if (mounted) {
            widget.onProgrammaticScroll?.call(false);
          }
        });
      }
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
          _scrollToFollowHighlight();
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

  // Normalize whitespace and trim string comparison between node.toPlainText()
  // and ttsState.currentSentenceText so title sentences like "Chapter 3: Resolve"
  // match and highlight immediately on speech start.
  final isFullMatch = normNode.toLowerCase() == normSentence.toLowerCase() ||
      normSentence.toLowerCase().startsWith(normNode.toLowerCase());

  if (isFullMatch) {
    final spans = _buildDefaultSpans(
      node,
      textStyle.copyWith(backgroundColor: theme.ttsHighlight),
    );
    if (spans.isNotEmpty) {
      return TextSpan(
        style: textStyle.copyWith(backgroundColor: theme.ttsHighlight),
        children: spans,
      );
    }
    return TextSpan(
      text: paragraphText,
      style: textStyle.copyWith(backgroundColor: theme.ttsHighlight),
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
      style: textStyle.copyWith(backgroundColor: theme.ttsHighlight),
    ),
    if (endIndex < paragraphText.length)
      TextSpan(text: paragraphText.substring(endIndex), style: textStyle),
  ]);
}
