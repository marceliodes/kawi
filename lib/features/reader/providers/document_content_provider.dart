import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document_models.dart';
import '../services/chapter_paginator.dart';
import '../services/document_extractor.dart';

/// Loads and caches the Table of Contents for a document.
final documentTocProvider = FutureProvider.family<List<TocEntry>, String>((
  ref,
  filePath,
) async {
  return DocumentExtractor.extractTableOfContents(filePath);
});

/// Loads and caches page text on-demand for a given document and page index.
///
/// Preserved for backward compatibility with fixed-layout PDF pages.
final documentPageContentProvider =
    FutureProvider.family<PageContent, ({String filePath, int pageIndex})>((
      ref,
      arg,
    ) async {
      return DocumentExtractor.extractPageText(arg.filePath, arg.pageIndex);
    });

/// Loads and caches semantic document AST nodes for a specific chapter.
///
/// For continuous scroll mode, these nodes are rendered directly into a ListView.
final documentChapterNodesProvider =
    FutureProvider.family<List<DocumentNode>, ({String filePath, int chapterIndex})>((
  ref,
  arg,
) async {
  return DocumentExtractor.extractChapterNodes(arg.filePath, arg.chapterIndex);
});

/// Parameters needed to paginate a chapter for a specific viewport.
class PaginationParams {
  const PaginationParams({
    required this.filePath,
    required this.chapterIndex,
    required this.maxWidth,
    required this.maxHeight,
    required this.textStyle,
    required this.paragraphSpacing,
  });

  final String filePath;
  final int chapterIndex;
  final double maxWidth;
  final double maxHeight;
  final TextStyle textStyle;
  final double paragraphSpacing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaginationParams &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          chapterIndex == other.chapterIndex &&
          maxWidth == other.maxWidth &&
          maxHeight == other.maxHeight &&
          textStyle == other.textStyle &&
          paragraphSpacing == other.paragraphSpacing;

  @override
  int get hashCode => Object.hash(
        filePath,
        chapterIndex,
        maxWidth,
        maxHeight,
        textStyle,
        paragraphSpacing,
      );
}

/// Slices and caches the pages for a chapter based on viewport and typography constraints.
final chapterPagesProvider =
    FutureProvider.family<List<PageChunk>, PaginationParams>((
  ref,
  params,
) async {
  final nodes = await ref.watch(
    documentChapterNodesProvider((
      filePath: params.filePath,
      chapterIndex: params.chapterIndex,
    )).future,
  );

  return ChapterPaginator.paginate(
    nodes: nodes,
    maxWidth: params.maxWidth,
    maxHeight: params.maxHeight,
    textStyle: params.textStyle,
    paragraphSpacing: params.paragraphSpacing,
    chapterIndex: params.chapterIndex,
  );
});

/// Reading position anchor within a chapter, used to restore and preserve
/// position across column width, font size, or window resize changes.
class ReadingAnchor {
  const ReadingAnchor({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.charOffset,
  });

  final int chapterIndex;
  final int paragraphIndex;
  final int charOffset;

  @override
  String toString() =>
      'ReadingAnchor(ch: $chapterIndex, P: $paragraphIndex, offset: $charOffset)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingAnchor &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          paragraphIndex == other.paragraphIndex &&
          charOffset == other.charOffset;

  @override
  int get hashCode => Object.hash(chapterIndex, paragraphIndex, charOffset);
}

/// State notifier tracking the active reading position anchor.
class ActiveReadingAnchorNotifier extends Notifier<ReadingAnchor?> {
  @override
  ReadingAnchor? build() => null;

  void updateAnchor({
    required int chapterIndex,
    required int paragraphIndex,
    required int charOffset,
  }) {
    state = ReadingAnchor(
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      charOffset: charOffset,
    );
  }

  /// Locates the page index in [pages] that matches the current anchor.
  int resolvePageForCurrentAnchor(List<PageChunk> pages) {
    final anchor = state;
    if (anchor == null || pages.isEmpty) return 0;
    if (pages.first.chapterIndex != anchor.chapterIndex) return 0;

    return ChapterPaginator.findPageForAnchor(
      pages: pages,
      paragraphIndex: anchor.paragraphIndex,
      charOffset: anchor.charOffset,
    );
  }
}

/// Provider for managing the active reading position anchor.
final activeReadingAnchorProvider =
    NotifierProvider<ActiveReadingAnchorNotifier, ReadingAnchor?>(
  ActiveReadingAnchorNotifier.new,
);
