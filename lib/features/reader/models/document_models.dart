import 'dart:typed_data';

import '../../../core/database/app_database.dart';

/// Abstract base class for all semantic document AST nodes.
sealed class DocumentNode {
  const DocumentNode();
}

/// Represents a single styled text run within a paragraph or heading.
class TextSegment {
  const TextSegment(
    this.text, {
    this.isBold = false,
    this.isItalic = false,
    this.href,
  });

  final String text;
  final bool isBold;
  final bool isItalic;
  final String? href;

  @override
  String toString() =>
      'TextSegment(text: $text, isBold: $isBold, isItalic: $isItalic, href: $href)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextSegment &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isBold == other.isBold &&
          isItalic == other.isItalic &&
          href == other.href;

  @override
  int get hashCode => Object.hash(text, isBold, isItalic, href);
}

/// Represents a standard paragraph block containing one or more [TextSegment]s.
class ParagraphNode extends DocumentNode {
  const ParagraphNode(this.segments);

  final List<TextSegment> segments;

  /// Returns the flattened plain text string of all segments.
  String get plainText => segments.map((s) => s.text).join();

  @override
  String toString() => 'ParagraphNode(segments: ${segments.length})';
}

/// Represents a heading block with a semantic [level] (1-6) and [TextSegment]s.
class HeadingNode extends DocumentNode {
  const HeadingNode(this.level, this.segments);

  final int level;
  final List<TextSegment> segments;

  /// Returns the flattened plain text string of all segments.
  String get plainText => segments.map((s) => s.text).join();

  @override
  String toString() =>
      'HeadingNode(level: $level, segments: ${segments.length})';
}

/// Represents an embedded image with resolved binary [bytes] and [altText].
class ImageNode extends DocumentNode {
  const ImageNode(this.bytes, this.altText);

  final Uint8List bytes;
  final String altText;

  @override
  String toString() =>
      'ImageNode(${bytes.length} bytes, altText: "$altText")';
}

/// Represents a paginated slice (a single screen/page) of a chapter.
///
/// Contains the layout [nodes] that fit within the viewport height, along with
/// anchor metadata ([startParagraphIndex], [endParagraphIndex], [startCharOffset], [endCharOffset])
/// to preserve reader positioning across font size changes or column resizing.
class PageChunk {
  const PageChunk({
    required this.pageIndexInChapter,
    required this.chapterIndex,
    required this.nodes,
    required this.startParagraphIndex,
    required this.endParagraphIndex,
    required this.startCharOffset,
    required this.endCharOffset,
  });

  final int pageIndexInChapter;
  final int chapterIndex;
  final List<DocumentNode> nodes;
  final int startParagraphIndex;
  final int endParagraphIndex;
  final int startCharOffset;
  final int endCharOffset;

  /// Returns true if this page contains the specified paragraph and character anchor.
  bool containsAnchor({
    required int paragraphIndex,
    required int charOffset,
  }) {
    if (paragraphIndex < startParagraphIndex ||
        paragraphIndex > endParagraphIndex) {
      return false;
    }
    if (paragraphIndex == startParagraphIndex &&
        paragraphIndex == endParagraphIndex) {
      return charOffset >= startCharOffset && charOffset <= endCharOffset;
    }
    if (paragraphIndex == startParagraphIndex) {
      return charOffset >= startCharOffset;
    }
    if (paragraphIndex == endParagraphIndex) {
      return charOffset <= endCharOffset;
    }
    return true;
  }

  /// Concatenated plain text of all text-bearing nodes on this page.
  String get plainText {
    final buffer = StringBuffer();
    for (final node in nodes) {
      if (node is ParagraphNode) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(node.plainText);
      } else if (node is HeadingNode) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(node.plainText);
      }
    }
    return buffer.toString();
  }

  @override
  String toString() =>
      'PageChunk(p$pageIndexInChapter in ch$chapterIndex, nodes: ${nodes.length}, P[$startParagraphIndex:$startCharOffset] -> P[$endParagraphIndex:$endCharOffset])';
}

/// Convenience extension on Drift [DocumentEntry] to detect EPUB documents.
extension DocumentEntryX on DocumentEntry {
  bool get isEpub =>
      format.toLowerCase() == 'epub' ||
      filePath.toLowerCase().endsWith('.epub');
}

