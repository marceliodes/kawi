import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../models/document_models.dart';
import 'document_extractor.dart';

/// Pure-Dart EPUB parsing engine.
///
/// Unpacks EPUBs via [epubx], parses chapter XHTML into semantic [DocumentNode]
/// AST trees using [html], extracts clean [TextSegment]s without synthetic line breaks,
/// and resolves image assets from the archive into [Uint8List].
class EpubParser {
  const EpubParser._();

  static const _blockTags = {
    'p',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'div',
    'blockquote',
    'ul',
    'ol',
    'li',
    'section',
    'article',
    'main',
    'header',
    'footer',
    'hr',
    'img',
    'figure',
    'figcaption',
  };

  /// Parses raw EPUB binary [bytes] into an [EpubBook].
  static Future<EpubBook> parseBook(Uint8List bytes) {
    return EpubReader.readBook(bytes);
  }

  /// Extracts standard [DocumentMetadata] from an [EpubBook].
  static DocumentMetadata extractMetadata(
    EpubBook book, {
    bool includeCover = true,
  }) {
    final title = book.Title?.trim();
    final author = book.Author?.trim();

    final chapters = book.Chapters ?? const [];
    final spineCount = book.Schema?.Package?.Spine?.Items?.length ?? 0;
    final pageCount = chapters.isNotEmpty
        ? chapters.length
        : (spineCount > 0 ? spineCount : 1);

    Uint8List? coverRgba;
    int? coverWidth;
    int? coverHeight;

    if (includeCover && book.CoverImage != null) {
      final cover = book.CoverImage!;
      coverWidth = cover.width;
      coverHeight = cover.height;
      coverRgba = Uint8List.fromList(cover.getBytes());
    }

    return DocumentMetadata(
      title: (title != null && title.isNotEmpty) ? title : null,
      author: (author != null && author.isNotEmpty) ? author : null,
      pageCount: pageCount,
      coverRgba: coverRgba,
      coverWidth: coverWidth,
      coverHeight: coverHeight,
    );
  }

  /// Extracts the hierarchical Table of Contents ([TocEntry] list) from an [EpubBook].
  static List<TocEntry> extractTableOfContents(EpubBook book) {
    final chapters = book.Chapters ?? const [];
    final entries = <TocEntry>[];

    for (var i = 0; i < chapters.length; i++) {
      entries.add(_mapChapterToToc(chapters[i], i));
    }

    return entries;
  }

  static TocEntry _mapChapterToToc(EpubChapter chapter, int chapterIndex) {
    final children = <TocEntry>[];
    if (chapter.SubChapters != null) {
      for (final sub in chapter.SubChapters!) {
        children.add(_mapChapterToToc(sub, chapterIndex));
      }
    }

    final rawTitle = chapter.Title?.trim() ?? '';
    final title = rawTitle.isNotEmpty ? rawTitle : 'Chapter ${chapterIndex + 1}';

    return TocEntry(
      title: title,
      pageIndex: chapterIndex,
      uri: chapter.ContentFileName,
      children: children,
    );
  }

  /// Parses the raw [html] of an EPUB chapter into a semantic [DocumentNode] list.
  ///
  /// Embedded images are looked up in [images] and decoded directly into [ImageNode]s.
  static List<DocumentNode> parseChapterHtml(
    String html,
    Map<String, EpubByteContentFile>? images,
  ) {
    if (html.trim().isEmpty) return const [];

    final document = html_parser.parse(html);
    final body = document.body ?? document.documentElement;
    if (body == null) return const [];

    final nodes = <DocumentNode>[];
    _walkNodes(body, nodes, images);
    return nodes;
  }

  static void _walkNodes(
    dom.Node node,
    List<DocumentNode> out,
    Map<String, EpubByteContentFile>? images,
  ) {
    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

    // Headings (h1 - h6)
    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      final level = int.tryParse(tag[1]) ?? 1;
      final segments = _extractSegments(node);
      if (segments.isNotEmpty) {
        out.add(HeadingNode(level, segments));
      }
      return;
    }

    // Paragraph or Blockquote
    if (tag == 'p' || tag == 'blockquote') {
      final segments = _extractSegments(node);
      if (segments.isNotEmpty) {
        out.add(ParagraphNode(segments));
      }
      return;
    }

    // Standard Image tag
    if (tag == 'img') {
      final src = node.attributes['src'];
      final alt = node.attributes['alt'] ?? '';
      final bytes = resolveImageBytes(src, images);
      if (bytes != null) {
        out.add(ImageNode(bytes, alt));
      }
      return;
    }

    // SVG Embedded Image tag
    if (tag == 'image' || tag == 'svg') {
      final src = node.attributes['href'] ??
          node.attributes['xlink:href'] ??
          node.querySelector('image')?.attributes['xlink:href'] ??
          node.querySelector('image')?.attributes['href'];
      final alt = node.attributes['alt'] ?? '';
      final bytes = resolveImageBytes(src, images);
      if (bytes != null) {
        out.add(ImageNode(bytes, alt));
      }
      return;
    }

    // List item (li)
    if (tag == 'li') {
      final segments = _extractSegments(node);
      if (segments.isNotEmpty) {
        out.add(ParagraphNode([const TextSegment('• '), ...segments]));
      }
      return;
    }

