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
  });

  final String filePath;
  final int pageCount;
  final ReaderSettings settings;
  final int initialPageIndex;
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

  @override
  ConsumerState<ReaderCanvas> createState() => ReaderCanvasState();
}

class ReaderCanvasState extends ConsumerState<ReaderCanvas> {
  final FocusNode _focusNode = FocusNode();
  ItemScrollController? _internalItemScrollController;
  ItemPositionsListener? _internalItemPositionsListener;

  bool get _isEpub =>
      widget.isEpub ??
      (widget.filePath.toLowerCase().endsWith('.epub') &&
          File(widget.filePath).existsSync());

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
    _currentChapterIndex = widget.chapterIndex ??
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

    if (widget.chapterIndex != null &&
        widget.chapterIndex != _currentChapterIndex) {
      _currentChapterIndex = widget.chapterIndex!;
      _currentPageIndexInChapter = widget.pageIndexInChapter ?? 0;
    } else if (widget.pageIndexInChapter != null &&
        widget.pageIndexInChapter != _currentPageIndexInChapter) {
      _currentPageIndexInChapter = widget.pageIndexInChapter!;
    } else if (widget.initialPageIndex != oldWidget.initialPageIndex) {
      _currentChapterIndex = widget.initialPageIndex.clamp(
        0,
        widget.pageCount > 0 ? widget.pageCount - 1 : 0,
      );
      _currentPageIndexInChapter = 0;
      if (widget.pageController.hasClients) {
        widget.pageController.jumpToPage(0);
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
          _effectiveItemScrollController.jumpTo(index: widget.initialPageIndex);
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
    if (!mounted || widget.settings.isPaginated || _isEpub) return;

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

  void scrollToPage(int targetPageIndex) {
    if (_isEpub) {
      setState(() {
        _currentChapterIndex = targetPageIndex.clamp(
          0,
          widget.pageCount > 0 ? widget.pageCount - 1 : 0,
        );
        _currentPageIndexInChapter = 0;
      });
      if (widget.pageController.hasClients) {
        widget.pageController.jumpToPage(0);
      }
      widget.onPageChanged(_currentChapterIndex, 0.0);
      widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
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
    // If the next page contains the active spoken word and current page does not,
    // advance to next page.
    final nextIdx = currentIdx + 1;
    if (nextIdx < pages.length) {
      final nextPage = pages[nextIdx];
      final currentWord = ttsState.currentWord.trim().toLowerCase();
      if (currentWord.isNotEmpty &&
          nextPage.plainText.toLowerCase().contains(currentWord) &&
          !lowerCurrentPage.contains(currentWord)) {
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

    return pagesAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: theme.accent),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error paginating chapter: $err',
          style: AppTypography.body.copyWith(color: theme.textMuted),
        ),
      ),
      data: (pages) => _buildEpubPagesStack(
        theme,
        pages,
        columnWidth,
        columnHeight,
        horizontalPadding,
        textStyle,
        params: params,
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

    // Settings reactivity: if layout changed, preserve anchor position
    if (params != null && _lastPaginationParams != null && _lastPaginationParams != params) {
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
    }
    if (params != null) {
      _lastPaginationParams = params;
    }

    // Auto-turn check on TTS progress
    final ttsState = ref.watch(ttsStateProvider);
    if (ttsState.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkAutoPageTurn(pages, ttsState);
      });
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

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: columnWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: Spacing.xl + 40.0,
                  ),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
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
                              ttsState,
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
    double horizontalPadding,
  ) {
    if (widget.epubNodes != null) {
      return _buildEpubListView(
        theme,
        widget.epubNodes!,
        columnWidth,
        horizontalPadding,
      );
    }

    final chapterNodesAsync = ref.watch(
      documentChapterNodesProvider((
        filePath: widget.filePath,
        chapterIndex: _currentChapterIndex,
      )),
    );

    return chapterNodesAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: theme.accent),
      ),
      error: (err, _) => Center(
        child: Text(
          'Error loading chapter: $err',
          style: AppTypography.body.copyWith(color: theme.textMuted),
        ),
      ),
      data: (nodes) => _buildEpubListView(
        theme,
        nodes,
        columnWidth,
        horizontalPadding,
      ),
    );
  }

  Widget _buildEpubListView(
    ReaderThemeData theme,
    List<DocumentNode> nodes,
    double columnWidth,
    double horizontalPadding,
  ) {
    final ttsState = ref.watch(ttsStateProvider);
    final baseStyle = TextStyle(
      fontFamily: widget.settings.fontFamily,
      fontSize: widget.settings.fontSize,
      height: widget.settings.lineHeight,
      color: theme.textPrimary,
    );

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: Spacing.xl + 40.0,
      ),
      itemCount: nodes.length + 1,
      itemBuilder: (context, index) {
        if (index == nodes.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_currentChapterIndex > 0)
                  TextButton.icon(
                    onPressed: () {
                      if (widget.onPreviousChapter != null) {
                        widget.onPreviousChapter!();
                      } else {
                        setState(() {
                          _currentChapterIndex--;
                        });
                        widget.onPageChanged(_currentChapterIndex, 0.0);
                        widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
                      }
                    },
                    icon: const PhosphorIcon(
                      PhosphorIconsLight.arrowLeft,
                      size: 18,
                    ),
                    label: const Text('Previous Chapter'),
                  ),
                const SizedBox(width: Spacing.md),
                if (_currentChapterIndex < widget.pageCount - 1)
                  TextButton.icon(
                    onPressed: () {
                      if (widget.onNextChapter != null) {
                        widget.onNextChapter!();
                      } else {
                        setState(() {
                          _currentChapterIndex++;
                        });
                        widget.onPageChanged(_currentChapterIndex, 0.0);
                        widget.onEpubPageChanged?.call(_currentChapterIndex, 0);
                      }
                    },
                    icon: const PhosphorIcon(
                      PhosphorIconsLight.arrowRight,
                      size: 18,
                    ),
                    label: const Text('Next Chapter'),
                  ),
              ],
            ),
          );
        }

        final node = nodes[index];
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildNodeWidget(node, baseStyle, theme, ttsState),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNodeWidget(
    DocumentNode node,
    TextStyle baseStyle,
    ReaderThemeData theme,
    TtsState ttsState,
  ) {
    if (node is ImageNode) {
      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            node.bytes,
            fit: BoxFit.contain,
            semanticLabel: node.altText,
          ),
        ),
      );
    }

    if (node is HeadingNode) {
      final scale = (1.6 - (node.level * 0.1)).clamp(1.15, 1.6);
      final headingStyle = baseStyle.copyWith(
        fontSize: (baseStyle.fontSize ?? 16.0) * scale,
        fontWeight: FontWeight.bold,
      );
      return SelectableText.rich(
        _buildHighlightedNodeSpan(
          node: node,
          baseStyle: headingStyle,
          theme: theme,
          ttsState: ttsState,
        ),
        textAlign: TextAlign.start,
        contextMenuBuilder: (context, editableTextState) {
          return _buildContextMenu(context, editableTextState, theme);
        },
      );
    }

    if (node is ParagraphNode) {
      return SelectableText.rich(
        _buildHighlightedNodeSpan(
          node: node,
          baseStyle: baseStyle,
          theme: theme,
          ttsState: ttsState,
        ),
        textAlign: TextAlign.start,
        contextMenuBuilder: (context, editableTextState) {
          return _buildContextMenu(context, editableTextState, theme);
        },
      );
    }

    return const SizedBox.shrink();
  }

  TextSpan _buildHighlightedNodeSpan({
    required DocumentNode node,
    required TextStyle baseStyle,
    required ReaderThemeData theme,
    required TtsState ttsState,
  }) {
    final List<TextSegment> segments = node is ParagraphNode
        ? node.segments
        : (node as HeadingNode).segments;

    final plainText = node is ParagraphNode
        ? node.plainText
        : (node as HeadingNode).plainText;

    final isTtsActive =
        (ttsState.isPlaying || ttsState.isPaused) &&
        ttsState.currentSentenceText.trim().isNotEmpty;

    final currentSentence = ttsState.currentSentenceText.trim();
    final lowerPlain = plainText.toLowerCase();
    final lowerSentence = currentSentence.toLowerCase();

    int matchIndex = -1;
    int matchEnd = -1;

    if (lowerPlain.contains(lowerSentence)) {
      matchIndex = lowerPlain.indexOf(lowerSentence);
      matchEnd = matchIndex + currentSentence.length;
    } else if (lowerPlain.trim().isNotEmpty &&
        lowerSentence.contains(lowerPlain.trim())) {
      matchIndex = 0;
      matchEnd = plainText.length;
    } else {
      final minLen = currentSentence.length < plainText.length
          ? currentSentence.length
          : plainText.length;
      for (var len = minLen; len >= 8; len--) {
        final prefix = lowerSentence.substring(0, len).trim();
        if (prefix.isNotEmpty && lowerPlain.endsWith(prefix)) {
          matchIndex = lowerPlain.lastIndexOf(prefix);
          matchEnd = plainText.length;
          break;
        }
      }
      if (matchIndex < 0) {
        for (var len = minLen; len >= 8; len--) {
          final suffix =
              lowerSentence.substring(lowerSentence.length - len).trim();
          if (suffix.isNotEmpty && lowerPlain.startsWith(suffix)) {
            matchIndex = 0;
            matchEnd = suffix.length;
            break;
          }
        }
      }
    }

    if (!isTtsActive || currentSentence.isEmpty || matchIndex < 0) {
      return TextSpan(
        style: baseStyle,
        children: [
          for (final s in segments)
            TextSpan(
              text: s.text,
              style: TextStyle(
                fontWeight: s.isBold ? FontWeight.bold : null,
                fontStyle: s.isItalic ? FontStyle.italic : null,
              ),
            ),
        ],
      );
    }

    final sentenceHighlightStyle = baseStyle.copyWith(
      backgroundColor: theme.ttsHighlight,
    );

    final children = <InlineSpan>[];
    var charAccumulator = 0;

    for (final seg in segments) {
      final segStart = charAccumulator;
      final segEnd = charAccumulator + seg.text.length;
      charAccumulator = segEnd;

      final segStyle = TextStyle(
        fontWeight: seg.isBold ? FontWeight.bold : null,
        fontStyle: seg.isItalic ? FontStyle.italic : null,
      );

      if (segEnd <= matchIndex || segStart >= matchEnd) {
        children.add(TextSpan(text: seg.text, style: segStyle));
        continue;
      }

      final overlapStart = (matchIndex - segStart).clamp(0, seg.text.length);
      final overlapEnd = (matchEnd - segStart).clamp(0, seg.text.length);

      final before = seg.text.substring(0, overlapStart);
      final highlighted = seg.text.substring(overlapStart, overlapEnd);
      final after = seg.text.substring(overlapEnd);

      if (before.isNotEmpty) {
        children.add(TextSpan(text: before, style: segStyle));
      }
      if (highlighted.isNotEmpty) {
        int wordStartInSeg = -1;
        int wordEndInSeg = -1;

        if (ttsState.currentWord.trim().isNotEmpty) {
          final cleanWord = ttsState.currentWord.trim();
          final wordRegex = RegExp(
            r'\b' + RegExp.escape(cleanWord) + r'\b',
            caseSensitive: false,
          );
          final m = wordRegex.firstMatch(highlighted) ??
              RegExp(RegExp.escape(cleanWord), caseSensitive: false)
                  .firstMatch(highlighted);
          if (m != null) {
            wordStartInSeg = m.start;
            wordEndInSeg = m.end;
          }
        }

        if (wordStartInSeg >= 0 && wordEndInSeg > wordStartInSeg) {
          final wBefore = highlighted.substring(0, wordStartInSeg);
          final wWord = highlighted.substring(wordStartInSeg, wordEndInSeg);
          final wAfter = highlighted.substring(wordEndInSeg);

          children.add(
            TextSpan(
              style: segStyle.merge(sentenceHighlightStyle),
              children: [
                if (wBefore.isNotEmpty) TextSpan(text: wBefore),
                TextSpan(
                  text: wWord,
                  style: sentenceHighlightStyle.copyWith(
                    backgroundColor: theme.accent.withValues(alpha: 0.38),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (wAfter.isNotEmpty) TextSpan(text: wAfter),
              ],
            ),
          );
        } else {
          children.add(
            TextSpan(
              text: highlighted,
              style: segStyle.merge(sentenceHighlightStyle),
            ),
          );
        }
      }
      if (after.isNotEmpty) {
        children.add(TextSpan(text: after, style: segStyle));
      }
    }

    return TextSpan(
      style: baseStyle,
      children: children,
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
    final selectedText = state.textEditingValue.selection.textInside(
      state.textEditingValue.text,
    );

    final items = <ContextMenuButtonItem>[
      if (selectedText.isNotEmpty && widget.onPlayFromHere != null)
        ContextMenuButtonItem(
          label: 'Play from here',
          onPressed: () {
            widget.onPlayFromHere!(selectedText);
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
                    return _buildContextMenu(context, editableTextState, theme);
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

          int wordStart = ttsState.activeWordStart;
          int wordEnd = ttsState.activeWordEnd;
          bool validOffsets = ttsState.currentWord.isNotEmpty &&
              wordStart >= 0 &&
              wordEnd <= sentence.length &&
              wordStart < wordEnd &&
              sentence.substring(wordStart, wordEnd).toLowerCase().contains(
                    ttsState.currentWord
                        .toLowerCase()
                        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), ''),
                  );

          if (!validOffsets && ttsState.currentWord.trim().isNotEmpty) {
            final cleanWord = RegExp.escape(ttsState.currentWord.trim());
            final wordRegex =
                RegExp(r'\b' + cleanWord + r'\b', caseSensitive: false);
            final wordMatch = wordRegex.firstMatch(sentence) ??
                RegExp(cleanWord, caseSensitive: false).firstMatch(sentence);
            if (wordMatch != null) {
              wordStart = wordMatch.start;
              wordEnd = wordMatch.end;
              validOffsets = true;
            }
          }

          if (validOffsets) {
            final wBefore = sentence.substring(0, wordStart);
            final wWord = sentence.substring(wordStart, wordEnd);
            final wAfter = sentence.substring(wordEnd);

            children.add(
              TextSpan(
                style: sentenceHighlightStyle,
                children: [
                  if (wBefore.isNotEmpty) TextSpan(text: wBefore),
                  TextSpan(
                    text: wWord,
                    style: sentenceHighlightStyle.copyWith(
                      backgroundColor: theme.accent.withValues(alpha: 0.38),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (wAfter.isNotEmpty) TextSpan(text: wAfter),
                ],
              ),
            );
          } else {
            children.add(
              TextSpan(text: sentence, style: sentenceHighlightStyle),
            );
          }
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

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState state,
    ReaderThemeData theme,
  ) {
    final selectedText = state.textEditingValue.selection.textInside(
      state.textEditingValue.text,
    );

    final items = <ContextMenuButtonItem>[
      if (selectedText.isNotEmpty && onPlayFromHere != null)
        ContextMenuButtonItem(
          label: 'Play from here',
          onPressed: () {
            onPlayFromHere!(selectedText);
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
}
