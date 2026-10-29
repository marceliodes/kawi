import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
        id: 'doc-annotations-test',
        title: 'Annotations Test Document',
        filePath: '/test/book.epub',
        format: 'epub',
        addedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('ReaderNavigationDrawer Annotations Tab Tests', () {
    testWidgets('switching to Notes tab displays empty state when no highlights exist', (tester) async {
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
            documentId: 'doc-annotations-test',
            filePath: '/test/book.epub',
            currentPageIndex: 0,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Tap Notes tab
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(find.text('No Highlights or Notes Yet'), findsOneWidget);
      expect(find.text('Select any text in the reader to highlight or add notes.'), findsOneWidget);
    });

    testWidgets('displays list of highlights with excerpt, note, and chapter title', (tester) async {
      final sampleToc = [
        const TocEntry(title: 'Chapter 1: The Beginning', pageIndex: 0),
        const TocEntry(title: 'Chapter 2: The Journey', pageIndex: 1),
      ];

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-1',
          documentId: 'doc-annotations-test',
          startChapterIndex: 0,
          startParagraphIndex: 2,
          startCharOffset: 5,
          endChapterIndex: 0,
          endParagraphIndex: 2,
          endCharOffset: 25,
          highlightedText: 'Call me Ishmael.',
          colorHex: '#FFD54F',
          note: const Value('Memorable opening line.'),
          createdAt: DateTime.now(),
        ),
      );

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-2',
          documentId: 'doc-annotations-test',
          startChapterIndex: 1,
          startParagraphIndex: 4,
          startCharOffset: 10,
          endChapterIndex: 1,
          endParagraphIndex: 4,
          endCharOffset: 30,
          highlightedText: 'Some years ago—never mind how long precisely.',
          colorHex: '#64B5F6',
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );

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
            documentId: 'doc-annotations-test',
            filePath: '/test/book.epub',
            currentPageIndex: 0,
            initialTab: NavigationDrawerTab.annotations,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Check excerpt text and chapter titles
      expect(find.text('“Call me Ishmael.”'), findsOneWidget);
      expect(find.text('Chapter 1: The Beginning'), findsOneWidget);
      expect(find.text('Memorable opening line.'), findsOneWidget);

      expect(find.text('“Some years ago—never mind how long precisely.”'), findsOneWidget);
      expect(find.text('Chapter 2: The Journey'), findsOneWidget);
    });

    testWidgets('search query switches from notes to search results and clear button restores notes view', (tester) async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-1',
          documentId: 'doc-annotations-test',
          startChapterIndex: 0,
          startParagraphIndex: 2,
          startCharOffset: 5,
          endChapterIndex: 0,
          endParagraphIndex: 2,
          endCharOffset: 25,
          highlightedText: 'Call me Ishmael.',
          colorHex: '#FFD54F',
          note: const Value('Classic opening.'),
          createdAt: DateTime.now(),
        ),
      );

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-2',
          documentId: 'doc-annotations-test',
          startChapterIndex: 1,
          startParagraphIndex: 4,
          startCharOffset: 10,
          endChapterIndex: 1,
          endParagraphIndex: 4,
          endCharOffset: 30,
          highlightedText: 'The sky was the color of television, tuned to a dead channel.',
          colorHex: '#81C784',
          note: const Value('Cyberpunk aesthetics.'),
          createdAt: DateTime.now(),
        ),
      );

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
            documentId: 'doc-annotations-test',
            filePath: '/test/book.epub',
            currentPageIndex: 0,
            initialTab: NavigationDrawerTab.annotations,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Both visible initially
      expect(find.text('“Call me Ishmael.”'), findsOneWidget);
      expect(find.textContaining('television'), findsOneWidget);

      // Enter search query into in-book search input
      await tester.enterText(find.byType(TextField), 'Cyberpunk');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Body switches to in-book search results view: notes are not rendered in body
      expect(find.text('“Call me Ishmael.”'), findsNothing);
      expect(find.byTooltip('Clear search'), findsOneWidget);

      // Tap clear button to return to notes view
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Both notes visible again in Notes tab
      expect(find.text('“Call me Ishmael.”'), findsOneWidget);
      expect(find.textContaining('television'), findsOneWidget);
    });

    testWidgets('tapping highlight card invokes onSelectAnchor callback', (tester) async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-1',
          documentId: 'doc-annotations-test',
          startChapterIndex: 2,
          startParagraphIndex: 7,
          startCharOffset: 14,
          endChapterIndex: 2,
          endParagraphIndex: 7,
          endCharOffset: 45,
          highlightedText: 'Target passage to jump to.',
          colorHex: '#FFD54F',
          createdAt: DateTime.now(),
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
            documentId: 'doc-annotations-test',
            filePath: '/test/book.epub',
            currentPageIndex: 0,
            initialTab: NavigationDrawerTab.annotations,
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

      // Tap on the highlight card
      await tester.tap(find.text('“Target passage to jump to.”'));
      await tester.pumpAndSettle();

      expect(selectedAnchor, isNotNull);
      expect(selectedAnchor!.chapterIndex, 2);
      expect(selectedAnchor!.paragraphIndex, 7);
      expect(selectedAnchor!.charOffset, 14);
    });

    testWidgets('tapping delete button deletes highlight from database', (tester) async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-del',
          documentId: 'doc-annotations-test',
          startChapterIndex: 0,
          startParagraphIndex: 1,
          startCharOffset: 0,
          endChapterIndex: 0,
          endParagraphIndex: 1,
          endCharOffset: 10,
          highlightedText: 'Delete me soon.',
          colorHex: '#FF8A80',
          createdAt: DateTime.now(),
        ),
      );

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
            documentId: 'doc-annotations-test',
            filePath: '/test/book.epub',
            currentPageIndex: 0,
            initialTab: NavigationDrawerTab.annotations,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('“Delete me soon.”'), findsOneWidget);

      final deleteBtn = find.byTooltip('Delete highlight');
      expect(deleteBtn, findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // Verify removed from database and UI shows empty state
      final remaining = await db.getHighlightsForDocument('doc-annotations-test');
      expect(remaining, isEmpty);
      expect(find.text('No Highlights or Notes Yet'), findsOneWidget);
    });

    testWidgets('tapping edit note button opens dialog and updates note in database', (tester) async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-edit',
          documentId: 'doc-annotations-test',
          startChapterIndex: 0,
          startParagraphIndex: 1,
          startCharOffset: 0,
          endChapterIndex: 0,
          endParagraphIndex: 1,
          endCharOffset: 10,
          highlightedText: 'Text to annotate.',
          colorHex: '#FFD54F',
          createdAt: DateTime.now(),
        ),
      );

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
            documentId: 'doc-annotations-test',
            filePath: '/test/book.epub',
            currentPageIndex: 0,
            initialTab: NavigationDrawerTab.annotations,
            onSelectPage: (_) {},
          ),
        ),
      );

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      final addNoteBtn = find.byTooltip('Add note');
      expect(addNoteBtn, findsOneWidget);

      await tester.tap(addNoteBtn);
      await tester.pumpAndSettle();

      // Dialog is open
      expect(find.text('Add Note'), findsOneWidget);

      // Enter note text in dialog TextField
      // Note that the search field is also in the tree, so find TextField inside the dialog
      final dialogTextField = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogTextField, 'Newly added insightful note.');
      await tester.pumpAndSettle();

      // Tap Save Note
      await tester.tap(find.text('Save Note'));
      await tester.pumpAndSettle();

      // Verify note updated in database
      final highlights = await db.getHighlightsForDocument('doc-annotations-test');
      expect(highlights.first.note, 'Newly added insightful note.');
      expect(find.text('Newly added insightful note.'), findsOneWidget);
    });
  });
}
