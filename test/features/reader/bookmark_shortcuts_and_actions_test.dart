import 'dart:io';

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
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

Widget _createTestApp({
  required ProviderContainer container,
  required DocumentEntry document,
}) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return UncontrolledProviderScope(
    container: container,
    child: ReaderTheme(
      data: themeData,
      child: MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: themeData.bgCanvas),
        home: ReaderScreen(document: document),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentEntry testEpubDoc;

  final List<DocumentNode> sampleNodes = [
    const HeadingNode(1, [TextSegment('Chapter 1: Down the Rabbit Hole')]),
    const ParagraphNode([
      TextSegment(
        'Alice was beginning to get very tired of sitting by her sister on the bank, '
        'and of having nothing to do: once or twice she had peeped into the book her sister was reading, '
        'but it had no pictures or conversations in it.',
      ),
    ]),
    const ParagraphNode([
      TextSegment(
        'So she was considering in her own mind, whether the pleasure of making a daisy-chain '
        'would be worth the trouble of getting up and picking the daisies.',
      ),
    ]),
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    testEpubDoc = DocumentEntry(
      id: 'doc-shortcuts-test',
      title: 'Shortcuts Test EPUB',
      author: 'Lewis Carroll',
      filePath: File('test_assets/alice.epub').absolute.path,
      format: 'epub',
      pageCount: 3,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: 4096,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Bookmark Shortcuts & Top Bar Actions Tests', () {
    testWidgets('top bar bookmark button shows outline initially, filled when tapped to add', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          documentChapterTitleProvider.overrideWith(
            (ref, arg) => Future.value('Chapter 1'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(readerSettingsProvider.notifier)
          .setReadingMode(ReadingMode.paginated);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      // Bookmark button should have "Add Bookmark (Ctrl+D)" tooltip and outline icon
      final addBtnFinder = find.byTooltip('Add Bookmark (Ctrl+D)');
      expect(addBtnFinder, findsOneWidget);

      final iconFinder = find.descendant(
        of: addBtnFinder,
        matching: find.byType(PhosphorIcon),
      );
      expect(iconFinder, findsOneWidget);
      final initialIcon = tester.widget<PhosphorIcon>(iconFinder);
      expect(initialIcon.icon, PhosphorIconsLight.bookmarkSimple);

      // Tap the bookmark button to add a bookmark
      await tester.tap(addBtnFinder);
      await tester.pumpAndSettle();

      // Check DB insertion
      final bookmarks = await db.getBookmarksForDocument('doc-shortcuts-test');
      expect(bookmarks.length, 1);
      expect(bookmarks.first.chapterTitle, 'Chapter 1');

      // Tooltip should now be "Remove Bookmark (Ctrl+D)" and icon filled
      final removeBtnFinder = find.byTooltip('Remove Bookmark (Ctrl+D)');
      expect(removeBtnFinder, findsOneWidget);
      final filledIconFinder = find.descendant(
        of: removeBtnFinder,
        matching: find.byType(PhosphorIcon),
      );
      final updatedIcon = tester.widget<PhosphorIcon>(filledIconFinder);
      expect(updatedIcon.icon, PhosphorIconsFill.bookmarkSimple);

      // Tap again to remove bookmark
      await tester.tap(removeBtnFinder);
      await tester.pumpAndSettle();

      final afterRemove = await db.getBookmarksForDocument('doc-shortcuts-test');
      expect(afterRemove, isEmpty);

      // Icon should be back to outline
      expect(find.byTooltip('Add Bookmark (Ctrl+D)'), findsOneWidget);
    });

    testWidgets('Ctrl+D shortcut toggles bookmark at current anchor', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          documentChapterTitleProvider.overrideWith(
            (ref, arg) => Future.value('Chapter 1'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(await db.getBookmarksForDocument('doc-shortcuts-test'), isEmpty);

      // Press Ctrl + D
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // Bookmark should now exist
      final bookmarks = await db.getBookmarksForDocument('doc-shortcuts-test');
      expect(bookmarks.length, 1);
      expect(bookmarks.first.snippet, contains('Down the Rabbit Hole'));

      // Press Ctrl + D again to remove
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(await db.getBookmarksForDocument('doc-shortcuts-test'), isEmpty);
    });

    testWidgets('Ctrl+T shortcut toggles navigation drawer open and closed', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          documentChapterTitleProvider.overrideWith(
            (ref, arg) => Future.value('Chapter 1'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      // Drawer should be closed initially
      expect(find.text('Contents'), findsNothing);

      // Press Ctrl + T to open drawer
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // Drawer should now be open
      expect(find.text('Contents'), findsOneWidget);
      expect(find.text('Bookmarks'), findsOneWidget);

      // Press Ctrl + T again to close drawer
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // Drawer should be closed
      expect(find.text('Contents'), findsNothing);
    });
  });
}
