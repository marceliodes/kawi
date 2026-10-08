import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
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

  @override
  ConsumerState<ReaderCanvas> createState() => ReaderCanvasState();
}

class ReaderCanvasState extends ConsumerState<ReaderCanvas> {
  final FocusNode _focusNode = FocusNode();
  ItemScrollController? _internalItemScrollController;
  ItemPositionsListener? _internalItemPositionsListener;

  bool get _isEpub =>
      widget.isEpub == true || widget.filePath.toLowerCase().endsWith('.epub');

  int _currentChapterIndex = 0;
  int _currentPageIndexInChapter = 0;
  List<PageChunk> _currentChapterPages = const [];
  PaginationParams? _lastPaginationParams;

  ItemScrollController get _effectiveItemScrollController =>
      widget.itemScrollController ??
      (_internalItemScrollController ??= ItemScrollController());

  ItemPositionsListener get _effectiveItemPositionsListener =>
      widget.itemPositionsListener ??
      (_internalItemPositionsListener ??= ItemPositionsListener.create());

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

    _effectiveItemPositionsListener.itemPositions.addListener(
      _onPositionsChanged,
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

    if (widget.chapterIndex != oldWidget.chapterIndex) {
      final newIndex = widget.chapterIndex ?? 0;
      _currentChapterIndex = newIndex;
      _currentPageIndexInChapter = 0;
      if (widget.settings.isPaginated) {
        if (widget.pageController.hasClients) {
          widget.pageController.jumpToPage(0);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.pageController.hasClients) {
              widget.pageController.jumpToPage(0);
            }
          });
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
        widget.pageIndexInChapter != _currentPageIndexInChapter) {
      _currentPageIndexInChapter = widget.pageIndexInChapter!;
    } else if (widget.initialPageIndex != oldWidget.initialPageIndex) {
      _currentChapterIndex = widget.initialPageIndex.clamp(
        0,
        widget.pageCount > 0 ? widget.pageCount - 1 : 0,
      );
      _currentPageIndexInChapter = 0;
      if (widget.settings.isPaginated) {
        if (widget.pageController.hasClients) {
          widget.pageController.jumpToPage(0);
        }
      }
    }

