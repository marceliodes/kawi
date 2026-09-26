import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kawi/main.dart';

void main() {
  testWidgets('KawiApp renders library empty state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KawiApp()));
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.text('Import Document'), findsOneWidget);
  });

  testWidgets(
    'Theme selection menu lists all 6 curated themes and updates preset',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: KawiApp()));
      await tester.pumpAndSettle();

      // Find and tap the theme menu button
      final themeButton = find.byTooltip('Select theme (Paper)');
      expect(themeButton, findsOneWidget);
      await tester.tap(themeButton);
      await tester.pumpAndSettle();

      // Verify all 6 curated themes are listed in the popup menu
      expect(find.text('Paper'), findsOneWidget);
      expect(find.text('Cupertino Light'), findsOneWidget);
      expect(find.text('Gruvbox Light'), findsOneWidget);
      expect(find.text('Gruvbox Dark'), findsOneWidget);
      expect(find.text('Cupertino Dark'), findsOneWidget);
      expect(find.text('OLED Black'), findsOneWidget);

      // Select OLED Black
      await tester.tap(find.text('OLED Black'));
      await tester.pumpAndSettle();

      // Tooltip should now reflect the selected preset
      expect(find.byTooltip('Select theme (OLED Black)'), findsOneWidget);
    },
  );
}
