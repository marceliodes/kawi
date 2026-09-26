import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/reader_theme_preset.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/typography.dart';
import '../providers/library_provider.dart';
import '../widgets/sidebar_widget.dart';
import 'library_screen.dart';

class KawiShell extends ConsumerStatefulWidget {
  const KawiShell({super.key});

  @override
  ConsumerState<KawiShell> createState() => _KawiShellState();
}

class _KawiShellState extends ConsumerState<KawiShell> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final preset = ref.watch(themePresetProvider);

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        final paths = details.files.map((f) => f.path);
        try {
          final service = ref.read(ingestionServiceProvider);
          await service.ingestFiles(paths);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to import dropped files: $e')),
            );
          }
        }
      },
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 720;

              if (isDesktop) {
                return Scaffold(
                  backgroundColor: theme.bgCanvas,
                  appBar: _buildAppBar(theme, preset),
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
                appBar: _buildAppBar(theme, preset),
                drawer: const Drawer(child: SidebarWidget()),
                body: const LibraryScreen(),
              );
            },
          ),
          if (_isDragging) _buildDropScrim(theme),
        ],
      ),
    );
  }

  Widget _buildDropScrim(ReaderThemeData theme) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: theme.bgCanvas.withValues(alpha: 0.88),
          padding: const EdgeInsets.all(Spacing.xl),
          child: CustomPaint(
            painter: _DashedRectPainter(
              color: theme.accent,
              strokeWidth: 2.5,
              gap: 8,
              dash: 12,
              radius: Radii.lg,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIconsLight.downloadSimple,
                    size: 64,
                    color: theme.accent,
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'Drop documents to import',
                    style: AppTypography.largeTitle.copyWith(
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'EPUB, PDF, MOBI, AZW',
                    style: AppTypography.body.copyWith(
                      color: theme.textMuted,
                      fontWeight: FontWeight.w500,
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

  PreferredSizeWidget _buildAppBar(
    ReaderThemeData theme,
    ReaderThemePreset preset,
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
                          color: theme.textPrimary,
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

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
    required this.dash,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final length = (distance + dash <= metric.length)
            ? dash
            : metric.length - distance;
        dashPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += dash + gap;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.gap != gap ||
      oldDelegate.dash != dash ||
      oldDelegate.radius != radius;
}
