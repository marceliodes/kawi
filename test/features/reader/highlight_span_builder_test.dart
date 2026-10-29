import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/models/highlight.dart';
import 'package:kawi/features/reader/models/search_models.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/services/highlight_span_builder.dart';
import 'package:kawi/features/tts/models/tts_models.dart';

void main() {
  const baseStyle = TextStyle(
    fontFamily: 'Literata',
    fontSize: 16.0,
    height: 1.5,
    color: Color(0xFF222222),
  );

  final theme = ReaderThemeTokens.fromPreset(ReaderThemePreset.oledBlack);

  group('HighlightSpanBuilder Zero-Reflow Tests', () {
    test('returns unadorned default spans when no highlights are active', () {
      const node = ParagraphNode([
        TextSegment('The quick brown fox jumps over the lazy dog.'),
      ]);

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 0,
        highlights: const [],
        theme: theme,
      );

      expect(span.style, baseStyle);
      final children = span.children!;
      expect(children.length, 1);
      final textSpan = children.first as TextSpan;
      expect(textSpan.text, 'The quick brown fox jumps over the lazy dog.');
      expect(textSpan.style?.backgroundColor, isNull);
      expect(textSpan.style?.decoration, isNull);
    });

    test('splits single segment into [pre, highlighted, post] with background tint', () {
      const node = ParagraphNode([
        TextSegment('Hello wonderful world of reading'),
      ]);
      // "wonderful" is at offset 6..15
      final highlight = Highlight(
        id: 'hl-1',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 6),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 15),
        highlightedText: 'wonderful',
        colorHex: '#FFD54F',
        createdAt: DateTime.now(),
      );

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 0,
        highlights: [highlight],
        theme: theme,
      );

      final children = span.children!;
      expect(children.length, 3);

      final pre = children[0] as TextSpan;
      final mid = children[1] as TextSpan;
      final post = children[2] as TextSpan;

      expect(pre.text, 'Hello ');
      expect(pre.style?.backgroundColor, isNull);

      expect(mid.text, 'wonderful');
      expect(mid.style?.backgroundColor, highlight.getBackgroundTint(isDark: theme.isDark));

      expect(post.text, ' world of reading');
      expect(post.style?.backgroundColor, isNull);

      // Verify font metrics are immutable
      expect(span.style?.fontSize, 16.0);
      expect(span.style?.height, 1.5);
      expect(span.style?.fontFamily, 'Literata');
    });

    test('preserves bold and italic formatting across sliced highlight boundaries', () {
      // "Normal, " (0..8) + bold "bold phrase, " (8..21) + italic "italic text." (21..33)
      const node = ParagraphNode([
        TextSegment('Normal, '),
        TextSegment('bold phrase, ', isBold: true),
        TextSegment('italic text.', isItalic: true),
      ]);

      // Highlight spans from offset 4 to 26 (spans into Normal, all of bold, and start of italic)
      final highlight = Highlight(
        id: 'hl-across',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 26),
        highlightedText: 'al, bold phrase, itali',
        colorHex: '#81C784',
        createdAt: DateTime.now(),
      );

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 0,
        highlights: [highlight],
        theme: theme,
      );

      final children = span.children!;
      // Expected boundaries: 0, 4, 8, 21, 26, 33
      // Intervals:
      // 0..4: 'Norm' (unhighlighted normal)
      // 4..8: 'al, ' (highlighted normal)
      // 8..21: 'bold phrase, ' (highlighted bold)
      // 21..26: 'itali' (highlighted italic)
      // 26..33: 'c text.' (unhighlighted italic)
      expect(children.length, 5);

      final s0 = children[0] as TextSpan;
      expect(s0.text, 'Norm');
      expect(s0.style?.fontWeight, isNull);
      expect(s0.style?.backgroundColor, isNull);

      final s1 = children[1] as TextSpan;
      expect(s1.text, 'al, ');
      expect(s1.style?.fontWeight, isNull);
      expect(s1.style?.backgroundColor, highlight.getBackgroundTint(isDark: theme.isDark));

      final s2 = children[2] as TextSpan;
      expect(s2.text, 'bold phrase, ');
      expect(s2.style?.fontWeight, FontWeight.bold);
      expect(s2.style?.backgroundColor, highlight.getBackgroundTint(isDark: theme.isDark));

      final s3 = children[3] as TextSpan;
      expect(s3.text, 'itali');
      expect(s3.style?.fontStyle, FontStyle.italic);
      expect(s3.style?.backgroundColor, highlight.getBackgroundTint(isDark: theme.isDark));

      final s4 = children[4] as TextSpan;
      expect(s4.text, 'c text.');
      expect(s4.style?.fontStyle, FontStyle.italic);
      expect(s4.style?.backgroundColor, isNull);
    });

    test('underline style applies TextDecoration.underline without background color', () {
      const node = ParagraphNode([
        TextSegment('Underlined phrase test'),
      ]);

      final underline = Highlight(
        id: 'hl-under',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 10),
        highlightedText: 'Underlined',
        colorHex: 'underline',
        createdAt: DateTime.now(),
      );

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 0,
        highlights: [underline],
        theme: theme,
      );

      final children = span.children!;
      final s0 = children[0] as TextSpan;
      expect(s0.text, 'Underlined');
      expect(s0.style?.decoration, TextDecoration.underline);
      expect(s0.style?.backgroundColor, isNull);
    });

    test('paginated node slice maps offsets relative to sliceCharOffset', () {
      // Second half of a paragraph on page 2: text starts at paragraph charOffset 50
      const node = ParagraphNode([
        TextSegment('continued text on the second page.'),
      ]);

      // Highlight in document coordinates: offset 60 to 74 (which corresponds to local 10..24)
      final highlight = Highlight(
        id: 'hl-page2',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 3, charOffset: 60),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 3, charOffset: 74),
        highlightedText: 'text on the se',
        colorHex: '#64B5F6',
        createdAt: DateTime.now(),
      );

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 3,
        sliceCharOffset: 50,
        highlights: [highlight],
        theme: theme,
      );

      final children = span.children!;
      expect(children.length, 3);
      expect((children[0] as TextSpan).text, 'continued ');
      expect((children[1] as TextSpan).text, 'text on the se');
      expect((children[1] as TextSpan).style?.backgroundColor, isNotNull);
      expect((children[2] as TextSpan).text, 'cond page.');
    });

    test('defensively ignores negative offsets and out-of-bounds highlight boundaries without RangeError', () {
      const text = 'Testing defensive boundary handling with negative start offset.';
      const node = ParagraphNode([
        TextSegment(text),
      ]);

      // Highlight with negative start offset (-1) and out-of-bounds end offset (9999)
      final negativeHighlight = Highlight(
        id: 'hl-neg',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: -1),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 9999),
        highlightedText: text,
        colorHex: '#FFD54F',
        createdAt: DateTime.now(),
      );

      // Highlight with zero-length
      final zeroLengthHighlight = Highlight(
        id: 'hl-zero',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 5),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 5),
        highlightedText: '',
        colorHex: '#FFD54F',
        createdAt: DateTime.now(),
      );

      expect(
        () => HighlightSpanBuilder.buildSpans(
          node: node,
          baseStyle: baseStyle,
          chapterIndex: 0,
          paragraphIndex: 0,
          highlights: [negativeHighlight, zeroLengthHighlight],
          theme: theme,
        ),
        returnsNormally,
      );

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 0,
        highlights: [negativeHighlight, zeroLengthHighlight],
        theme: theme,
      );

      expect(span.text, isNull);
      final children = span.children!;
      // Entire text is covered by negativeHighlight clamped to 0..text.length
      expect(children.isNotEmpty, isTrue);
      final reconstructed = children.map((c) => (c as TextSpan).text).join();
      expect(reconstructed, text);
    });

    test('handles negative sliceCharOffset and excessive sliceCharOffset cleanly', () {
      const text = 'Slice offset handling test.';
      const node = ParagraphNode([
        TextSegment(text),
      ]);

      final highlight = Highlight(
        id: 'hl-slice',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 10),
        highlightedText: 'Slice off',
        colorHex: '#81C784',
        createdAt: DateTime.now(),
      );

      // Slicing offset greater than plainText length
      expect(
        () => HighlightSpanBuilder.buildSpans(
          node: node,
          baseStyle: baseStyle,
          chapterIndex: 0,
          paragraphIndex: 0,
          sliceCharOffset: 1000,
          highlights: [highlight],
          theme: theme,
        ),
        returnsNormally,
      );

      // Slicing offset negative
      expect(
        () => HighlightSpanBuilder.buildSpans(
          node: node,
          baseStyle: baseStyle,
          chapterIndex: 0,
          paragraphIndex: 0,
          sliceCharOffset: -10,
          highlights: [highlight],
          theme: theme,
        ),
        returnsNormally,
      );
    });

    test('handles TTS state with non-matching or invalid sentence without RangeError', () {
      const text = 'TTS boundary sanitation test.';
      const node = ParagraphNode([
        TextSegment(text),
      ]);

      expect(
        () => HighlightSpanBuilder.buildSpans(
          node: node,
          baseStyle: baseStyle,
          chapterIndex: 0,
          paragraphIndex: 0,
          highlights: const [],
          theme: theme,
          ttsState: const TtsState(
            playbackState: TtsPlaybackState.playing,
            currentSentenceText: 'This text is not in the paragraph at all',
          ),
        ),
        returnsNormally,
      );
    });

    test('renders passive search matches with subtle yellow tint and active search matches with high-contrast amber', () {
      const node = ParagraphNode([
        TextSegment('The quick brown fox jumps over the quick dog.'),
      ]);
      const passiveMatch = SearchMatch(
        id: 'c0_p0_o4',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 9),
        matchedText: 'quick',
        snippet: 'The quick brown fox...',
        snippetMatchStart: 4,
        snippetMatchEnd: 9,
        matchIndexInBook: 0,
      );
      const activeMatch = SearchMatch(
        id: 'c0_p0_o35',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 35),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 40),
        matchedText: 'quick',
        snippet: '...over the quick dog.',
        snippetMatchStart: 12,
        snippetMatchEnd: 17,
        matchIndexInBook: 1,
      );

      final span = HighlightSpanBuilder.buildSpans(
        node: node,
        baseStyle: baseStyle,
        chapterIndex: 0,
        paragraphIndex: 0,
        highlights: const [],
        searchMatches: [passiveMatch, activeMatch],
        activeSearchMatch: activeMatch,
        theme: theme,
      );

      final children = span.children!;
      final passiveSpan = children.firstWhere((c) => (c as TextSpan).text == 'quick') as TextSpan;
      expect(
        passiveSpan.style?.backgroundColor,
        const Color(0xFFFFEB3B).withValues(alpha: 0.35),
      );

      final activeSpan = children.lastWhere((c) => (c as TextSpan).text == 'quick') as TextSpan;
      expect(
        activeSpan.style?.backgroundColor,
        const Color(0xFFFF9800).withValues(alpha: 0.75),
      );
      expect(activeSpan.style?.decoration, TextDecoration.underline);
      expect(activeSpan.style?.decorationColor, theme.accent);

      // Invariant: zero reflow, child spans do not set fontSize/fontFamily, inheriting root baseStyle
      expect(activeSpan.style?.fontSize, isNull);
      expect(activeSpan.style?.fontFamily, isNull);
      expect(span.style?.fontSize, baseStyle.fontSize);
      expect(span.style?.fontFamily, baseStyle.fontFamily);
    });
  });
}
