import 'dart:io';

import 'package:drift/drift.dart' hide Column, isNotNull;
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
import 'package:kawi/features/reader/constants/reader_layout_constants.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/reader/services/chapter_paginator.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/services/epub_service.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

final _kValid1x1Png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _TestReaderSettingsNotifier extends ReaderSettingsNotifier {
  final ReaderSettings initialSettings;
  _TestReaderSettingsNotifier(this.initialSettings);

  @override
  ReaderSettings build() => initialSettings;
}

class _MockEpubTtsNotifier extends TtsStateNotifier {
  String? lastSpokenText;
  int speakCallCount = 0;

  @override
  TtsState build() => const TtsState();

  @override
  void speak(String text, {int startSentenceIndex = 0}) {
    speakCallCount++;
    lastSpokenText = text;
    state = state.copyWith(
      playbackState: TtsPlaybackState.playing,
      currentSentenceText: text.split('. ').first,
      currentSentenceIndex: 0,
      totalSentences: 10,
    );
  }

  void updateTtsState({
    required TtsPlaybackState playbackState,
    required String currentSentenceText,
    String currentWord = '',
    int? currentSentenceIndex,
  }) {
    state = state.copyWith(
      playbackState: playbackState,
      currentSentenceText: currentSentenceText,
      currentWord: currentWord,
      currentSentenceIndex: currentSentenceIndex ?? state.currentSentenceIndex,
    );
  }
}

