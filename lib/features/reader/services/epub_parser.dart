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

  /// Opens an EPUB book without unpacking chapter content or images (fast/lazy loading).
  static Future<EpubBookRef> openBook(Uint8List bytes) {
    return EpubReader.openBook(bytes);
  }

  /// Parses raw EPUB binary [bytes] into a fully-unpacked [EpubBook].
  static Future<EpubBook> parseBook(Uint8List bytes) {
    return EpubReader.readBook(bytes);
  }

  /// Extracts standard [DocumentMetadata] from a lazily opened [EpubBookRef].
  static Future<DocumentMetadata> extractMetadataFromRef(
    EpubBookRef bookRef, {
    bool includeCover = true,
  }) async {
    final title = bookRef.Title?.trim();
    final author = bookRef.Author?.trim();

    final chapters = await bookRef.getChapters();
    final spineCount = bookRef.Schema?.Package?.Spine?.Items?.length ?? 0;
    final pageCount = chapters.isNotEmpty
        ? chapters.length
        : (spineCount > 0 ? spineCount : 1);

    Uint8List? coverRgba;
    int? coverWidth;
    int? coverHeight;

    if (includeCover) {
      try {
        final cover = await bookRef.readCover();
        if (cover != null) {
          coverWidth = cover.width;
          coverHeight = cover.height;
          coverRgba = Uint8List.fromList(cover.getBytes());
        }
      } catch (_) {}
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

  /// Extracts the hierarchical Table of Contents ([TocEntry] list) from an [EpubBookRef].
  static Future<List<TocEntry>> extractTableOfContentsFromRef(EpubBookRef bookRef) async {
    final chapters = await bookRef.getChapters();
    final entries = <TocEntry>[];

    for (var i = 0; i < chapters.length; i++) {
      entries.add(_mapChapterRefToToc(chapters[i], i));
    }

    return entries;
  }

  static TocEntry _mapChapterRefToToc(EpubChapterRef chapter, int chapterIndex) {
    final children = <TocEntry>[];
    if (chapter.SubChapters != null) {
      for (final sub in chapter.SubChapters!) {
        children.add(_mapChapterRefToToc(sub, chapterIndex));
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
  /// Embedded images are looked up in [images] or [imageBytes] and decoded directly into [ImageNode]s.
  static List<DocumentNode> parseChapterHtml(
    String html,
    Map<String, EpubByteContentFile>? images, {
    Map<String, List<int>>? imageBytes,
  }) {
    if (html.trim().isEmpty) return const [];

    final document = html_parser.parse(html);
    final body = document.body ?? document.documentElement;
    if (body == null) return const [];

    final nodes = <DocumentNode>[];
    _walkNodes(body, nodes, images, imageBytes: imageBytes);
    return nodes;
  }

  static bool _hasImage(dom.Element element) {
    final tag = element.localName?.toLowerCase() ?? '';
    if (tag == 'img' || tag == 'image' || tag == 'svg') return true;
    return element.querySelector('img, image, svg') != null;
  }

  static ImageNode? _tryExtractImageNode(
    dom.Element element,
    Map<String, EpubByteContentFile>? images, {
    Map<String, List<int>>? imageBytes,
  }) {
    final tag = element.localName?.toLowerCase() ?? '';
    if (tag == 'img') {
      final src = element.attributes['src'];
      final alt = element.attributes['alt'] ?? '';
      final bytes = resolveImageBytes(src, images, imageBytes: imageBytes);
      if (bytes != null) {
        return ImageNode(bytes, alt);
      }
    } else if (tag == 'image' || tag == 'svg') {
      final src = element.attributes['href'] ??
          element.attributes['xlink:href'] ??
          element.querySelector('image')?.attributes['xlink:href'] ??
          element.querySelector('image')?.attributes['href'];
      final alt = element.attributes['alt'] ?? '';
      final bytes = resolveImageBytes(src, images, imageBytes: imageBytes);
      if (bytes != null) {
        return ImageNode(bytes, alt);
      }
    }
    return null;
  }

  static void _walkMixedContainer(
    dom.Element container,
    List<DocumentNode> out,
    Map<String, EpubByteContentFile>? images, {
    Map<String, List<int>>? imageBytes,
    bool isLi = false,
  }) {
    final currentSegments = <TextSegment>[];
    bool isFirstParagraph = true;

    void flushSegments() {
      if (currentSegments.isEmpty) return;
      final cleaned = _cleanAndMergeSegments(currentSegments);
      currentSegments.clear();
      if (cleaned.isNotEmpty) {
        if (isLi && isFirstParagraph) {
          out.add(ParagraphNode([const TextSegment('• '), ...cleaned]));
          isFirstParagraph = false;
        } else {
          out.add(ParagraphNode(cleaned));
        }
      }
    }

    void process(
      dom.Node current, {
      bool isBold = false,
      bool isItalic = false,
      String? href,
    }) {
      if (current is dom.Text) {
        final normalized = current.text.replaceAll(RegExp(r'\s+'), ' ');
        if (normalized.isNotEmpty) {
          currentSegments.add(TextSegment(
            normalized,
            isBold: isBold,
            isItalic: isItalic,
            href: href,
          ));
        }
        return;
      }

      if (current is! dom.Element) return;

      final tag = current.localName?.toLowerCase() ?? '';

      // Direct image element
      if (tag == 'img' || tag == 'image' || tag == 'svg') {
        final img = _tryExtractImageNode(current, images, imageBytes: imageBytes);
        if (img != null) {
          flushSegments();
          out.add(img);
        }
        return;
      }

      if (tag == 'br') {
        currentSegments.add(TextSegment('\n', isBold: isBold, isItalic: isItalic, href: href));
        return;
      }

      // Check styling on current element
      final style = current.attributes['style']?.toLowerCase() ?? '';
      final childBold = isBold ||
          tag == 'b' ||
          tag == 'strong' ||
          style.contains('font-weight: bold') ||
          style.contains('font-weight:bold') ||
          style.contains('font-weight: 700') ||
          style.contains('font-weight:700');

      final childItalic = isItalic ||
          tag == 'i' ||
          tag == 'em' ||
          tag == 'cite' ||
          tag == 'dfn' ||
          style.contains('font-style: italic') ||
          style.contains('font-style:italic');

      final childHref = href ?? (tag == 'a' ? current.attributes['href'] : null);

      final hasImg = _hasImage(current);

      if (!hasImg) {
        // If this child is a block-level element (e.g. nested <p>, <h1-6>, <div>, <figcaption>)
        if (_blockTags.contains(tag) && tag != 'span' && tag != 'a') {
          flushSegments();
          _walkNodes(current, out, images, imageBytes: imageBytes);
        } else {
          // Inline element without images (e.g. <span>, <b>, <i>, <a>)
          final segs = _extractSegments(
            current,
            isBold: childBold,
            isItalic: childItalic,
            href: childHref,
          );
          currentSegments.addAll(segs);
        }
      } else {
        // Child contains an image (e.g. <a><img/></a>, <figure><img/><figcaption></figure>, <div>...<img/>...</div>)
        // If this child is a block element, flush preceding segments
        if (_blockTags.contains(tag) && tag != 'span' && tag != 'a') {
          flushSegments();
        }
        // Walk into its children
        for (final child in current.nodes) {
          process(
            child,
            isBold: childBold,
            isItalic: childItalic,
            href: childHref,
          );
        }
      }
    }

    for (final child in container.nodes) {
      process(child);
    }

    flushSegments();
  }

  static void _walkNodes(
    dom.Node node,
    List<DocumentNode> out,
    Map<String, EpubByteContentFile>? images, {
    Map<String, List<int>>? imageBytes,
  }) {
    if (node is dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        out.add(ParagraphNode([TextSegment(text)]));
      }
      return;
    }

    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

    // Document root containers
    if (tag == 'body' || tag == 'html') {
      for (final child in node.nodes) {
        _walkNodes(child, out, images, imageBytes: imageBytes);
      }
      return;
    }

    // Standard Image tag
    if (tag == 'img') {
      final img = _tryExtractImageNode(node, images, imageBytes: imageBytes);
      if (img != null) {
        out.add(img);
      }
      return;
    }

    // SVG Embedded Image tag
    if (tag == 'image' || tag == 'svg') {
      final img = _tryExtractImageNode(node, images, imageBytes: imageBytes);
      if (img != null) {
        out.add(img);
      }
      return;
    }

    // Headings (h1 - h6)
    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      if (_hasImage(node)) {
        _walkMixedContainer(node, out, images, imageBytes: imageBytes);
      } else {
        final level = int.tryParse(tag[1]) ?? 1;
        final segments = _extractSegments(node);
        if (segments.isNotEmpty) {
          out.add(HeadingNode(level, segments));
        }
      }
      return;
    }

    // Check if element contains any image tags (e.g. <p>, <blockquote>, <li>, <figure>, <div>)
    if (_hasImage(node)) {
      _walkMixedContainer(node, out, images, imageBytes: imageBytes, isLi: tag == 'li');
      return;
    }

    // Paragraph or Blockquote (without images)
    if (tag == 'p' || tag == 'blockquote') {
      final segments = _extractSegments(node);
      if (segments.isNotEmpty) {
        out.add(ParagraphNode(segments));
      }
      return;
    }

    // List item (li) (without images)
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
        _walkNodes(child, out, images, imageBytes: imageBytes);
      }
    } else {
      // Leaf container without block children (e.g. <div>text</div>)
      final segments = _extractSegments(node);
      if (segments.isNotEmpty) {
        out.add(ParagraphNode(segments));
      }
    }
  }

  /// Cleans whitespace and merges consecutive identical segments.
  static List<TextSegment> _cleanAndMergeSegments(List<TextSegment> rawSegments) {
    if (rawSegments.isEmpty) return const [];

    final list = List<TextSegment>.from(rawSegments);

    // Remove empty segments
    list.removeWhere((s) => s.text.isEmpty);
    if (list.isEmpty) return const [];

    // Trim leading whitespace from first segment(s)
    while (list.isNotEmpty) {
      final first = list.first;
      final trimmed = first.text.replaceFirst(RegExp(r'^\s+'), '');
      if (trimmed.isEmpty) {
        list.removeAt(0);
      } else {
        if (trimmed != first.text) {
          list[0] = TextSegment(
            trimmed,
            isBold: first.isBold,
            isItalic: first.isItalic,
            href: first.href,
          );
        }
        break;
      }
    }

    if (list.isEmpty) return const [];

    // Trim trailing whitespace from last segment(s)
    while (list.isNotEmpty) {
      final last = list.last;
      final trimmed = last.text.replaceFirst(RegExp(r'\s+$'), '');
      if (trimmed.isEmpty) {
        list.removeLast();
      } else {
        if (trimmed != last.text) {
          list[list.length - 1] = TextSegment(
            trimmed,
            isBold: last.isBold,
            isItalic: last.isItalic,
            href: last.href,
          );
        }
        break;
      }
    }

    // Merge consecutive segments with identical styling
    final merged = <TextSegment>[];
    for (final seg in list) {
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

    return _cleanAndMergeSegments(rawSegments);
  }

  /// Resolves image binary bytes for a given [src] reference from [images] or [imageBytes].
  static Uint8List? resolveImageBytes(
    String? src,
    Map<String, EpubByteContentFile>? images, {
    Map<String, List<int>>? imageBytes,
  }) {
    if (src == null || src.trim().isEmpty) return null;
    final cleanSrc = src.split('?').first.split('#').first.trim();
    final decoded = Uri.decodeFull(cleanSrc);
    final lowerDecoded = decoded.toLowerCase();
    final base = p.basename(decoded);
    final lowerBase = base.toLowerCase();

    if (imageBytes != null && imageBytes.isNotEmpty) {
      if (imageBytes.containsKey(cleanSrc)) {
        return Uint8List.fromList(imageBytes[cleanSrc]!);
      }
      if (imageBytes.containsKey(decoded)) {
        return Uint8List.fromList(imageBytes[decoded]!);
      }
      for (final entry in imageBytes.entries) {
        if (entry.key.toLowerCase() == lowerDecoded) {
          return Uint8List.fromList(entry.value);
        }
      }

      final normalized = p.normalize(decoded).replaceAll(r'\', '/');
      final lowerNormalized = normalized.toLowerCase();
      for (final entry in imageBytes.entries) {
        final key = p.normalize(entry.key).replaceAll(r'\', '/');
        final lowerKey = key.toLowerCase();
        if (key == normalized ||
            key.endsWith('/$normalized') ||
            lowerKey == lowerNormalized ||
            lowerKey.endsWith('/$lowerNormalized')) {
          return Uint8List.fromList(entry.value);
        }
      }

      for (final entry in imageBytes.entries) {
        final entryBase = p.basename(entry.key);
        if (entryBase == base || entryBase.toLowerCase() == lowerBase) {
          return Uint8List.fromList(entry.value);
        }
      }
    }

    if (images == null || images.isEmpty) return null;

    // 1. Exact key match (exact & case-insensitive)
    if (images.containsKey(cleanSrc)) {
      final c = images[cleanSrc]!.Content;
      if (c != null) return Uint8List.fromList(c);
    }
    if (images.containsKey(decoded)) {
      final c = images[decoded]!.Content;
      if (c != null) return Uint8List.fromList(c);
    }
    for (final entry in images.entries) {
      if (entry.key.toLowerCase() == lowerDecoded) {
        final c = entry.value.Content;
        if (c != null) return Uint8List.fromList(c);
      }
    }

    // 2. Normalized path suffix match (exact & case-insensitive)
    final normalized = p.normalize(decoded).replaceAll(r'\', '/');
    final lowerNormalized = normalized.toLowerCase();
    for (final entry in images.entries) {
      final key = p.normalize(entry.key).replaceAll(r'\', '/');
      final lowerKey = key.toLowerCase();
      if (key == normalized ||
          key.endsWith('/$normalized') ||
          lowerKey == lowerNormalized ||
          lowerKey.endsWith('/$lowerNormalized')) {
        final c = entry.value.Content;
        if (c != null) return Uint8List.fromList(c);
      }
    }

    // 3. Basename fallback match (exact & case-insensitive)
    for (final entry in images.entries) {
      final entryBase = p.basename(entry.key);
      if (entryBase == base || entryBase.toLowerCase() == lowerBase) {
        final c = entry.value.Content;
        if (c != null) return Uint8List.fromList(c);
      }
    }

    return null;
  }
}
