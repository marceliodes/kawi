import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../models/tts_models.dart';
import '../providers/voice_manager_provider.dart';

/// Modal bottom sheet or dedicated view for managing TTS voice models.
///
/// Packaging & UI hierarchy:
/// - Kokoro: Single engine card with ONE download button (~85 MB INT8 model).
///   Once installed, provides a dropdown/selector to choose between the 6 voice styles
///   without requiring additional downloads.
/// - Piper: Individual downloadable models with individual download buttons.
/// - Percentage progress bar: Shows clear percentage and progress indicator for active downloads.
/// - Zero-Model state: Informative alert banner when no engines are installed.
class VoiceManagerScreen extends ConsumerWidget {
  const VoiceManagerScreen({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const VoiceManagerScreen(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final voiceState = ref.watch(voiceManagerProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: theme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice Manager',
                        style: AppTypography.headline.copyWith(
                          color: theme.textPrimary,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total disk usage: ${_formatBytes(voiceState.totalDiskUsageBytes)}',
                        style: AppTypography.micro.copyWith(
                          color: theme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: PhosphorIcon(
                    PhosphorIconsLight.x,
                    size: 20,
                    color: theme.textMuted,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content body
          Flexible(
            child: voiceState.isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(Spacing.xl),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(Spacing.md),
                    children: [
                      // Zero-Model warning banner
                      if (!voiceState.hasInstalledModels)
                        Container(
                          margin: const EdgeInsets.only(bottom: Spacing.md),
                          padding: const EdgeInsets.all(Spacing.md),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              PhosphorIcon(
                                PhosphorIconsFill.warningCircle,
                                color: Colors.amber.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: Text(
                                  'No TTS engine downloaded. Download a voice model below to enable speech playback.',
                                  style: AppTypography.body.copyWith(
                                    color: theme.textPrimary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Section: Kokoro Neural Engine
                      _buildSectionHeader('Neural Engine (Kokoro)', theme),
                      const SizedBox(height: Spacing.xs),
                      _buildKokoroEngineCard(
                        context: context,
                        ref: ref,
                        voiceState: voiceState,
                        theme: theme,
                      ),

                      const SizedBox(height: Spacing.lg),

                      // Section: Piper Models
                      _buildSectionHeader(
                        'Piper Models (${voiceState.piperVoices.length})',
                        theme,
                      ),
                      const SizedBox(height: Spacing.xs),
                      ...voiceState.piperVoices.map(
                        (voice) => _buildPiperVoiceCard(
                          context: context,
                          ref: ref,
                          voice: voice,
                          isActive: voiceState.activeVoice?.id == voice.id,
                          isDownloading:
                              voiceState.downloadingModelId == voice.id,
                          downloadProgress: voiceState.downloadProgress,
                          downloadStatus: voiceState.downloadStatus,
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ReaderThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 4),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.micro.copyWith(
          color: theme.textMuted,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildKokoroEngineCard({
    required BuildContext context,
    required WidgetRef ref,
    required VoiceManagerState voiceState,
    required ReaderThemeData theme,
  }) {
    final isInstalled = voiceState.isKokoroInstalled;
    final isDownloading = voiceState.isKokoroDownloading;
    final isKokoroActive =
        voiceState.activeVoice?.engineType == TtsEngineType.kokoro;

    // The default or active Kokoro voice model
    final activeKokoroVoice = voiceState.activeVoice?.engineType ==
            TtsEngineType.kokoro
        ? voiceState.activeVoice
        : voiceState.kokoroVoices.where((v) => v.isInstalled).firstOrNull ??
            voiceState.kokoroVoices.firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      decoration: BoxDecoration(
        color: isKokoroActive
            ? theme.accent.withValues(alpha: 0.08)
            : theme.bgCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isKokoroActive ? theme.accent : theme.borderSubtle,
          width: isKokoroActive ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Radio icon if installed
                if (isInstalled && activeKokoroVoice != null)
                  GestureDetector(
                    onTap: () {
                      ref
                          .read(voiceManagerProvider.notifier)
                          .selectVoice(activeKokoroVoice);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: Spacing.sm),
                      child: PhosphorIcon(
                        isKokoroActive
                            ? PhosphorIconsFill.checkCircle
                            : PhosphorIconsLight.circle,
                        color: isKokoroActive ? theme.accent : theme.textMuted,
                        size: 22,
                      ),
                    ),
                  ),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Kokoro 82M Neural TTS',
                              style: AppTypography.body.copyWith(
                                color: theme.textPrimary,
                                fontWeight: isKokoroActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Spacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'INT8 Quantized',
                              style: AppTypography.micro.copyWith(
                                color: theme.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isInstalled
                            ? 'Installed • ~85 MB • 6 Embedded Voice Styles'
                            : 'All-in-one download • ~85 MB • 6 Voice Styles',
                        style: AppTypography.micro.copyWith(
                          color: theme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action button: Delete if installed, Download if available
                if (isInstalled && activeKokoroVoice != null)
                  IconButton(
                    tooltip: 'Delete Kokoro engine (~85 MB)',
                    icon: PhosphorIcon(
                      PhosphorIconsLight.trash,
                      size: 20,
                      color: Colors.redAccent.withValues(alpha: 0.8),
                    ),
                    onPressed: () => _confirmDeleteKokoro(
                      context,
                      ref,
                      activeKokoroVoice,
                      theme,
                    ),
                  )
                else if (isDownloading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                    child: Text(
                      voiceState.downloadPercentage,
                      style: AppTypography.micro.copyWith(
                        color: theme.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.accent,
                      backgroundColor: theme.accent.withValues(alpha: 0.1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: Spacing.xs,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const PhosphorIcon(
                      PhosphorIconsLight.downloadSimple,
                      size: 16,
                    ),
                    label: const Text('Download Engine'),
                    onPressed: () {
                      ref
                          .read(voiceManagerProvider.notifier)
                          .downloadKokoroEngine();
                    },
                  ),
              ],
            ),

            // Progress bar if downloading
            if (isDownloading) ...[
              const SizedBox(height: Spacing.sm),
              _buildProgressBar(
                progress: voiceState.downloadProgress,
                status: voiceState.downloadStatus,
                theme: theme,
              ),
            ],

            // Voice Style dropdown if installed
            if (isInstalled) ...[
              const SizedBox(height: Spacing.sm),
              const Divider(height: 1),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Text(
                    'Voice Style:',
                    style: AppTypography.micro.copyWith(
                      color: theme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: theme.bgCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.borderSubtle),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: activeKokoroVoice?.id,
                          isExpanded: true,
                          dropdownColor: theme.bgCard,
                          icon: PhosphorIcon(
                            PhosphorIconsLight.caretDown,
                            size: 16,
                            color: theme.textMuted,
                          ),
                          items: voiceState.kokoroVoices.map((voice) {
                            return DropdownMenuItem<String>(
                              value: voice.id,
                              child: Text(
                                voice.name,
                                style: AppTypography.body.copyWith(
                                  color: theme.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (newId) {
                            if (newId != null) {
                              final picked = voiceState.kokoroVoices
                                  .where((v) => v.id == newId)
                                  .firstOrNull;
                              if (picked != null) {
                                ref
                                    .read(voiceManagerProvider.notifier)
                                    .selectVoice(picked);
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPiperVoiceCard({
    required BuildContext context,
    required WidgetRef ref,
    required TtsVoiceModel voice,
    required bool isActive,
    required bool isDownloading,
    required double downloadProgress,
    required String downloadStatus,
    required ReaderThemeData theme,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      decoration: BoxDecoration(
        color: isActive
            ? theme.accent.withValues(alpha: 0.08)
            : theme.bgCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? theme.accent : theme.borderSubtle,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Radio checkmark if installed
                if (voice.isInstalled)
                  GestureDetector(
                    onTap: () {
                      ref
                          .read(voiceManagerProvider.notifier)
                          .selectVoice(voice);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: Spacing.sm),
                      child: PhosphorIcon(
                        isActive
                            ? PhosphorIconsFill.checkCircle
                            : PhosphorIconsLight.circle,
                        color: isActive ? theme.accent : theme.textMuted,
                        size: 22,
                      ),
                    ),
                  ),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              voice.name,
                              style: AppTypography.body.copyWith(
                                color: theme.textPrimary,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Spacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Piper VITS',
                              style: AppTypography.micro.copyWith(
                                color: theme.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${voice.locale} • ${_formatBytes(voice.sizeBytes)}',
                        style: AppTypography.micro.copyWith(
                          color: theme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action button: Delete if installed, Download if available
                if (voice.isInstalled)
                  IconButton(
                    tooltip: 'Delete voice model',
                    icon: PhosphorIcon(
                      PhosphorIconsLight.trash,
                      size: 20,
                      color: Colors.redAccent.withValues(alpha: 0.8),
                    ),
                    onPressed: () =>
                        _confirmDeletePiper(context, ref, voice, theme),
                  )
                else if (isDownloading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                    child: Text(
                      '${(downloadProgress * 100).clamp(0, 100).toInt()}%',
                      style: AppTypography.micro.copyWith(
                        color: theme.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.accent,
                      backgroundColor: theme.accent.withValues(alpha: 0.1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: Spacing.xs,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const PhosphorIcon(
                      PhosphorIconsLight.downloadSimple,
                      size: 16,
                    ),
                    label: const Text('Download'),
                    onPressed: () {
                      ref
                          .read(voiceManagerProvider.notifier)
                          .downloadVoice(voice);
                    },
                  ),
              ],
            ),

            if (isDownloading) ...[
              const SizedBox(height: Spacing.sm),
              _buildProgressBar(
                progress: downloadProgress,
                status: downloadStatus,
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    required double progress,
    required String status,
    required ReaderThemeData theme,
  }) {
    final pct = (progress * 100).clamp(0, 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                status.isNotEmpty ? status : 'Downloading...',
                style: AppTypography.micro.copyWith(
                  color: theme.textMuted,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              '$pct%',
              style: AppTypography.micro.copyWith(
                color: theme.accent,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            backgroundColor: theme.borderSubtle,
            valueColor: AlwaysStoppedAnimation<Color>(theme.accent),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  void _confirmDeleteKokoro(
    BuildContext context,
    WidgetRef ref,
    TtsVoiceModel voice,
    ReaderThemeData theme,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: theme.bgCard,
        title: Text(
          'Delete Kokoro Engine?',
          style: AppTypography.headline.copyWith(
            color: theme.textPrimary,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Are you sure you want to delete the Kokoro 82M engine and all 6 voice styles? This will free up ~85 MB of disk space.',
          style: AppTypography.body.copyWith(color: theme.textPrimary),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: theme.textMuted)),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete Engine'),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(voiceManagerProvider.notifier).deleteVoice(voice);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeletePiper(
    BuildContext context,
    WidgetRef ref,
    TtsVoiceModel voice,
    ReaderThemeData theme,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: theme.bgCard,
        title: Text(
          'Delete Voice Model?',
          style: AppTypography.headline.copyWith(
            color: theme.textPrimary,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${voice.name}"? This will free up ${_formatBytes(voice.sizeBytes)} of disk space.',
          style: AppTypography.body.copyWith(color: theme.textPrimary),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: theme.textMuted)),
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              ref.read(voiceManagerProvider.notifier).deleteVoice(voice);
            },
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
