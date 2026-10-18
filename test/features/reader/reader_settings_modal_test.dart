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
import 'package:kawi/core/theme/theme_provider.dart';
import 'package:kawi/core/theme/typography.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/reader/widgets/reader_settings_modal.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';

class _MockVoiceManagerNotifier extends VoiceManagerNotifier {
  @override
  VoiceManagerState build() {
    const mockVoice = TtsVoiceModel(
      id: 'mock-kokoro',
      name: 'Default (af)',
      engineType: TtsEngineType.kokoro,
      isInstalled: true,
    );
    return const VoiceManagerState(
      voices: [mockVoice],
      activeVoice: mockVoice,
    );
  }
}

class _TestReaderSettingsNotifier extends ReaderSettingsNotifier {
  _TestReaderSettingsNotifier(this._initial);
  final ReaderSettings _initial;
  @override
  ReaderSettings build() => _initial;
}

final sampleToc = [
  const TocEntry(title: 'Chapter 1', pageIndex: 0),
  const TocEntry(title: 'Chapter 2', pageIndex: 1),
  const TocEntry(title: 'Chapter 3', pageIndex: 2),
];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentEntry testDoc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testDoc = DocumentEntry(
      id: 'test-doc-1',
      filePath: '/test/path/book.epub',
      title: 'Test Book',
      author: 'Author',
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

  Widget createTestApp({
    required ProviderContainer container,
    int initialTab = 0,
    VoidCallback? onToggleTts,
  }) {
    final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
    return UncontrolledProviderScope(
      container: container,
      child: ReaderTheme(
        data: themeData,
        child: MaterialApp(
          home: Scaffold(
            body: ReaderSettingsModal(
              initialTab: initialTab,
              onToggleTts: onToggleTts,
            ),
          ),
        ),
      ),
    );
  }

  Widget createReaderApp({required ProviderContainer container}) {
    final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
    return UncontrolledProviderScope(
      container: container,
      child: ReaderTheme(
        data: themeData,
        child: MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: themeData.bgCanvas),
          home: ReaderScreen(document: testDoc),
        ),
      ),
    );
  }

  group('ReaderSettingsModal Unit & Widget Tests', () {
    testWidgets('renders Display and Audio segmented tabs', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      expect(find.text('Reader Settings'), findsOneWidget);
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);

      // Default Display tab is selected
      expect(find.text('THEME'), findsOneWidget);
      expect(find.text('LAYOUT MODE'), findsOneWidget);
      expect(find.text('TYPEFACE'), findsOneWidget);
      expect(find.text('Font Size'), findsOneWidget);
      expect(find.text('Line Spacing'), findsOneWidget);
      expect(find.text('Paragraph Spacing'), findsOneWidget);
      expect(find.text('Column Width'), findsOneWidget);
      expect(find.text('Horizontal Margin'), findsOneWidget);
    });

    testWidgets('updates typeface and layout mode on Display tab', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Change typeface to Inter
      await tester.tap(find.text('Inter'));
      await tester.pumpAndSettle();
      expect(
        container.read(readerSettingsProvider).fontFamily,
        AppTypography.readerSans,
      );

      // Change layout mode to Paginated
      await tester.tap(find.text('Paginated'));
      await tester.pumpAndSettle();
      expect(
        container.read(readerSettingsProvider).mode,
        ReadingMode.paginated,
      );
    });

    testWidgets('updates theme preset on Display tab', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Gruvbox Light preset
      await tester.tap(find.text(ReaderThemePreset.gruvboxLight.displayName));
      await tester.pumpAndSettle();

      expect(
        container.read(themePresetProvider),
        ReaderThemePreset.gruvboxLight,
      );
    });

    testWidgets('switching to Audio tab displays TTS controls and updates settings', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          voiceManagerProvider.overrideWith(_MockVoiceManagerNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(createTestApp(container: container));
      await tester.pumpAndSettle();

      // Tap Audio tab
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      expect(find.text('VOICE ENGINE & MODEL'), findsOneWidget);
      expect(find.text('AUDIO PLAYBACK CONTROLS'), findsOneWidget);
      expect(find.text('SPEECH HIGHLIGHT & NAVIGATION'), findsOneWidget);
      expect(find.text('Speech Rate'), findsOneWidget);
      expect(find.text('Voice Pitch'), findsOneWidget);
      expect(find.text('Highlight Style'), findsOneWidget);
      expect(find.text('Auto-Advance Pages'), findsOneWidget);

      // Switch highlight style to Underline
      await tester.ensureVisible(find.text('Underline'));
      await tester.tap(find.text('Underline'));
      await tester.pumpAndSettle();

      expect(
        container.read(readerSettingsProvider).ttsHighlightStyle,
        TtsHighlightStyle.underline,
      );

      // Toggle Auto-Advance switch
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        container.read(readerSettingsProvider).ttsAutoAdvance,
        isFalse,
      );
    });

    testWidgets('pressing Escape key dismisses modal dialog immediately', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ReaderTheme(
            data: themeData,
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => ReaderSettingsModal.show(context),
                    child: const Text('Open Modal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(ReaderSettingsModal), findsOneWidget);

      // Press Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ReaderSettingsModal), findsNothing);
    });

    testWidgets('closing modal via Esc restores focus back to reader canvas', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hasInstalledTtsModelsProvider.overrideWithValue(true),
          documentTocProvider(testDoc.filePath)
              .overrideWith((ref) => Future.value(sampleToc)),
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

      await tester.pumpWidget(createReaderApp(container: container));
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Open Reader Settings via top app bar button
      final settingsButton = find.byTooltip('Reader Settings');
      expect(settingsButton, findsOneWidget);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(find.byType(ReaderSettingsModal), findsOneWidget);

      // Close modal with Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ReaderSettingsModal), findsNothing);

      // ReaderCanvas state should now have focus restored
      final canvasState =
          tester.state<ReaderCanvasState>(find.byType(ReaderCanvas));
      expect(canvasState.focusNode.hasFocus, isTrue);

      // Keyboard navigation (Right Arrow) should work immediately without clicking
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Advance to Page 2
      expect(find.text('Page 2 of 3'), findsOneWidget);
    });
  });
}
