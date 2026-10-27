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
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/widgets/reader_navigation_drawer.dart';

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

    testWidgets('search input has placeholder "Search chapters...", clear button clears query, and Escape clears query before closing drawer', (tester) async {
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

      // 1. Placeholder is "Search chapters..."
      expect(find.text('Search chapters...'), findsOneWidget);

      // Trailing clear button should not be visible when text is empty
      expect(find.byTooltip('Clear search'), findsNothing);

      // Type "Middle" into search
      await tester.enterText(find.byType(TextField), 'Middle');
      await tester.pumpAndSettle();

      // Filtered: Chapter 2 is visible, Chapter 1 & 3 are filtered out
      expect(find.text('Chapter 2: The Middle'), findsOneWidget);
      expect(find.text('Chapter 1: The Start'), findsNothing);

      // Trailing clear button should now be visible
      expect(find.byTooltip('Clear search'), findsOneWidget);

      // Tap clear button
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      // Query cleared and all chapters visible again
      expect(find.text('Chapter 1: The Start'), findsOneWidget);
      expect(find.text('Chapter 2: The Middle'), findsOneWidget);
      expect(find.text('Chapter 3: The End'), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsNothing);

      // Type "Start" into search
      await tester.enterText(find.byType(TextField), 'Start');
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1: The Start'), findsOneWidget);
      expect(find.text('Chapter 2: The Middle'), findsNothing);

      // Press Escape key while text is not empty
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Escape should have cleared query and reset filter, without closing the drawer
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
      await tester.tap(find.text('Bookmarks'));
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
  });
}
