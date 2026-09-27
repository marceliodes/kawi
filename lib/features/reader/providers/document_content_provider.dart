import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/document_extractor.dart';

/// Loads and caches the Table of Contents for a document.
final documentTocProvider = FutureProvider.family<List<TocEntry>, String>((
  ref,
  filePath,
) async {
  return DocumentExtractor.extractTableOfContents(filePath);
});

/// Loads and caches page text on-demand for a given document and page index.
final documentPageContentProvider =
    FutureProvider.family<PageContent, ({String filePath, int pageIndex})>((
      ref,
      arg,
    ) async {
      return DocumentExtractor.extractPageText(arg.filePath, arg.pageIndex);
    });
