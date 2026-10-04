import 'dart:io';
import 'dart:isolate';

import '../models/document_models.dart';
import 'document_extractor.dart';
import 'document_service.dart';
import 'epub_parser.dart';

/// Pure-Dart implementation of [DocumentService] for reflowable EPUB documents.
class EpubService implements DocumentService {
  const EpubService();

  static const EpubService instance = EpubService();

  @override
  Future<DocumentMetadata> extractMetadata(
    String filePath, {
    bool includeCover = true,
  }) {
    return Isolate.run(() async {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('EPUB file not found: $filePath');
      }
      final bytes = await file.readAsBytes();
      final book = await EpubParser.parseBook(bytes);
      return EpubParser.extractMetadata(book, includeCover: includeCover);
    });
  }

  @override
  Future<List<TocEntry>> extractTableOfContents(String filePath) {
    return Isolate.run(() async {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('EPUB file not found: $filePath');
      }
      final bytes = await file.readAsBytes();
      final book = await EpubParser.parseBook(bytes);
      return EpubParser.extractTableOfContents(book);
    });
  }

  @override
  Future<List<DocumentNode>> extractChapterNodes(
    String filePath,
    int chapterIndex,
  ) {
    return Isolate.run(() async {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('EPUB file not found: $filePath');
      }
      final bytes = await file.readAsBytes();
      final book = await EpubParser.parseBook(bytes);
      final chapters = book.Chapters ?? const [];
      if (chapterIndex < 0 || chapterIndex >= chapters.length) {
        return const <DocumentNode>[];
      }
      final chapter = chapters[chapterIndex];
      return EpubParser.parseChapterHtml(
        chapter.HtmlContent ?? '',
        book.Content?.Images,
      );
    });
  }

  @override
  Future<PageContent> extractPageText(String filePath, int pageIndex) async {
    final nodes = await extractChapterNodes(filePath, pageIndex);
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

    return PageContent(
      pageIndex: pageIndex,
      plainText: buffer.toString(),
      words: const [],
    );
  }
}
