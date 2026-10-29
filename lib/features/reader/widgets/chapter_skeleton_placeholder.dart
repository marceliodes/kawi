import 'package:flutter/material.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';

/// An Apple-style shimmer skeleton placeholder for loading chapters.
///
/// Displays a subtle rounded heading bar and 4 natural body paragraph lines
/// with a continuous, gentle shimmer gradient sweep across the surface color.
class ChapterSkeletonPlaceholder extends StatefulWidget {
  const ChapterSkeletonPlaceholder({
    super.key,
    this.columnWidth,
    this.padding,
    this.theme,
  });

  /// The constrained reading column width.
  final double? columnWidth;

  /// Optional padding around the skeleton content.
  final EdgeInsetsGeometry? padding;

  /// Optional explicit reader theme override. If omitted, uses [ReaderTheme.of].
  final ReaderThemeData? theme;

  @override
  State<ChapterSkeletonPlaceholder> createState() =>
      _ChapterSkeletonPlaceholderState();
}

class _ChapterSkeletonPlaceholderState extends State<ChapterSkeletonPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ReaderThemeData? themeData = widget.theme;
    if (themeData == null) {
      try {
        themeData = ReaderTheme.of(context);
      } catch (_) {
        themeData = null;
      }
    }

    final textColor = themeData?.textPrimary ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black);

    // Subtle surface tint with base alpha 0.04 and sweep highlight alpha 0.09
    final baseColor = textColor.withValues(alpha: 0.04);
    final highlightColor = textColor.withValues(alpha: 0.09);

    final skeletonContent = SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header placeholder: matching heading height (width: 140px, height: 20px, borderRadius: 4)
          Container(
            width: 140,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),

          // Body paragraph skeletons: 4 rounded placeholder lines with natural text widths
          // (95%, 90%, 98%, 45%), height 14px, spacing 12px
          _buildSkeletonLine(widthFactor: 0.95),
          const SizedBox(height: 12),
          _buildSkeletonLine(widthFactor: 0.90),
          const SizedBox(height: 12),
          _buildSkeletonLine(widthFactor: 0.98),
          const SizedBox(height: 12),
          _buildSkeletonLine(widthFactor: 0.45),
        ],
      ),
    );

    Widget content = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-2.0 + 4.0 * _controller.value, 0.0),
              end: Alignment(-0.5 + 4.0 * _controller.value, 0.0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: skeletonContent,
    );

    if (widget.columnWidth != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.columnWidth!),
        child: content,
      );
    }

    return Padding(
      padding: widget.padding ??
          const EdgeInsets.symmetric(
            vertical: Spacing.xl,
            horizontal: Spacing.md,
          ),
      child: Center(child: content),
    );
  }

  Widget _buildSkeletonLine({required double widthFactor}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
