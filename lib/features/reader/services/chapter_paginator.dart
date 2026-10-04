import 'package:flutter/material.dart';

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
    var remainingHeight = maxHeight;

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
      remainingHeight = maxHeight;
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

      // Handle ImageNode
      if (currentNode is ImageNode) {
        const estimatedImageHeight = 250.0;
        if (estimatedImageHeight <= remainingHeight || currentPageNodes.isEmpty) {
          currentPageNodes.add(currentNode);
          remainingHeight -= (estimatedImageHeight + paragraphSpacing);
          pageEndNodeIndex = originalNodeIndex;
          pageEndCharOffset = 0;
          inFlightNode = null;
          inFlightCharOffset = 0;
          i++;
        } else {
          finalizePage();
        }
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
      );
      painter.layout(maxWidth: maxWidth);

      if (painter.height <= remainingHeight) {
        // Fits completely on the current page
        currentPageNodes.add(currentNode);
        remainingHeight -= (painter.height + paragraphSpacing);

        final nodeLength = currentNode is ParagraphNode
            ? currentNode.plainText.length
            : (currentNode as HeadingNode).plainText.length;

        pageEndNodeIndex = originalNodeIndex;
        pageEndCharOffset = startOffsetInThisNode + nodeLength;

        inFlightNode = null;
        inFlightCharOffset = 0;
        i++;
      } else {
        // Exceeds remaining height: measure fitting lines
        final lineMetrics = painter.computeLineMetrics();
        var accumulatedHeight = 0.0;
        var fittingLinesCount = 0;

        for (final line in lineMetrics) {
          if (accumulatedHeight + line.height <= remainingHeight) {
            accumulatedHeight += line.height;
            fittingLinesCount++;
          } else {
            break;
          }
        }

        // If not even a single line fits
        if (fittingLinesCount == 0) {
          if (currentPageNodes.isNotEmpty) {
            // Push entire node to the next page
            finalizePage();
            continue;
          }
          // The page is empty but height is smaller than line height: force 1 line
          fittingLinesCount = 1;
          accumulatedHeight = lineMetrics.isNotEmpty ? lineMetrics.first.height : remainingHeight;
        }

        final targetY = accumulatedHeight > 0
            ? (accumulatedHeight - 1.0)
            : (lineMetrics.isNotEmpty ? lineMetrics.first.height - 1.0 : 0.0);

        final pos = painter.getPositionForOffset(Offset(maxWidth, targetY));
        var splitOffset = pos.offset;

        final plainText = currentNode is ParagraphNode
            ? currentNode.plainText
            : (currentNode as HeadingNode).plainText;

        // Walk backward to nearest whitespace boundary to avoid cutting words
        while (splitOffset > 0 && !RegExp(r'\s').hasMatch(plainText[splitOffset - 1])) {
          splitOffset--;
        }

        // If no whitespace was found before splitOffset
        if (splitOffset <= 0) {
          if (currentPageNodes.isNotEmpty) {
            // Push entire node to next page
            finalizePage();
            continue;
          }
          // On an empty page, slice at raw offset (at least 1 character)
          splitOffset = pos.offset.clamp(1, plainText.length);
        }

        final split = _splitSegments(segments, splitOffset);
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

        inFlightNode = bottomNode;
        inFlightCharOffset = startOffsetInThisNode + splitOffset;
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
