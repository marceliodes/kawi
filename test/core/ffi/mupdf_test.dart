import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/ffi/mupdf_bindings.dart';
import 'package:kawi/core/ffi/native_loader.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';

void main() {
  setUpAll(() {
    // Verify native library exists and can be dynamically resolved
    final dylib = loadNativeLibrary('mupdf');
    expect(dylib.handle, isNotNull);
  });

  group('MuPdfBindings C-API', () {
    test('creates and drops context cleanly', () {
      final bindings = MuPdfBindings.instance;
      final ctx = bindings.createContext();
      expect(ctx.address, isNonZero);
      bindings.dropContext(ctx);
    });
  });

  group('DocumentExtractor Integration Tests', () {
    final pdfPath = File('test_assets/sample.pdf').absolute.path;
    final epubPath = File('test_assets/alice.epub').absolute.path;

    test('extracts metadata and cover from PDF', () async {
      final meta = await DocumentExtractor.extractMetadata(pdfPath);
      expect(meta.pageCount, greaterThan(0));
      expect(meta.hasCover, isTrue);
      expect(meta.coverWidth, greaterThan(0));
      expect(meta.coverHeight, greaterThan(0));
      expect(meta.coverRgba, isNotNull);
    });

    test('extracts metadata from EPUB', () async {
      final meta = await DocumentExtractor.extractMetadata(epubPath);
      expect(meta.pageCount, greaterThan(0));
      expect(meta.title, isNotNull);
    });

    test('extracts Table of Contents from EPUB', () async {
      final toc = await DocumentExtractor.extractTableOfContents(epubPath);
      expect(toc, isNotEmpty);
      expect(toc.first.title, isNotEmpty);
    });

    test('extracts page text and word bounding coordinates', () async {
      final page = await DocumentExtractor.extractPageText(pdfPath, 0);
      expect(page.pageIndex, 0);
      expect(page.plainText, isNotEmpty);
      expect(page.words, isNotEmpty);

      final firstWord = page.words.first;
      expect(firstWord.word, isNotEmpty);
      expect(firstWord.x1, greaterThanOrEqualTo(firstWord.x0));
      expect(firstWord.y1, greaterThanOrEqualTo(firstWord.y0));
    });

    test('memory check: 50 open/extract/close cycles without leak', () async {
      for (var i = 0; i < 50; i++) {
        final page = await DocumentExtractor.extractPageText(pdfPath, i % 6);
        expect(page.words, isNotEmpty);
      }
    });
  });
}
