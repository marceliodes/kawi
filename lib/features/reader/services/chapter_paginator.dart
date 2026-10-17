import 'package:flutter/material.dart';

import '../constants/reader_layout_constants.dart';
import '../models/document_models.dart';

/// Pure-Dart layout measurement and viewport pagination engine.
///
/// Slices a chapter's semantic AST ([DocumentNode] list) into screen-sized [PageChunk]s
/// based on exact typographic constraints ([maxWidth], [maxHeight], [textStyle], and [paragraphSpacing]).
/// Large paragraphs are cleanly split across page boundaries without clipping or cutting words in half.
class ChapterPaginator {
  const ChapterPaginator._();

  /// Paginates [nodes] into a sequential list of [PageChunk]s that fit within [maxHeight].
  static List<PageChunk> paginate({
    required List<DocumentNode> nodes,
    required double maxWidth,
    required double maxHeight,
    required TextStyle textStyle,
    required double paragraphSpacing,
    int chapterIndex = 0,
    double safetyBuffer = 12.0,
  }) {
    if (nodes.isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return [
        PageChunk(
          pageIndexInChapter: 0,
          chapterIndex: chapterIndex,
          nodes: const [],
          startParagraphIndex: 0,
          endParagraphIndex: 0,
          startCharOffset: 0,
          endCharOffset: 0,
        ),
      ];
    }

    final pages = <PageChunk>[];
    var currentPageNodes = <DocumentNode>[];
    final lineHeight =
        (textStyle.fontSize ?? 16.0) * (textStyle.height ?? 1.5);
    final nodeHeadroomSlack = (lineHeight * 0.85).clamp(18.0, 26.0);
    final usableHeight = maxHeight;
    var remainingHeight = usableHeight;

    var pageStartNodeIndex = 0;
    var pageStartCharOffset = 0;
    var pageEndNodeIndex = 0;
    var pageEndCharOffset = 0;

    void finalizePage() {
      pages.add(PageChunk(
        pageIndexInChapter: pages.length,
        chapterIndex: chapterIndex,
        nodes: List.unmodifiable(currentPageNodes),
        startParagraphIndex: pageStartNodeIndex,
        endParagraphIndex: pageEndNodeIndex,
        startCharOffset: pageStartCharOffset,
        endCharOffset: pageEndCharOffset,
      ));
      currentPageNodes = [];
      remainingHeight = usableHeight;
    }

    var i = 0;
    DocumentNode? inFlightNode;
    var inFlightCharOffset = 0;

    while (i < nodes.length || inFlightNode != null) {
      final currentNode = inFlightNode ?? nodes[i];
      final originalNodeIndex = i;
      final startOffsetInThisNode = inFlightCharOffset;

      if (currentPageNodes.isEmpty) {
        pageStartNodeIndex = originalNodeIndex;
        pageStartCharOffset = startOffsetInThisNode;
      }

      if (currentNode is ImageNode) {
        // Finalize any accumulated text nodes before the image
        if (currentPageNodes.isNotEmpty) {
          pages.add(PageChunk(
            pageIndexInChapter: pages.length,
            chapterIndex: chapterIndex,
            nodes: List.unmodifiable(currentPageNodes),
            startParagraphIndex: pageStartNodeIndex,
            endParagraphIndex: pageEndNodeIndex,
            startCharOffset: pageStartCharOffset,
            endCharOffset: pageEndCharOffset,
          ));
          currentPageNodes.clear();
        }

        // Place the ImageNode strictly on its own standalone PageChunk
        pages.add(PageChunk(
          pageIndexInChapter: pages.length,
          chapterIndex: chapterIndex,
          nodes: [currentNode],
          startParagraphIndex: originalNodeIndex,
          endParagraphIndex: originalNodeIndex,
          startCharOffset: 0,
          endCharOffset: 0,
        ));

        // Reset pagination height for subsequent nodes
        remainingHeight = usableHeight;
        inFlightNode = null;
        inFlightCharOffset = 0;
        i++;
        continue;
      }

      // Compute typographic styling for headings vs standard paragraphs
      final TextStyle nodeStyle;
      if (currentNode is HeadingNode) {
        final scale = (1.6 - (currentNode.level * 0.1)).clamp(1.15, 1.6);
        nodeStyle = textStyle.copyWith(
          fontSize: (textStyle.fontSize ?? 16.0) * scale,
          fontWeight: FontWeight.bold,
        );
      } else {
        nodeStyle = textStyle;
      }

      final List<TextSegment> segments = currentNode is ParagraphNode
          ? currentNode.segments
          : (currentNode as HeadingNode).segments;

      final span = _buildTextSpan(segments, nodeStyle);
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        strutStyle: EpubPaginationMetrics.strutStyleFor(nodeStyle),
      );
      painter.layout(maxWidth: maxWidth);

      final nodeTotalHeight = painter.height + paragraphSpacing;
      final requiresBuffer = currentPageNodes.isNotEmpty;
      if (nodeTotalHeight + (requiresBuffer ? nodeHeadroomSlack : 0.0) <=
          remainingHeight) {
        // Fits completely on the current page
        currentPageNodes.add(currentNode);
        remainingHeight -= nodeTotalHeight;

        final nodeLength = currentNode is ParagraphNode
            ? currentNode.plainText.length
            : (currentNode as HeadingNode).plainText.length;

        pageEndNodeIndex = originalNodeIndex;
        pageEndCharOffset = startOffsetInThisNode + nodeLength;

        inFlightNode = null;
        inFlightCharOffset = 0;
        i++;
      } else {
        // Exceeds remaining height
        final lineMetrics = painter.computeLineMetrics();
        var accumulatedHeight = 0.0;
        var fittingLinesCount = 0;

        for (final line in lineMetrics) {
          if (accumulatedHeight + line.height + paragraphSpacing <=
              remainingHeight - nodeHeadroomSlack) {
            accumulatedHeight += line.height;
            fittingLinesCount++;
          } else {
            break;
          }
        }

        // If some nodes are already on this page and less than 2 lines fit,
        // defer the entire node to the next page chunk to avoid orphan single lines.
        if (currentPageNodes.isNotEmpty && fittingLinesCount < 2) {
          finalizePage();
          continue;
        }

        // If the page is empty, force at least 1 line so forward progress is guaranteed
        if (fittingLinesCount == 0) {
          fittingLinesCount = 1;
          accumulatedHeight =
              lineMetrics.isNotEmpty ? lineMetrics.first.height : remainingHeight;
        }

        final lastLineIdx =
            (fittingLinesCount - 1).clamp(0, lineMetrics.length - 1);
        final targetLine = lineMetrics[lastLineIdx];
        final targetX = targetLine.left + targetLine.width;
        final targetY = targetLine.baseline - (targetLine.ascent * 0.5);

        final pos = painter.getPositionForOffset(Offset(targetX, targetY));
        var splitOffset = pos.offset;

        final plainText = currentNode is ParagraphNode
            ? currentNode.plainText
            : (currentNode as HeadingNode).plainText;

        // Walk backward to nearest whitespace boundary to avoid cutting words
        while (
            splitOffset > 0 && !RegExp(r'\s').hasMatch(plainText[splitOffset - 1])) {
          splitOffset--;
        }

        // If no whitespace was found before splitOffset, slice at raw offset (at least 1 character)
        if (splitOffset <= 0) {
          splitOffset = pos.offset.clamp(1, plainText.length);
        }

        // Verification and self-correction loop:
        // Ensure testPainter height + paragraphSpacing strictly <= remainingHeight - 4.0
        // and line count does not exceed fittingLinesCount
        var split = _splitSegments(segments, splitOffset);
        var testPainter = TextPainter(
          text: _buildTextSpan(split.top, nodeStyle),
          textDirection: TextDirection.ltr,
          strutStyle: EpubPaginationMetrics.strutStyleFor(nodeStyle),
        )..layout(maxWidth: maxWidth);

        final verificationSlack =
            (currentPageNodes.isEmpty && fittingLinesCount == 1)
                ? 0.0
                : nodeHeadroomSlack;
        while ((testPainter.height + paragraphSpacing >
                    remainingHeight - verificationSlack ||
                testPainter.computeLineMetrics().length > fittingLinesCount) &&
            splitOffset > 1) {
          // Pull back past preceding whitespace
          while (splitOffset > 0 &&
              RegExp(r'\s').hasMatch(plainText[splitOffset - 1])) {
            splitOffset--;
          }
          // Pull back to the start of the preceding word
          while (splitOffset > 0 &&
              !RegExp(r'\s').hasMatch(plainText[splitOffset - 1])) {
            splitOffset--;
          }
          if (splitOffset <= 0) {
            splitOffset = 1;
            break;
          }
          split = _splitSegments(segments, splitOffset);
          testPainter = TextPainter(
            text: _buildTextSpan(split.top, nodeStyle),
            textDirection: TextDirection.ltr,
            strutStyle: EpubPaginationMetrics.strutStyleFor(nodeStyle),
          )..layout(maxWidth: maxWidth);
        }

        final topNode = currentNode is ParagraphNode
            ? ParagraphNode(split.top)
            : HeadingNode((currentNode as HeadingNode).level, split.top);
        final bottomNode = currentNode is ParagraphNode
            ? ParagraphNode(split.bottom)
            : HeadingNode((currentNode as HeadingNode).level, split.bottom);

        currentPageNodes.add(topNode);
        pageEndNodeIndex = originalNodeIndex;
        pageEndCharOffset = startOffsetInThisNode + splitOffset;

        finalizePage();

        final isBottomEmpty =
            split.bottom.every((s) => s.text.trim().isEmpty);
        if (isBottomEmpty) {
          inFlightNode = null;
          inFlightCharOffset = 0;
          i++;
        } else {
          inFlightNode = bottomNode;
          inFlightCharOffset = startOffsetInThisNode + splitOffset;
        }
      }
    }

