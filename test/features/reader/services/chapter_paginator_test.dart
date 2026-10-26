import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/reader/constants/reader_layout_constants.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/services/chapter_paginator.dart';

void main() {
  const baseStyle = TextStyle(
    fontSize: 16.0,
    height: 1.5,
  );
  const paragraphSpacing = 16.0;

  group('ChapterPaginator: Exact paragraph measurement', () {
    test('fits multiple short paragraphs onto a single page when height allows', () {
      final nodes = [
        const HeadingNode(1, [TextSegment('Chapter Title')]),
        const ParagraphNode([TextSegment('First short paragraph.')]),
        const ParagraphNode([TextSegment('Second short paragraph.')]),
      ];

      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 400,
        maxHeight: 800,
        textStyle: baseStyle,
        paragraphSpacing: paragraphSpacing,
      );

      expect(pages.length, 1);
      final page = pages.first;
      expect(page.pageIndexInChapter, 0);
      expect(page.chapterIndex, 0);
      expect(page.nodes.length, 3);
      expect(page.startParagraphIndex, 0);
      expect(page.endParagraphIndex, 2);
      expect(page.startCharOffset, 0);
      expect(page.endCharOffset, 'Second short paragraph.'.length);
      expect(page.plainText, contains('Chapter Title'));
      expect(page.plainText, contains('Second short paragraph.'));
    });

    test('returns a single empty PageChunk when nodes list is empty', () {
      final pages = ChapterPaginator.paginate(
        nodes: const [],
        maxWidth: 400,
        maxHeight: 600,
        textStyle: baseStyle,
        paragraphSpacing: paragraphSpacing,
        chapterIndex: 2,
      );

      expect(pages.length, 1);
      expect(pages.first.chapterIndex, 2);
      expect(pages.first.nodes, isEmpty);
      expect(pages.first.pageIndexInChapter, 0);
    });

    test('places ImageNode on its own strictly dedicated PageChunk', () {
      final imgNode = ImageNode(Uint8List.fromList([1, 2, 3]), 'Illustration');
      final nodes = [
        const HeadingNode(1, [TextSegment('Chapter One')]),
        const ParagraphNode([TextSegment('Some intro text before the illustration.')]),
        imgNode,
        const ParagraphNode([TextSegment('Some subsequent text after the illustration.')]),
      ];

      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 400,
        maxHeight: 1000,
        textStyle: baseStyle,
        paragraphSpacing: paragraphSpacing,
      );

      // Should be split into 3 distinct pages:
      // Page 0: Heading + Paragraph 1
      // Page 1: Dedicated ImageNode alone
      // Page 2: Paragraph 2 alone
      expect(pages.length, 3);

      expect(pages[0].nodes.length, 2);
      expect(pages[0].nodes[0], isA<HeadingNode>());
      expect(pages[0].nodes[1], isA<ParagraphNode>());

      expect(pages[1].nodes.length, 1);
      expect(pages[1].nodes.first, same(imgNode));

      expect(pages[2].nodes.length, 1);
      expect(pages[2].nodes.first, isA<ParagraphNode>());
    });
  });

  group('ChapterPaginator: Overflow splitting without word truncation', () {
    test('splits a long paragraph across pages cleanly at whitespace boundaries', () {
      const longText =
          'Alice was beginning to get very tired of sitting by her sister on the bank, '
          'and of having nothing to do: once or twice she had peeped into the book her sister was reading, '
          'but it had no pictures or conversations in it, and what is the use of a book thought Alice '
          'without pictures or conversations? So she was considering in her own mind whether the pleasure '
          'of making a daisy-chain would be worth the trouble of getting up and picking the daisies, '
          'when suddenly a White Rabbit with pink eyes ran close by her.';

      final nodes = [
        const ParagraphNode([
          TextSegment(longText),
        ]),
      ];

      // Constrain height to approximately 3 lines of text (~72px)
      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 300,
        maxHeight: 80,
        textStyle: baseStyle,
        paragraphSpacing: paragraphSpacing,
        chapterIndex: 1,
      );

      expect(pages.length, greaterThan(1));

      for (var i = 0; i < pages.length; i++) {
        final p = pages[i];
        expect(p.nodes, isNotEmpty);
        expect(p.startParagraphIndex, 0);
        expect(p.endParagraphIndex, 0);

        // Verify no words are sliced in half across pages
        if (i < pages.length - 1) {
          final topPlain = (p.nodes.last as ParagraphNode).plainText;
          final nextPageFirstPlain =
              (pages[i + 1].nodes.first as ParagraphNode).plainText;

          // Neither page ends or starts with raw whitespace
          expect(topPlain.endsWith(' '), isFalse);
          expect(nextPageFirstPlain.startsWith(' '), isFalse);

          // Splicing top and bottom at split boundary should match a space in original text
          final spaceIndex = p.endCharOffset - 1;
          expect(
            longText[spaceIndex],
            anyOf(equals(' '), equals('\n')),
            reason: 'Character immediately preceding the next page must be whitespace',
          );
        }
      }

      // Verify the entire text is reconstructed across all pages
      final fullReconstructed = pages
          .map((p) => (p.nodes.first as ParagraphNode).plainText)
          .join(' ');
      expect(fullReconstructed.replaceAll(RegExp(r'\s+'), ' '),
          longText.replaceAll(RegExp(r'\s+'), ' '));
    });

    test('preserves styled TextSegments (bold/italic) across page split boundaries', () {
      const boldText =
          'This is a really long bold passage that will definitely exceed the viewport boundary and need to split across two pages. ';
      const italicText = 'Trailing italic text that finishes on the second page.';

      final nodes = [
        const ParagraphNode([
          TextSegment(boldText, isBold: true),
          TextSegment(italicText, isItalic: true),
        ]),
      ];

      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 250,
        maxHeight: 90,
        textStyle: baseStyle,
        paragraphSpacing: paragraphSpacing,
      );

      expect(pages.length, greaterThanOrEqualTo(2));

      // Page 0 contains bold segment
      final page0Segments = (pages[0].nodes.first as ParagraphNode).segments;
      expect(page0Segments.any((s) => s.isBold), isTrue);

      // Page 1 continues bold segment
      final page1Segments = (pages[1].nodes.first as ParagraphNode).segments;
      expect(
        page1Segments.any((s) => s.isBold),
        isTrue,
        reason: 'Bold formatting must be preserved on subsequent pages',
      );

      // Later page contains italic segment
      final lastPageSegments = (pages.last.nodes.first as ParagraphNode).segments;
      expect(
        lastPageSegments.any((s) => s.isItalic),
        isTrue,
        reason: 'Italic formatting must be preserved on final page',
      );
    });
  });

  group('ChapterPaginator: Resizing and anchor offset preservation', () {
    test('preserves reading position across column width and font size adjustments', () {
      final nodes = [
        const HeadingNode(1, [TextSegment('Chapter I')]),
        for (var i = 0; i < 10; i++)
          ParagraphNode([
            TextSegment(
              'Paragraph $i: The rabbit-hole went straight on like a tunnel for some way, '
              'and then dipped suddenly down, so suddenly that Alice had not a moment to think '
              'about stopping herself before she found herself falling down a very deep well.',
            ),
          ]),
      ];

      // Initial layout: large viewport
      final initialPages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 400,
        maxHeight: 500,
        textStyle: const TextStyle(fontSize: 16, height: 1.4),
        paragraphSpacing: paragraphSpacing,
      );

      // User is reading at paragraph 5, character offset 60
      const anchorParagraph = 5;
      const anchorCharOffset = 60;

      final initialPageIndex = ChapterPaginator.findPageForAnchor(
        pages: initialPages,
        paragraphIndex: anchorParagraph,
        charOffset: anchorCharOffset,
      );

      expect(
        initialPages[initialPageIndex].containsAnchor(
          paragraphIndex: anchorParagraph,
          charOffset: anchorCharOffset,
        ),
        isTrue,
      );

      // User increases font size significantly (from 16 to 24)
      final resizedPages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 400,
        maxHeight: 500,
        textStyle: const TextStyle(fontSize: 24, height: 1.4),
        paragraphSpacing: paragraphSpacing,
      );

      // More pages should have been generated due to larger font
      expect(resizedPages.length, greaterThan(initialPages.length));

      // Resolve the anchor in the new layout
      final newPageIndex = ChapterPaginator.findPageForAnchor(
        pages: resizedPages,
        paragraphIndex: anchorParagraph,
        charOffset: anchorCharOffset,
      );

      final matchingPage = resizedPages[newPageIndex];
      expect(
        matchingPage.containsAnchor(
          paragraphIndex: anchorParagraph,
          charOffset: anchorCharOffset,
        ),
        isTrue,
        reason: 'Anchor must be correctly found on the new page layout',
      );
    });
  });

  group('ReadingAnchor Provider Integration', () {
    test('ActiveReadingAnchorNotifier updates and resolves page index correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(activeReadingAnchorProvider.notifier);
      expect(container.read(activeReadingAnchorProvider), isNull);

      notifier.updateAnchor(
        chapterIndex: 1,
        paragraphIndex: 3,
        charOffset: 45,
      );

      final anchor = container.read(activeReadingAnchorProvider);
      expect(anchor, isNotNull);
      expect(anchor!.chapterIndex, 1);
      expect(anchor.paragraphIndex, 3);
      expect(anchor.charOffset, 45);

      final dummyPages = [
        const PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: 1,
          nodes: [],
          startParagraphIndex: 0,
          endParagraphIndex: 2,
          startCharOffset: 0,
          endCharOffset: 100,
        ),
        const PageChunk(
          pageIndexInChapter: 1,
          chapterIndex: 1,
          nodes: [],
          startParagraphIndex: 2,
          endParagraphIndex: 4,
          startCharOffset: 100,
          endCharOffset: 80,
        ),
      ];

      final resolvedPage = notifier.resolvePageForCurrentAnchor(dummyPages);
      expect(resolvedPage, 1);
    });
  });

  group('ChapterPaginator: Strict Whole-Line Slicing & Height Invariants', () {
    test(
        'rendered content height of every PageChunk is strictly <= maxHeight across multiple configurations',
        () {
      final sampleParagraphs = [
        for (var i = 0; i < 8; i++)
          ParagraphNode([
            TextSegment(
              'Paragraph $i: ${List.generate(
                15,
                (w) =>
                    'word$w${w % 5 == 0 ? ", punctuation" : ""} in a long narrative context',
              ).join(' ')}.',
            ),
          ]),
      ];

      final testHeights = [200.0, 350.0, 500.0, 720.0];
      final fontSizes = [14.0, 18.0, 24.0];

      for (final h in testHeights) {
        for (final fs in fontSizes) {
          final style = TextStyle(fontSize: fs, height: 1.5);
          final pages = ChapterPaginator.paginate(
            nodes: sampleParagraphs,
            maxWidth: 400.0,
            maxHeight: h,
            textStyle: style,
            paragraphSpacing: 16.0,
          );

          expect(pages, isNotEmpty);

          for (var p = 0; p < pages.length; p++) {
            final chunk = pages[p];
            var totalHeight = 0.0;

            for (final node in chunk.nodes) {
              final segments = node is ParagraphNode
                  ? node.segments
                  : (node as HeadingNode).segments;
              final span = TextSpan(
                style: style,
                children: [
                  for (final s in segments)
                    TextSpan(
                      text: s.text,
                      style: TextStyle(
                        fontWeight: s.isBold ? FontWeight.bold : null,
                        fontStyle: s.isItalic ? FontStyle.italic : null,
                      ),
                    ),
                ],
              );
              final painter = TextPainter(
                text: span,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: 400.0);

              totalHeight += painter.height + 16.0;
            }

            expect(
              totalHeight,
              lessThanOrEqualTo(h),
              reason:
                  'Page $p with maxHeight=$h, fontSize=$fs exceeded budget (was $totalHeight)',
            );
          }
        }
      }
    });

    test(
        'splits a paragraph cleanly across page boundaries when space allows >= 2 lines',
        () {
      final nodes = [
        const ParagraphNode([
          TextSegment('Short intro paragraph that takes about 1 or 2 lines.'),
        ]),
        ParagraphNode([
          TextSegment(
            List.generate(
              30,
              (i) =>
                  'sentence$i with substantial length to wrap across many lines.',
            ).join(' '),
          ),
        ]),
      ];

      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 350.0,
        maxHeight: 250.0,
        textStyle: const TextStyle(fontSize: 16.0, height: 1.5),
        paragraphSpacing: 16.0,
      );

      // Verify that page 0 has more than 1 node (first paragraph + part of second paragraph)
      expect(pages.length, greaterThanOrEqualTo(2));
      expect(pages[0].nodes.length, 2);

      // Verify that page 0 does not exceed maxHeight
      var page0Height = 0.0;
      for (final node in pages[0].nodes) {
        final segments = (node as ParagraphNode).segments;
        final span = TextSpan(
          style: const TextStyle(fontSize: 16.0, height: 1.5),
          children: [for (final s in segments) TextSpan(text: s.text)],
        );
        final painter = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 350.0);
        page0Height += painter.height + 16.0;
      }
      expect(page0Height, lessThanOrEqualTo(250.0));
    });

    test(
        'handles extreme small maxHeight without crashing or infinite loops',
        () {
      final nodes = [
        const ParagraphNode([TextSegment('Test with very tiny height.')]),
      ];

      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: 300.0,
        maxHeight: 30.0,
        textStyle: const TextStyle(fontSize: 16.0, height: 1.5),
        paragraphSpacing: 16.0,
      );

      expect(pages, isNotEmpty);
      expect(pages.first.nodes, isNotEmpty);
    });

    test(
        'maximized viewport (maxHeight=1200) packs multiple paragraphs and heading strictly within height budget',
        () {
      const maxWidth = 600.0;
      const maxHeight = 1200.0;
      const textStyle = TextStyle(fontSize: 18.0, height: 1.5);
      const paragraphSpacing = 16.0;

      final nodes = <DocumentNode>[
        const HeadingNode(1, [TextSegment('Chapter 1: The Maximized Viewport')]),
        for (var i = 1; i <= 12; i++)
          ParagraphNode([
            TextSegment(
              'Paragraph $i: This is a realistic body paragraph with several lines of prose '
              'describing the scenery, actions, and internal thoughts of the protagonist. '
              'It continues on to ensure multiple wrapping lines per paragraph in order to test '
              'the cumulative height metrics and ensure no line slicing occurs on tall viewports.',
            ),
          ]),
      ];

      final pages = ChapterPaginator.paginate(
        nodes: nodes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        textStyle: textStyle,
        paragraphSpacing: paragraphSpacing,
      );

      expect(pages, isNotEmpty);

      for (var p = 0; p < pages.length; p++) {
        final page = pages[p];
        var totalHeight = 0.0;

        for (final node in page.nodes) {
          TextStyle nodeStyle = textStyle;
          List<TextSegment> segments;
          if (node is HeadingNode) {
            final scale = (1.6 - node.level * 0.1).clamp(1.1, 1.8);
            nodeStyle = textStyle.copyWith(
              fontSize: (textStyle.fontSize ?? 16.0) * scale,
              fontWeight: FontWeight.bold,
              height: 1.3,
            );
            segments = node.segments;
          } else if (node is ParagraphNode) {
            segments = node.segments;
          } else {
            continue;
          }

          final span = TextSpan(
            style: nodeStyle,
            children: [
              for (final s in segments)
                TextSpan(
                  text: s.text,
                  style: TextStyle(
                    fontWeight: s.isBold ? FontWeight.bold : null,
                    fontStyle: s.isItalic ? FontStyle.italic : null,
                  ),
                ),
            ],
          );

          final painter = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: maxWidth);

          totalHeight += painter.height + paragraphSpacing;
        }

        expect(
          totalHeight,
          lessThanOrEqualTo(maxHeight),
          reason:
              'Page $p exceeded maxHeight budget of $maxHeight (measured $totalHeight)',
        );
      }
    });

    test(
        'nodeHeadroomSlack pushes marginal paragraph to next page when space leaves less than nodeHeadroomSlack',
        () {
      const maxWidth = 500.0;
      const textStyle = TextStyle(fontSize: 16.0, height: 1.5);
      const paragraphSpacing = 16.0;

      const testText = 'Line one of paragraph.\nLine two of paragraph.';
      const testParagraph = ParagraphNode([
        TextSegment(testText),
      ]);
      final painter = TextPainter(
        text: const TextSpan(
          text: testText,
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
        strutStyle: EpubPaginationMetrics.strutStyleFor(textStyle),
      )..layout(maxWidth: maxWidth);
      expect(painter.computeLineMetrics().length, 2);
      final pHeight = painter.height + paragraphSpacing;

      const leadText = 'Lead paragraph occupying a known height.';
      const leadNode = ParagraphNode([
        TextSegment(leadText),
      ]);
      final leadPainter = TextPainter(
        text: const TextSpan(
          text: leadText,
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
        strutStyle: EpubPaginationMetrics.strutStyleFor(textStyle),
      )..layout(maxWidth: maxWidth);
      final leadHeight = leadPainter.height + paragraphSpacing;

      // Set maxHeight such that leadNode + testParagraph fits in raw height (leadHeight + pHeight + 2.0),
      // but NOT with nodeHeadroomSlack (leadHeight + pHeight + nodeHeadroomSlack > maxHeight)
      final maxHeight = leadHeight + pHeight + 2.0;

      final pages = ChapterPaginator.paginate(
        nodes: [leadNode, testParagraph],
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        textStyle: textStyle,
        paragraphSpacing: paragraphSpacing,
        bottomHeadroom: 0.0,
      );
      expect(pages.length, 2);
      expect(pages[0].nodes.length, 1);
      expect(pages[0].nodes.first, same(leadNode));
      expect(pages[1].nodes.length, 1);
      expect(pages[1].nodes.first, same(testParagraph));
    });
  });

  group('ChapterPaginator: Anchor Resolution & Boundary Gap Resilience', () {
    test('returns 0 when pages list is empty', () {
      final pageIndex = ChapterPaginator.findPageForAnchor(
        pages: const [],
        paragraphIndex: 5,
        charOffset: 50,
      );
      expect(pageIndex, 0);
    });

    test('returns 0 when anchor is before first page', () {
      final pages = [
        const PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 2,
          endParagraphIndex: 3,
          startCharOffset: 10,
          endCharOffset: 50,
        ),
      ];

      expect(
        ChapterPaginator.findPageForAnchor(
          pages: pages,
          paragraphIndex: 1,
          charOffset: 0,
        ),
        0,
      );
      expect(
        ChapterPaginator.findPageForAnchor(
          pages: pages,
          paragraphIndex: 2,
          charOffset: 5,
        ),
        0,
      );
    });

    test('returns pages.length - 1 when anchor is after the last page', () {
      final pages = [
        const PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 0,
          endParagraphIndex: 1,
          startCharOffset: 0,
          endCharOffset: 100,
        ),
        const PageChunk(
          pageIndexInChapter: 1,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 1,
          endParagraphIndex: 2,
          startCharOffset: 105,
          endCharOffset: 80,
        ),
      ];

      expect(
        ChapterPaginator.findPageForAnchor(
          pages: pages,
          paragraphIndex: 5,
          charOffset: 0,
        ),
        1,
      );
    });

    test('exact match locates correct page within multi-page chapter', () {
      final pages = [
        const PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 0,
          endParagraphIndex: 2,
          startCharOffset: 0,
          endCharOffset: 50,
        ),
        const PageChunk(
          pageIndexInChapter: 1,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 2,
          endParagraphIndex: 4,
          startCharOffset: 60,
          endCharOffset: 30,
        ),
        const PageChunk(
          pageIndexInChapter: 2,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 4,
          endParagraphIndex: 6,
          startCharOffset: 40,
          endCharOffset: 100,
        ),
      ];

      expect(
        ChapterPaginator.findPageForAnchor(
          pages: pages,
          paragraphIndex: 3,
          charOffset: 10,
        ),
        1,
      );
      expect(
        ChapterPaginator.findPageForAnchor(
          pages: pages,
          paragraphIndex: 5,
          charOffset: 20,
        ),
        2,
      );
    });

    test('resolves to adjacent page when charOffset falls in trimmed whitespace gap between pages', () {
      // Paragraph 2 split across page 0 and page 1:
      // Page 0 ends at char 140.
      // Trimmed whitespace gap between 140 and 150.
      // Page 1 starts at char 150.
      final pages = [
        const PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 1,
          endParagraphIndex: 2,
          startCharOffset: 0,
          endCharOffset: 140,
        ),
        const PageChunk(
          pageIndexInChapter: 1,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 2,
          endParagraphIndex: 3,
          startCharOffset: 150,
          endCharOffset: 80,
        ),
        const PageChunk(
          pageIndexInChapter: 2,
          chapterIndex: 0,
          nodes: [],
          startParagraphIndex: 3,
          endParagraphIndex: 5,
          startCharOffset: 90,
          endCharOffset: 200,
        ),
      ];

      // Offset 145 falls in trimmed whitespace between Page 0 and Page 1
      final resolved = ChapterPaginator.findPageForAnchor(
        pages: pages,
        paragraphIndex: 2,
        charOffset: 145,
      );

      // Must NOT fall through to the last page (index 2)!
      expect(resolved, anyOf(equals(0), equals(1)));
      expect(resolved, isNot(equals(2)));
    });
  });
}
