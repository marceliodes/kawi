import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../models/reader_settings.dart';

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() {
    _loadFromDatabase();
    return const ReaderSettings();
  }

  Future<void> _loadFromDatabase() async {
    try {
      final db = ref.read(databaseProvider);
      final all = await db.getAllSettings();
      if (all.isNotEmpty) {
        state = ReaderSettings.fromSettingsMap(all);
      }
    } catch (_) {
      // Fallback to default if loading fails or during memory tests
    }
  }

  Future<void> setFontFamily(String family) async {
    state = state.copyWith(fontFamily: family);
    await _persist('reader_font_family', family);
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    await _persist('reader_font_size', size.toString());
  }

  Future<void> setLineHeight(double height) async {
    state = state.copyWith(lineHeight: height);
    await _persist('reader_line_height', height.toString());
  }

  Future<void> setParagraphSpacing(double spacing) async {
    state = state.copyWith(paragraphSpacing: spacing);
    await _persist('reader_paragraph_spacing', spacing.toString());
  }

  Future<void> setContentMaxWidth(double width) async {
    state = state.copyWith(contentMaxWidth: width);
    await _persist('reader_content_max_width', width.toString());
  }

  Future<void> setHorizontalPadding(double padding) async {
    state = state.copyWith(horizontalPadding: padding);
    await _persist('reader_horizontal_padding', padding.toString());
  }

  Future<void> setReadingMode(ReadingMode mode) async {
    state = state.copyWith(mode: mode);
    await _persist('reader_mode', mode.name);
  }

  Future<void> setTtsAutoAdvance(bool enabled) async {
    state = state.copyWith(ttsAutoAdvance: enabled);
    await _persist('reader_tts_auto_advance', enabled.toString());
  }

  Future<void> setTtsHighlightStyle(TtsHighlightStyle style) async {
    state = state.copyWith(ttsHighlightStyle: style);
    await _persist('reader_tts_highlight_style', style.name);
  }

  Future<void> updateSettings(ReaderSettings newSettings) async {
    state = newSettings;
    final map = newSettings.toSettingsMap();
    try {
      final db = ref.read(databaseProvider);
      for (final entry in map.entries) {
        await db.setSetting(entry.key, entry.value);
      }
    } catch (_) {}
  }

  Future<void> _persist(String key, String value) async {
    try {
      final db = ref.read(databaseProvider);
      await db.setSetting(key, value);
    } catch (_) {}
  }
}