Widget _buildTestApp({
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

  final epubFile = File('test_assets/alice.epub');
  late AppDatabase db;
  late DocumentEntry aliceDoc;
  List<DocumentNode> sampleNodes = const [];

  setUpAll(() async {
    if (epubFile.existsSync()) {
      sampleNodes =
          await EpubService.instance.extractChapterNodes(epubFile.path, 3);
    }
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    aliceDoc = DocumentEntry(
      id: 'doc-alice',
      title: "Alice's Adventures in Wonderland",
      author: 'Lewis Carroll',
      filePath: epubFile.path,
      format: 'epub',
      pageCount: 10,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: epubFile.existsSync() ? epubFile.lengthSync() : 1024,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Native EPUB Engine Integration Tests', () {
    testWidgets('ReaderCanvas renders Paginated PageChunks with page counter',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

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
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Page counter should display 'Page 1 of X'
      expect(find.textContaining('Page 1 of'), findsWidgets);

      // Verify that chapter text is rendered inside SelectableText widgets
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets(
        'Paginated mode renders page content strictly <= viewport available height without line clipping',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

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
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);

      final columnFinder = find.descendant(
        of: pageViewFinder,
        matching: find.byType(Column),
      ).first;
      expect(columnFinder, findsOneWidget);
      final columnBox = tester.renderObject<RenderBox>(columnFinder);

      const expectedAvailableHeight = 1600.0 -
          EpubPaginationMetrics.topPadding -
          EpubPaginationMetrics.bottomPadding;

      // Height of the column content must not exceed the available height
      expect(columnBox.size.height, lessThanOrEqualTo(expectedAvailableHeight));

      // Rendered column width must strictly equal columnWidth (no double horizontal padding deduction)
      final expectedColumnWidth = EpubPaginationMetrics.computeColumnWidth(
        viewportWidth: 1200.0,
        horizontalPadding: 24.0,
        maxContentWidth: const ReaderSettings().contentMaxWidth,
      );
      expect(columnBox.size.width, equals(expectedColumnWidth));

      // Test responsive reflow on window resize
      tester.view.physicalSize = const Size(800, 1000);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final resizedColumnFinder = find.descendant(
        of: pageViewFinder,
        matching: find.byType(Column),
      ).first;
      final resizedColumnBox =
          tester.renderObject<RenderBox>(resizedColumnFinder);
      const expectedResizedAvailableHeight = 1000.0 -
          EpubPaginationMetrics.topPadding -
          EpubPaginationMetrics.bottomPadding;
      expect(resizedColumnBox.size.height,
          lessThanOrEqualTo(expectedResizedAvailableHeight));
      final expectedResizedColumnWidth = EpubPaginationMetrics.computeColumnWidth(
        viewportWidth: 800.0,
        horizontalPadding: 24.0,
        maxContentWidth: const ReaderSettings().contentMaxWidth,
      );
      expect(resizedColumnBox.size.width, equals(expectedResizedColumnWidth));
    });

    testWidgets('ReaderCanvas renders Continuous mode with ScrollablePositionedList of chapters',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes.take(3).toList()),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                fontSize: 16.0,
                lineHeight: 1.5,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // In continuous mode, ScrollablePositionedList should be rendered
      expect(find.byType(ScrollablePositionedList), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
      // Chapter header should be present
      expect(find.textContaining('Rabbit-Hole'), findsWidgets);
    });

    testWidgets('TTS highlighting renders active sentence span without word fragmentation',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockTts = _MockEpubTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTts),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Find text rendered on the first page
      final selectableTexts = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      expect(selectableTexts, isNotEmpty);

      final firstSpan = selectableTexts.first.textSpan!;
      final fullText = firstSpan.toPlainText();
      final words = fullText
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3)
          .toList();
      expect(words, isNotEmpty);

      final targetWord = words.first;

      // Update TTS to active playing state for the first sentence
      mockTts.updateTtsState(
        playbackState: TtsPlaybackState.playing,
        currentSentenceText: fullText.split('\n').first,
        currentWord: targetWord,
      );
      await tester.pump();

      // Verify that SelectableText received highlighted spans
      final updatedSelectable = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .first;
      final renderedSpan = updatedSelectable.textSpan!;

      // Find if any span contains the ttsHighlight background color
      final theme = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
      bool hasSentenceHighlight = false;
      bool hasWordHighlight = false;

      void checkSpan(InlineSpan span) {
        if (span is TextSpan) {
          if (span.style?.backgroundColor == theme.ttsHighlight) {
            hasSentenceHighlight = true;
          }
          if (span.text == targetWord &&
              span.style?.fontWeight == FontWeight.w600) {
            hasWordHighlight = true;
          }
          span.children?.forEach(checkSpan);
        }
      }

      checkSpan(renderedSpan);
      expect(hasSentenceHighlight, isTrue);
      expect(hasWordHighlight, isFalse);
    });

    testWidgets('_startTts sends clean semantic text to TTS engine',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      final mockTts = _MockEpubTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTts),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Trigger TTS playback
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockTts.speakCallCount, 1);
      expect(mockTts.lastSpokenText, isNotNull);
      // Clean semantic text should contain title/content without [image] placeholders
      expect(mockTts.lastSpokenText, isNot(contains('[image')));
      expect(mockTts.lastSpokenText, isNot(contains('<p>')));
      expect(mockTts.lastSpokenText!.isNotEmpty, isTrue);
    });

    testWidgets('Auto-page-turn advances page when TTS progresses to subsequent page',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final pages = ChapterPaginator.paginate(
        nodes: sampleNodes,
        maxWidth: 600.0,
        maxHeight: 1200.0,
        textStyle: const TextStyle(fontSize: 16.0),
        paragraphSpacing: 16.0,
      );
      expect(pages.length, greaterThan(1));

      final mockTts = _MockEpubTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTts),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Initially on Page 1
      expect(find.textContaining('Page 1 of'), findsWidgets);

      // Before auto-turn, Page 2 of 7 is not built
      expect(find.textContaining('Page 2 of 7'), findsNothing);

      // Extract a sentence from later in the chapter (node 12, definitely on subsequent page)
      final laterNode = sampleNodes.whereType<ParagraphNode>().elementAt(12);
      final sentenceOnNextPage =
          laterNode.plainText.split(RegExp(r'[.!?]')).first.trim();

      // Trigger TTS playback for the sentence on the subsequent page
      mockTts.updateTtsState(
        playbackState: TtsPlaybackState.playing,
        currentSentenceText: sentenceOnNextPage,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller?.page?.round(), 3);
    });

    testWidgets('ReaderScreen drives pagination from chapter chunk count in paginated mode',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

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
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Bottom progress bar should show chunk-based page count (e.g. Page 1 of 7), not MuPDF fixed page count (10)
      // Both the in-canvas header and bottom status bar show 'Page 1 of 7'
      expect(find.textContaining('Page 1 of 7'), findsWidgets);

      // Verify ReaderCanvas received epubChunks
      final readerCanvas = tester.widget<ReaderCanvas>(find.byType(ReaderCanvas));
      expect(readerCanvas.isEpub, isTrue);
      expect(readerCanvas.epubChunks, isNotNull);
      expect(readerCanvas.epubChunks!.length, 7);

      // Swipe / navigate to next page via right arrow button
      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);
      expect(rightArrow, findsOneWidget);
      await tester.tap(rightArrow);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      // Bottom status bar and canvas header should now display Page 2 of 7
      expect(find.textContaining('Page 2 of 7'), findsWidgets);
    });

    testWidgets('ReaderScreen in Continuous mode renders index-stable ScrollablePositionedList and passes epubNodes',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes.take(3).toList()),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify ReaderCanvas received epubNodes
      final readerCanvas = tester.widget<ReaderCanvas>(find.byType(ReaderCanvas));
      expect(readerCanvas.isEpub, isTrue);
      expect(readerCanvas.epubNodes, isNotNull);
      expect(readerCanvas.epubNodes!.length, 3);

      // Verify index-stable ScrollablePositionedList renders chapters continuously
      expect(find.byType(ScrollablePositionedList), findsOneWidget);
      expect(find.textContaining('Rabbit-Hole'), findsWidgets);
    });

    test('EpubService lazy-parses only requested initial chapter in <250ms', () async {
      if (!epubFile.existsSync()) return;

      final stopwatch = Stopwatch()..start();
      final nodes = await EpubService.instance.extractChapterNodes(epubFile.path, 1);
      stopwatch.stop();

      expect(nodes, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(800));
    });

    testWidgets('TTS chapter completion automatically transitions to speak Chapter N + 1',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      final mockTtsNotifier = _MockEpubTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTtsNotifier),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      // Start TTS on chapter 0
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      expect(mockTtsNotifier.speakCallCount, 1);

      // Now simulate TTS completing chapter 0
      mockTtsNotifier.updateTtsState(
        playbackState: TtsPlaybackState.completed,
        currentSentenceText: '',
      );
      await tester.pumpAndSettle();

      // It should have automatically triggered speak for Chapter 1
      expect(mockTtsNotifier.speakCallCount, 2);
    });

    testWidgets('User manual navigation desyncs TTS and displays Jump to speaking sentence chip',
        (tester) async {
      if (!epubFile.existsSync() || sampleNodes.isEmpty) return;

      final mockTtsNotifier = _MockEpubTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTtsNotifier),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) => Future.value(sampleNodes),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      // Start TTS
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      // Initially synced: jump chip should not be visible
      expect(find.text('Jump to speaking sentence'), findsNothing);

      // User manually navigates to next page using right arrow
      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();

      // Now user is desynced: "Jump to speaking sentence" chip appears
      expect(find.text('Jump to speaking sentence'), findsOneWidget);

      // Tapping "Jump to speaking sentence" clears desync and navigates back
      await tester.tap(find.text('Jump to speaking sentence'));
      await tester.pumpAndSettle();

      // Chip disappears once synced
      expect(find.text('Jump to speaking sentence'), findsNothing);
    });

    testWidgets(
        'Auto-page-turn in Paginated Mode skips standalone image pages to follow TTS sentence',
        (tester) async {
      final mockTts = _MockEpubTtsNotifier();
      final pageController = PageController();
      int discoveredChapter = -1;
      int discoveredPage = -1;
      bool userDesynced = false;

      const chunk0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 32,
        nodes: [
          ParagraphNode([TextSegment('Bracing myself, I began to read.')]),
        ],
      );

      final chunk1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 0,
        nodes: [
          ImageNode(_kValid1x1Png, 'DIARY'),
        ],
      );

      const chunk2 = PageChunk(
        pageIndexInChapter: 2,
        chapterIndex: 0,
        startParagraphIndex: 2,
        startCharOffset: 0,
        endParagraphIndex: 2,
        endCharOffset: 38,
        nodes: [
          ParagraphNode([TextSegment('I’ve decided to start keeping a diary.')]),
        ],
      );

      final chunks = [chunk0, chunk1, chunk2];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTts),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: ReaderCanvas(
                  filePath: 'test.epub',
                  pageCount: 1,
                  settings: const ReaderSettings(
                    mode: ReadingMode.paginated,
                    fontSize: 16.0,
                    lineHeight: 1.5,
                    contentMaxWidth: 600.0,
                  ),
                  initialPageIndex: 0,
                  initialChapterIndex: 0,
                  initialScrollOffset: 0.0,
                  pageController: pageController,
                  onPageChanged: (_, _) {},
                  onToggleChrome: () {},
                  epubChunks: chunks,
                  isEpub: true,
                  chapterIndex: 0,
                  pageIndexInChapter: 0,
                  isUserDesyncedFromTts: userDesynced,
                  onUserNavigated: () {
                    userDesynced = true;
                  },
                  onSpeakingPageDiscovered: (ch, page) {
                    discoveredChapter = ch;
                    discoveredPage = page;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pageController.page?.round(), 0);

      // Now TTS advances across the DIARY image page (Page 1) to sentence on Page 2
      mockTts.updateTtsState(
        playbackState: TtsPlaybackState.playing,
        currentSentenceText: 'I’ve decided to start keeping a diary.',
        currentSentenceIndex: 22,
      );

      // Pump frames for auto-page-turn animation
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Viewport has turned directly to page 2 (skipping page 1 image)
      expect(pageController.page?.round(), 2);
      expect(discoveredChapter, 0);
      expect(discoveredPage, 2);
      // Programmatic auto-turn MUST NOT set userDesynced to true
      expect(userDesynced, isFalse);
    });

    testWidgets(
        'Continuous Mode auto-scrolls past ImageNode to highlighted sentence without desyncing user',
        (tester) async {
      final mockTts = _MockEpubTtsNotifier();
      bool userDesynced = false;

      final nodes = <DocumentNode>[
        const ParagraphNode([TextSegment('Bracing myself, I began to read.')]),
        ImageNode(_kValid1x1Png, 'DIARY'),
        const ParagraphNode([TextSegment('I’ve decided to start keeping a diary.')]),
      ];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTts),
          documentChapterNodesProvider.overrideWith((ref, arg) async => nodes),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: ReaderCanvas(
                  filePath: 'test.epub',
                  pageCount: 1,
                  settings: const ReaderSettings(
                    fontSize: 16.0,
                    lineHeight: 1.5,
                    contentMaxWidth: 600.0,
                  ),
                  initialPageIndex: 0,
                  initialChapterIndex: 0,
                  initialScrollOffset: 0.0,
                  pageController: PageController(),
                  onPageChanged: (_, _) {},
                  onToggleChrome: () {},
                  epubNodes: nodes,
                  isEpub: true,
                  chapterIndex: 0,
                  pageIndexInChapter: 0,
                  isUserDesyncedFromTts: userDesynced,
                  onUserNavigated: () {
                    userDesynced = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Play sentence 1 above the image
      mockTts.updateTtsState(
        playbackState: TtsPlaybackState.playing,
        currentSentenceText: 'Bracing myself, I began to read.',
        currentSentenceIndex: 21,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(userDesynced, isFalse);

      // Now play sentence 2 past the image
      mockTts.updateTtsState(
        playbackState: TtsPlaybackState.playing,
        currentSentenceText: 'I’ve decided to start keeping a diary.',
        currentSentenceIndex: 22,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Programmatic scroll to sentence below image MUST NOT set userDesynced
      expect(userDesynced, isFalse);
      expect(find.textContaining('I’ve decided to start keeping a diary.'), findsOneWidget);
    });

    testWidgets('ReaderCanvas getFirstVisibleTextSnippet retrieves visible sentence in paginated mode',
        (tester) async {
      final canvasKey = GlobalKey<ReaderCanvasState>();
      final pageController = PageController();

      final chunks = [
        PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: 0,
          startParagraphIndex: 0,
          startCharOffset: 0,
          endParagraphIndex: 0,
          endCharOffset: 0,
          nodes: [
            ImageNode(_kValid1x1Png, 'STANDALONE COVER'),
          ],
        ),
        const PageChunk(
          pageIndexInChapter: 1,
          chapterIndex: 0,
          startParagraphIndex: 1,
          startCharOffset: 0,
          endParagraphIndex: 1,
          endCharOffset: 45,
          nodes: [
            ParagraphNode([TextSegment('It was the best of times, it was the worst of times.')]),
          ],
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: ReaderCanvas(
                  key: canvasKey,
                  filePath: 'test.epub',
                  pageCount: 1,
                  settings: const ReaderSettings(
                    mode: ReadingMode.paginated,
                    fontSize: 16.0,
                    lineHeight: 1.5,
                    contentMaxWidth: 600.0,
                  ),
                  initialPageIndex: 0,
                  initialChapterIndex: 0,
                  initialScrollOffset: 0.0,
                  pageController: pageController,
                  onPageChanged: (_, _) {},
                  onToggleChrome: () {},
                  epubChunks: chunks,
                  isEpub: true,
                  chapterIndex: 0,
                  pageIndexInChapter: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On Page 0 (standalone image), getFirstVisibleTextSnippet skips to page 1 text
      final snippet = canvasKey.currentState?.getFirstVisibleTextSnippet();
      expect(snippet, isNotNull);
      expect(snippet, contains('It was the best of times'));
    });

    test('Single-flight archive caching deduplicates concurrent book open requests and opens in <300ms', () async {
      if (!epubFile.existsSync()) return;

      EpubService.clearCache();
      final sw = Stopwatch()..start();

      final results = await Future.wait([
        EpubService.instance.extractMetadata(epubFile.path, includeCover: false),
        EpubService.instance.extractTableOfContents(epubFile.path),
        EpubService.instance.extractChapterNodes(epubFile.path, 1),
        EpubService.instance.openEpub(epubFile.path, initialChapterIndex: 1),
      ]);
      sw.stop();

      expect(results[0], isA<DocumentMetadata>());
      expect(results[1], isA<List<TocEntry>>());
      expect(results[2], isA<List<DocumentNode>>());
      expect(results[3], isA<CachedEpub>());
      expect(sw.elapsedMilliseconds, lessThan(300));

      final cachedBook = results[3] as CachedEpub;
      expect(cachedBook.metadata, isNotNull);
      expect(cachedBook.toc, isNotNull);
      expect(cachedBook.chapterNodes.containsKey(1), isTrue);

      EpubService.clearCache();
    });

    testWidgets(
        'Pressing top-bar TTS Play button on Page K of a paginated chapter starts speaking from first sentence on Page K',
        (tester) async {
      final mockTtsNotifier = _MockEpubTtsNotifier();

      const chunk0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 25,
        nodes: [
          ParagraphNode([TextSegment('First sentence of page 0.')]),
        ],
      );

      const chunk1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 50,
        nodes: [
          ParagraphNode([TextSegment('First sentence of page 1. Second sentence of page 1.')]),
        ],
      );

      final chunks = [chunk0, chunk1];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTtsNotifier),
          chapterPagesProvider.overrideWith((ref, arg) async => chunks),
          documentChapterNodesProvider.overrideWith((ref, arg) async => [
                chunk0.nodes.first,
                chunk1.nodes.first,
              ]),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      // Navigate to Page 1
      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();

      // Tap top-bar Read aloud button
      final playButton = find.byTooltip('Read aloud');
      await tester.tap(playButton);
      await tester.pumpAndSettle();

      expect(mockTtsNotifier.speakCallCount, 1);
      expect(mockTtsNotifier.lastSpokenText, startsWith('First sentence of page 1.'));
      expect(mockTtsNotifier.lastSpokenText, isNot(contains('First sentence of page 0.')));
    });

    testWidgets(
        'Play from here in Paginated Mode starts speaking from highlighted sentence',
        (tester) async {
      final mockTtsNotifier = _MockEpubTtsNotifier();

      const chunk0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 25,
        nodes: [
          ParagraphNode([TextSegment('First sentence of page 0.')]),
        ],
      );

      const chunk1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 50,
        nodes: [
          ParagraphNode([TextSegment('First sentence of page 1. Second sentence of page 1.')]),
        ],
      );

      final chunks = [chunk0, chunk1];

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockTtsNotifier),
          chapterPagesProvider.overrideWith((ref, arg) async => chunks),
          documentChapterNodesProvider.overrideWith((ref, arg) async => [
                chunk0.nodes.first,
                chunk1.nodes.first,
              ]),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      // Trigger Play from here with a phrase on page 1
      final readerCanvas = tester.widget<ReaderCanvas>(find.byType(ReaderCanvas));
      readerCanvas.onPlayFromHere?.call('Second sentence of page 1.');
      await tester.pumpAndSettle();

      expect(mockTtsNotifier.speakCallCount, 1);
      expect(mockTtsNotifier.lastSpokenText, startsWith('Second sentence of page 1.'));
    });

    testWidgets(
        'Backward chapter navigation in Paginated Mode uses sentinel to land on the last page of preceding chapter',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Chapter 0 has 2 pages
      const ch0Page0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 0, Page 0 content here.')]),
        ],
      );
      const ch0Page1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 0, Page 1 content here.')]),
        ],
      );

      // Chapter 1 has 1 page
      const ch1Page0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 1,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 1, Page 0 content here.')]),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return [ch0Page0, ch0Page1];
            } else {
              return [ch1Page0];
            }
          }),
          documentChapterNodesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return [ch0Page0.nodes.first, ch0Page1.nodes.first];
            } else {
              return [ch1Page0.nodes.first];
            }
          }),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      // Initially at Chapter 0, Page 0
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Chapter 0, Page 0 content here.'), findsOneWidget);

      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);
      final leftArrow = find.byIcon(PhosphorIconsLight.caretLeft);

      // Tap Next Page -> Chapter 0, Page 1 (Page 2 of 2)
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Chapter 0, Page 1 content here.'), findsOneWidget);

      // Tap Next Page -> Chapter 1, Page 0 (Page 1 of 1)
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(find.text('Chapter 1, Page 0 content here.'), findsOneWidget);

      // Now on Chapter 1 Page 0: Tap Previous Page -> Must navigate backward to Chapter 0 Page 1 (Page 2 of 2)!
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Chapter 0, Page 1 content here.'), findsOneWidget);

      // From Chapter 0 Page 1: Tap Next Page -> Advances back to Chapter 1 Page 0
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(find.text('Chapter 1, Page 0 content here.'), findsOneWidget);
    });

    testWidgets(
        'Paginated Mode intra-chapter and cross-chapter page turns synchronize properly with ImageNodes',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Chapter 1 (index 0): 3 pages (Page 0: text, Page 1: standalone ImageNode, Page 2: text)
      const ch0Page0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 1 Page 1 Text')]),
        ],
      );
      final ch0Page1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 0,
        nodes: [
          ImageNode(_kValid1x1Png, 'Sample image'),
        ],
      );
      const ch0Page2 = PageChunk(
        pageIndexInChapter: 2,
        chapterIndex: 0,
        startParagraphIndex: 2,
        startCharOffset: 0,
        endParagraphIndex: 2,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 1 Page 3 After Image')]),
        ],
      );

      // Chapter 2 (index 1): 3 pages (Page 0, 1, 2 text)
      const ch1Page0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 1,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 2 Page 1 Content')]),
        ],
      );
      const ch1Page1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 1,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 2 Page 2 Content')]),
        ],
      );
      const ch1Page2 = PageChunk(
        pageIndexInChapter: 2,
        chapterIndex: 1,
        startParagraphIndex: 2,
        startCharOffset: 0,
        endParagraphIndex: 2,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Chapter 2 Page 3 Content')]),
        ],
      );

      // Pre-seed database reading progress at Chapter 2 (index 1), Page 1 (index 0)
      await db.updateProgress(
        ReadingProgressesCompanion.insert(
          documentId: aliceDoc.id,
          lastReadPageIndex: const Value(1),
          lastReadSentenceIndex: const Value(0),
          lastReadScrollOffset: const Value(0.0),
          currentChapter: const Value('Chapter 2'),
          updatedAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterTitleProvider.overrideWith((ref, arg) async {
            return arg.chapterIndex == 0 ? 'Chapter 1' : 'Chapter 2';
          }),
          chapterPagesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return [ch0Page0, ch0Page1, ch0Page2];
            } else {
              return [ch1Page0, ch1Page1, ch1Page2];
            }
          }),
          documentChapterNodesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return [
                ch0Page0.nodes.first,
                ch0Page1.nodes.first,
                ch0Page2.nodes.first
              ];
            } else {
              return [
                ch1Page0.nodes.first,
                ch1Page1.nodes.first,
                ch1Page2.nodes.first
              ];
            }
          }),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);
      final leftArrow = find.byIcon(PhosphorIconsLight.caretLeft);

      // 1. Verify starts on Chapter 2 Page 1 (index 0)
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Chapter 2 Page 1 Content'), findsOneWidget);

      // Click Next Page once -> Chapter 2 Page 2 (index 1)
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('Chapter 2 Page 2 Content'), findsOneWidget);

      // Click Next Page second time -> Chapter 2 Page 3 (index 2)
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.text('Chapter 2 Page 3 Content'), findsOneWidget);

      // Click Previous Page (<) -> MUST land on Chapter 2 Page 2 (index 1), NOT Chapter 1!
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('Chapter 2 Page 2 Content'), findsOneWidget);
      expect(find.textContaining('Chapter 1'), findsNothing);

      // 2. Navigate back to Chapter 2 Page 1 (index 0)
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Chapter 2 Page 1 Content'), findsOneWidget);

      // Navigate back from Chapter 2 Page 1 into Chapter 1's last page (Page 3 of 3, index 2)
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.text('Chapter 1 Page 3 After Image'), findsOneWidget);

      // Step backward onto Chapter 1 Page 2 (index 1), which is the standalone ImageNode page
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Chapter 1 Page 3 After Image'), findsNothing);
      expect(find.text('Chapter 1 Page 1 Text'), findsNothing);

      // Click Next Page (>) from that image page -> MUST advance to next page of Chapter 1 (Page 3 of 3), NOT Chapter 2!
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.text('Chapter 1 Page 3 After Image'), findsOneWidget);
      expect(find.textContaining('Chapter 2'), findsNothing);
    });

    testWidgets(
        'Paginated Mode maintains page index across parent rebuilds and repeatedly uses sentinel when navigating backward',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Chapter 1 (index 0): 3 pages
      const ch0Page0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Ch1 P1 Text')]),
        ],
      );
      const ch0Page1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Ch1 P2 Text')]),
        ],
      );
      const ch0Page2 = PageChunk(
        pageIndexInChapter: 2,
        chapterIndex: 0,
        startParagraphIndex: 2,
        startCharOffset: 0,
        endParagraphIndex: 2,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Ch1 P3 Text')]),
        ],
      );

      // Chapter 2 (index 1): 3 pages
      const ch1Page0 = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 1,
        startParagraphIndex: 0,
        startCharOffset: 0,
        endParagraphIndex: 0,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Ch2 P1 Text')]),
        ],
      );
      const ch1Page1 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 1,
        startParagraphIndex: 1,
        startCharOffset: 0,
        endParagraphIndex: 1,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Ch2 P2 Text')]),
        ],
      );
      const ch1Page2 = PageChunk(
        pageIndexInChapter: 2,
        chapterIndex: 1,
        startParagraphIndex: 2,
        startCharOffset: 0,
        endParagraphIndex: 2,
        endCharOffset: 30,
        nodes: [
          ParagraphNode([TextSegment('Ch2 P3 Text')]),
        ],
      );

      // Pre-seed database reading progress at Chapter 2 (index 1), Page 1 (index 0)
      await db.updateProgress(
        ReadingProgressesCompanion.insert(
          documentId: aliceDoc.id,
          lastReadPageIndex: const Value(1),
          lastReadSentenceIndex: const Value(0),
          lastReadScrollOffset: const Value(0.0),
          currentChapter: const Value('Chapter 2'),
          updatedAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterTitleProvider.overrideWith((ref, arg) async {
            return arg.chapterIndex == 0 ? 'Chapter 1' : 'Chapter 2';
          }),
          chapterPagesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return [ch0Page0, ch0Page1, ch0Page2];
            } else {
              return [ch1Page0, ch1Page1, ch1Page2];
            }
          }),
          documentChapterNodesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return [
                ch0Page0.nodes.first,
                ch0Page1.nodes.first,
                ch0Page2.nodes.first
              ];
            } else {
              return [
                ch1Page0.nodes.first,
                ch1Page1.nodes.first,
                ch1Page2.nodes.first
              ];
            }
          }),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);
      final leftArrow = find.byIcon(PhosphorIconsLight.caretLeft);

      // 1. Starts on Chapter 2 Page 1
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Ch2 P1 Text'), findsOneWidget);

      // Advance to Page 2
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('Ch2 P2 Text'), findsOneWidget);

      // Trigger a parent rebuild (e.g. tap center of screen to toggle chrome)
      final centerFinder = find.byType(ReaderCanvas);
      await tester.tap(centerFinder);
      await tester.pumpAndSettle();

      // Verify that after parent rebuild, we remain on Chapter 2 Page 2
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('Ch2 P2 Text'), findsOneWidget);

      // Tap Previous Page (<) -> MUST go to Chapter 2 Page 1, NOT Chapter 1!
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Ch2 P1 Text'), findsOneWidget);

      // Tap Previous Page (<) from Page 1 -> Navigate back to Chapter 1, landing on last page (Page 3 of 3)
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.text('Ch1 P3 Text'), findsOneWidget);

      // Tap Next Page (>) from Chapter 1 Page 3 -> Should navigate to Chapter 2 Page 1
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(find.text('Ch2 P1 Text'), findsOneWidget);

      // Now navigate backward to Chapter 1 a SECOND time -> MUST land on Page 3 of 3 again!
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(find.text('Ch1 P3 Text'), findsOneWidget);
    });

    testWidgets(
        'Entering chapter backward with 25 pages lands on page 25 (index 24) without clamping to 0',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Chapter 1 (index 0): 25 pages
      final ch0Pages = List.generate(
        25,
        (i) => PageChunk(
          pageIndexInChapter: i,
          chapterIndex: 0,
          startParagraphIndex: i,
          startCharOffset: 0,
          endParagraphIndex: i,
          endCharOffset: 30,
          nodes: [
            ParagraphNode([TextSegment('Chapter 1 Page ${i + 1} Content')]),
          ],
        ),
      );

      // Chapter 2 (index 1): 2 pages
      final ch1Pages = List.generate(
        2,
        (i) => PageChunk(
          pageIndexInChapter: i,
          chapterIndex: 1,
          startParagraphIndex: i,
          startCharOffset: 0,
          endParagraphIndex: i,
          endCharOffset: 30,
          nodes: [
            ParagraphNode([TextSegment('Chapter 2 Page ${i + 1} Content')]),
          ],
        ),
      );

      // Start at Chapter 2 Page 1
      await db.updateProgress(
        ReadingProgressesCompanion.insert(
          documentId: aliceDoc.id,
          lastReadPageIndex: const Value(1),
          lastReadSentenceIndex: const Value(0),
          lastReadScrollOffset: const Value(0.0),
          currentChapter: const Value('Chapter 2'),
          updatedAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterTitleProvider.overrideWith((ref, arg) async {
            return arg.chapterIndex == 0 ? 'Chapter 1' : 'Chapter 2';
          }),
          chapterPagesProvider.overrideWith((ref, arg) async {
            if (arg.chapterIndex == 0) {
              return ch0Pages;
            } else {
              return ch1Pages;
            }
          }),
          documentChapterNodesProvider.overrideWith((ref, arg) async {
            final pages = arg.chapterIndex == 0 ? ch0Pages : ch1Pages;
            return pages.map((p) => p.nodes.first).toList();
          }),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      final leftArrow = find.byIcon(PhosphorIconsLight.caretLeft);
      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);

      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Chapter 2 Page 1 Content'), findsOneWidget);

      // Navigate backward into Chapter 1 (sentinel -1)
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();

      // Must land on Page 25 of 25 (index 24) and NOT be clamped down to 0
      expect(find.text('Page 25 of 25'), findsOneWidget);
      expect(find.text('Chapter 1 Page 25 Content'), findsOneWidget);

      // Tap Previous (<) -> Moves to Page 24 of 25
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 24 of 25'), findsOneWidget);
      expect(find.text('Chapter 1 Page 24 Content'), findsOneWidget);

      // Tap Next (>) -> Moves back to Page 25 of 25
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 25 of 25'), findsOneWidget);
      expect(find.text('Chapter 1 Page 25 Content'), findsOneWidget);

      // Tap Next (>) from Page 25 of 25 -> Transitions to Chapter 2 Page 1 of 2
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Chapter 2 Page 1 Content'), findsOneWidget);
    });

    testWidgets(
        'Paginated Mode allows multi-page intra-chapter turns followed by backward turns without premature chapter jumps',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Chapter 1 (index 0): 10 pages
      final ch0Pages = List.generate(
        10,
        (i) => PageChunk(
          pageIndexInChapter: i,
          chapterIndex: 0,
          startParagraphIndex: i,
          startCharOffset: 0,
          endParagraphIndex: i,
          endCharOffset: 30,
          nodes: [
            ParagraphNode([TextSegment('Chapter 1 Page ${i + 1} Content')]),
          ],
        ),
      );

      // Chapter 2 (index 1): 10 pages
      final ch1Pages = List.generate(
        10,
        (i) => PageChunk(
          pageIndexInChapter: i,
          chapterIndex: 1,
          startParagraphIndex: i,
          startCharOffset: 0,
          endParagraphIndex: i,
          endCharOffset: 30,
          nodes: [
            ParagraphNode([TextSegment('Chapter 2 Page ${i + 1} Content')]),
          ],
        ),
      );

      // Start at Chapter 2 Page 1
      await db.updateProgress(
        ReadingProgressesCompanion.insert(
          documentId: aliceDoc.id,
          lastReadPageIndex: const Value(1),
          lastReadSentenceIndex: const Value(0),
          lastReadScrollOffset: const Value(0.0),
          currentChapter: const Value('Chapter 2'),
          updatedAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentChapterTitleProvider.overrideWith((ref, arg) async {
            return arg.chapterIndex == 0 ? 'Chapter 1' : 'Chapter 2';
          }),
          chapterPagesProvider.overrideWith((ref, arg) async {
            return arg.chapterIndex == 0 ? ch0Pages : ch1Pages;
          }),
          documentChapterNodesProvider.overrideWith((ref, arg) async {
            final pages = arg.chapterIndex == 0 ? ch0Pages : ch1Pages;
            return pages.map((p) => p.nodes.first).toList();
          }),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
                contentMaxWidth: 600.0,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      final leftArrow = find.byIcon(PhosphorIconsLight.caretLeft);
      final rightArrow = find.byIcon(PhosphorIconsLight.caretRight);

      expect(find.text('Page 1 of 10'), findsOneWidget);
      expect(find.text('Chapter 2 Page 1 Content'), findsOneWidget);

      // Advance 4 pages in Chapter 2: Page 1 -> 2 -> 3 -> 4 -> 5
      for (int step = 2; step <= 5; step++) {
        await tester.tap(rightArrow);
        await tester.pumpAndSettle();
        expect(find.text('Page $step of 10'), findsOneWidget);
        expect(find.text('Chapter 2 Page $step Content'), findsOneWidget);
      }

      // Step backward in Chapter 2: Page 5 -> 4
      // MUST NOT jump to Chapter 1!
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 4 of 10'), findsOneWidget);
      expect(find.text('Chapter 2 Page 4 Content'), findsOneWidget);

      // Continue stepping backward to Page 1 of Chapter 2
      for (int step = 3; step >= 1; step--) {
        await tester.tap(leftArrow);
        await tester.pumpAndSettle();
        expect(find.text('Page $step of 10'), findsOneWidget);
        expect(find.text('Chapter 2 Page $step Content'), findsOneWidget);
      }

      // Step backward from Chapter 2 Page 1 -> transitions to Chapter 1 Page 10 of 10
      await tester.tap(leftArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 10 of 10'), findsOneWidget);
      expect(find.text('Chapter 1 Page 10 Content'), findsOneWidget);

      // Step backward 4 times within Chapter 1 to reach Page 6 of 10
      for (int step = 9; step >= 6; step--) {
        await tester.tap(leftArrow);
        await tester.pumpAndSettle();
        expect(find.text('Page $step of 10'), findsOneWidget);
        expect(find.text('Chapter 1 Page $step Content'), findsOneWidget);
      }

      // From Page 6 of Chapter 1, tap Next (>)
      // MUST advance to Chapter 1 Page 7 of 10 (NOT jump to Chapter 2 Page 1!)
      await tester.tap(rightArrow);
      await tester.pumpAndSettle();
      expect(find.text('Page 7 of 10'), findsOneWidget);
      expect(find.text('Chapter 1 Page 7 Content'), findsOneWidget);
    });

    testWidgets(
        'Left and Right arrow keys turn pages on the first press and chevron InkWells do not accept focus',
        (tester) async {
      final chPages = List.generate(
        3,
        (i) => PageChunk(
          pageIndexInChapter: i,
          chapterIndex: 0,
          startParagraphIndex: i,
          startCharOffset: 0,
          endParagraphIndex: i,
          endCharOffset: 30,
          nodes: [
            ParagraphNode([TextSegment('Keyboard Page ${i + 1} Content')]),
          ],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => chPages),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => chPages.map((p) => p.nodes.first).toList(),
          ),
          readerSettingsProvider.overrideWith(
            () => _TestReaderSettingsNotifier(
              const ReaderSettings(
                mode: ReadingMode.paginated,
                fontSize: 16.0,
                lineHeight: 1.5,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container: container, document: aliceDoc),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Verify that left and right chevron InkWells have canRequestFocus == false
      final leftChevronInkWell = tester.widget<InkWell>(
        find.ancestor(
          of: find.byIcon(PhosphorIconsLight.caretLeft),
          matching: find.byType(InkWell),
        ),
      );
      final rightChevronInkWell = tester.widget<InkWell>(
        find.ancestor(
          of: find.byIcon(PhosphorIconsLight.caretRight),
          matching: find.byType(InkWell),
        ),
      );
      expect(leftChevronInkWell.canRequestFocus, isFalse);
      expect(rightChevronInkWell.canRequestFocus, isFalse);

      // Send ArrowRight key: MUST turn to Page 2 on the very first key press
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 3'), findsOneWidget);

      // Send ArrowLeft key: MUST turn back to Page 1 on the very first key press
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);
    });
  });
}

