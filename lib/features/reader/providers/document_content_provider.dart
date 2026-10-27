import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/reader_layout_constants.dart';
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

/// Resolves the chapter title for a specific chapter index from the TOC.
final documentChapterTitleProvider =
    FutureProvider.family<String?, ({String filePath, int chapterIndex})>((
  ref,
  arg,
) async {
  final toc = await ref.watch(documentTocProvider(arg.filePath).future);
  if (toc.isEmpty) return null;

  final flat = <TocEntry>[];
  void flatten(List<TocEntry> list) {
    for (final e in list) {
      flat.add(e);
      if (e.children.isNotEmpty) flatten(e.children);
    }
  }

  flatten(toc);

  // 1. Try exact match on page/chapter index
  for (final entry in flat) {
    if (entry.pageIndex == arg.chapterIndex && entry.title.trim().isNotEmpty) {
      return entry.title.trim();
    }
  }

  final isEpub = arg.filePath.toLowerCase().endsWith('.epub');
  if (isEpub) {
    return null;
  }

  // 2. Fallback to closest preceding TOC entry (for fixed-layout/PDF)
  flat.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
  String? closestTitle;
  for (final entry in flat) {
    if (entry.pageIndex <= arg.chapterIndex && entry.title.trim().isNotEmpty) {
      closestTitle = entry.title.trim();
    } else if (entry.pageIndex > arg.chapterIndex) {
      break;
    }
  }
  return closestTitle;
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
  final file = File(arg.filePath);
  if (!file.existsSync()) {
    int startPage = arg.chapterIndex;
    int endPage = arg.chapterIndex + 1;
    try {
      final tocAsync = ref.watch(documentTocProvider(arg.filePath));
      final toc = tocAsync.asData?.value;
      if (toc != null && toc.isNotEmpty) {
        final flat = <TocEntry>[];
        void flatten(List<TocEntry> list) {
          for (final e in list) {
            flat.add(e);
            if (e.children.isNotEmpty) flatten(e.children);
          }
        }
        flatten(toc);
        flat.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
        int? entryIdx;
        for (var i = 0; i < flat.length; i++) {
          if (flat[i].pageIndex == arg.chapterIndex) {
            entryIdx = i;
            break;
          }
        }
        if (entryIdx == null && arg.chapterIndex < flat.length) {
          entryIdx = arg.chapterIndex;
        }

        if (entryIdx != null) {
          startPage = flat[entryIdx].pageIndex;
          if (entryIdx + 1 < flat.length) {
            endPage = flat[entryIdx + 1].pageIndex;
          } else {
            endPage = startPage + 1;
          }
        }
      }
    } catch (_) {}

    final nodes = <DocumentNode>[];
    for (var p = startPage; p < endPage; p++) {
      try {
        final page = await ref.watch(
          documentPageContentProvider((
            filePath: arg.filePath,
            pageIndex: p,
          )).future,
        );
        if (page.plainText.isEmpty) continue;
        final cleanText = page.plainText
            .replaceAll(RegExp(r'\[image[^\]]*\]', caseSensitive: false), '')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (cleanText.isEmpty) continue;
        final paragraphs = cleanText
            .split(RegExp(r'\n{2,}'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => ParagraphNode([TextSegment(s)]));
        nodes.addAll(paragraphs);
      } catch (_) {}
    }
    return nodes;
  }
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
    this.bottomHeadroom = EpubPaginationMetrics.bottomHeadroom,
  });

  final String filePath;
  final int chapterIndex;
  final double maxWidth;
  final double maxHeight;
  final TextStyle textStyle;
  final double paragraphSpacing;
  final double bottomHeadroom;

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
          paragraphSpacing == other.paragraphSpacing &&
          bottomHeadroom == other.bottomHeadroom;

  @override
  int get hashCode => Object.hash(
        filePath,
        chapterIndex,
        maxWidth,
        maxHeight,
        textStyle,
        paragraphSpacing,
        bottomHeadroom,
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
    bottomHeadroom: params.bottomHeadroom,
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

  ReadingAnchor copyWith({
    int? chapterIndex,
    int? paragraphIndex,
    int? charOffset,
  }) {
    return ReadingAnchor(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      charOffset: charOffset ?? this.charOffset,
    );
  }

  Map<String, dynamic> toJson() => {
    'chapterIndex': chapterIndex,
    'paragraphIndex': paragraphIndex,
    'charOffset': charOffset,
  };

  factory ReadingAnchor.fromJson(Map<String, dynamic> json) => ReadingAnchor(
    chapterIndex: json['chapterIndex'] as int,
    paragraphIndex: json['paragraphIndex'] as int,
    charOffset: json['charOffset'] as int,
  );

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

/// Asynchronously pre-warms adjacent chapter AST nodes in memory
/// for zero-lag scroll transitions.
void prewarmAdjacentChapters(
  WidgetRef ref, {
  required String filePath,
  required int chapterIndex,
  required int totalChapters,
}) {
  final next = chapterIndex + 1;
  final prev = chapterIndex - 1;

  if (next < totalChapters) {
    ref.read(documentChapterNodesProvider((
      filePath: filePath,
      chapterIndex: next,
    )).future);
  }
  if (prev >= 0) {
    ref.read(documentChapterNodesProvider((
      filePath: filePath,
      chapterIndex: prev,
    )).future);
  }
}

