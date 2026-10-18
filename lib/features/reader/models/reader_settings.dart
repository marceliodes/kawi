import '../../../core/theme/typography.dart';

enum ReadingMode {
  continuous,
  paginated;

  String get displayName => switch (this) {
    continuous => 'Continuous',
    paginated => 'Paginated',
  };
}

enum TtsHighlightStyle {
  background,
  underline;

  String get displayName => switch (this) {
    background => 'Background',
    underline => 'Underline',
  };
}

class ReaderSettings {
  const ReaderSettings({
    this.fontFamily = AppTypography.readerSerif,
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.paragraphSpacing = 16.0,
    this.contentMaxWidth = 680.0,
    this.horizontalPadding = 24.0,
    this.mode = ReadingMode.continuous,
    this.ttsAutoAdvance = true,
    this.ttsHighlightStyle = TtsHighlightStyle.background,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double contentMaxWidth;
  final double horizontalPadding;
  final ReadingMode mode;
  final bool ttsAutoAdvance;
  final TtsHighlightStyle ttsHighlightStyle;

  bool get isPaginated => mode == ReadingMode.paginated;

  /// Alias for contentMaxWidth to support columnWidth property access.
  double get columnWidth => contentMaxWidth;

  ReaderSettings copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? contentMaxWidth,
    double? horizontalPadding,
    ReadingMode? mode,
    bool? ttsAutoAdvance,
    TtsHighlightStyle? ttsHighlightStyle,
  }) {
    return ReaderSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      mode: mode ?? this.mode,
      ttsAutoAdvance: ttsAutoAdvance ?? this.ttsAutoAdvance,
      ttsHighlightStyle: ttsHighlightStyle ?? this.ttsHighlightStyle,
    );
  }

  Map<String, String> toSettingsMap() {
    return {
      'reader_font_family': fontFamily,
      'reader_font_size': fontSize.toString(),
      'reader_line_height': lineHeight.toString(),
      'reader_paragraph_spacing': paragraphSpacing.toString(),
      'reader_content_max_width': contentMaxWidth.toString(),
      'reader_horizontal_padding': horizontalPadding.toString(),
      'reader_mode': mode.name,
      'reader_tts_auto_advance': ttsAutoAdvance.toString(),
      'reader_tts_highlight_style': ttsHighlightStyle.name,
    };
  }

  factory ReaderSettings.fromSettingsMap(Map<String, String> map) {
    return ReaderSettings(
      fontFamily: map['reader_font_family'] ?? AppTypography.readerSerif,
      fontSize: double.tryParse(map['reader_font_size'] ?? '') ?? 18.0,
      lineHeight: double.tryParse(map['reader_line_height'] ?? '') ?? 1.6,
      paragraphSpacing:
          double.tryParse(map['reader_paragraph_spacing'] ?? '') ?? 16.0,
      contentMaxWidth:
          double.tryParse(map['reader_content_max_width'] ?? '') ?? 680.0,
      horizontalPadding:
          double.tryParse(map['reader_horizontal_padding'] ?? '') ?? 24.0,
      mode: map['reader_mode'] == ReadingMode.paginated.name
          ? ReadingMode.paginated
          : ReadingMode.continuous,
      ttsAutoAdvance: map['reader_tts_auto_advance'] == null
          ? true
          : (map['reader_tts_auto_advance'] == 'true'),
      ttsHighlightStyle: TtsHighlightStyle.values.firstWhere(
        (e) => e.name == map['reader_tts_highlight_style'],
        orElse: () => TtsHighlightStyle.background,
      ),
    );
  }
}