    if (currentPageNodes.isNotEmpty) {
      finalizePage();
    }

    return pages;
  }

  /// Locates the page index in [pages] that contains the given anchor offset.
  ///
  /// If the anchor is before the first page, returns 0. If after the last page,
  /// returns `pages.length - 1`.
  static int findPageForAnchor({
    required List<PageChunk> pages,
    required int paragraphIndex,
    required int charOffset,
  }) {
    if (pages.isEmpty) return 0;

    for (var i = 0; i < pages.length; i++) {
      if (pages[i].containsAnchor(
        paragraphIndex: paragraphIndex,
        charOffset: charOffset,
      )) {
        return i;
      }
    }

    if (paragraphIndex <= pages.first.startParagraphIndex) {
      return 0;
    }
    return pages.length - 1;
  }

  static TextSpan _buildTextSpan(
    List<TextSegment> segments,
    TextStyle baseStyle,
  ) {
    return TextSpan(
      style: baseStyle,
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
  }

  static ({List<TextSegment> top, List<TextSegment> bottom}) _splitSegments(
    List<TextSegment> segments,
    int splitCharOffset,
  ) {
    final top = <TextSegment>[];
    final bottom = <TextSegment>[];
    var accumulated = 0;

    for (final seg in segments) {
      final segStart = accumulated;
      final segEnd = accumulated + seg.text.length;
      accumulated = segEnd;

      if (segEnd <= splitCharOffset) {
        top.add(seg);
      } else if (segStart >= splitCharOffset) {
        bottom.add(seg);
      } else {
        // Split point falls inside this segment
        final cut = splitCharOffset - segStart;
        final topStr = seg.text.substring(0, cut);
        final bottomStr = seg.text.substring(cut);

        if (topStr.isNotEmpty) {
          top.add(TextSegment(
            topStr,
            isBold: seg.isBold,
            isItalic: seg.isItalic,
            href: seg.href,
          ));
        }
        if (bottomStr.isNotEmpty) {
          bottom.add(TextSegment(
            bottomStr,
            isBold: seg.isBold,
            isItalic: seg.isItalic,
            href: seg.href,
          ));
        }
      }
    }

    _trimTrailingWhitespace(top);
    _trimLeadingWhitespace(bottom);

    return (top: top, bottom: bottom);
  }

  static void _trimTrailingWhitespace(List<TextSegment> segments) {
    while (segments.isNotEmpty) {
      final last = segments.last;
      final trimmed = last.text.replaceFirst(RegExp(r'\s+$'), '');
      if (trimmed.isEmpty) {
        segments.removeLast();
      } else {
        if (trimmed != last.text) {
          segments[segments.length - 1] = TextSegment(
            trimmed,
            isBold: last.isBold,
            isItalic: last.isItalic,
            href: last.href,
          );
        }
        break;
      }
    }
  }

  static void _trimLeadingWhitespace(List<TextSegment> segments) {
    while (segments.isNotEmpty) {
      final first = segments.first;
      final trimmed = first.text.replaceFirst(RegExp(r'^\s+'), '');
      if (trimmed.isEmpty) {
        segments.removeAt(0);
      } else {
        if (trimmed != first.text) {
          segments[0] = TextSegment(
            trimmed,
            isBold: first.isBold,
            isItalic: first.isItalic,
            href: first.href,
          );
        }
        break;
      }
    }
  }
}
