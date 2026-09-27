import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/reader_theme_preset.dart';
import '../../../core/theme/reader_theme_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/typography.dart';
import '../models/reader_settings.dart';
import '../providers/reader_settings_provider.dart';

class TypographySettingsSheet extends ConsumerWidget {
  const TypographySettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final settingsNotifier = ref.read(readerSettingsProvider.notifier);
    final activePreset = ref.watch(themePresetProvider);
    final presetNotifier = ref.read(themePresetProvider.notifier);

    return Container(
      constraints: const BoxConstraints(maxWidth: 540),
      decoration: BoxDecoration(
        color: theme.bgCard,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.xl),
        ),
        border: Border(
          top: BorderSide(color: theme.borderSubtle),
          left: BorderSide(color: theme.borderSubtle),
          right: BorderSide(color: theme.borderSubtle),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Appearance & Typography',
                    style: AppTypography.headline.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: PhosphorIcon(
                      PhosphorIconsLight.x,
                      size: 20,
                      color: theme.textMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),

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
                          color: isSelected
                              ? theme.accent
                              : presetTokens.borderSubtle,
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
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
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
              const SizedBox(height: Spacing.lg),

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

              // Font Size Slider
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

              // Line Height Slider
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

              // Max Content Width Slider
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
              const SizedBox(height: Spacing.md),
            ],
          ),
        ),
      ),
    );
  }

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
            value: value,
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
