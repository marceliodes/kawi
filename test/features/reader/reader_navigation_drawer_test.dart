import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/models/search_models.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/search_provider.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/widgets/reader_navigation_drawer.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

Widget _wrapWithTestApp({
  required ProviderContainer container,
  required Widget drawer,
}) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return UncontrolledProviderScope(
    container: container,
    child: ReaderTheme(
      data: themeData,
      child: MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: themeData.bgCanvas),
        home: Scaffold(
          body: const Text('Main Screen'),
          drawer: drawer,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-drawer-test',
        title: 'Drawer Test Document',
        filePath: '/test/drawer.epub',
        format: 'epub',
        addedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('ReaderNavigationDrawer Widget Tests', () {
    testWidgets('renders Contents tab and Table of Contents by default', (tester) async {
      final sampleToc = [
        const TocEntry(title: 'Chapter 1: The Start', pageIndex: 0),
        const TocEntry(title: 'Chapter 2: The Middle', pageIndex: 1),
      ];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(sampleToc)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
          ),
        ),
      );

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Contents'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Chapter 1: The Start'), findsOneWidget);
      expect(find.text('Chapter 2: The Middle'), findsOneWidget);
    });

    testWidgets('search input has placeholder "Search in book...", switches to search results, clear button resets query, and Escape clears query before closing drawer', (tester) async {
      final sampleToc = [
        const TocEntry(title: 'Chapter 1: The Start', pageIndex: 0),
        const TocEntry(title: 'Chapter 2: The Middle', pageIndex: 1),
        const TocEntry(title: 'Chapter 3: The End', pageIndex: 2),
      ];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(sampleToc)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // 1. Placeholder is "Search in book..."
      expect(find.text('Search in book...'), findsOneWidget);

      // Trailing clear button should not be visible when text is empty
      expect(find.byTooltip('Clear search'), findsNothing);

      // Verify TOC items are visible when query is empty
      expect(find.text('Chapter 1: The Start'), findsOneWidget);
      expect(find.text('Chapter 2: The Middle'), findsOneWidget);

      // Type "Middle" into search
      await tester.enterText(find.byType(TextField), 'Middle');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Body switches to search results view: TOC items are no longer shown in body
      expect(find.text('Chapter 1: The Start'), findsNothing);

      // Trailing clear button should now be visible
      expect(find.byTooltip('Clear search'), findsOneWidget);

      // Tap clear button
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Query cleared and all chapters visible again
      expect(find.text('Chapter 1: The Start'), findsOneWidget);
      expect(find.text('Chapter 2: The Middle'), findsOneWidget);
      expect(find.text('Chapter 3: The End'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsNothing);

      // Type "Start" into search
      await tester.enterText(find.byType(TextField), 'Start');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Chapter 1: The Start'), findsNothing);

      // Press Escape key while text is not empty
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Escape should have cleared query and reset to TOC, without closing the drawer
      expect(scaffoldState.isDrawerOpen, isTrue);
      expect(find.text('Chapter 1: The Start'), findsOneWidget);
      expect(find.text('Chapter 2: The Middle'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsNothing);

      // Press Escape key again now that search text is empty
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Drawer should now be closed
      expect(scaffoldState.isDrawerOpen, isFalse);
    });

    testWidgets('switching to Bookmarks tab displays empty state when no bookmarks', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Tap Bookmarks tab
      await tester.tap(find.byIcon(PhosphorIconsLight.bookmarkSimple));
      await tester.pumpAndSettle();

      expect(find.text('No Bookmarks Yet'), findsOneWidget);
      expect(find.textContaining('Press Ctrl+D'), findsOneWidget);
    });

    testWidgets('displays list of bookmarks, deletes a bookmark, and triggers navigation callback', (tester) async {
      // Insert 2 bookmarks into DB
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-1',
          documentId: 'doc-drawer-test',
          chapterIndex: 0,
          paragraphIndex: 5,
          charOffset: 0,
          chapterTitle: const Value('Chapter 1'),
          snippet: 'Snippet for chapter 1',
          createdAt: DateTime.now(),
        ),
      );
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-2',
          documentId: 'doc-drawer-test',
          chapterIndex: 1,
          paragraphIndex: 8,
          charOffset: 20,
          chapterTitle: const Value('Chapter 2'),
          snippet: 'Snippet for chapter 2',
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      ReadingAnchor? selectedAnchor;

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            initialTab: NavigationDrawerTab.bookmarks,
            onSelectPage: (_) {},
            onSelectAnchor: (anchor) {
              selectedAnchor = anchor;
            },
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Both bookmarks should be visible
      expect(find.text('Snippet for chapter 1'), findsOneWidget);
      expect(find.text('Snippet for chapter 2'), findsOneWidget);

      // Tap on the second bookmark to navigate
      await tester.tap(find.text('Snippet for chapter 2'));
      await tester.pumpAndSettle();

      expect(selectedAnchor, isNotNull);
      expect(selectedAnchor!.chapterIndex, 1);
      expect(selectedAnchor!.paragraphIndex, 8);
      expect(selectedAnchor!.charOffset, 20);

      // Re-open drawer to test delete button
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Find delete buttons (IconButton with trash icon)
      final deleteButtons = find.byTooltip('Delete bookmark');
      expect(deleteButtons, findsNWidgets(2));

      // Tap delete on the first one
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // Database should only have 1 bookmark left
      final remaining = await db.getBookmarksForDocument('doc-drawer-test');
      expect(remaining.length, 1);
    });

    testWidgets('header contains exactly 3 tabs (Contents, Bookmarks, Notes) without Search tab', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Contents'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Search'), findsNothing);
    });

    testWidgets('full-text search renders grouped results and tapping snippet triggers onSelectAnchor', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      const sampleMatch = SearchMatch(
        id: 'c0_p1_o10',
        chapterIndex: 0,
        chapterTitle: 'Chapter 1: The Beginning',
        paragraphIndex: 1,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 10),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 15),
        matchedText: 'magic',
        snippet: 'A world full of magic and mystery awaits.',
        snippetMatchStart: 16,
        snippetMatchEnd: 21,
        matchIndexInBook: 0,
      );

      ReadingAnchor? clickedAnchor;

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
            onSelectAnchor: (anchor) => clickedAnchor = anchor,
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Enter query "magic"
      await tester.enterText(find.byType(TextField), 'magic');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Populate search state directly in controller (isSearching: false)
      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'magic',
        matches: [sampleMatch],
        groups: [
          SearchResultGroup(
            chapterIndex: 0,
            chapterTitle: 'Chapter 1: The Beginning',
            matches: [sampleMatch],
          ),
        ],
        activeMatchIndex: 0,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Match count header displayed
      expect(find.text('1 match found'), findsOneWidget);

      // Chapter header and match snippet displayed
      expect(find.text('Chapter 1: The Beginning'), findsOneWidget);
      expect(find.textContaining('mystery', findRichText: true), findsOneWidget);

      // Tap snippet card
      await tester.tap(find.textContaining('mystery', findRichText: true));
      await tester.pumpAndSettle();

      // Drawer popped and callback triggered with startAnchor
      expect(scaffoldState.isDrawerOpen, isFalse);
      expect(clickedAnchor, equals(sampleMatch.startAnchor));
    });

    testWidgets('autoFocusSearch: true auto-focuses search text field', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider.overrideWith((ref, path) => Future.value(const [])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapWithTestApp(
          container: container,
          drawer: ReaderNavigationDrawer(
            documentId: 'doc-drawer-test',
            filePath: '/test/drawer.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
            autoFocusSearch: true,
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.focusNode?.hasFocus, isTrue);
    });
  });
}
