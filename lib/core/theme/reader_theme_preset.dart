enum ReaderThemePreset {
  paper,
  cupertinoLight,
  gruvboxLight,
  gruvboxDark,
  cupertinoDark,
  oledBlack;

  bool get isDark => switch (this) {
    paper || cupertinoLight || gruvboxLight => false,
    gruvboxDark || cupertinoDark || oledBlack => true,
  };

  String get displayName => switch (this) {
    paper => 'Paper',
    cupertinoLight => 'Cupertino Light',
    gruvboxLight => 'Gruvbox Light',
    gruvboxDark => 'Gruvbox Dark',
    cupertinoDark => 'Cupertino Dark',
    oledBlack => 'OLED Black',
  };
}
