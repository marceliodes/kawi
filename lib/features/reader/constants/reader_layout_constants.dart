import 'package:flutter/material.dart';

/// Single source of truth for EPUB pagination viewport measurements and padding metrics.
abstract final class EpubPaginationMetrics {
  /// Top padding for paginated EPUB view, allowing room for auto-hiding header and status area.
  static const double topPadding = 64.0; // Spacing.xl + 32.0

  /// Bottom padding for paginated EPUB view, lean clean margin without bottom status bar bloat.
  static const double bottomPadding = 24.0;

  /// Exact fixed height for the page counter & chapter header row.
  static const double pageHeaderHeight = 32.0;

  /// Spacing between paragraphs.
  static const double paragraphSpacing = 16.0;

  /// Total vertical chrome subtracted from the viewport constraints to get the content height:
  /// top padding (64.0) + bottom padding (24.0) + page header row height (32.0) = 120.0px.
  static const double verticalChromeHeight =
      topPadding + bottomPadding + pageHeaderHeight;

  /// Uniform strut style ensuring exact mathematical line-height parity
  /// between TextPainter measurement and widget rendering.
  static StrutStyle strutStyleFor(TextStyle style) => StrutStyle(
        fontFamily: style.fontFamily,
        fontSize: style.fontSize,
        height: style.height,
        forceStrutHeight: true,
      );

  /// Calculates the exact content column width for pagination and canvas constraints.
  static double computeColumnWidth({
    required double viewportWidth,
    required double horizontalPadding,
    required double maxContentWidth,
  }) {
    return (viewportWidth - (horizontalPadding * 2))
        .clamp(100.0, maxContentWidth);
  }

  /// Calculates the exact content column height for pagination and canvas constraints.
  static double computeColumnHeight(double viewportHeight) {
    return (viewportHeight - verticalChromeHeight)
        .clamp(100.0, viewportHeight);
  }
}