    if (!oldWidget.settings.isPaginated && widget.settings.isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.pageController.hasClients) {
          widget.pageController.jumpToPage(_currentPageIndexInChapter);
        }
      });
    } else if (oldWidget.settings.isPaginated && !widget.settings.isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _effectiveItemScrollController.isAttached) {
          _effectiveItemScrollController.jumpTo(index: _currentChapterIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    _effectiveItemPositionsListener.itemPositions.removeListener(
      _onPositionsChanged,
    );
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

    final visible = positions
        .where((pos) => pos.itemTrailingEdge > 0.0)
        .toList();
    final sorted = (visible.isNotEmpty ? visible : positions.toList())
      ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    final visibleChapterIndex = sorted.first.index;

    if (visibleChapterIndex != _currentChapterIndex) {
      _currentChapterIndex = visibleChapterIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onChapterChanged?.call(visibleChapterIndex);
        widget.onPageChanged(visibleChapterIndex, 0.0);
      });
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
        _currentPageIndexInChapter = 0;
      });
      if (widget.settings.isPaginated) {
        if (widget.pageController.hasClients) {
          widget.pageController.jumpToPage(0);
        }
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
      if (widget.pageController.hasClients) {
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

  void _goToNextPageOrChapter() {
    if (_isEpub) {
      if (_currentPageIndexInChapter < _currentChapterPages.length - 1) {
        if (widget.pageController.hasClients) {
          widget.pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      } else if (widget.onNextChapter != null) {
        widget.onNextChapter!();
      } else if (_currentChapterIndex < widget.pageCount - 1) {
        setState(() {
          _currentChapterIndex++;
          _currentPageIndexInChapter = 0;
        });
        if (widget.pageController.hasClients) {
          widget.pageController.jumpToPage(0);
        }
        widget.onPageChanged(_currentChapterIndex, 0.0);
        widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
      }
      return;
    }

    if (widget.pageController.hasClients) {
      widget.pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPreviousPageOrChapter() {
    if (_isEpub) {
      if (_currentPageIndexInChapter > 0) {
        if (widget.pageController.hasClients) {
          widget.pageController.previousPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        }
      } else if (widget.onPreviousChapter != null) {
        widget.onPreviousChapter!();
      } else if (_currentChapterIndex > 0) {
        setState(() {
          _currentChapterIndex--;
          _currentPageIndexInChapter = 0;
        });
        if (widget.pageController.hasClients) {
          widget.pageController.jumpToPage(0);
        }
        widget.onPageChanged(_currentChapterIndex, 0.0);
        widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
      }
      return;
    }

    if (widget.pageController.hasClients) {
      widget.pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _checkAutoPageTurn(List<PageChunk> pages, TtsState ttsState) {
    if (!widget.settings.isPaginated || pages.isEmpty || !ttsState.isPlaying) {
      return;
    }

    final currentSentence = ttsState.currentSentenceText.trim();
    if (currentSentence.isEmpty) return;

    final currentIdx =
        _currentPageIndexInChapter.clamp(0, pages.length - 1);
    final currentPage = pages[currentIdx];
    final lowerSentence = currentSentence.toLowerCase();
    final lowerCurrentPage = currentPage.plainText.toLowerCase();

    // If active page already contains this sentence, keep current page
    if (lowerCurrentPage.contains(lowerSentence)) {
      return;
    }

    // Check if subsequent pages contain the sentence
    for (var i = currentIdx + 1; i < pages.length; i++) {
      if (pages[i].plainText.toLowerCase().contains(lowerSentence)) {
        if (widget.pageController.hasClients &&
            widget.pageController.page?.round() != i) {
          widget.pageController.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
        return;
      }
    }

    // Handle split sentence between currentIdx and currentIdx + 1:
    // If the next page contains the active sentence or its continuation, advance to it.
    final nextIdx = currentIdx + 1;
    if (nextIdx < pages.length) {
      final nextPage = pages[nextIdx];
      final lowerNextPage = nextPage.plainText.toLowerCase().trim();
      if (lowerNextPage.isNotEmpty &&
          (lowerSentence.contains(lowerNextPage) || lowerNextPage.contains(lowerSentence)) &&
          !lowerCurrentPage.contains(lowerSentence)) {
        if (widget.pageController.hasClients &&
            widget.pageController.page?.round() != nextIdx) {
          widget.pageController.animateToPage(
            nextIdx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
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
        _checkAutoPageTurn(_currentChapterPages, next);
      }
    });

    debugPrint('>>> [PROBE] ReaderCanvas _isEpub: $_isEpub | widget.isEpub: ${widget.isEpub} | isPaginated: $isPaginated');

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            _goToPreviousPageOrChapter();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _goToNextPageOrChapter();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onToggleChrome,
        child: _isEpub
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final columnWidth = (constraints.maxWidth -
                          (widget.settings.horizontalPadding * 2))
                      .clamp(100.0, widget.settings.contentMaxWidth);
                  final columnHeight = (constraints.maxHeight -
                          (Spacing.xl * 2 + 80.0) -
                          32.0)
                      .clamp(100.0, constraints.maxHeight);

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

    if (widget.epubChunks != null) {
      return _buildEpubPagesStack(
        theme,
        widget.epubChunks!,
        columnWidth,
        columnHeight,
        horizontalPadding,
        textStyle,
      );
    }

    final params = PaginationParams(
      filePath: widget.filePath,
      chapterIndex: _currentChapterIndex,
      maxWidth: columnWidth,
      maxHeight: columnHeight,
      textStyle: textStyle,
      paragraphSpacing: 16.0,
    );

    final pagesAsync = ref.watch(chapterPagesProvider(params));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: pagesAsync.when(
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
        data: (pages) => KeyedSubtree(
          key: ValueKey('paginated_pages_${_currentChapterIndex}_${pages.length}'),
          child: _buildEpubPagesStack(
            theme,
            pages,
            columnWidth,
            columnHeight,
            horizontalPadding,
            textStyle,
            params: params,
          ),
        ),
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

    // Settings reactivity: if layout changed within the same chapter, preserve anchor position
    if (params != null &&
        _lastPaginationParams != null &&
        _lastPaginationParams!.chapterIndex == params.chapterIndex &&
        _lastPaginationParams != params) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetPage = ref
            .read(activeReadingAnchorProvider.notifier)
            .resolvePageForCurrentAnchor(pages);

        if (widget.pageController.hasClients &&
            widget.pageController.page?.round() != targetPage) {
          widget.pageController.jumpToPage(targetPage);
        }
      });
    } else if (params != null &&
        _lastPaginationParams != null &&
        _lastPaginationParams!.chapterIndex != params.chapterIndex) {
      final targetPage = widget.pageIndexInChapter ?? 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.pageController.hasClients &&
            widget.pageController.page?.round() != targetPage) {
          widget.pageController.jumpToPage(targetPage);
        }
      });
    } else if (_lastPaginationParams == null) {
      final targetPage = widget.pageIndexInChapter ?? 0;
      if (targetPage > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (widget.pageController.hasClients &&
              widget.pageController.page?.round() != targetPage) {
            widget.pageController.jumpToPage(targetPage);
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
        PageView.builder(
          controller: widget.pageController,
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
            widget.onPageChanged(_currentChapterIndex, 0.0);
            widget.onEpubPageChanged?.call(_currentChapterIndex, pageIndex);
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

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: columnWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: Spacing.xl + 40.0,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Page Header Info (Chapter & Page in Chapter)
                        Padding(
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

                        for (final node in chunk.nodes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
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
            );
          },
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
              onTap: _goToPreviousPageOrChapter,
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
              onTap: _goToNextPageOrChapter,
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
      baseStyle: baseStyle,
      theme: theme,
      viewportHeight: viewportHeight,
      contextMenuBuilder: (context, editableTextState) {
        return _buildContextMenu(context, editableTextState, theme);
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
              onTap: () {
                if (widget.pageController.hasClients) {
                  widget.pageController.previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  );
                }
              },
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
              onTap: () {
                if (widget.pageController.hasClients) {
                  widget.pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  );
                }
              },
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
    ReaderThemeData theme,
  ) {
    return _buildReaderContextMenu(
      context,
      state,
      theme,
      onPlayFromHere: widget.onPlayFromHere,
    );
  }
}

class _PageContentWidget extends ConsumerWidget {
  const _PageContentWidget({
    required this.filePath,
    required this.pageIndex,
    required this.settings,
    this.onPlayFromHere,
  });

  final String filePath;
  final int pageIndex;
  final ReaderSettings settings;
  final ValueChanged<String>? onPlayFromHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final pageAsync = ref.watch(
      documentPageContentProvider((filePath: filePath, pageIndex: pageIndex)),
    );

    return pageAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        child: Center(
          child: Text(
            'Loading page ${pageIndex + 1}...',
            style: AppTypography.micro.copyWith(color: theme.textMuted),
          ),
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text(
          'Error loading page ${pageIndex + 1}: $err',
          style: AppTypography.body.copyWith(color: theme.textMuted),
        ),
      ),
      data: (content) {
        final text = TtsTextNormalizer.flattenSoftLineBreaks(content.plainText);
        final isPaginated = settings.isPaginated;

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
                        'Page ${pageIndex + 1}',
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
                      fontFamily: settings.fontFamily,
                      fontSize: settings.fontSize,
                      height: settings.lineHeight,
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
                      onPlayFromHere: onPlayFromHere,
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

Widget _buildReaderContextMenu(
  BuildContext context,
  EditableTextState state,
  ReaderThemeData theme, {
  ValueChanged<String>? onPlayFromHere,
}) {
  final selectedText = state.textEditingValue.selection.textInside(
    state.textEditingValue.text,
  );

  final items = <ContextMenuButtonItem>[
    if (selectedText.isNotEmpty && onPlayFromHere != null)
      ContextMenuButtonItem(
        label: 'Play from here',
        onPressed: () {
          onPlayFromHere(selectedText);
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

  const _ContinuousChapterSectionWidget({
    required this.filePath,
    required this.chapterIndex,
    this.initialNodes,
    required this.columnWidth,
    required this.columnHeight,
    required this.theme,
    required this.baseStyle,
    this.onPlayFromHere,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialNodes != null && initialNodes!.isNotEmpty) {
      return _buildContent(context, initialNodes!);
    }

    final nodesAsync = ref.watch(documentChapterNodesProvider((
      filePath: filePath,
      chapterIndex: chapterIndex,
    )));

    return nodesAsync.when(
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
                      baseStyle: baseStyle,
                      theme: theme,
                      viewportHeight: columnHeight,
                      contextMenuBuilder: (ctx, editableTextState) =>
                          _buildReaderContextMenu(
                        ctx,
                        editableTextState,
                        theme,
                        onPlayFromHere: onPlayFromHere,
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

class _EpubScopedNodeWidget extends ConsumerWidget {
  final DocumentNode node;
  final TextStyle baseStyle;
  final ReaderThemeData theme;
  final double? viewportHeight;
  final Widget Function(BuildContext, EditableTextState)? contextMenuBuilder;

  const _EpubScopedNodeWidget({
    required this.node,
    required this.baseStyle,
    required this.theme,
    this.viewportHeight,
    this.contextMenuBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (node is ImageNode) {
      final img = node as ImageNode;
      Widget imageWidget = Image.memory(
        img.bytes,
        fit: BoxFit.contain,
        semanticLabel: img.altText,
      );

      if (viewportHeight != null) {
        imageWidget = ConstrainedBox(
          constraints: BoxConstraints(maxHeight: viewportHeight!),
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

    final paragraphText = node.toPlainText();

    final isMatched = ref.watch(
      ttsStateProvider.select((s) {
        if (!s.isPlaying && !s.isPaused) return false;
        final sentence = s.currentSentenceText.trim();
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
      }),
    );

    TextStyle effectiveStyle = baseStyle;
    if (node is HeadingNode) {
      final scale =
          (1.6 - ((node as HeadingNode).level * 0.1)).clamp(1.15, 1.6);
      effectiveStyle = baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16.0) * scale,
        fontWeight: FontWeight.bold,
      );
    }

    if (!isMatched) {
      return SelectableText.rich(
        TextSpan(children: _buildDefaultSpans(node, effectiveStyle)),
        textAlign: TextAlign.start,
        contextMenuBuilder: contextMenuBuilder,
      );
    }

    final ttsState = ref.watch(ttsStateProvider);

    return SelectableText.rich(
      _buildHighlightedNodeSpan(
        node: node,
        textStyle: effectiveStyle,
        theme: theme,
        ttsState: ttsState,
      ),
      textAlign: TextAlign.start,
      contextMenuBuilder: contextMenuBuilder,
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
