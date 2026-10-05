import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

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
      final bookRef = await EpubParser.openBook(bytes);
      return EpubParser.extractMetadataFromRef(bookRef, includeCover: includeCover);
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
      final bookRef = await EpubParser.openBook(bytes);
      return EpubParser.extractTableOfContentsFromRef(bookRef);
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
      final bookRef = await EpubParser.openBook(bytes);
      final chapters = await bookRef.getChapters();
      if (chapterIndex < 0 || chapterIndex >= chapters.length) {
        return const <DocumentNode>[];
      }
      final chapter = chapters[chapterIndex];
      final html = await chapter.readHtmlContent();

      // Lazy load only images referenced in this chapter's html
      final imageRefs = bookRef.Content?.Images;
      final imageBytesMap = <String, List<int>>{};
      if (imageRefs != null && imageRefs.isNotEmpty) {
        final lowerHtml = html.toLowerCase();
        for (final entry in imageRefs.entries) {
          final key = entry.key;
          final filename = p.basename(key);
          final decodedKey = Uri.decodeFull(key);
          final decodedFilename = p.basename(decodedKey);

          final isReferenced = lowerHtml.contains(key.toLowerCase()) ||
              lowerHtml.contains(filename.toLowerCase()) ||
              lowerHtml.contains(decodedKey.toLowerCase()) ||
              lowerHtml.contains(decodedFilename.toLowerCase());

          if (isReferenced) {
            try {
              final imgBytes = await entry.value.readContentAsBytes();
              imageBytesMap[key] = imgBytes;
              imageBytesMap[filename] = imgBytes;
              if (decodedKey != key) {
                imageBytesMap[decodedKey] = imgBytes;
              }
              if (decodedFilename != filename) {
                imageBytesMap[decodedFilename] = imgBytes;
              }
            } catch (_) {}
          }
        }
      }

      return EpubParser.parseChapterHtml(
        html,
        null,
        imageBytes: imageBytesMap,
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
