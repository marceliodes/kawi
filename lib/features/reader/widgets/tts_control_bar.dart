import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../../tts/models/tts_models.dart';
import '../../tts/providers/tts_provider.dart';
import '../../tts/providers/voice_manager_provider.dart';
import '../../tts/screens/voice_manager_screen.dart';

/// A compact floating pill media control bar for real-time TTS playback.
///
/// Anchored at the bottom-center of the reader screen, providing
/// play, pause, stop, previous, next, speed toggle, voice selector, and progress display.
///
/// Supports auto-collapsing to a low-profile mini capsule during playback inactivity (3.5s),
/// and expands immediately on hover, touch, or click.
class TtsControlBar extends ConsumerStatefulWidget {
  const TtsControlBar({
    super.key,
    required this.onClose,
    this.onPlay,
  });

  final VoidCallback onClose;
  final VoidCallback? onPlay;

  static const List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  ConsumerState<TtsControlBar> createState() => _TtsControlBarState();
}

class _TtsControlBarState extends ConsumerState<TtsControlBar> {
  bool _isCollapsed = false;
  Timer? _inactivityTimer;

  static const Duration _inactivityDuration = Duration(milliseconds: 3500);

  @override
  void initState() {
    super.initState();
    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.isPlaying) {
      _startInactivityTimer();
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, () {
      if (!mounted) return;
      final ttsState = ref.read(ttsStateProvider);
      if (ttsState.isPlaying) {
        setState(() {
          _isCollapsed = true;
        });
      }
    });
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void _expandAndResetTimer() {
    if (_isCollapsed) {
      setState(() {
        _isCollapsed = false;
      });
    }
    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.isPlaying) {
      _startInactivityTimer();
    } else {
      _cancelInactivityTimer();
    }
  }

  @override
  void dispose() {
    _cancelInactivityTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TtsState>(ttsStateProvider, (previous, next) {
      if (next.isPlaying) {
        if (previous?.isPlaying != true) {
          _startInactivityTimer();
        }
      } else {
        _cancelInactivityTimer();
        if (_isCollapsed) {
          setState(() {
            _isCollapsed = false;
          });
        }
      }
    });

    final theme = ReaderTheme.of(context);
    final ttsState = ref.watch(ttsStateProvider);
    final ttsNotifier = ref.read(ttsNotifierProvider.notifier);
    final hasInstalledModels = ref.watch(hasInstalledTtsModelsProvider);

    final isPlaying = ttsState.isPlaying;
    final hasSentences = ttsState.totalSentences > 0;
    final currentSpeed = ttsState.speechRate;

    return MouseRegion(
      onEnter: (_) => _expandAndResetTimer(),
      onHover: (_) => _expandAndResetTimer(),
      child: Listener(
        onPointerDown: (_) => _expandAndResetTimer(),
        child: Material(
          color: Colors.transparent,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              height: _isCollapsed ? 32.0 : 48.0,
              padding: _isCollapsed
                  ? const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 2.0)
                  : const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
              decoration: BoxDecoration(
                color: theme.bgCard.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(_isCollapsed ? 16.0 : 32.0),
                border: Border.all(color: theme.borderSubtle, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                child: _isCollapsed
                    ? SizedBox(
                        width: 130.0,
                        child: _buildMiniCapsule(
                          theme: theme,
                          ttsState: ttsState,
                          ttsNotifier: ttsNotifier,
                          isPlaying: isPlaying,
                          hasSentences: hasSentences,
                        ),
                      )
                    : _buildExpandedPill(
                        theme: theme,
                        ttsState: ttsState,
                        ttsNotifier: ttsNotifier,
                        hasInstalledModels: hasInstalledModels,
                        isPlaying: isPlaying,
                        hasSentences: hasSentences,
                        currentSpeed: currentSpeed,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniCapsule({
    required ReaderThemeData theme,
    required TtsState ttsState,
    required dynamic ttsNotifier,
    required bool isPlaying,
    required bool hasSentences,
  }) {
    return Row(
      key: const ValueKey('tts_mini_capsule'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Compact Play / Pause Button
        SizedBox(
          width: 24,
          height: 24,
          child: IconButton(
            key: const ValueKey('tts_mini_play_pause'),
            tooltip: isPlaying ? 'Pause' : 'Play',
            iconSize: 14,
            padding: EdgeInsets.zero,
            icon: PhosphorIcon(
              isPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
              size: 14,
              color: theme.textPrimary,
            ),
            onPressed: () {
              _expandAndResetTimer();
              if (isPlaying) {
                ttsNotifier.pause();
              } else {
                ttsNotifier.play();
              }
            },
          ),
        ),
        const SizedBox(width: Spacing.xs),

        // Subtle Sentence / Playback Indicator
        Flexible(
          child: Text(
            hasSentences
                ? '${ttsState.currentSentenceIndex + 1}/${ttsState.totalSentences}'
                : 'TTS',
            key: const ValueKey('tts_mini_sentence_indicator'),
            style: AppTypography.micro.copyWith(
              color: theme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedPill({
    required ReaderThemeData theme,
    required TtsState ttsState,
    required dynamic ttsNotifier,
    required bool hasInstalledModels,
    required bool isPlaying,
    required bool hasSentences,
    required double currentSpeed,
  }) {
    return Row(
      key: const ValueKey('tts_expanded_pill'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Previous Sentence Button
        IconButton(
          tooltip: 'Previous Sentence',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: PhosphorIcon(
            PhosphorIconsLight.skipBack,
            color: hasSentences && ttsState.currentSentenceIndex > 0
                ? theme.textPrimary
                : theme.textMuted.withValues(alpha: 0.4),
          ),
          onPressed: hasSentences && ttsState.currentSentenceIndex > 0
              ? ttsNotifier.previousSentence
              : null,
        ),
        const SizedBox(width: Spacing.xxs),

        // Play / Pause Button
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.textPrimary.withValues(alpha: 0.08),
          ),
          child: IconButton(
            tooltip: !hasInstalledModels
                ? 'No TTS engine downloaded.'
                : (isPlaying ? 'Pause' : 'Play'),
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            icon: PhosphorIcon(
              isPlaying
                  ? PhosphorIconsFill.pause
                  : PhosphorIconsFill.play,
              color: !hasInstalledModels
                  ? theme.textMuted.withValues(alpha: 0.4)
                  : theme.textPrimary,
            ),
            onPressed: () {
              AppLogger.d('>>> [ACTIVE UI BAR] Clicked play button on screen <<<');
              AppLogger.d('>>> [TTS UI] PLAY BUTTON PRESSED (isPlaying=$isPlaying, hasSentences=$hasSentences, onPlay=${widget.onPlay != null}) <<<');
              if (!hasInstalledModels) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No TTS engine downloaded.'),
                    duration: Duration(seconds: 2),
                  ),
                );
                VoiceManagerScreen.show(context);
                return;
              }
              if (isPlaying) {
                ttsNotifier.pause();
              } else {
                if (ttsState.isPaused) {
                  ttsNotifier.play();
                } else if (hasSentences && !ttsState.isStopped) {
                  ttsNotifier.play();
                } else if (widget.onPlay != null) {
                  widget.onPlay!();
                } else {
                  ttsNotifier.play();
                }
              }
            },
          ),
        ),
        const SizedBox(width: Spacing.xxs),

        // Next Sentence Button
        IconButton(
          tooltip: 'Next Sentence',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: PhosphorIcon(
            PhosphorIconsLight.skipForward,
            color: hasSentences &&
                    ttsState.currentSentenceIndex + 1 < ttsState.totalSentences
                ? theme.textPrimary
                : theme.textMuted.withValues(alpha: 0.4),
          ),
          onPressed: hasSentences &&
                  ttsState.currentSentenceIndex + 1 < ttsState.totalSentences
              ? ttsNotifier.nextSentence
              : null,
        ),
        const SizedBox(width: Spacing.xxs),

        // Stop Button
        IconButton(
          tooltip: 'Stop',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: PhosphorIcon(
            PhosphorIconsLight.stop,
            color: ttsState.isStopped
                ? theme.textMuted.withValues(alpha: 0.4)
                : theme.textPrimary,
          ),
          onPressed: ttsState.isStopped ? null : ttsNotifier.stop,
        ),

        if (hasSentences) ...[
          const SizedBox(width: Spacing.xs),
          Container(
            width: 1,
            height: 16,
            color: theme.borderSubtle,
          ),
          const SizedBox(width: Spacing.xs),

          // Progress Indicator: Sentence X / Total
          Text(
            '${ttsState.currentSentenceIndex + 1}/${ttsState.totalSentences}',
            style: AppTypography.micro.copyWith(
              color: theme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],

        const SizedBox(width: Spacing.xs),
        Container(
          width: 1,
          height: 16,
          color: theme.borderSubtle,
        ),
        const SizedBox(width: Spacing.xs),

        // Speech Rate Toggle Button
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final nextIndex = (TtsControlBar._speeds.indexWhere(
                          (s) => (s - currentSpeed).abs() < 0.05,
                        ) +
                        1) %
                TtsControlBar._speeds.length;
            ttsNotifier.setRate(TtsControlBar._speeds[nextIndex]);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.xs,
              vertical: Spacing.xxs,
            ),
            child: Text(
              '${currentSpeed.toStringAsFixed(currentSpeed.truncateToDouble() == currentSpeed ? 0 : 2)}x',
              style: AppTypography.micro.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),

        const SizedBox(width: Spacing.xxs),

        // Voice Manager / Settings Button
        IconButton(
          tooltip: 'Voice Settings',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: PhosphorIcon(
            PhosphorIconsLight.waveform,
            color: theme.accent,
          ),
          onPressed: () {
            VoiceManagerScreen.show(context);
          },
        ),

        const SizedBox(width: Spacing.xxs),

        // Close / Dismiss Control Bar Button
        IconButton(
          tooltip: 'Close TTS Bar',
          iconSize: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: PhosphorIcon(
            PhosphorIconsLight.x,
            color: theme.textMuted,
          ),
          onPressed: () {
            ttsNotifier.stop();
            widget.onClose();
          },
        ),
      ],
    );
  }
}
