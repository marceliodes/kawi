import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/reader_theme_data.dart';
import '../../../core/theme/reader_theme_preset.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/typography.dart';
import '../widgets/sidebar_widget.dart';
import 'library_screen.dart';

class KawiShell extends ConsumerWidget {
  const KawiShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final preset = ref.watch(themePresetProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 720;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: theme.bgCanvas,
            appBar: _buildAppBar(theme, preset, ref),
            body: const Row(
              children: [
                SidebarWidget(),
                Expanded(child: LibraryScreen()),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: theme.bgCanvas,
          appBar: _buildAppBar(theme, preset, ref),
          drawer: const Drawer(child: SidebarWidget()),
          body: const LibraryScreen(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    ReaderThemeData theme,
    ReaderThemePreset preset,
    WidgetRef ref,
  ) {
    return AppBar(
      backgroundColor: theme.bgCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        'Kawi',
        style: AppTypography.headline.copyWith(color: theme.textPrimary),
      ),
      actions: [
        PopupMenuButton<ReaderThemePreset>(
          tooltip: 'Select theme (${preset.displayName})',
          initialValue: preset,
          color: theme.bgCard,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: BorderSide(color: theme.borderSubtle),
          ),
          onSelected: (selectedPreset) {
            ref.read(themePresetProvider.notifier).setPreset(selectedPreset);
          },
          itemBuilder: (context) {
            return ReaderThemePreset.values.map((itemPreset) {
              final isSelected = itemPreset == preset;
              return PopupMenuItem<ReaderThemePreset>(
                value: itemPreset,
                child: Row(
                  children: [
                    PhosphorIcon(
                      isSelected
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsLight.circle,
                      size: 16,
                      color: isSelected ? theme.accent : theme.textMuted,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        itemPreset.displayName,
                        style: AppTypography.body.copyWith(
                          color: isSelected
                              ? theme.textPrimary
                              : theme.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          icon: PhosphorIcon(
            PhosphorIconsLight.palette,
            color: theme.textMuted,
          ),
        ),
        const SizedBox(width: Spacing.xs),
      ],
    );
  }
}
