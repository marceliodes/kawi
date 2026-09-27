import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/src/internals.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/library/providers/library_provider.dart';
import 'package:kawi/features/library/screens/kawi_shell.dart';
import 'package:kawi/features/library/screens/library_screen.dart';
import 'package:kawi/features/library/widgets/book_card.dart';
import 'package:kawi/features/library/widgets/typeset_book_jacket.dart';

Widget _createTestApp({
  required List<Override> overrides,
  Widget child = const KawiShell(),
}) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return ProviderScope(
    overrides: overrides,
    child: ReaderTheme(
      data: themeData,
      child: MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: themeData.bgCanvas),
        home: child,
      ),
    ),
  );
}

void main() {
  testWidgets('renders book grid when documents exist in library', (
    tester,
  ) async {
    final now = DateTime.now();
    final sampleDocs = [
      DocumentEntry(
        id: 'doc-1',
        title: 'Alice in Wonderland',
        author: 'Lewis Carroll',
        filePath: '/sandbox/alice.epub',
        format: 'epub',
        pageCount: 150,
        addedAt: now,
        isCompleted: false,
        fileSizeBytes: 2048,
      ),
      DocumentEntry(
        id: 'doc-2',
        title: 'Deep Learning',
        author: 'Ian Goodfellow',
        filePath: '/sandbox/dl.pdf',
        format: 'pdf',
        pageCount: 800,
        addedAt: now,
        isCompleted: false,
        fileSizeBytes: 4096,
      ),
    ];

    await tester.pumpWidget(
      _createTestApp(
        overrides: [
          documentsStreamProvider.overrideWith(
            (ref) => Stream.value(sampleDocs),
          ),
          shelvesStreamProvider.overrideWith((ref) => Stream.value(<Shelf>[])),
          documentProgressProvider.overrideWith(
            (ref, docId) => Stream.value(null),
          ),
        ],
        child: const LibraryScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify grid elements
    expect(find.text('All Documents'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('Alice in Wonderland'), findsNWidgets(2));
    expect(find.text('Lewis Carroll'), findsNWidgets(2));
    expect(find.text('Deep Learning'), findsNWidgets(2));
    expect(find.text('Ian Goodfellow'), findsNWidgets(2));
    expect(find.byType(BookCard), findsNWidgets(2));
    expect(find.byType(TypesetBookJacket), findsNWidgets(2));
  });

  testWidgets('displays typeset jacket with spine and Literata font', (
    tester,
  ) async {
    await tester.pumpWidget(
      _createTestApp(
        overrides: const [],
        child: const Scaffold(
          body: SizedBox(
            width: 150,
            height: 220,
            child: TypesetBookJacket(
              title: 'Great Gatsby',
              author: 'F. Scott Fitzgerald',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Great Gatsby'), findsOneWidget);
    expect(find.text('F. Scott Fitzgerald'), findsOneWidget);
  });

  testWidgets('sidebar switches category filter when tapped', (tester) async {
    final container = ProviderContainer(
      overrides: [
        shelvesStreamProvider.overrideWith((ref) => Stream.value(<Shelf>[])),
        documentsStreamProvider.overrideWith(
          (ref) => Stream.value(<DocumentEntry>[]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ReaderTheme(
          data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
          child: const MaterialApp(home: KawiShell()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(libraryFilterProvider).category,
      LibraryFilterCategory.all,
    );

    // Tap "Currently Reading" in sidebar
    await tester.tap(find.text('Currently Reading'));
    await tester.pumpAndSettle();

    expect(
      container.read(libraryFilterProvider).category,
      LibraryFilterCategory.reading,
    );

    // Tap "Completed" in sidebar
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(
      container.read(libraryFilterProvider).category,
      LibraryFilterCategory.completed,
    );
  });

  testWidgets('creates a new shelf via sidebar dialog', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        documentsStreamProvider.overrideWith(
          (ref) => Stream.value(<DocumentEntry>[]),
        ),
        shelvesStreamProvider.overrideWith((ref) => Stream.value(<Shelf>[])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ReaderTheme(
          data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
          child: const MaterialApp(home: KawiShell()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Tap "New Shelf"
    await tester.tap(find.text('New Shelf'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsOneWidget);

    // Enter shelf name
    await tester.enterText(find.byType(TextField), 'Sci-Fi Classics');
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Create button
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify shelf created in database
    final shelves = await (db.select(db.shelves)).get();
    expect(shelves.length, 1);
    expect(shelves.first.name, 'Sci-Fi Classics');

    // Verify filter changed to the new shelf
    final activeFilter = container.read(libraryFilterProvider);
    expect(activeFilter.category, LibraryFilterCategory.shelf);
    expect(activeFilter.shelfName, 'Sci-Fi Classics');
  });

  testWidgets(
    'custom shelf empty state displays "Add from Library" and "Import from Disk"',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          documentsStreamProvider.overrideWith(
            (ref) => Stream.value(<DocumentEntry>[]),
          ),
          shelvesStreamProvider.overrideWith((ref) => Stream.value(<Shelf>[])),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(libraryFilterProvider.notifier)
          .setFilter(LibraryFilterState.shelf('shelf-1', 'Philosophy'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(home: LibraryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add from Library'), findsOneWidget);
      expect(find.text('Import from Disk'), findsOneWidget);
      expect(find.text('Import Document'), findsNothing);
    },
  );

  testWidgets(
    'custom shelf populated state displays "Add from Library" and "Import from Disk" in header',
    (tester) async {
      final now = DateTime.now();
      final sampleDocs = [
        DocumentEntry(
          id: 'doc-1',
          title: 'Meditations',
          author: 'Marcus Aurelius',
          filePath: '/sandbox/meditations.epub',
          format: 'epub',
          pageCount: 150,
          addedAt: now,
          isCompleted: false,
          fileSizeBytes: 2048,
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          documentsStreamProvider.overrideWith(
            (ref) => Stream.value(sampleDocs),
          ),
          shelvesStreamProvider.overrideWith((ref) => Stream.value(<Shelf>[])),
          documentProgressProvider.overrideWith(
            (ref, docId) => Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(libraryFilterProvider.notifier)
          .setFilter(LibraryFilterState.shelf('shelf-1', 'Philosophy'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(home: LibraryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add from Library'), findsOneWidget);
      expect(find.text('Import from Disk'), findsOneWidget);
      expect(find.text('Philosophy'), findsOneWidget);
      expect(find.text('Meditations'), findsNWidgets(2));
    },
  );

  testWidgets(
    'tapping "Add from Library" opens dialog and allows selecting documents to add',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.insertShelf(
        ShelvesCompanion.insert(
          id: 'shelf-1',
          name: 'Philosophy',
          createdAt: DateTime.now(),
        ),
      );

      final now = DateTime.now();
      await db.insertOrUpdateDocument(
        DocumentsCompanion.insert(
          id: 'doc-1',
          title: 'Meditations',
          author: const Value('Marcus Aurelius'),
          filePath: '/sandbox/meditations.epub',
          format: 'epub',
          pageCount: const Value(150),
          addedAt: now,
        ),
      );
      await db.insertOrUpdateDocument(
        DocumentsCompanion.insert(
          id: 'doc-2',
          title: 'Nicomachean Ethics',
          author: const Value('Aristotle'),
          filePath: '/sandbox/ethics.epub',
          format: 'epub',
          pageCount: const Value(250),
          addedAt: now,
        ),
      );

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      container
          .read(libraryFilterProvider.notifier)
          .setFilter(LibraryFilterState.shelf('shelf-1', 'Philosophy'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(home: LibraryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add from Library'), findsOneWidget);

      await tester.tap(find.text('Add from Library'));
      await tester.pumpAndSettle();

      expect(find.text('Add to "Philosophy"'), findsOneWidget);
      expect(find.text('Meditations'), findsOneWidget);
      expect(find.text('Nicomachean Ethics'), findsOneWidget);

      await tester.tap(find.text('Meditations'));
      await tester.pumpAndSettle();

      expect(find.text('Add (1)'), findsOneWidget);

      await tester.tap(find.text('Add (1)'));
      await tester.pumpAndSettle();

      final shelfDocs = await db.watchDocumentsInShelf('shelf-1').first;
      expect(shelfDocs.length, 1);
      expect(shelfDocs.first.id, 'doc-1');

      final allDocs = await db.watchAllDocuments().first;
      expect(allDocs.length, 2);
    },
  );

  testWidgets(
    'removing a document from a custom shelf removes it from shelf but keeps in All Documents',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db.insertShelf(
        ShelvesCompanion.insert(
          id: 'shelf-1',
          name: 'Philosophy',
          createdAt: DateTime.now(),
        ),
      );

      final now = DateTime.now();
      await db.insertOrUpdateDocument(
        DocumentsCompanion.insert(
          id: 'doc-1',
          title: 'Meditations',
          author: const Value('Marcus Aurelius'),
          filePath: '/sandbox/meditations.epub',
          format: 'epub',
          pageCount: const Value(150),
          addedAt: now,
        ),
      );
      await db.addDocumentToShelf('doc-1', 'shelf-1');

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      container
          .read(libraryFilterProvider.notifier)
          .setFilter(LibraryFilterState.shelf('shelf-1', 'Philosophy'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(home: LibraryScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menuButton = find.byType(PopupMenuButton<String>);
      expect(menuButton, findsOneWidget);

      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      expect(find.text('Remove from Philosophy'), findsOneWidget);

      await tester.tap(find.text('Remove from Philosophy'));
      await tester.pumpAndSettle();

      final shelfDocs = await db.watchDocumentsInShelf('shelf-1').first;
      expect(shelfDocs, isEmpty);

      final allDocs = await db.watchAllDocuments().first;
      expect(allDocs.length, 1);
      expect(allDocs.first.id, 'doc-1');
    },
  );
}
