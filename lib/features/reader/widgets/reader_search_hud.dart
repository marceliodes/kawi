import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../models/search_models.dart';
import '../providers/search_provider.dart';

/// Floating desktop search HUD widget with match counter, next/previous controls,
/// and shortcut isolation.
class ReaderSearchHud extends ConsumerStatefulWidget {
  const ReaderSearchHud({
    super.key,
    required this.onClose,
    required this.onNavigateToMatch,
    this.onOpenAllResults,
  });

  final VoidCallback onClose;
  final ValueChanged<SearchMatch> onNavigateToMatch;
  final VoidCallback? onOpenAllResults;

  @override
  ConsumerState<ReaderSearchHud> createState() => _ReaderSearchHudState();
}

class _ReaderSearchHudState extends ConsumerState<ReaderSearchHud> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final searchState = ref.read(searchControllerProvider);
    _textController = TextEditingController(text: searchState.query);
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        if (_textController.text.isNotEmpty) {
          _textController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _textController.text.length,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleNext() {
    final next = ref.read(searchControllerProvider.notifier).nextMatch();
    if (next != null) {
      widget.onNavigateToMatch(next);
    }
  }

  void _handlePrevious() {
    final prev = ref.read(searchControllerProvider.notifier).previousMatch();
    if (prev != null) {
      widget.onNavigateToMatch(prev);
    }
  }

  void _handleClose() {
    ref.read(searchControllerProvider.notifier).clearSearch();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final searchState = ref.watch(searchControllerProvider);

    return Actions(
      // Isolate focus so reader navigation hotkeys (e.g. Space, Arrows) do not trigger while searching
      actions: <Type, Action<Intent>>{
        DoNothingIntent: DoNothingAction(),
      },
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _handleClose();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                _handlePrevious();
              } else {
                _handleNext();
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          color: theme.bgCard,
          child: Container(
            width: 390,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.isDark ? Colors.white12 : Colors.black12,
              ),
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsLight.magnifyingGlass,
                  size: 18,
                  color: theme.textMuted,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: AppTypography.body.copyWith(
                      color: theme.textPrimary,
                      fontSize: 14,
                    ),
                    cursorColor: theme.accent,
                    decoration: InputDecoration(
                      hintText: 'Find in book…',
                      hintStyle: AppTypography.body.copyWith(
                        color: theme.textMuted,
                        fontSize: 14,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) {
                      ref
                          .read(searchControllerProvider.notifier)
                          .onQueryChanged(val);
                    },
                    onSubmitted: (_) => _handleNext(),
                  ),
                ),
                if (_textController.text.isNotEmpty)
                  IconButton(
                    icon: PhosphorIcon(
                      PhosphorIconsLight.xCircle,
                      size: 16,
                      color: theme.textMuted,
                    ),
                    tooltip: 'Clear',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      _textController.clear();
                      ref.read(searchControllerProvider.notifier).clearSearch();
                    },
                  ),
                const SizedBox(width: Spacing.xxs),
                // Counter badge
                _buildMatchCounter(theme, searchState),
                const SizedBox(width: Spacing.xxs),
                // Previous button
                IconButton(
                  icon: PhosphorIcon(
                    PhosphorIconsLight.caretUp,
                    size: 16,
                    color: searchState.hasMatches
                        ? theme.textPrimary
                        : theme.textMuted.withValues(alpha: 0.4),
                  ),
                  tooltip: 'Previous match (Shift+Enter)',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: searchState.hasMatches ? _handlePrevious : null,
                ),
                // Next button
                IconButton(
                  icon: PhosphorIcon(
                    PhosphorIconsLight.caretDown,
                    size: 16,
                    color: searchState.hasMatches
                        ? theme.textPrimary
                        : theme.textMuted.withValues(alpha: 0.4),
                  ),
                  tooltip: 'Next match (Enter)',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: searchState.hasMatches ? _handleNext : null,
                ),
                if (widget.onOpenAllResults != null) ...[
                  const SizedBox(width: Spacing.xxs),
                  IconButton(
                    icon: PhosphorIcon(
                      PhosphorIconsLight.listBullets,
                      size: 16,
                      color: theme.textMuted,
                    ),
                    tooltip: 'All results',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: widget.onOpenAllResults,
                  ),
                ],
                const SizedBox(width: Spacing.xxs),
                // Close button
                IconButton(
                  icon: PhosphorIcon(
                    PhosphorIconsLight.x,
                    size: 16,
                    color: theme.textMuted,
                  ),
                  tooltip: 'Close (Esc)',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _handleClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchCounter(ReaderThemeData theme, SearchState state) {
    if (state.isEmpty) {
      return const SizedBox.shrink();
    }

    if (state.isSearching && state.matches.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.accent,
            ),
          ),
          const SizedBox(width: Spacing.xxs),
          Text(
            'Searching…',
            style: AppTypography.micro.copyWith(
              color: theme.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    if (!state.isSearching && state.matches.isEmpty) {
      return Text(
        '0 of 0',
        style: AppTypography.micro.copyWith(
          color: theme.isDark ? const Color(0xFFEF5350) : const Color(0xFFE53935),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final activeNumber = state.activeMatchIndex >= 0 ? state.activeMatchIndex + 1 : 0;
    return Text(
      '$activeNumber of ${state.totalMatches}${state.isSearching ? "…" : ""}',
      style: AppTypography.micro.copyWith(
        color: theme.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
