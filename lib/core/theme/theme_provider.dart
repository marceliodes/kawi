import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reader_theme_preset.dart';

final themePresetProvider =
    NotifierProvider<ThemePresetNotifier, ReaderThemePreset>(
      ThemePresetNotifier.new,
    );

class ThemePresetNotifier extends Notifier<ReaderThemePreset> {
  @override
  ReaderThemePreset build() => ReaderThemePreset.paper;

  void setPreset(ReaderThemePreset preset) => state = preset;

  void cycleNext() {
    const values = ReaderThemePreset.values;
    final nextIndex = (state.index + 1) % values.length;
    state = values[nextIndex];
  }
}
