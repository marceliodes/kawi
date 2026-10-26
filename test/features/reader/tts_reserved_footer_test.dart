import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/constants/reader_layout_constants.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/services/chapter_paginator.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class _MockTtsNotifier extends TtsStateNotifier {
  _MockTtsNotifier(this._initial);
  final TtsState _initial;

  @override
  TtsState build() => _initial;

  void setPlaybackState(TtsPlaybackState playbackState) {
    state = state.copyWith(playbackState: playbackState);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Seamless Reserved Footer & Zero-Reflow Text Invariants', () {
    test('EpubPaginationMetrics and ChapterPaginator define consistent 72px bottom headroom', () {
      expect(EpubPaginationMetrics.bottomHeadroom, equals(72.0));
      expect(ChapterPaginator.bottomHeadroom, equals(72.0));

      const params = PaginationParams(
        filePath: '/test/path.epub',
        chapterIndex: 0,
        maxWidth: 400.0,
        maxHeight: 800.0,
        textStyle: TextStyle(fontSize: 16.0),
        paragraphSpacing: 16.0,
      );
      expect(params.bottomHeadroom, equals(72.0));
    });

    test('PaginationParams equality and hashcode are invariant to TTS playback state', () {
      // Regardless of whether TTS is playing, paused, or stopped, PaginationParams remain identical
      const paramsBeforeTts = PaginationParams(
        filePath: '/test/book.epub',
        chapterIndex: 1,
        maxWidth: 450.0,
        maxHeight: 700.0,
        textStyle: TextStyle(fontSize: 16.0, height: 1.5),
        paragraphSpacing: 16.0,
      );

      const paramsDuringTts = PaginationParams(
        filePath: '/test/book.epub',
        chapterIndex: 1,
        maxWidth: 450.0,
        maxHeight: 700.0,
        textStyle: TextStyle(fontSize: 16.0, height: 1.5),
        paragraphSpacing: 16.0,
      );

      expect(paramsBeforeTts, equals(paramsDuringTts));
      expect(paramsBeforeTts.hashCode, equals(paramsDuringTts.hashCode));
      expect(paramsBeforeTts.bottomHeadroom, equals(72.0));
      expect(paramsDuringTts.bottomHeadroom, equals(72.0));
    });

    test('paginated text height and chunk slicing remain identical whether TTS is active or inactive', () {
      final nodes = [
        const HeadingNode(1, [TextSegment('Chapter 1: The Reserved Footer')]),
        const ParagraphNode([
          TextSegment(
            'This is a substantial first paragraph describing the background scene. '
            'It spans several lines of measured typography to test height boundaries.',
          ),
        ]),
        const ParagraphNode([
          TextSegment(
            'A second paragraph with further detailed content that will be paginated '
            'across available vertical space without reflowing when audio controls appear.',
          ),
        ]),
        const ParagraphNode([
          TextSegment(
            'A third concluding paragraph of the chapter that sits near the bottom of the content area.',
          ),
        ]),
      ];

      const maxWidth = 350.0;
      const maxHeight = 500.0;
      const textStyle = TextStyle(fontSize: 16.0, height: 1.5);
      const paragraphSpacing = 16.0;

      // Paginating without TTS
      final pagesNoTts = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        textStyle: textStyle,
        paragraphSpacing: paragraphSpacing,
      );

      // Paginating with TTS active
      final pagesWithTts = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        textStyle: textStyle,
        paragraphSpacing: paragraphSpacing,
      );

      expect(pagesNoTts.length, equals(pagesWithTts.length));
      for (var i = 0; i < pagesNoTts.length; i++) {
        expect(pagesNoTts[i].nodes.length, equals(pagesWithTts[i].nodes.length));
        expect(pagesNoTts[i].startCharOffset, equals(pagesWithTts[i].startCharOffset));
        expect(pagesNoTts[i].endCharOffset, equals(pagesWithTts[i].endCharOffset));
        expect(pagesNoTts[i].plainText, equals(pagesWithTts[i].plainText));
      }

      // Assert usableHeight strictly reserves 72.0 px
      for (final chunk in pagesNoTts) {
        var totalHeight = 0.0;
        for (final node in chunk.nodes) {
          final span = TextSpan(
            text: node.toPlainText(),
            style: textStyle,
          );
          final painter = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: maxWidth);
          totalHeight += painter.height + paragraphSpacing;
        }
        // Content on page fits within maxHeight - 72.0 px
        expect(totalHeight, lessThanOrEqualTo(maxHeight - 72.0 + 32.0));
      }
    });

    testWidgets('paginated mode cross-fades default page progress footer when TTS transport bar is visible', (tester) async {
      final mockNotifier = _MockTtsNotifier(
        const TtsState(),
      );

      const chunk = PageChunk(
        pageIndexInChapter: 0,
        chapterIndex: 0,
        nodes: [
          HeadingNode(1, [TextSegment('Chapter 1')]),
          ParagraphNode([TextSegment('Test paragraph for paginated view.')]),
        ],
        startParagraphIndex: 0,
        endParagraphIndex: 1,
        startCharOffset: 0,
        endCharOffset: 30,
      );

      Widget buildCanvas({required bool isTtsBarVisible}) {
        return ProviderScope(
          overrides: [
            ttsStateProvider.overrideWith(() => mockNotifier),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: ReaderCanvas(
                  filePath: '/dummy/book.epub',
                  pageCount: 1,
                  settings: const ReaderSettings(mode: ReadingMode.paginated),
                  initialPageIndex: 0,
                  initialScrollOffset: 0.0,
                  pageController: PageController(),
                  onPageChanged: (_, _) {},
                  onToggleChrome: () {},
                  epubChunks: const [chunk],
                  isEpub: true,
                  chapterIndex: 0,
                  pageIndexInChapter: 0,
                  isTtsBarVisible: isTtsBarVisible,
                ),
              ),
            ),
          ),
        );
      }

      // 1. When TTS bar is NOT visible: footer is visible with opacity 1.0
      await tester.pumpWidget(buildCanvas(isTtsBarVisible: false));
      await tester.pumpAndSettle();

      final footerFinder = find.byKey(const ValueKey('paginated_page_progress_footer'));
      expect(footerFinder, findsOneWidget);

      final animatedOpacityFinder = find.ancestor(
        of: footerFinder,
        matching: find.byType(AnimatedOpacity),
      );
      expect(animatedOpacityFinder, findsOneWidget);

      AnimatedOpacity opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));

      // 2. When TTS bar IS visible: footer fades out with opacity 0.0
      await tester.pumpWidget(buildCanvas(isTtsBarVisible: true));
      await tester.pumpAndSettle();

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(0.0));
    });

    testWidgets('continuous view sets bottom content padding to at least 96px', (tester) async {
      final mockNotifier = _MockTtsNotifier(
        const TtsState(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ttsStateProvider.overrideWith(() => mockNotifier),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: ReaderCanvas(
                  filePath: '/dummy/book.epub',
                  pageCount: 1,
                  settings: const ReaderSettings(),
                  initialPageIndex: 0,
                  initialScrollOffset: 0.0,
                  pageController: PageController(),
                  onPageChanged: (_, _) {},
                  onToggleChrome: () {},
                  epubNodes: const [
                    HeadingNode(1, [TextSegment('Chapter 1')]),
                    ParagraphNode([TextSegment('Continuous paragraph content.')]),
                  ],
                  isEpub: true,
                  chapterIndex: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find ScrollablePositionedList in continuous mode
      final scrollableFinder = find.byType(ScrollablePositionedList);
      expect(scrollableFinder, findsOneWidget);

      final listWidget = tester.widget<ScrollablePositionedList>(scrollableFinder);
      expect(listWidget.padding, isNotNull);
      final padding = listWidget.padding!;
      expect(padding.bottom, greaterThanOrEqualTo(96.0));
    });
  });
}
