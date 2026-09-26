import 'package:flutter/material.dart';

import 'reader_theme_data.dart';
import 'reader_theme_preset.dart';

abstract final class ReaderThemeTokens {
  static ReaderThemeData fromPreset(ReaderThemePreset preset) =>
      switch (preset) {
        ReaderThemePreset.paper => _paper,
        ReaderThemePreset.cupertinoLight => _cupertinoLight,
        ReaderThemePreset.gruvboxLight => _gruvboxLight,
        ReaderThemePreset.gruvboxDark => _gruvboxDark,
        ReaderThemePreset.cupertinoDark => _cupertinoDark,
        ReaderThemePreset.oledBlack => _oledBlack,
      };

  static const _paper = ReaderThemeData(
    bgCanvas: Color(0xFFF8F9FA),
    bgCard: Color(0xFFFFFFFF),
    bgDock: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A1A1A),
    textMuted: Color(0xFF71717A),
    accent: Color(0xFF2563EB),
    ttsHighlight: Color(0xFFE8EAED),
    borderSubtle: Color(0xFFE4E4E7),
    isDark: false,
  );

  static const _cupertinoLight = ReaderThemeData(
    bgCanvas: Color(0xFFF5F5F7),
    bgCard: Color(0xFFFFFFFF),
    bgDock: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1D1D1F),
    textMuted: Color(0xFF86868B),
    accent: Color(0xFF0071E3),
    ttsHighlight: Color(0xFFE8F0FE),
    borderSubtle: Color(0xFFD2D2D7),
    isDark: false,
  );

  static const _gruvboxLight = ReaderThemeData(
    bgCanvas: Color(0xFFFBF1C7),
    bgCard: Color(0xFFF2E5BC),
    bgDock: Color(0xFFEBDBB2),
    textPrimary: Color(0xFF3C3836),
    textMuted: Color(0xFF7C6F64),
    accent: Color(0xFFB57614),
    ttsHighlight: Color(0xFFEBDBB2),
    borderSubtle: Color(0xFFD5C4A1),
    isDark: false,
  );

  static const _gruvboxDark = ReaderThemeData(
    bgCanvas: Color(0xFF282828),
    bgCard: Color(0xFF32302F),
    bgDock: Color(0xFF3C3836),
    textPrimary: Color(0xFFEBDBB2),
    textMuted: Color(0xFFA89984),
    accent: Color(0xFFFE8019),
    ttsHighlight: Color(0xFF3C3836),
    borderSubtle: Color(0xFF504945),
    isDark: true,
  );

  static const _cupertinoDark = ReaderThemeData(
    bgCanvas: Color(0xFF1E1E1E),
    bgCard: Color(0xFF2A2A2C),
    bgDock: Color(0xFF2C2C2E),
    textPrimary: Color(0xFFF5F5F7),
    textMuted: Color(0xFFA1A1A6),
    accent: Color(0xFF2997FF),
    ttsHighlight: Color(0xFF2A3A4E),
    borderSubtle: Color(0xFF38383A),
    isDark: true,
  );

  static const _oledBlack = ReaderThemeData(
    bgCanvas: Color(0xFF000000),
    bgCard: Color(0xFF121212),
    bgDock: Color(0xFF181818),
    textPrimary: Color(0xFFE0E0E0),
    textMuted: Color(0xFF737373),
    accent: Color(0xFF60A5FA),
    ttsHighlight: Color(0xFF262626),
    borderSubtle: Color(0xFF262626),
    isDark: true,
  );
}
