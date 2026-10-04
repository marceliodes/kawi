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
import 'package:kawi/features/reader/services/chapter_paginator.dart';
import 'package:kawi/features/reader/services/epub_service.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

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
  }) {
    state = state.copyWith(
      playbackState: playbackState,
      currentSentenceText: currentSentenceText,
      currentWord: currentWord,
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

    testWidgets('ReaderCanvas renders Continuous mode with ListView of nodes',
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

      // In continuous mode, ListView should be rendered
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
      // Next Chapter button should be present at the bottom of the list
      expect(find.text('Next Chapter'), findsOneWidget);
    });

    testWidgets('TTS highlighting renders active sentence and word spans',
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
      expect(hasWordHighlight, isTrue);
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

      // Tap Read Aloud (TTS)
      final ttsButton = find.byTooltip('Read Aloud (TTS)');
      expect(ttsButton, findsOneWidget);
      await tester.tap(ttsButton);
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

    testWidgets('ReaderScreen in Continuous mode passes epubNodes and handles Next Chapter',
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

      // Tap Next Chapter button
      final nextChapterBtn = find.text('Next Chapter');
      expect(nextChapterBtn, findsOneWidget);
      await tester.tap(nextChapterBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Document progress should advance to chapter 1
      final updatedCanvas = tester.widget<ReaderCanvas>(find.byType(ReaderCanvas));
      expect(updatedCanvas.chapterIndex, 1);
    });
  });
}

