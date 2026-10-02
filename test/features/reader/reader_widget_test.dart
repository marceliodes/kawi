import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/core/theme/typography.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/reader/widgets/tts_control_bar.dart';
import 'package:kawi/features/reader/widgets/typography_settings_sheet.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';
import 'package:kawi/features/tts/services/tts_text_normalizer.dart';

Widget _createReaderTestApp({
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
  late DocumentEntry testDoc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testDoc = DocumentEntry(
      id: 'doc-test-1',
      title: 'Meditations of Marcus Aurelius',
      author: 'Marcus Aurelius',
      filePath: '/sandbox/meditations.epub',
      format: 'epub',
      pageCount: 12,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: 4096,
    );
  });

  tearDown(() async {
    await db.close();
  });

  final sampleToc = [
    const TocEntry(title: 'Book One', pageIndex: 0),
    const TocEntry(title: 'Book Two', pageIndex: 3),
    const TocEntry(title: 'Book Three', pageIndex: 7),
  ];

  PageContent mockPageContent(int pageIndex) {
    return PageContent(
      pageIndex: pageIndex,
      plainText: 'This is the text content for page ${pageIndex + 1}.',
      words: const [],
    );
  }

  testWidgets(
    'ReaderScreen renders shell, document title, and auto-hiding chrome',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider(testDoc.filePath)
              .overrideWith((ref) => Future.value(sampleToc)),
          documentPageContentProvider.overrideWith(
            (ref, arg) => Future.value(mockPageContent(arg.pageIndex)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createReaderTestApp(container: container, document: testDoc),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Verify Title and top navigation bar
      expect(find.text('Meditations of Marcus Aurelius'), findsOneWidget);
      expect(find.byTooltip('Back to Library'), findsOneWidget);
      expect(find.byTooltip('Table of Contents'), findsOneWidget);
      expect(find.byTooltip('Appearance & Typography'), findsOneWidget);

      // Verify Reading Canvas with loaded text
      expect(find.byType(ReaderCanvas), findsOneWidget);
      expect(
        find.textContaining('This is the text content for page 1.'),
        findsOneWidget,
      );

      // Bottom progress indicator
      expect(find.textContaining('Page 1 of 12'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping Appearance opens TypographySettingsSheet and modifies settings',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider(testDoc.filePath)
              .overrideWith((ref) => Future.value(sampleToc)),
          documentPageContentProvider.overrideWith(
            (ref, arg) => Future.value(mockPageContent(arg.pageIndex)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createReaderTestApp(container: container, document: testDoc),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Tap Appearance button
      await tester.tap(find.byTooltip('Appearance & Typography'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(TypographySettingsSheet), findsOneWidget);
      expect(find.text('Appearance & Typography'), findsOneWidget);
      expect(find.text('TYPEFACE'), findsOneWidget);
      expect(find.text('LAYOUT MODE'), findsOneWidget);

      // Switch typeface to Inter
      await tester.ensureVisible(find.text('Inter'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Inter'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(readerSettingsProvider).fontFamily,
        AppTypography.readerSans,
      );

      // Switch layout mode to Paginated
      await tester.ensureVisible(find.text('Paginated'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Paginated'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(readerSettingsProvider).mode,
        ReadingMode.paginated,
      );
    },
  );

  testWidgets(
    'tapping Table of Contents opens TocDrawer and navigates on chapter select',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          documentTocProvider(testDoc.filePath)
              .overrideWith((ref) => Future.value(sampleToc)),
          documentPageContentProvider.overrideWith(
            (ref, arg) => Future.value(mockPageContent(arg.pageIndex)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createReaderTestApp(container: container, document: testDoc),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Tap TOC button
      await tester.tap(find.byTooltip('Table of Contents'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));

      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      expect(scaffoldState.isDrawerOpen, isTrue);
      expect(find.text('Book One'), findsOneWidget);
      expect(find.text('Book Two'), findsOneWidget);
      expect(find.text('Book Three'), findsOneWidget);

      // Select Book Two (page 4, index 3)
      await tester.tap(find.text('Book Two'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify TocDrawer closed
      expect(scaffoldState.isDrawerOpen, isFalse);

      // Verify chapter name in status
      expect(find.text('Book Two'), findsWidgets);
    },
  );

  testWidgets('reading progress is loaded and saved to Drift database', (
    tester,
  ) async {
    // Pre-seed reading progress in database
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: testDoc.id,
        title: testDoc.title,
        filePath: testDoc.filePath,
        format: testDoc.format,
        addedAt: DateTime.now(),
      ),
    );

    await db.updateProgress(
      ReadingProgressesCompanion.insert(
        documentId: testDoc.id,
        lastReadPageIndex: const Value(3),
        lastReadScrollOffset: const Value(150.0),
        currentChapter: const Value('Book Two'),
        updatedAt: DateTime.now(),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        documentTocProvider(testDoc.filePath)
            .overrideWith((ref) => Future.value(sampleToc)),
        documentPageContentProvider.overrideWith(
          (ref, arg) => Future.value(mockPageContent(arg.pageIndex)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _createReaderTestApp(container: container, document: testDoc),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));

    // Verify restored state
    expect(find.textContaining('Page 4 of 12'), findsOneWidget);
    expect(find.text('Book Two'), findsWidgets);
  });

  testWidgets(
    'tapping Listen with TTS collects full chapter text across pages when initial page is a short heading',
    (tester) async {
      final mockNotifier = _MockReaderTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockNotifier),
          documentTocProvider(testDoc.filePath)
              .overrideWith((ref) => Future.value(sampleToc)),
          documentPageContentProvider.overrideWith((ref, arg) {
            if (arg.pageIndex == 0) {
              // Stub heading like "CHAPTER 1" (9 chars)
              return Future.value(
                const PageContent(
                  pageIndex: 0,
                  plainText: 'CHAPTER 1',
                  words: [],
                ),
              );
            } else {
              return Future.value(
                const PageContent(
                  pageIndex: 1,
                  plainText:
                      'It was the best of times, it was the worst of times.\n'
                      'It was the age of wisdom, it was the age of foolishness.\n'
                      'It was the epoch of belief.',
                  words: [],
                ),
              );
            }
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createReaderTestApp(container: container, document: testDoc),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Tap the Read Aloud (TTS) button in top bar
      final ttsButton = find.byTooltip('Read Aloud (TTS)');
      expect(ttsButton, findsOneWidget);
      await tester.tap(ttsButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // TTS control bar should now be visible
      expect(find.byType(TtsControlBar), findsOneWidget);

      // Verify that speak() received text from page 0 AND page 1
      expect(mockNotifier.lastSpokenText, isNotNull);
      expect(mockNotifier.lastSpokenText, contains('CHAPTER 1'));
      expect(mockNotifier.lastSpokenText, contains('It was the best of times'));
      expect(mockNotifier.lastSpokenText, contains('It was the epoch of belief.'));

      // Verify that sentences from all visible pages were collected (not just 1/1 for page 0)
      expect(mockNotifier.state.totalSentences, greaterThanOrEqualTo(4));
      expect(
        find.text('1/${mockNotifier.state.totalSentences}'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping Listen with TTS strips [image] placeholders and ensures sentence 1 begins directly with chapter title',
    (tester) async {
      final mockNotifier = _MockReaderTtsNotifier();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          ttsStateProvider.overrideWith(() => mockNotifier),
          documentTocProvider(testDoc.filePath)
              .overrideWith((ref) => Future.value(sampleToc)),
          documentPageContentProvider.overrideWith((ref, arg) {
            if (arg.pageIndex == 0) {
              return Future.value(
                const PageContent(
                  pageIndex: 0,
                  plainText: '[image:cover.jpg] [image:1] Chapter 1: The Diary (Part 1)',
                  words: [],
                ),
              );
            } else {
              return Future.value(
                const PageContent(
                  pageIndex: 1,
                  plainText:
                      'It was a dark and quiet evening.\n'
                      'The stars were shining bright.',
                  words: [],
                ),
              );
            }
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _createReaderTestApp(container: container, document: testDoc),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final ttsButton = find.byTooltip('Read Aloud (TTS)');
      await tester.tap(ttsButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockNotifier.lastSpokenText, isNotNull);
      expect(mockNotifier.lastSpokenText, isNot(contains('[image')));
      expect(mockNotifier.lastSpokenText, contains('Chapter 1: The Diary (Part 1)'));
      expect(mockNotifier.lastSpokenText, contains('It was a dark and quiet evening.'));

      // Sentence 1 must be the chapter title itself, not empty or bracket tokens
      expect(mockNotifier.state.currentSentenceIndex, equals(0));
      expect(
        mockNotifier.state.currentSentenceText,
        equals('Chapter 1: The Diary (Part 1)'),
      );
    },
  );
}

class _MockReaderTtsNotifier extends TtsStateNotifier {
  _MockReaderTtsNotifier() : super();

  String? lastSpokenText;

  @override
  TtsState build() => const TtsState();

  @override
  void speak(String text, {int startSentenceIndex = 0}) {
    lastSpokenText = text;
    final sentences = TtsTextNormalizer.splitIntoSentences(text);
    state = state.copyWith(
      playbackState: TtsPlaybackState.playing,
      currentSentenceIndex: startSentenceIndex,
      totalSentences: sentences.length,
      currentSentenceText: sentences.isNotEmpty ? sentences[startSentenceIndex].text : '',
    );
  }

  @override
  void stop() {
    state = state.copyWith(playbackState: TtsPlaybackState.stopped);
  }
}
