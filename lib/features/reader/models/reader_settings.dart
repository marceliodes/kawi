import '../../../core/theme/typography.dart';

enum ReadingMode {
  continuous,
  paginated;

  String get displayName => switch (this) {
    continuous => 'Continuous',
    paginated => 'Paginated',
  };
}

class ReaderSettings {
  const ReaderSettings({
    this.fontFamily = AppTypography.readerSerif,
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.contentMaxWidth = 680.0,
    this.horizontalPadding = 24.0,
    this.mode = ReadingMode.continuous,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double contentMaxWidth;
  final double horizontalPadding;
  final ReadingMode mode;

  bool get isPaginated => mode == ReadingMode.paginated;

  ReaderSettings copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? contentMaxWidth,
    double? horizontalPadding,
    ReadingMode? mode,
  }) {
    return ReaderSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      mode: mode ?? this.mode,
    );
  }

  Map<String, String> toSettingsMap() {
    return {
      'reader_font_family': fontFamily,
      'reader_font_size': fontSize.toString(),
      'reader_line_height': lineHeight.toString(),
      'reader_content_max_width': contentMaxWidth.toString(),
      'reader_horizontal_padding': horizontalPadding.toString(),
      'reader_mode': mode.name,
    };
  }

  factory ReaderSettings.fromSettingsMap(Map<String, String> map) {
    return ReaderSettings(
      fontFamily: map['reader_font_family'] ?? AppTypography.readerSerif,
      fontSize: double.tryParse(map['reader_font_size'] ?? '') ?? 18.0,
      lineHeight: double.tryParse(map['reader_line_height'] ?? '') ?? 1.6,
      contentMaxWidth:
          double.tryParse(map['reader_content_max_width'] ?? '') ?? 680.0,
      horizontalPadding:
          double.tryParse(map['reader_horizontal_padding'] ?? '') ?? 24.0,
      mode: map['reader_mode'] == ReadingMode.paginated.name
          ? ReadingMode.paginated
          : ReadingMode.continuous,
    );
  }
}
