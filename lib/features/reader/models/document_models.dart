import 'dart:typed_data';

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
