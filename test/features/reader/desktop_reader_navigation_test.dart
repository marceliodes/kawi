import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
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
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';

class MockTtsNotifier extends TtsStateNotifier {
  MockTtsNotifier(this._initial);
  final TtsState _initial;

  bool playCalled = false;
  bool pauseCalled = false;
  bool stopCalled = false;
  bool nextCalled = false;
  bool prevCalled = false;
  bool seekCalled = false;
  int? seekSentenceIndex;

  @override
  TtsState build() => _initial;

  @override
  void speak(String text, {int startSentenceIndex = 0}) {
    playCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.playing);
  }

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

  @override
  void stop() {
    stopCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.stopped);
  }

  @override
  void nextSentence() {
    nextCalled = true;
    if (state.currentSentenceIndex + 1 < state.totalSentences) {
      state = state.copyWith(currentSentenceIndex: state.currentSentenceIndex + 1);
    }
  }

  @override
  void previousSentence() {
    prevCalled = true;
    if (state.currentSentenceIndex > 0) {
      state = state.copyWith(currentSentenceIndex: state.currentSentenceIndex - 1);
    }
  }

  @override
  void seekSentence(int index) {
    seekCalled = true;
    seekSentenceIndex = index;
    state = state.copyWith(
      currentSentenceIndex: index.clamp(0, state.totalSentences > 0 ? state.totalSentences - 1 : 0),
      activeWordStart: 0,
      activeWordEnd: 0,
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

class _TestReaderSettingsNotifier extends ReaderSettingsNotifier {
  _TestReaderSettingsNotifier(this._initial);
  final ReaderSettings _initial;
  @override
  ReaderSettings build() => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentEntry testEpubDoc;
  late DocumentEntry testPdfDoc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testEpubDoc = DocumentEntry(
      id: 'doc-epub-1',
      title: 'Alice in Wonderland',
      author: 'Lewis Carroll',
      filePath: File('test_assets/alice.epub').absolute.path,
      format: 'epub',
      pageCount: 3,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: 4096,
    );
    testPdfDoc = DocumentEntry(
      id: 'doc-pdf-1',
      title: 'Sample PDF',
      author: 'Author',
      filePath: File('test_assets/sample.pdf').absolute.path,
      format: 'pdf',
      pageCount: 5,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: 8192,
    );
  });

  tearDown(() async {
    await db.close();
  });

  final epubChunks = List.generate(
    3,
    (i) => PageChunk(
      pageIndexInChapter: i,
      chapterIndex: 0,
      startParagraphIndex: i,
      startCharOffset: 0,
      endParagraphIndex: i,
      endCharOffset: 30,
      nodes: [
        ParagraphNode([TextSegment('EPUB Page ${i + 1} content text.')]),
      ],
    ),
  );

  PageContent mockPdfPageContent(int pageIndex) {
    return PageContent(
      pageIndex: pageIndex,
      plainText: 'PDF Page ${pageIndex + 1} content line.',
      words: const [],
    );
  }

  group('TTS Desktop Keyboard Shortcuts', () {
    testWidgets('Ctrl + Space and media keys toggle TTS playback state', (tester) async {
      final mockNotifier = MockTtsNotifier(
        const TtsState(
          totalSentences: 3,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockNotifier),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(mockNotifier.state.isPlaying, isFalse);

      // Press Ctrl + Space: Should toggle/play TTS
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.playCalled, isTrue);
      expect(mockNotifier.state.isPlaying, isTrue);

      // Press Ctrl + Space again: Should pause TTS
      mockNotifier.playCalled = false;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.pauseCalled, isTrue);
      expect(mockNotifier.state.isPaused, isTrue);

      // Press mediaPlayPause: Should toggle/play TTS
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();

      expect(mockNotifier.playCalled, isTrue);
      expect(mockNotifier.state.isPlaying, isTrue);

      // Press mediaPause: Should pause TTS
      mockNotifier.pauseCalled = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pumpAndSettle();

      expect(mockNotifier.pauseCalled, isTrue);

      // Press mediaPlay: Should play TTS
      mockNotifier.playCalled = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pumpAndSettle();

      expect(mockNotifier.playCalled, isTrue);
    });

    testWidgets('Alt + Arrow keys skip forward and backward in TTS segments', (tester) async {
      final mockNotifier = MockTtsNotifier(
        const TtsState(
          playbackState: TtsPlaybackState.playing,
          totalSentences: 3,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockNotifier),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(mockNotifier.state.currentSentenceIndex, 0);

      // Press Alt + Right Arrow: advance TTS to next sentence
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.nextCalled, isTrue);
      expect(mockNotifier.state.currentSentenceIndex, 1);

      // Press Alt + Right Arrow again: advance to sentence 2
      mockNotifier.nextCalled = false;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.nextCalled, isTrue);
      expect(mockNotifier.state.currentSentenceIndex, 2);

      // Press Alt + Left Arrow: rewind TTS to sentence 1
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.prevCalled, isTrue);
      expect(mockNotifier.state.currentSentenceIndex, 1);

      // Simulate sentence 1 underway (active word offset > 0)
      mockNotifier.state = mockNotifier.state.copyWith(activeWordStart: 5, activeWordEnd: 10);
      mockNotifier.prevCalled = false;
      mockNotifier.seekCalled = false;

      // Press Alt + Left Arrow while underway: rewinds to beginning of current sentence (sentence 1)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.seekCalled, isTrue);
      expect(mockNotifier.seekSentenceIndex, 1);
      expect(mockNotifier.state.currentSentenceIndex, 1);

      // Now with sentence 1 NOT underway, press Alt + Left Arrow: rewinds to previous sentence (sentence 0)
      mockNotifier.prevCalled = false;
      mockNotifier.seekCalled = false;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.prevCalled, isTrue);
      expect(mockNotifier.state.currentSentenceIndex, 0);
    });

    testWidgets('Space navigates forward and Shift + Space navigates backward with page turn animation', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Press plain Space: animates to Page 2
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 3'), findsOneWidget);

      // Press Shift + Space: animates back to Page 1
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('Standard Left and Right arrow keys without Alt turn pages without TTS interference', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Press Right Arrow without Alt: turns page forward to Page 2
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 3'), findsOneWidget);

      // Press Left Arrow without Alt: turns page back to Page 1
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('Shortcuts work reliably regardless of which child widget holds focus', (tester) async {
      final mockNotifier = MockTtsNotifier(
        const TtsState(
          totalSentences: 3,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockNotifier),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      // Explicitly focus a different child widget (e.g. top bar button)
      final settingsButton = find.byTooltip('Reader Settings');
      expect(settingsButton, findsOneWidget);
      Focus.of(tester.element(settingsButton)).requestFocus();
      await tester.pump();

      // Press Right Arrow: Should turn page forward to Page 2 via reader shortcuts
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 3'), findsOneWidget);

      // Press Ctrl + Space: Should toggle TTS playback even while that focus node is active
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(mockNotifier.playCalled, isTrue);
    });
  });

  group('Trackpad / Touchpad Horizontal Swipe Navigation', () {
    testWidgets('Swipe left (dx > 0) navigates to next page and swipe right (dx < 0) navigates to previous page in EPUB', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);

      final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

      // Small swipe (< 50px threshold): should NOT trigger page turn
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(30.0, 0.0),
        ),
      );
      await tester.pump();
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Accumulate remaining delta to reach threshold (30 + 25 = 55 >= 50)
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(25.0, 0.0),
        ),
      );
      // Allow the 200ms smooth page turn animation to reach completion and settle (total 250ms < 380ms)
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('Page 2 of 3'), findsOneWidget);

      // Immediately send inertial fling events within cooldown (at t~250ms < 380ms cooldown)
      // Must absorb them and NOT turn another page!
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(60.0, 0.0),
        ),
      );
      await tester.pump();
      expect(find.text('Page 2 of 3'), findsOneWidget);

      // Wait remaining time for cooldown (380ms) to elapse (total > 400ms)
      await tester.pump(const Duration(milliseconds: 200));

      // Now swipe right (dx < 0) exceeding 50px threshold to navigate back to Page 1
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(-55.0, 0.0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('Swipe direction change clears accumulated delta', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);
      final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

      // Swipe +40px left (towards next page)
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(40.0, 0.0),
        ),
      );
      await tester.pump();
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Reverse direction: swipe -20px right.
      // This MUST clear the +40px accumulated delta, setting delta to -20px.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(-20.0, 0.0),
        ),
      );
      await tester.pump();
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Now send +20px left again: accumulated delta should be +20px, not 40+20.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(20.0, 0.0),
        ),
      );
      await tester.pumpAndSettle();
      // Still Page 1 because accumulated is only +20px (< 50px)
      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('Pointer lift (PointerUpEvent) clears accumulated delta', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

      // Swipe +40px left
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(40.0, 0.0),
        ),
      );
      await tester.pump();

      // Lift pointer (pointer down then up to simulate pointer tap/release)
      await tester.sendEventToBinding(
        PointerDownEvent(position: canvasCenter),
      );
      await tester.sendEventToBinding(
        PointerUpEvent(position: canvasCenter),
      );
      await tester.pump();

      // Now send +20px: should NOT reach 50px since previous 40px was cleared
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(20.0, 0.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('PointerPanZoomUpdateEvent navigates pages with momentum latch', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          chapterPagesProvider.overrideWith((ref, arg) async => epubChunks),
          documentChapterNodesProvider.overrideWith(
            (ref, arg) async => epubChunks.map((p) => p.nodes.first).toList(),
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
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

      // Pan left (panDelta.dx < 0, equivalent to scrollDelta.dx > 0)
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: canvasCenter),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: canvasCenter,
          panDelta: const Offset(-55.0, 0.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Page 2 of 3'), findsOneWidget);

      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: canvasCenter),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('Touchpad horizontal swipe works in paginated PDF reader mode', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentPageContentProvider.overrideWith(
            (ref, arg) => Future.value(mockPdfPageContent(arg.pageIndex)),
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
        _createTestApp(container: container, document: testPdfDoc),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('PDF Page 1 content line.'), findsOneWidget);
      final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

      // Swipe left (dx > 0) with >= 50px threshold
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(60.0, 0.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('PDF Page 2 content line.'), findsOneWidget);

      // Wait for cooldown (380ms)
      await tester.pump(const Duration(milliseconds: 400));

      // Swipe right (dx < 0) with <= -50px threshold
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvasCenter,
          scrollDelta: const Offset(-60.0, 0.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('PDF Page 1 content line.'), findsOneWidget);
    });
  });
}
