import 'package:flutter/material.dart';

import 'reader_theme_data.dart';

class ReaderTheme extends InheritedWidget {
  const ReaderTheme({required this.data, required super.child, super.key});

  final ReaderThemeData data;

  static ReaderThemeData of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ReaderTheme>();
    assert(widget != null, 'No ReaderTheme found in context');
    return widget!.data;
  }

  ThemeData toMaterialTheme() {
    final brightness = data.isDark ? Brightness.dark : Brightness.light;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: data.bgCanvas,
      cardColor: data.bgCard,
      dividerColor: data.borderSubtle,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: data.accent,
        onPrimary: data.isDark ? Colors.black : Colors.white,
        secondary: data.accent,
        onSecondary: data.isDark ? Colors.black : Colors.white,
        surface: data.bgCard,
        onSurface: data.textPrimary,
        error: const Color(0xFFDC2626),
        onError: Colors.white,
      ),
    );
  }

  @override
  bool updateShouldNotify(ReaderTheme oldWidget) => data != oldWidget.data;
}
