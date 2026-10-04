import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/document_models.dart';
import 'document_service.dart';
import 'epub_service.dart';
import 'mupdf_document_service.dart';

class DocumentMetadata {
  const DocumentMetadata({
    required this.title,
    required this.author,
    required this.pageCount,
    this.coverRgba,
    this.coverWidth,
    this.coverHeight,
  });

  final String? title;
  final String? author;
  final int pageCount;
  final Uint8List? coverRgba;
  final int? coverWidth;
  final int? coverHeight;

  bool get hasCover =>
      coverRgba != null && (coverWidth ?? 0) > 0 && (coverHeight ?? 0) > 0;
}

class TocEntry {
  const TocEntry({
    required this.title,
    required this.pageIndex,
    this.uri,
    this.children = const [],
  });

  final String title;
  final int pageIndex;
  final String? uri;
  final List<TocEntry> children;
}

class WordBounds {
  const WordBounds({
    required this.word,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  final String word;
  final double x0;
  final double y0;
  final double x1;
  final double y1;
}

class PageContent {
  const PageContent({
    required this.pageIndex,
    required this.plainText,
    required this.words,
  });

  final int pageIndex;
  final String plainText;
  final List<WordBounds> words;
}

/// Headless document extraction gateway that delegates to the appropriate
/// [DocumentService] based on file format (e.g., [EpubService] for EPUBs,
/// [MuPdfDocumentService] for PDFs).
abstract final class DocumentExtractor {
  static DocumentService _serviceFor(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    if (ext == '.epub') {
      return EpubService.instance;
    }
    return MuPdfDocumentService.instance;
  }

  /// Extracts document metadata, page/chapter count, and cover raster (if present).
  static Future<DocumentMetadata> extractMetadata(
    String filePath, {
    bool includeCover = true,
  }) {
    return _serviceFor(filePath).extractMetadata(
      filePath,
      includeCover: includeCover,
    );
  }

  /// Extracts the hierarchical Table of Contents (Outline).
  static Future<List<TocEntry>> extractTableOfContents(String filePath) {
    return _serviceFor(filePath).extractTableOfContents(filePath);
  }

  /// Extracts the plain text and word-level bounding coordinates for [pageIndex].
  static Future<PageContent> extractPageText(String filePath, int pageIndex) {
    return _serviceFor(filePath).extractPageText(filePath, pageIndex);
  }

  /// Extracts semantic document nodes (paragraphs, headings, images) for reflowable chapters.
  static Future<List<DocumentNode>> extractChapterNodes(
    String filePath,
    int chapterIndex,
  ) {
    return _serviceFor(filePath).extractChapterNodes(filePath, chapterIndex);
  }
}
