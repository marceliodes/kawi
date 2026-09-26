import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';

void main() {
  group('ReaderThemePreset', () {
    test('light presets report isDark false', () {
      expect(ReaderThemePreset.paper.isDark, isFalse);
      expect(ReaderThemePreset.cupertinoLight.isDark, isFalse);
      expect(ReaderThemePreset.gruvboxLight.isDark, isFalse);
    });

    test('dark presets report isDark true', () {
      expect(ReaderThemePreset.gruvboxDark.isDark, isTrue);
      expect(ReaderThemePreset.cupertinoDark.isDark, isTrue);
      expect(ReaderThemePreset.oledBlack.isDark, isTrue);
    });

    test('preset displayNames match DESIGN.md', () {
      expect(ReaderThemePreset.paper.displayName, 'Paper');
      expect(ReaderThemePreset.cupertinoLight.displayName, 'Cupertino Light');
      expect(ReaderThemePreset.gruvboxLight.displayName, 'Gruvbox Light');
      expect(ReaderThemePreset.gruvboxDark.displayName, 'Gruvbox Dark');
      expect(ReaderThemePreset.cupertinoDark.displayName, 'Cupertino Dark');
      expect(ReaderThemePreset.oledBlack.displayName, 'OLED Black');
    });
  });

  group('ReaderThemeTokens', () {
    test('all presets produce valid theme data', () {
      for (final preset in ReaderThemePreset.values) {
        final data = ReaderThemeTokens.fromPreset(preset);
        expect(data.bgCanvas, isA<Color>());
        expect(data.bgCard, isA<Color>());
        expect(data.bgDock, isA<Color>());
        expect(data.textPrimary, isA<Color>());
        expect(data.textMuted, isA<Color>());
        expect(data.accent, isA<Color>());
        expect(data.ttsHighlight, isA<Color>());
        expect(data.borderSubtle, isA<Color>());
      }
    });

    test('paper preset matches DESIGN.md hex values', () {
      final paper = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
      expect(paper.bgCanvas, const Color(0xFFF8F9FA));
      expect(paper.textPrimary, const Color(0xFF1A1A1A));
      expect(paper.accent, const Color(0xFF2563EB));
      expect(paper.borderSubtle, const Color(0xFFE4E4E7));
    });

    test('oledBlack preset matches DESIGN.md hex values', () {
      final oled = ReaderThemeTokens.fromPreset(ReaderThemePreset.oledBlack);
      expect(oled.bgCanvas, const Color(0xFF000000));
      expect(oled.bgCard, const Color(0xFF121212));
      expect(oled.accent, const Color(0xFF60A5FA));
      expect(oled.isDark, isTrue);
    });

    test('isDark matches preset isDark', () {
      for (final preset in ReaderThemePreset.values) {
        final data = ReaderThemeTokens.fromPreset(preset);
        expect(data.isDark, preset.isDark);
      }
    });
  });
}
