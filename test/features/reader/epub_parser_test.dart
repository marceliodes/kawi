import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/services/epub_parser.dart';
import 'package:kawi/features/reader/services/epub_service.dart';

void main() {
  group('Document AST Models', () {
    test('TextSegment equality and toString', () {
      const seg1 = TextSegment('Hello', isBold: true);
      const seg2 = TextSegment('Hello', isBold: true);
      const seg3 = TextSegment('Hello', isItalic: true);

      expect(seg1, equals(seg2));
      expect(seg1, isNot(equals(seg3)));
      expect(seg1.toString(), contains('isBold: true'));
    });

    test('ParagraphNode plainText joins segments', () {
      const p = ParagraphNode([
        TextSegment('The '),
        TextSegment('quick ', isBold: true),
        TextSegment('brown fox', isItalic: true),
      ]);

      expect(p.plainText, 'The quick brown fox');
      expect(p.segments.length, 3);
    });

    test('HeadingNode properties and plainText', () {
      const h = HeadingNode(1, [
        TextSegment('Chapter One: '),
        TextSegment('The Beginning', isItalic: true),
      ]);

      expect(h.level, 1);
      expect(h.plainText, 'Chapter One: The Beginning');
    });

    test('ImageNode stores bytes and alt text', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final img = ImageNode(bytes, 'Illustration');

      expect(img.bytes, bytes);
      expect(img.altText, 'Illustration');
    });
  });

  group('EpubParser Unit Tests', () {
    test('parseChapterHtml extracts headings, styled paragraphs, and list items', () {
      const html = '''
<html>
  <body>
    <h1>Main Title</h1>
    <p>This is a <b>bold</b> and <i>italic</i> sentence.</p>
    <ul>
      <li>First item</li>
      <li>Second item</li>
    </ul>
  </body>
</html>
''';

      final nodes = EpubParser.parseChapterHtml(html, null);

      expect(nodes.length, 4);

      // Node 0: Heading 1
      expect(nodes[0], isA<HeadingNode>());
      final h1 = nodes[0] as HeadingNode;
      expect(h1.level, 1);
      expect(h1.plainText, 'Main Title');

      // Node 1: Paragraph with bold and italic segments
      expect(nodes[1], isA<ParagraphNode>());
      final p = nodes[1] as ParagraphNode;
      expect(p.plainText, 'This is a bold and italic sentence.');
      expect(p.segments.any((s) => s.text == 'bold' && s.isBold), isTrue);
      expect(p.segments.any((s) => s.text == 'italic' && s.isItalic), isTrue);

      // Node 2 & 3: List items
      expect(nodes[2], isA<ParagraphNode>());
      expect((nodes[2] as ParagraphNode).plainText, contains('• First item'));
      expect(nodes[3], isA<ParagraphNode>());
      expect((nodes[3] as ParagraphNode).plainText, contains('• Second item'));
    });

    test('parseChapterHtml trims outer whitespace and merges adjacent identical segments', () {
      const html = '<p>   Hello <b>world</b><b>!</b>   </p>';
      final nodes = EpubParser.parseChapterHtml(html, null);

      expect(nodes.length, 1);
      final p = nodes.first as ParagraphNode;
      expect(p.plainText, 'Hello world!');
      // world and ! should be merged into one bold segment
      final boldSegs = p.segments.where((s) => s.isBold).toList();
      expect(boldSegs.length, 1);
      expect(boldSegs.first.text, 'world!');
    });
  });

  group('EpubService & DocumentExtractor Integration Tests', () {
    final epubFile = File('test_assets/alice.epub');
    final pdfFile = File('test_assets/sample.pdf');

    test('EpubService extracts metadata, cover, and TOC from alice.epub', () async {
      if (!epubFile.existsSync()) return;

      final meta = await EpubService.instance.extractMetadata(epubFile.path);
      expect(meta.title, contains('Alice'));
      expect(meta.author, contains('Lewis Carroll'));
      expect(meta.pageCount, greaterThan(0));
      expect(meta.hasCover, isTrue);

      final toc = await EpubService.instance.extractTableOfContents(epubFile.path);
      expect(toc, isNotEmpty);
      expect(toc.first.title, isNotEmpty);
      expect(toc.any((t) => t.title.contains('Rabbit-Hole')), isTrue);
    });

    test('EpubService extracts chapter AST nodes and plain text without synthetic wraps', () async {
      if (!epubFile.existsSync()) return;

      final nodes = await EpubService.instance.extractChapterNodes(epubFile.path, 3);
      expect(nodes, isNotEmpty);
      expect(nodes.any((n) => n is HeadingNode), isTrue);
      expect(nodes.any((n) => n is ParagraphNode), isTrue);

      final page = await EpubService.instance.extractPageText(epubFile.path, 3);
      expect(page.plainText, contains('Down the Rabbit-Hole'));
      expect(page.plainText, contains('Alice was beginning to get very tired'));
    });

    test('DocumentExtractor routes .epub to EpubService and .pdf to MuPdfDocumentService', () async {
      if (!epubFile.existsSync() || !pdfFile.existsSync()) return;

      final epubMeta = await DocumentExtractor.extractMetadata(epubFile.path);
      expect(epubMeta.title, contains('Alice'));

      final pdfMeta = await DocumentExtractor.extractMetadata(pdfFile.path);
      expect(pdfMeta.pageCount, greaterThan(0));
    });
  });
}