    // Check if container element has block-level children
    final hasBlockChildren = node.children.any(
      (c) => _blockTags.contains(c.localName?.toLowerCase()),
    );

    if (hasBlockChildren) {
      for (final child in node.nodes) {
        _walkNodes(child, out, images);
      }
    } else {
      // Leaf container without block children (e.g. <div>text</div>)
      final segments = _extractSegments(node);
      if (segments.isNotEmpty) {
        out.add(ParagraphNode(segments));
      }
    }
  }

  /// Extracts styled [TextSegment]s recursively from [node].
  static List<TextSegment> _extractSegments(
    dom.Node node, {
    bool isBold = false,
    bool isItalic = false,
    String? href,
  }) {
    final rawSegments = <TextSegment>[];

    void collect(
      dom.Node current, {
      required bool b,
      required bool i,
      required String? h,
    }) {
      for (final child in current.nodes) {
        if (child is dom.Text) {
          final normalized = child.text.replaceAll(RegExp(r'\s+'), ' ');
          if (normalized.isNotEmpty) {
            rawSegments.add(TextSegment(
              normalized,
              isBold: b,
              isItalic: i,
              href: h,
            ));
          }
        } else if (child is dom.Element) {
          final tag = child.localName?.toLowerCase() ?? '';
          if (tag == 'br') {
            rawSegments.add(TextSegment('\n', isBold: b, isItalic: i, href: h));
            continue;
          }

          final style = child.attributes['style']?.toLowerCase() ?? '';
          final childBold = b ||
              tag == 'b' ||
              tag == 'strong' ||
              style.contains('font-weight: bold') ||
              style.contains('font-weight:bold') ||
              style.contains('font-weight: 700') ||
              style.contains('font-weight:700');

          final childItalic = i ||
              tag == 'i' ||
              tag == 'em' ||
              tag == 'cite' ||
              tag == 'dfn' ||
              style.contains('font-style: italic') ||
              style.contains('font-style:italic');

          final childHref = h ?? (tag == 'a' ? child.attributes['href'] : null);

          collect(
            child,
            b: childBold,
            i: childItalic,
            h: childHref,
          );
        }
      }
    }

    collect(node, b: isBold, i: isItalic, h: href);

    if (rawSegments.isEmpty) return const [];

    // Trim leading whitespace from first segment
    final first = rawSegments.first;
    final trimmedFirst = first.text.replaceFirst(RegExp(r'^\s+'), '');
    if (trimmedFirst.isEmpty) {
      rawSegments.removeAt(0);
    } else if (trimmedFirst != first.text) {
      rawSegments[0] = TextSegment(
        trimmedFirst,
        isBold: first.isBold,
        isItalic: first.isItalic,
        href: first.href,
      );
    }

    if (rawSegments.isEmpty) return const [];

    // Trim trailing whitespace from last segment
    final last = rawSegments.last;
    final trimmedLast = last.text.replaceFirst(RegExp(r'\s+$'), '');
    if (trimmedLast.isEmpty) {
      rawSegments.removeLast();
    } else if (trimmedLast != last.text) {
      rawSegments[rawSegments.length - 1] = TextSegment(
        trimmedLast,
        isBold: last.isBold,
        isItalic: last.isItalic,
        href: last.href,
      );
    }

    // Merge consecutive segments with identical styling
    final merged = <TextSegment>[];
    for (final seg in rawSegments) {
      if (seg.text.isEmpty) continue;
      if (merged.isNotEmpty &&
          merged.last.isBold == seg.isBold &&
          merged.last.isItalic == seg.isItalic &&
          merged.last.href == seg.href) {
        final prev = merged.removeLast();
        merged.add(TextSegment(
          '${prev.text}${seg.text}',
          isBold: seg.isBold,
          isItalic: seg.isItalic,
          href: seg.href,
        ));
      } else {
        merged.add(seg);
      }
    }

    return merged;
  }

  /// Resolves image binary bytes for a given [src] reference from [images].
  static Uint8List? resolveImageBytes(
    String? src,
    Map<String, EpubByteContentFile>? images,
  ) {
    if (src == null || images == null || images.isEmpty) return null;
    final decoded = Uri.decodeFull(src);

    // 1. Exact key match
    if (images.containsKey(src)) {
      final c = images[src]!.Content;
      if (c != null) return Uint8List.fromList(c);
    }
    if (images.containsKey(decoded)) {
      final c = images[decoded]!.Content;
      if (c != null) return Uint8List.fromList(c);
    }

    // 2. Normalized path suffix match
    final normalized = p.normalize(decoded).replaceAll(r'\', '/');
    for (final entry in images.entries) {
      final key = p.normalize(entry.key).replaceAll(r'\', '/');
      if (key == normalized || key.endsWith('/$normalized')) {
        final c = entry.value.Content;
        if (c != null) return Uint8List.fromList(c);
      }
    }

    // 3. Basename fallback match
    final base = p.basename(decoded);
    for (final entry in images.entries) {
      if (p.basename(entry.key) == base) {
        final c = entry.value.Content;
        if (c != null) return Uint8List.fromList(c);
      }
    }

    return null;
  }
}
