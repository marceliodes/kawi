import 'package:flutter/material.dart';

@immutable
class ReaderThemeData {
  const ReaderThemeData({
    required this.bgCanvas,
    required this.bgCard,
    required this.bgDock,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.ttsHighlight,
    required this.borderSubtle,
    required this.isDark,
  });

  final Color bgCanvas;
  final Color bgCard;
  final Color bgDock;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color ttsHighlight;
  final Color borderSubtle;
  final bool isDark;

  Color get hoverOverlay => isDark
      ? const Color.fromRGBO(255, 255, 255, 0.06)
      : const Color.fromRGBO(0, 0, 0, 0.04);
}
