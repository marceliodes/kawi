import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/reader_theme.dart';
import 'core/theme/reader_theme_tokens.dart';
import 'core/theme/theme_provider.dart';
import 'features/library/screens/kawi_shell.dart';

void main() {
  runApp(const ProviderScope(child: KawiApp()));
}

class KawiApp extends ConsumerWidget {
  const KawiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(themePresetProvider);
    final themeData = ReaderThemeTokens.fromPreset(preset);
    final readerTheme = ReaderTheme(
      data: themeData,
      child: const _MaterialShell(),
    );
    return readerTheme;
  }
}

class _MaterialShell extends StatelessWidget {
  const _MaterialShell();

  @override
  Widget build(BuildContext context) {
    final readerTheme = context
        .dependOnInheritedWidgetOfExactType<ReaderTheme>()!;
    return MaterialApp(
      title: 'Kawi',
      debugShowCheckedModeBanner: false,
      theme: readerTheme.toMaterialTheme(),
      home: const KawiShell(),
    );
  }
}
