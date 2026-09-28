import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../models/reader_settings.dart';
import '../providers/document_content_provider.dart';
import '../../tts/models/tts_models.dart';
import '../../tts/providers/tts_provider.dart';

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

  @override
  ConsumerState<ReaderCanvas> createState() => ReaderCanvasState();
}

class ReaderCanvasState extends ConsumerState<ReaderCanvas> {
  final FocusNode _focusNode = FocusNode();
  ItemScrollController? _internalItemScrollController;
  ItemPositionsListener? _internalItemPositionsListener;

  ItemScrollController get _effectiveItemScrollController =>
      widget.itemScrollController ??
      (_internalItemScrollController ??= ItemScrollController());

  ItemPositionsListener get _effectiveItemPositionsListener =>
      widget.itemPositionsListener ??
      (_internalItemPositionsListener ??= ItemPositionsListener.create());

  @override
  void initState() {
    super.initState();
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

    if (!oldWidget.settings.isPaginated && widget.settings.isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.pageController.hasClients) {
          widget.pageController.jumpToPage(widget.initialPageIndex);
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
    if (!mounted || widget.settings.isPaginated) return;

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
            if (isPaginated && widget.pageController.hasClients) {
              widget.pageController.previousPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.space) {
            if (isPaginated && widget.pageController.hasClients) {
              widget.pageController.nextPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onToggleChrome,
        child: isPaginated
            ? _buildPaginatedView(theme)
            : _buildContinuousView(theme),
      ),
    );
  }

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
        vertical: Spacing.xl + 40.0, // Clear top floating app bar
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
        final text = content.plainText.trim();

        final isPaginated = settings.isPaginated;

        return Padding(
          padding: EdgeInsets.only(
            bottom: isPaginated ? Spacing.xl : Spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Page marker header (only displayed in Paginated mode)
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
    if ((!ttsState.isPlaying && !ttsState.isPaused) ||
        ttsState.currentSentenceText.trim().isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final sentence = ttsState.currentSentenceText.trim();
    final matchIndex = text.indexOf(sentence);
    if (matchIndex == -1) {
      return TextSpan(text: text, style: baseStyle);
    }

    final before = text.substring(0, matchIndex);
    final match = text.substring(matchIndex, matchIndex + sentence.length);
    final after = text.substring(matchIndex + sentence.length);

    final sentenceHighlightStyle = baseStyle.copyWith(
      backgroundColor: theme.accent.withValues(alpha: 0.18),
    );

    InlineSpan sentenceSpan;
    if (ttsState.currentWord.isNotEmpty &&
        ttsState.activeWordStart >= 0 &&
        ttsState.activeWordEnd <= match.length &&
        ttsState.activeWordStart < ttsState.activeWordEnd) {
      final wBefore = match.substring(0, ttsState.activeWordStart);
      final wWord = match.substring(ttsState.activeWordStart, ttsState.activeWordEnd);
      final wAfter = match.substring(ttsState.activeWordEnd);

      sentenceSpan = TextSpan(
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
      );
    } else {
      sentenceSpan = TextSpan(text: match, style: sentenceHighlightStyle);
    }

    return TextSpan(
      style: baseStyle,
      children: [
        if (before.isNotEmpty) TextSpan(text: before),
        sentenceSpan,
        if (after.isNotEmpty) TextSpan(text: after),
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
