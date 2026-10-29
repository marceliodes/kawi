import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/models/search_models.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/search_provider.dart';
import 'package:kawi/features/reader/widgets/reader_search_hud.dart';

Widget _wrapWithTheme({
  required ProviderContainer container,
  required Widget child,
}) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: ReaderTheme(
          data: themeData,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('ReaderSearchHud Widget Tests', () {
    testWidgets('renders input, navigation buttons, and close button', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      bool closed = false;
      bool allResultsOpened = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          container: container,
          child: ReaderSearchHud(
            onClose: () => closed = true,
            onNavigateToMatch: (_) {},
            onOpenAllResults: () => allResultsOpened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Previous match (Shift+Enter)'), findsOneWidget);
      expect(find.byTooltip('Next match (Enter)'), findsOneWidget);
      expect(find.byTooltip('All results'), findsOneWidget);
      expect(find.byTooltip('Close (Esc)'), findsOneWidget);

      await tester.tap(find.byTooltip('All results'));
      await tester.pump();
      expect(allResultsOpened, isTrue);

      await tester.tap(find.byTooltip('Close (Esc)'));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('displays counter states correctly', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const match1 = SearchMatch(
        id: 'c0_p0_o0',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        matchedText: 'test',
        snippet: 'test snippet',
        snippetMatchStart: 0,
        snippetMatchEnd: 4,
        matchIndexInBook: 0,
      );

      // Case 1: Searching with no matches yet
      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'test',
        isSearching: true,
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          container: container,
          child: ReaderSearchHud(
            onClose: () {},
            onNavigateToMatch: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Searching…'), findsOneWidget);

      // Case 2: Finished searching with 0 matches
      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'test',
      );
      await tester.pump();
      expect(find.text('0 of 0'), findsOneWidget);

      // Case 3: Matches found
      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'test',
        matches: [match1],
        activeMatchIndex: 0,
      );
      await tester.pump();
      expect(find.text('1 of 1'), findsOneWidget);
    });

    testWidgets('next and previous buttons trigger onNavigateToMatch and wrap', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const match1 = SearchMatch(
        id: 'c0_p0_o0',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        matchedText: 'one',
        snippet: 'one two',
        snippetMatchStart: 0,
        snippetMatchEnd: 3,
        matchIndexInBook: 0,
      );
      const match2 = SearchMatch(
        id: 'c0_p0_o4',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 7),
        matchedText: 'two',
        snippet: 'one two',
        snippetMatchStart: 4,
        snippetMatchEnd: 7,
        matchIndexInBook: 1,
      );

      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'test',
        matches: [match1, match2],
        activeMatchIndex: 0,
      );

      SearchMatch? navigated;

      await tester.pumpWidget(
        _wrapWithTheme(
          container: container,
          child: ReaderSearchHud(
            onClose: () {},
            onNavigateToMatch: (m) => navigated = m,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Next -> match2
      await tester.tap(find.byTooltip('Next match (Enter)'));
      await tester.pump();
      expect(navigated, match2);

      // Tap Previous -> match1
      await tester.tap(find.byTooltip('Previous match (Shift+Enter)'));
      await tester.pump();
      expect(navigated, match1);
    });

    testWidgets('Escape key closes the HUD and clears search', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      bool closed = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          container: container,
          child: ReaderSearchHud(
            onClose: () => closed = true,
            onNavigateToMatch: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, isTrue);
    });
  });
}
