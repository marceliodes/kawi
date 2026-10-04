import '../models/document_models.dart';
import 'document_extractor.dart';

/// Abstract interface for extracting metadata, table of contents, and content
/// from documents (PDF, EPUB, etc.).
abstract interface class DocumentService {
  /// Extracts document metadata, page/chapter count, and cover raster (if present).
  Future<DocumentMetadata> extractMetadata(
    String filePath, {
    bool includeCover = true,
  });

  /// Extracts the hierarchical Table of Contents (Outline).
  Future<List<TocEntry>> extractTableOfContents(String filePath);

  /// Extracts plain text and word-level bounding coordinates for a given page or chapter index.
  Future<PageContent> extractPageText(String filePath, int pageIndex);

  /// Extracts semantic document nodes (paragraphs, headings, images) for reflowable chapters.
  Future<List<DocumentNode>> extractChapterNodes(
    String filePath,
    int chapterIndex,
  );
}
