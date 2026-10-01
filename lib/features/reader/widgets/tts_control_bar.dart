import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../tts/providers/tts_provider.dart';
import '../../tts/providers/voice_manager_provider.dart';
import '../../tts/screens/voice_manager_screen.dart';

/// A compact floating pill media control bar for real-time TTS playback.
///
/// Anchored at the bottom-center of the [DocumentViewerScreen], providing
/// play, pause, stop, previous, next, speed toggle, voice selector, and progress display.
class TtsControlBar extends ConsumerWidget {
  const TtsControlBar({
    super.key,
    required this.onClose,
    this.onPlay,
  });

  final VoidCallback onClose;
  final VoidCallback? onPlay;

  static const List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final ttsState = ref.watch(ttsStateProvider);
    final ttsNotifier = ref.read(ttsStateProvider.notifier);
    final hasInstalledModels = ref.watch(hasInstalledTtsModelsProvider);

    final isPlaying = ttsState.isPlaying;
    final hasSentences = ttsState.totalSentences > 0;
    final currentSpeed = ttsState.speechRate;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: theme.bgCard.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: theme.borderSubtle, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
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
                onPressed: !hasInstalledModels
                    ? null
                    : () {
                        // ignore: avoid_print
                        print('>>> [TTS UI] PLAY BUTTON PRESSED (isPlaying=$isPlaying, hasSentences=$hasSentences, onPlay=${onPlay != null}) <<<');
                        if (isPlaying) {
                          ttsNotifier.pause();
                        } else {
                          if (hasSentences) {
                            ttsNotifier.play();
                          } else if (onPlay != null) {
                            onPlay!();
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
                final nextIndex = (_speeds.indexWhere(
                              (s) => (s - currentSpeed).abs() < 0.05,
                            ) +
                            1) %
                    _speeds.length;
                ttsNotifier.setRate(_speeds[nextIndex]);
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
                onClose();
              },
            ),
          ],
        ),
      ),
    );
  }
}
