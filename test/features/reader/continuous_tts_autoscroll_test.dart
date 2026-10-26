import 'dart:io';

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
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class _TestTtsNotifier extends TtsStateNotifier {
  _TestTtsNotifier(this._initial);
  final TtsState _initial;

  @override
  TtsState build() => _initial;

  void setPlayingSentence(String text, int index) {
    state = state.copyWith(
      playbackState: TtsPlaybackState.playing,
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

  // 30 substantial paragraphs to provide sufficient vertical scroll extent (>3000px)
  final List<DocumentNode> sampleNodes = [
    const HeadingNode(1, [TextSegment('Chapter 1: The Long Journey')]),
    for (var i = 1; i <= 30; i++)
      ParagraphNode([
        TextSegment(
          'Paragraph $i is a substantial paragraph of text designed to take multiple lines '
          'and simulate realistic prose inside an EPUB continuous scroll reader. '
          'It provides enough height so that advancing sentences down the chapter moves '
          'past the dead-zone threshold and exercises smooth auto-scrolling.',
        ),
      ]),
  ];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testEpubDoc = DocumentEntry(
      id: 'doc-epub-continuous-test',
      title: 'Continuous Scroll TTS Test EPUB',
      author: 'Author',
      filePath: File('test_assets/alice.epub').absolute.path,
      format: 'epub',
      pageCount: 1,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: 4096,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Continuous Scroll Mode TTS Audio Following (Auto-Scroll) Tests', () {
    testWidgets(
        'Sentence in dead zone (top 15%-60%) does not trigger jittery micro-scrolls',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
          .setReadingMode(ReadingMode.continuous);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ScrollablePositionedList), findsOneWidget);

      final scrollableFinder = find.byType(Scrollable).first;
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      expect(scrollableState.position.pixels, 0.0);

      // Play on Paragraph 1 (near top, within 15%-60% dead zone)
      final p1Text = sampleNodes[1].toPlainText();
      ttsNotifier.setPlayingSentence(p1Text, 1);
      await tester.pumpAndSettle();

      // Scroll position must remain at 0.0 without jitter
      expect(scrollableState.position.pixels, 0.0);

      // Advance to Paragraph 2 (still within dead zone near top)
      final p2Text = sampleNodes[2].toPlainText();
      ttsNotifier.setPlayingSentence(p2Text, 2);
      await tester.pumpAndSettle();

      // Still no micro-scroll
      expect(scrollableState.position.pixels, 0.0);
    });

    testWidgets(
        'Advancing TTS past lower threshold (>60% of viewport) smoothly auto-scrolls to upper-middle third (30%-40%)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
          .setReadingMode(ReadingMode.continuous);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(Scrollable).first;
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      expect(scrollableState.position.pixels, 0.0);

      // Paragraph 8 is positioned well past 60% of 1000px viewport height
      final p8Finder = find.textContaining('Paragraph 8 is');
      expect(p8Finder, findsOneWidget);
      final p8InitialDy = tester.getTopLeft(p8Finder).dy;
      expect(p8InitialDy, greaterThan(600.0),
          reason: 'Paragraph 8 should start near or past the 60% threshold');

      // Play on Paragraph 8
      final p8Text = sampleNodes[8].toPlainText();
      ttsNotifier.setPlayingSentence(p8Text, 8);

      // Trigger the post-frame callback
      await tester.pump();
      // Pump animation duration
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Viewport has scrolled down (scrollable position increased)
      expect(scrollableState.position.pixels, greaterThan(0.0));

      // Paragraph 8 is now comfortably positioned in the upper-middle third (250px - 450px)
      final p8NewDy = tester.getTopLeft(p8Finder).dy;
      expect(p8NewDy, greaterThanOrEqualTo(250.0));
      expect(p8NewDy, lessThanOrEqualTo(450.0),
          reason: 'Auto-scroll should bring active sentence to ~35% of 1000px viewport');
    });

    testWidgets(
        'User scrolling suspends auto-scroll during active sentence and resumes on next sentence',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
          .setReadingMode(ReadingMode.continuous);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final canvasFinder = find.byType(ReaderCanvas);
      final canvasState = tester.state<ReaderCanvasState>(canvasFinder);

      final scrollableFinder = find.byType(Scrollable).first;
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);

      // Set playing on Paragraph 5
      final p5Text = sampleNodes[5].toPlainText();
      ttsNotifier.setPlayingSentence(p5Text, 5);
      await tester.pumpAndSettle();

      // Simulate user manual scroll gesture
      final center = tester.getCenter(find.byType(ReaderCanvas));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.down(center));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, 150),
        ),
      );
      await tester.pump();

      // Verify that auto-scroll is suspended by user interaction
      expect(canvasState.isAutoScrollSuspendedByUser, isTrue);

      // Advance within the SAME sentence index (e.g. word update or re-eval)
      ttsNotifier.setPlayingSentence(p5Text, 5);
      await tester.pumpAndSettle();

      // Auto-scroll remains suspended for sentence 5
      expect(canvasState.isAutoScrollSuspendedByUser, isTrue);

      // Wait past debounce so user interaction is marked ended
      await tester.pump(const Duration(milliseconds: 350));

      // Advance to the NEXT sentence (Paragraph 12, located lower on screen)
      final p12Text = sampleNodes[12].toPlainText();
      ttsNotifier.setPlayingSentence(p12Text, 12);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Suspension is lifted on sentence advancement and auto-scroll brings Paragraph 12 into view
      expect(canvasState.isAutoScrollSuspendedByUser, isFalse);
      expect(scrollableState.position.pixels, greaterThan(0.0));
    });

    testWidgets(
        'Off-screen top sentence (< 70px) smoothly scrolls down to the 35% viewing line',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
          .setReadingMode(ReadingMode.continuous);

      await tester.pumpWidget(
        _createTestApp(container: container, document: testEpubDoc),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.byType(Scrollable).first;
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);

      // Programmatically scroll down so Paragraph 2 is scrolled off the top
      scrollableState.position.jumpTo(500.0);
      await tester.pumpAndSettle();
      expect(scrollableState.position.pixels, 500.0);

      // Now play on Paragraph 2 (which is off-screen above the viewport, dy < 70px)
      final p2Text = sampleNodes[2].toPlainText();
      ttsNotifier.setPlayingSentence(p2Text, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Scroll position must have animated backwards (decreased) to bring Paragraph 2 back down
      expect(scrollableState.position.pixels, lessThan(500.0));

      final p2Finder = find.textContaining('Paragraph 2 is');
      expect(p2Finder, findsOneWidget);
      final p2Dy = tester.getTopLeft(p2Finder).dy;
      expect(p2Dy, greaterThanOrEqualTo(250.0));
      expect(p2Dy, lessThanOrEqualTo(450.0),
          reason: 'Sentence off-screen top should scroll down to ~35% of viewport');
    });
  });
}
