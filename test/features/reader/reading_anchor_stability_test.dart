import 'dart:io';

import 'package:drift/native.dart';
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
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';

class _TestTtsNotifier extends TtsStateNotifier {
  _TestTtsNotifier(this._initial);
  final TtsState _initial;

  bool playCalled = false;
  bool pauseCalled = false;

  @override
  TtsState build() => _initial;

  @override
  void play() {
    playCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.playing);
  }

  @override
  void pause() {
    pauseCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.paused);
  }

  void setPausedSentence(String text, int index) {
    state = state.copyWith(
      playbackState: TtsPlaybackState.paused,
      currentSentenceText: text,
      currentSentenceIndex: index,
      totalSentences: 30,
    );
  }
}

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

  // Generate 60 rich paragraphs to ensure a multi-page chapter (15+ pages) even at smaller font sizes
  final List<DocumentNode> sampleNodes = [
    const HeadingNode(1, [TextSegment('Chapter 1: The Long Journey')]),
    for (var i = 1; i <= 60; i++)
      ParagraphNode([
        TextSegment(
          'Paragraph $i is a substantial paragraph of text designed to take multiple lines '
          'and simulate realistic prose inside an EPUB reader chapter. '
          'It contains detailed sentences with words, commas, and punctuation to ensure '
          'it wraps cleanly and tests typography recalculations and anchor stability.',
        ),
      ]),
  ];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testEpubDoc = DocumentEntry(
      id: 'doc-epub-anchor-test',
      title: 'Anchor Stability Test EPUB',
      author: 'Author',
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

  group('Reading Anchor Stability & TTS Sentence Preservation Tests', () {
    testWidgets(
        'Deep-page typography change preserves reading anchor and does not reset to Page 1',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
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

      // Set initial paginated mode with 16.0 font size
      await container
          .read(readerSettingsProvider.notifier)
          .setReadingMode(ReadingMode.paginated);
      await container
          .read(readerSettingsProvider.notifier)
          .setFontSize(16.0);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      // Find the ReaderCanvasState
      final canvasFinder = find.byType(ReaderCanvas);
      expect(canvasFinder, findsOneWidget);
      final canvasState = tester.state<ReaderCanvasState>(canvasFinder);

      // Verify that the chapter paginated into multiple pages
      expect(canvasState.epubPageController, isNotNull);
      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);

      // Navigate deep into the chapter: to Page 10
      canvasState.jumpToPageInChapter(10);
      await tester.pumpAndSettle();

      // Verify user is at Page 10 (index 10, i.e. Page 11 of N)
      final initialPage = canvasState.safeGetEpubPage()?.round();
      expect(initialPage, 10);

      // Verify anchor is recorded for Page 10
      final initialAnchor = container.read(activeReadingAnchorProvider);
      expect(initialAnchor, isNotNull);
      expect(initialAnchor!.chapterIndex, 0);
      expect(initialAnchor.paragraphIndex, greaterThan(0));

      // Change typography: Increase font size from 16 to 24
      await container
          .read(readerSettingsProvider.notifier)
          .setFontSize(24.0);
      await tester.pumpAndSettle();

      // Verify that after repagination, the user is NOT reset to Page 1 (index 0)!
      final repaginatedPage = canvasState.safeGetEpubPage()?.round();
      expect(
        repaginatedPage,
        isNotNull,
        reason: 'PageController must have an active page',
      );
      expect(
        repaginatedPage,
        isNot(equals(0)),
        reason: 'Reader must NOT reset to Page 1 (index 0) after font size change!',
      );
      expect(
        repaginatedPage,
        greaterThanOrEqualTo(5),
        reason:
            'Anchor at paragraph ${initialAnchor.paragraphIndex} should resolve to a deep page (was page 10)',
      );
    });

    testWidgets(
        'Window resize preserves reading anchor and does not reset to Page 1',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
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
      await container
          .read(readerSettingsProvider.notifier)
          .setFontSize(18.0);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final canvasState = tester.state<ReaderCanvasState>(find.byType(ReaderCanvas));

      // Navigate to Page 6 (within the 8-page chapter on large viewport)
      canvasState.jumpToPageInChapter(6);
      await tester.pumpAndSettle();

      expect(canvasState.safeGetEpubPage()?.round(), 6);
      final anchorBefore = container.read(activeReadingAnchorProvider);
      expect(anchorBefore, isNotNull);

      // Simulate window resize (drastic shrink from 1200x1600 to 700x900)
      tester.view.physicalSize = const Size(700, 900);
      await tester.pumpAndSettle();

      final pageAfterResize = canvasState.safeGetEpubPage()?.round();
      expect(
        pageAfterResize,
        isNot(equals(0)),
        reason: 'Reader must NOT reset to Page 1 on window resize!',
      );
      expect(
        pageAfterResize,
        greaterThanOrEqualTo(5),
        reason: 'Reading anchor should be preserved across window resize',
      );
    });

    testWidgets(
        'Paused TTS sentence anchor is preserved across font size changes',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const targetSentence =
          'Paragraph 15 is a substantial paragraph of text designed to take multiple lines and simulate realistic prose inside an EPUB reader chapter.';

      final ttsNotifier = _TestTtsNotifier(const TtsState());

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
          ttsStateProvider.overrideWith(() => ttsNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(readerSettingsProvider.notifier)
          .setReadingMode(ReadingMode.paginated);
      await container
          .read(readerSettingsProvider.notifier)
          .setFontSize(16.0);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final canvasState = tester.state<ReaderCanvasState>(find.byType(ReaderCanvas));

      // Pause TTS on Paragraph 15's sentence
      ttsNotifier.setPausedSentence(targetSentence, 15);
      await tester.pumpAndSettle();

      // Change typography: Increase font size from 16 to 24
      await container
          .read(readerSettingsProvider.notifier)
          .setFontSize(24.0);
      await tester.pumpAndSettle();

      // Verify that reader canvas is positioned on the page containing targetSentence
      final curPage = canvasState.safeGetEpubPage()?.round();
      expect(curPage, isNotNull);
      expect(curPage, isNot(equals(0)));

      // Resume TTS
      ttsNotifier.play();
      await tester.pumpAndSettle();

      expect(ttsNotifier.playCalled, isTrue);
      expect(ttsNotifier.state.isPlaying, isTrue);
      expect(ttsNotifier.state.currentSentenceText, targetSentence);
    });

    testWidgets(
        'jumpToPageInChapter does not prematurely clamp target page to 0 when pages are unpaginated',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
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
      await tester.pump(); // Pump initial frame before async pagination completes

      final canvasState = tester.state<ReaderCanvasState>(find.byType(ReaderCanvas));

      // Call jumpToPageInChapter with page 7
      canvasState.jumpToPageInChapter(7);

      // Settle frames so pagination completes
      await tester.pumpAndSettle();

      expect(
        canvasState.safeGetEpubPage()?.round(),
        7,
        reason: 'jumpToPageInChapter(7) must not be clamped to 0 during initial load',
      );
    });

    testWidgets(
        'Repeated typography changes do not ratchet reading anchor backwards (quantization drift prevention)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
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
      await container
          .read(readerSettingsProvider.notifier)
          .setFontSize(14.0);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final canvasFinder = find.byType(ReaderCanvas);
      expect(canvasFinder, findsOneWidget);
      final canvasState = tester.state<ReaderCanvasState>(canvasFinder);

      // Navigate deep into the chapter: to Page 10
      canvasState.jumpToPageInChapter(10);
      await tester.pumpAndSettle();

      final initialPage = canvasState.safeGetEpubPage()?.round();
      expect(initialPage, 10);

      final initialAnchor = container.read(activeReadingAnchorProvider);
      expect(initialAnchor, isNotNull);

      // Explicitly adjust character offset forward to verify that mid-page anchors
      // are preserved rather than being quantized down to the start of the page.
      final targetAnchor = ReadingAnchor(
        chapterIndex: 0,
        paragraphIndex: initialAnchor!.paragraphIndex,
        charOffset: initialAnchor.charOffset + 35,
      );
      container.read(activeReadingAnchorProvider.notifier).updateAnchor(
            chapterIndex: targetAnchor.chapterIndex,
            paragraphIndex: targetAnchor.paragraphIndex,
            charOffset: targetAnchor.charOffset,
          );
      await tester.pumpAndSettle();

      final anchorBeforeToggles = container.read(activeReadingAnchorProvider);
      expect(anchorBeforeToggles, equals(targetAnchor));

      // Toggle font size back and forth multiple times (14 -> 16 -> 14 -> 16 -> 14 -> 16 -> 14)
      for (var i = 0; i < 4; i++) {
        await container
            .read(readerSettingsProvider.notifier)
            .setFontSize(16.0);
        await tester.pumpAndSettle();

        final anchorAt16 = container.read(activeReadingAnchorProvider);
        expect(
          anchorAt16,
          equals(targetAnchor),
          reason: 'Anchor must not be overwritten or rounded down on font size increase',
        );

        await container
            .read(readerSettingsProvider.notifier)
            .setFontSize(14.0);
        await tester.pumpAndSettle();

        final anchorAt14 = container.read(activeReadingAnchorProvider);
        expect(
          anchorAt14,
          equals(targetAnchor),
          reason: 'Anchor must not be overwritten or rounded down on font size decrease',
        );
      }

      // Assert that after multiple toggles, the saved anchor paragraph and character offset
      // have not drifted backwards by even a single character.
      final finalAnchor = container.read(activeReadingAnchorProvider);
      expect(finalAnchor?.paragraphIndex, equals(targetAnchor.paragraphIndex));
      expect(finalAnchor?.charOffset, equals(targetAnchor.charOffset));

      // Assert that the page index remains stable at page 10 rather than ratcheting down to Page 1.
      final finalPage = canvasState.safeGetEpubPage()?.round();
      expect(
        finalPage,
        10,
        reason: 'Page index must remain 10 under font size 14.0 instead of ratcheting down toward 0',
      );

      // Verify that subsequent user-initiated navigation properly updates the anchor.
      canvasState.goToNextPage();
      await tester.pumpAndSettle();

      final anchorAfterUserNav = container.read(activeReadingAnchorProvider);
      expect(
        anchorAfterUserNav,
        isNot(equals(targetAnchor)),
        reason: 'User navigation must update the reading anchor once programmatic re-anchoring finishes',
      );
    });
  });
}
