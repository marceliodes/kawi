import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/reader/widgets/reader_selection_toolbar.dart';

Widget _wrapCanvas({
  required ProviderContainer container,
  required Widget child,
}) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return UncontrolledProviderScope(
    container: container,
    child: ReaderTheme(
      data: themeData,
      child: MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: themeData.bgCanvas),
        home: Scaffold(
          body: child,
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
        id: 'doc-selection-test',
        title: 'Selection Test Document',
        filePath: '/test/selection.epub',
        format: 'epub',
        addedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Desktop Selection & Toolbar Interactions', () {
    testWidgets('mouse drag selection automatically displays ReaderSelectionToolbar on pointer up',
        (tester) async {
      const sampleNodes = [
        ParagraphNode(
          [
            TextSegment(
              'The quick brown fox jumps over the lazy dog near the riverbank.',
            ),
          ],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapCanvas(
          container: container,
          child: ReaderCanvas(
            documentId: 'doc-selection-test',
            filePath: '/test/selection.epub',
            pageCount: 1,
            isEpub: true,
            epubNodes: sampleNodes,
            settings: const ReaderSettings(
              fontSize: 16.0,
              lineHeight: 1.5,
              contentMaxWidth: 600.0,
            ),
            initialPageIndex: 0,
            initialChapterIndex: 0,
            chapterIndex: 0,
            initialScrollOffset: 0.0,
            pageController: PageController(),
            onPageChanged: (_, _) {},
            onToggleChrome: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final paragraphFinder = find.textContaining('The quick brown fox');
      expect(paragraphFinder, findsOneWidget);

      // Initially no toolbar is visible
      expect(find.byType(ReaderSelectionToolbar), findsNothing);

      // Simulate mouse drag selection over the text
      final textTopLeft = tester.getTopLeft(paragraphFinder);
      final textCenter = tester.getCenter(paragraphFinder);

      final gesture = await tester.startGesture(
        textTopLeft + const Offset(10, 5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(textCenter);
      await tester.pump();

      // Complete drag (pointer up)
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Floating ReaderSelectionToolbar should be visible immediately upon mouse release!
      expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
      expect(find.byTooltip('Amber'), findsOneWidget);
      expect(find.byTooltip('Mint'), findsOneWidget);
    });

    testWidgets('secondary click does not collapse active selection to a single cursor',
        (tester) async {
      const sampleNodes = [
        ParagraphNode(
          [
            TextSegment(
              'Highlight this specific sentence and try right clicking.',
            ),
          ],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapCanvas(
          container: container,
          child: ReaderCanvas(
            documentId: 'doc-selection-test',
            filePath: '/test/selection.epub',
            pageCount: 1,
            isEpub: true,
            epubNodes: sampleNodes,
            settings: const ReaderSettings(
              fontSize: 16.0,
              lineHeight: 1.5,
              contentMaxWidth: 600.0,
            ),
            initialPageIndex: 0,
            initialChapterIndex: 0,
            chapterIndex: 0,
            initialScrollOffset: 0.0,
            pageController: PageController(),
            onPageChanged: (_, _) {},
            onToggleChrome: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final paragraphFinder = find.textContaining('Highlight this specific');
      final textTopLeft = tester.getTopLeft(paragraphFinder);
      final textCenter = tester.getCenter(paragraphFinder);

      // Mouse drag select text
      final gesture = await tester.startGesture(
        textTopLeft + const Offset(5, 5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(textCenter);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ReaderSelectionToolbar), findsOneWidget);

      // Secondary click (right click) on the text
      final secondaryGesture = await tester.startGesture(
        textCenter,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await secondaryGesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Selection must NOT be collapsed to an empty cursor; toolbar remains visible!
      expect(find.byType(ReaderSelectionToolbar), findsOneWidget);
    });

    testWidgets('clicking color chip applies highlight, collapses selection, and dismisses toolbar',
        (tester) async {
      const sampleNodes = [
        ParagraphNode(
          [
            TextSegment(
              'Sentence to be permanently highlighted in mint green.',
            ),
          ],
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _wrapCanvas(
          container: container,
          child: ReaderCanvas(
            documentId: 'doc-selection-test',
            filePath: '/test/selection.epub',
            pageCount: 1,
            isEpub: true,
            epubNodes: sampleNodes,
            settings: const ReaderSettings(
              fontSize: 16.0,
              lineHeight: 1.5,
              contentMaxWidth: 600.0,
            ),
            initialPageIndex: 0,
            initialChapterIndex: 0,
            chapterIndex: 0,
            initialScrollOffset: 0.0,
            pageController: PageController(),
            onPageChanged: (_, _) {},
            onToggleChrome: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final paragraphFinder = find.textContaining('Sentence to be permanently');
      final textTopLeft = tester.getTopLeft(paragraphFinder);
      final textCenter = tester.getCenter(paragraphFinder);

      // Drag to select text
      final gesture = await tester.startGesture(
        textTopLeft + const Offset(5, 5),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(textCenter);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ReaderSelectionToolbar), findsOneWidget);

      // Tap Mint chip
      await tester.tap(find.byTooltip('Mint'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Toolbar is dismissed
      expect(find.byType(ReaderSelectionToolbar), findsNothing);

      // Highlight saved in DB
      final highlightsInDb = await db.getHighlightsForDocument('doc-selection-test');
      expect(highlightsInDb.length, 1);
      expect(highlightsInDb.first.colorHex, '#81C784');
    });
  });
}
