import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/reader_theme_preset.dart';
import '../../../core/theme/reader_theme_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/typography.dart';
import '../../tts/models/tts_models.dart';
import '../../tts/providers/tts_provider.dart';
import '../../tts/providers/voice_manager_provider.dart';
import '../../tts/screens/voice_manager_screen.dart';
import '../models/reader_settings.dart';
import '../providers/reader_settings_provider.dart';

/// Unified modal dialog for reader settings with segmented tabs for "Display" and "Audio".
class ReaderSettingsModal extends ConsumerStatefulWidget {
  const ReaderSettingsModal({
    super.key,
    this.initialTab = 0,
    this.onToggleTts,
  });

  /// 0 = Display, 1 = Audio
  final int initialTab;
  final VoidCallback? onToggleTts;

  /// Shows the unified settings modal dialog.
  static Future<void> show(
    BuildContext context, {
    int initialTab = 0,
    VoidCallback? onToggleTts,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => ReaderSettingsModal(
        initialTab: initialTab,
        onToggleTts: onToggleTts,
      ),
    );
  }

  @override
  ConsumerState<ReaderSettingsModal> createState() =>
      _ReaderSettingsModalState();
}

class _ReaderSettingsModalState extends ConsumerState<ReaderSettingsModal> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final settingsNotifier = ref.read(readerSettingsProvider.notifier);
    final activePreset = ref.watch(themePresetProvider);
    final presetNotifier = ref.read(themePresetProvider.notifier);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (intent) => Navigator.of(context).pop(),
          ),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Dialog(
            backgroundColor: theme.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.lg),
              side: BorderSide(color: theme.borderSubtle),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xl,
            ),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 560,
                maxHeight: 680,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal Header
                  _buildHeader(theme),

                  // Segmented Tab Bar (Display / Audio)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: Spacing.xs,
                    ),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment<int>(
                          value: 0,
                          label: Text('Display'),
                          icon: PhosphorIcon(
                            PhosphorIconsLight.textAa,
                            size: 16,
                          ),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          label: Text('Audio'),
                          icon: PhosphorIcon(
                            PhosphorIconsLight.speakerHigh,
                            size: 16,
                          ),
                        ),
                      ],
                      selected: {_selectedTab},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _selectedTab = selection.first;
                        });
                      },
                      style: _segmentedButtonStyle(theme),
                    ),
                  ),

                  const Divider(height: Spacing.sm),

                  // Tab Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: Spacing.sm,
                      ),
                      child: _selectedTab == 0
                          ? _buildDisplayTab(
                              theme: theme,
                              settings: settings,
                              settingsNotifier: settingsNotifier,
                              activePreset: activePreset,
                              presetNotifier: presetNotifier,
                            )
                          : _buildAudioTab(
                              theme: theme,
                              settings: settings,
                              settingsNotifier: settingsNotifier,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(ReaderThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.sm,
        Spacing.xs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              PhosphorIcon(
                PhosphorIconsLight.faders,
                size: 20,
                color: theme.accent,
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                'Reader Settings',
                style: AppTypography.headline.copyWith(
                  color: theme.textPrimary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Close (Esc)',
            icon: PhosphorIcon(
              PhosphorIconsLight.x,
              size: 20,
              color: theme.textMuted,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Display & Typography Tab
  // ---------------------------------------------------------------------------

  Widget _buildDisplayTab({
    required ReaderThemeData theme,
    required ReaderSettings settings,
    required ReaderSettingsNotifier settingsNotifier,
    required ReaderThemePreset activePreset,
    required dynamic presetNotifier,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Theme Palette Swatches
        _buildSectionHeader(theme, 'THEME'),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: ReaderThemePreset.values.map((preset) {
            final presetTokens = ReaderThemeTokens.fromPreset(preset);
            final isSelected = preset == activePreset;
            return InkWell(
              onTap: () => presetNotifier.setPreset(preset),
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: Spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: presetTokens.bgCanvas,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color:
                        isSelected ? theme.accent : presetTokens.borderSubtle,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: presetTokens.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      preset.displayName,
                      style: AppTypography.micro.copyWith(
                        color: presetTokens.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: Spacing.lg),

        // Layout Reading Mode
        _buildSectionHeader(theme, 'LAYOUT MODE'),
        const SizedBox(height: Spacing.xs),
        SegmentedButton<ReadingMode>(
          segments: const [
            ButtonSegment<ReadingMode>(
              value: ReadingMode.continuous,
              label: Text('Continuous'),
              icon: PhosphorIcon(
                PhosphorIconsLight.arrowsDownUp,
                size: 16,
              ),
            ),
            ButtonSegment<ReadingMode>(
              value: ReadingMode.paginated,
              label: Text('Paginated'),
              icon: PhosphorIcon(PhosphorIconsLight.bookOpen, size: 16),
            ),
          ],
          selected: {settings.mode},
          onSelectionChanged: (newSelection) {
            settingsNotifier.setReadingMode(newSelection.first);
          },
          style: _segmentedButtonStyle(theme),
        ),
        const SizedBox(height: Spacing.lg),

        // Font Family Selector
        _buildSectionHeader(theme, 'TYPEFACE'),
        const SizedBox(height: Spacing.xs),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: AppTypography.readerSerif,
              label: Text('Literata'),
            ),
            ButtonSegment<String>(
              value: AppTypography.readerSans,
              label: Text('Inter'),
            ),
            ButtonSegment<String>(
              value: AppTypography.readerHighDistinction,
              label: Text('Atkinson'),
            ),
          ],
          selected: {settings.fontFamily},
          onSelectionChanged: (newSelection) {
            settingsNotifier.setFontFamily(newSelection.first);
          },
          style: _segmentedButtonStyle(theme),
        ),
        const SizedBox(height: Spacing.md),

        // Live Font Preview
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: theme.bgCanvas,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: theme.borderSubtle),
          ),
          child: Text(
            'The quick brown fox jumps over the lazy dog.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: settings.fontFamily,
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: theme.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),

        // Typography Sliders
        _buildSliderRow(
          theme: theme,
          title: 'Font Size',
          valueDisplay: '${settings.fontSize.round()} pt',
          min: 12.0,
          max: 32.0,
          divisions: 20,
          value: settings.fontSize,
          onChanged: settingsNotifier.setFontSize,
        ),
        const SizedBox(height: Spacing.sm),

        _buildSliderRow(
          theme: theme,
          title: 'Line Spacing',
          valueDisplay: '${settings.lineHeight.toStringAsFixed(1)}x',
          min: 1.2,
          max: 2.4,
          divisions: 12,
          value: settings.lineHeight,
          onChanged: settingsNotifier.setLineHeight,
        ),
        const SizedBox(height: Spacing.sm),

        _buildSliderRow(
          theme: theme,
          title: 'Paragraph Spacing',
          valueDisplay: '${settings.paragraphSpacing.round()} px',
          min: 8.0,
          max: 36.0,
          divisions: 14,
          value: settings.paragraphSpacing,
          onChanged: settingsNotifier.setParagraphSpacing,
        ),
        const SizedBox(height: Spacing.sm),

        _buildSliderRow(
          theme: theme,
          title: 'Column Width',
          valueDisplay: '${settings.contentMaxWidth.round()} px',
          min: 480.0,
          max: 900.0,
          divisions: 21,
          value: settings.contentMaxWidth,
          onChanged: settingsNotifier.setContentMaxWidth,
        ),
        const SizedBox(height: Spacing.sm),

        _buildSliderRow(
          theme: theme,
          title: 'Horizontal Margin',
          valueDisplay: '${settings.horizontalPadding.round()} px',
          min: 12.0,
          max: 64.0,
          divisions: 13,
          value: settings.horizontalPadding,
          onChanged: settingsNotifier.setHorizontalPadding,
        ),
        const SizedBox(height: Spacing.md),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Voice & Audio Tab
  // ---------------------------------------------------------------------------

  Widget _buildAudioTab({
    required ReaderThemeData theme,
    required ReaderSettings settings,
    required ReaderSettingsNotifier settingsNotifier,
  }) {
    final voiceState = ref.watch(voiceManagerProvider);
    final voiceNotifier = ref.read(voiceManagerProvider.notifier);
    final ttsState = ref.watch(ttsStateProvider);
    final ttsNotifier = ref.read(ttsStateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Voice Engine & Model Selection
        _buildSectionHeader(theme, 'VOICE ENGINE & MODEL'),
        const SizedBox(height: Spacing.xs),

        if (!voiceState.hasInstalledModels)
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.warningCircle,
                  color: Colors.amber.shade700,
                  size: 22,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'No TTS models installed. Download a voice model to enable speech playback.',
                    style: AppTypography.body.copyWith(
                      color: theme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                TextButton.icon(
                  onPressed: () => VoiceManagerScreen.show(context),
                  icon: const PhosphorIcon(
                    PhosphorIconsLight.downloadSimple,
                    size: 16,
                  ),
                  label: const Text('Download'),
                ),
              ],
            ),
          )
        else ...[
          // Active Voice Dropdown
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  decoration: BoxDecoration(
                    color: theme.bgCanvas,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: theme.borderSubtle),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: voiceState.activeVoice?.id,
                      isExpanded: true,
                      dropdownColor: theme.bgCard,
                      icon: PhosphorIcon(
                        PhosphorIconsLight.caretDown,
                        size: 16,
                        color: theme.textMuted,
                      ),
                      hint: Text(
                        'Select a voice model',
                        style: AppTypography.body.copyWith(
                          color: theme.textMuted,
                        ),
                      ),
                      items: voiceState.installedVoices.map((voice) {
                        final isKokoro =
                            voice.engineType == TtsEngineType.kokoro;
                        return DropdownMenuItem<String>(
                          value: voice.id,
                          child: Text(
                            isKokoro
                                ? 'Kokoro Neural (${voice.name})'
                                : '${voice.name} (${voice.locale})',
                            style: AppTypography.body.copyWith(
                              color: theme.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (newVoiceId) {
                        if (newVoiceId != null) {
                          final picked = voiceState.installedVoices
                              .where((v) => v.id == newVoiceId)
                              .firstOrNull;
                          if (picked != null) {
                            voiceNotifier.selectVoice(picked);
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.xs),
              IconButton(
                tooltip: 'Open Voice Manager',
                icon: PhosphorIcon(
                  PhosphorIconsLight.arrowSquareOut,
                  size: 20,
                  color: theme.textMuted,
                ),
                onPressed: () => VoiceManagerScreen.show(context),
              ),
            ],
          ),

          // Kokoro Speaker / Voice Style Picker if active voice is Kokoro
          if (voiceState.activeVoice?.engineType == TtsEngineType.kokoro ||
              voiceState.isKokoroInstalled) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Text(
                  'Speaker Style:',
                  style: AppTypography.micro.copyWith(
                    color: theme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.sm),
                    decoration: BoxDecoration(
                      color: theme.bgCanvas,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: theme.borderSubtle),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: voiceState.activeVoice?.engineType ==
                                TtsEngineType.kokoro
                            ? voiceState.activeVoice?.id
                            : voiceState.kokoroVoices.firstOrNull?.id,
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
                              voiceNotifier.selectVoice(picked);
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
        const SizedBox(height: Spacing.lg),

        // Playback Speed & Pitch Controls
        _buildSectionHeader(theme, 'AUDIO PLAYBACK CONTROLS'),
        const SizedBox(height: Spacing.xs),

        _buildSliderRow(
          theme: theme,
          title: 'Speech Rate',
          valueDisplay: '${ttsState.speechRate.toStringAsFixed(2)}x',
          min: 0.5,
          max: 2.5,
          divisions: 20,
          value: ttsState.speechRate,
          onChanged: ttsNotifier.setRate,
        ),
        const SizedBox(height: Spacing.sm),

        _buildSliderRow(
          theme: theme,
          title: 'Voice Pitch',
          valueDisplay: '${ttsState.pitch.toStringAsFixed(2)}x',
          min: 0.5,
          max: 1.5,
          divisions: 20,
          value: ttsState.pitch,
          onChanged: ttsNotifier.setPitch,
        ),
        const SizedBox(height: Spacing.lg),

        // Highlighting & Auto-Advance Behavior
        _buildSectionHeader(theme, 'SPEECH HIGHLIGHT & NAVIGATION'),
        const SizedBox(height: Spacing.xs),

        // Audio Highlight Style
        Text(
          'Highlight Style',
          style: AppTypography.body.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        SegmentedButton<TtsHighlightStyle>(
          segments: const [
            ButtonSegment<TtsHighlightStyle>(
              value: TtsHighlightStyle.background,
              label: Text('Background'),
              icon: PhosphorIcon(
                PhosphorIconsLight.paintBucket,
                size: 16,
              ),
            ),
            ButtonSegment<TtsHighlightStyle>(
              value: TtsHighlightStyle.underline,
              label: Text('Underline'),
              icon: PhosphorIcon(
                PhosphorIconsLight.textUnderline,
                size: 16,
              ),
            ),
          ],
          selected: {settings.ttsHighlightStyle},
          onSelectionChanged: (newSelection) {
            settingsNotifier.setTtsHighlightStyle(newSelection.first);
          },
          style: _segmentedButtonStyle(theme),
        ),
        const SizedBox(height: Spacing.md),

        // Auto-Advance Behavior Toggle
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.bgCanvas,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: theme.borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-Advance Pages',
                      style: AppTypography.body.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Turn pages and scroll smoothly as audio advances',
                      style: AppTypography.micro.copyWith(
                        color: theme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: settings.ttsAutoAdvance,
                activeThumbColor: theme.accent,
                onChanged: settingsNotifier.setTtsAutoAdvance,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Styling Helpers
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(ReaderThemeData theme, String title) {
    return Text(
      title,
      style: AppTypography.sectionHeader.copyWith(
        color: theme.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _buildSliderRow({
    required ReaderThemeData theme,
    required String title,
    required String valueDisplay,
    required double min,
    required double max,
    required int divisions,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: AppTypography.body.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              valueDisplay,
              style: AppTypography.micro.copyWith(
                color: theme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: theme.accent,
            inactiveTrackColor: theme.borderSubtle,
            thumbColor: theme.accent,
            overlayColor: theme.accent.withValues(alpha: 0.12),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  ButtonStyle _segmentedButtonStyle(ReaderThemeData theme) {
    return SegmentedButton.styleFrom(
      backgroundColor: theme.bgCanvas,
      selectedBackgroundColor: theme.accent.withValues(alpha: 0.15),
      foregroundColor: theme.textPrimary,
      selectedForegroundColor: theme.accent,
      side: BorderSide(color: theme.borderSubtle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
    );
  }
}
