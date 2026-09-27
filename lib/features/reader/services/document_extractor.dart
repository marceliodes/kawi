import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../core/ffi/mupdf_bindings.dart';

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

/// Headless document extraction service that offloads native parsing
/// onto background Dart worker isolates (via [Isolate.run]).
abstract final class DocumentExtractor {
  /// Extracts document metadata, page count, and cover raster (if present).
  static Future<DocumentMetadata> extractMetadata(
    String filePath, {
    bool includeCover = true,
  }) {
    return Isolate.run(() => _extractMetadataSync(filePath, includeCover));
  }

  /// Extracts the hierarchical Table of Contents (Outline).
  static Future<List<TocEntry>> extractTableOfContents(String filePath) {
    return Isolate.run(() => _extractTableOfContentsSync(filePath));
  }

  /// Extracts the plain text and word-level bounding coordinates for [pageIndex].
  static Future<PageContent> extractPageText(String filePath, int pageIndex) {
    return Isolate.run(() => _extractPageTextSync(filePath, pageIndex));
  }

  // --- Synchronous worker routines (executed strictly inside isolates) ---

  static DocumentMetadata _extractMetadataSync(
    String filePath,
    bool includeCover,
  ) {
    final bindings = MuPdfBindings.instance;
    final ctx = bindings.createContext();
    try {
      final pathUtf8 = filePath.toNativeUtf8();
      Pointer<FzDocument> doc = nullptr;
      try {
        doc = bindings.fzOpenDocument(ctx, pathUtf8);
        if (doc == nullptr) {
          throw StateError('Failed to open document: $filePath');
        }

        final pageCount = bindings.fzCountPages(ctx, doc);

        // Extract Title & Author
        String? title;
        String? author;

        final buf = calloc<Uint8>(1024).cast<Utf8>();
        final keyTitle = 'info:Title'.toNativeUtf8();
        final keyAuthor = 'info:Author'.toNativeUtf8();
        try {
          final titleLen = bindings.fzLookupMetadata(
            ctx,
            doc,
            keyTitle,
            buf,
            1024,
          );
          if (titleLen > 0) {
            title = buf.toDartString();
          }

          final authorLen = bindings.fzLookupMetadata(
            ctx,
            doc,
            keyAuthor,
            buf,
            1024,
          );
          if (authorLen > 0) {
            author = buf.toDartString();
          }
        } finally {
          calloc.free(buf);
          calloc.free(keyTitle);
          calloc.free(keyAuthor);
        }

        // Extract Cover raster from page 0
        Uint8List? coverRgba;
        int? coverWidth;
        int? coverHeight;

        if (includeCover && pageCount > 0) {
          final ctm = calloc<FzMatrix>();
          try {
            FzMatrix.setIdentity(ctm);
            // Default 72 DPI scale
            final cs = bindings.fzDeviceRgb(ctx);
            final pixmap = bindings.fzNewPixmapFromPageNumber(
              ctx,
              doc,
              0,
              ctm.ref,
              cs,
              1, // alpha channel
            );

            if (pixmap != nullptr) {
              try {
                coverWidth = bindings.fzPixmapWidth(ctx, pixmap);
                coverHeight = bindings.fzPixmapHeight(ctx, pixmap);
                final sampleBytesCount = coverWidth * coverHeight * 4;
                final samplesPtr = bindings.fzPixmapSamples(ctx, pixmap);
                if (samplesPtr != nullptr &&
                    coverWidth > 0 &&
                    coverHeight > 0) {
                  coverRgba = Uint8List.fromList(
                    samplesPtr.asTypedList(sampleBytesCount),
                  );
                }
              } finally {
                bindings.fzDropPixmap(ctx, pixmap);
              }
            }
          } finally {
            calloc.free(ctm);
          }
        }

        return DocumentMetadata(
          title: title,
          author: author,
          pageCount: pageCount,
          coverRgba: coverRgba,
          coverWidth: coverWidth,
          coverHeight: coverHeight,
        );
      } finally {
        if (doc != nullptr) {
          bindings.fzDropDocument(ctx, doc);
        }
        calloc.free(pathUtf8);
      }
    } finally {
      bindings.dropContext(ctx);
    }
  }

  static List<TocEntry> _extractTableOfContentsSync(String filePath) {
    final bindings = MuPdfBindings.instance;
    final ctx = bindings.createContext();
    try {
      final pathUtf8 = filePath.toNativeUtf8();
      Pointer<FzDocument> doc = nullptr;
      try {
        doc = bindings.fzOpenDocument(ctx, pathUtf8);
        if (doc == nullptr) {
          throw StateError('Failed to open document: $filePath');
        }

        final outline = bindings.fzLoadOutline(ctx, doc);
        if (outline == nullptr) {
          return const [];
        }

        try {
          return _parseOutlineList(bindings, ctx, doc, outline);
        } finally {
          bindings.fzDropOutline(ctx, outline);
        }
      } finally {
        if (doc != nullptr) {
          bindings.fzDropDocument(ctx, doc);
        }
        calloc.free(pathUtf8);
      }
    } finally {
      bindings.dropContext(ctx);
    }
  }

  static List<TocEntry> _parseOutlineList(
    MuPdfBindings bindings,
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    Pointer<FzOutline> outline,
  ) {
    final entries = <TocEntry>[];
    var current = outline;

    while (current != nullptr) {
      final titlePtr = bindings.kawiOutlineTitle(current);
      final uriPtr = bindings.kawiOutlineUri(current);
      final title = titlePtr != nullptr ? titlePtr.toDartString() : '';
      final rawUri = uriPtr != nullptr ? uriPtr.toDartString() : null;
      final uri = rawUri != null && rawUri.isNotEmpty ? rawUri : null;

      var pageIndex = bindings.kawiOutlinePageNumber(ctx, doc, current);

      final down = bindings.kawiOutlineDown(current);
      final children = down != nullptr
          ? _parseOutlineList(bindings, ctx, doc, down)
          : const <TocEntry>[];

      // If a container item lacks a direct target, inherit its first child's page index
      if (pageIndex < 0 && children.isNotEmpty) {
        pageIndex = children.first.pageIndex;
      }

      entries.add(
        TocEntry(
          title: title,
          pageIndex: pageIndex,
          uri: uri,
          children: children,
        ),
      );

      current = bindings.kawiOutlineNext(current);
    }

    return entries;
  }

  static PageContent _extractPageTextSync(String filePath, int pageIndex) {
    final bindings = MuPdfBindings.instance;
    final ctx = bindings.createContext();
    try {
      final pathUtf8 = filePath.toNativeUtf8();
      Pointer<FzDocument> doc = nullptr;
      try {
        doc = bindings.fzOpenDocument(ctx, pathUtf8);
        if (doc == nullptr) {
          throw StateError('Failed to open document: $filePath');
        }

        final page = bindings.fzLoadPage(ctx, doc, pageIndex);
        if (page == nullptr) {
          return PageContent(
            pageIndex: pageIndex,
            plainText: '',
            words: const [],
          );
        }

        try {
          final stextPage = bindings.fzNewStextPageFromPage(ctx, page, nullptr);
          if (stextPage == nullptr) {
            return PageContent(
              pageIndex: pageIndex,
              plainText: '',
              words: const [],
            );
          }

          try {
            // 1. Plain text via buffer
            String plainText = '';
            final buffer = bindings.fzNewBufferFromStextPage(ctx, stextPage);
            if (buffer != nullptr) {
              try {
                final strPtr = bindings.fzStringFromBuffer(ctx, buffer);
                if (strPtr != nullptr) {
                  plainText = strPtr.toDartString();
                }
              } finally {
                bindings.fzDropBuffer(ctx, buffer);
              }
            }

            // 2. Structured word coordinates via safe native C extraction
            final words = <WordBounds>[];
            final wordsPtrPtr = calloc<Pointer<KawiWord>>();
            try {
              final count = bindings.kawiExtractWords(
                ctx,
                stextPage,
                wordsPtrPtr,
              );
              final wordsPtr = wordsPtrPtr.value;
              if (wordsPtr != nullptr && count > 0) {
                try {
                  for (var i = 0; i < count; i++) {
                    final kw = wordsPtr[i];
                    final wordText = kw.wordString.trim();
                    if (wordText.isNotEmpty) {
                      words.add(
                        WordBounds(
                          word: wordText,
                          x0: kw.x0,
                          y0: kw.y0,
                          x1: kw.x1,
                          y1: kw.y1,
                        ),
                      );
                    }
                  }
                } finally {
                  bindings.kawiFreeWords(wordsPtr);
                }
              }
            } finally {
              calloc.free(wordsPtrPtr);
            }

            return PageContent(
              pageIndex: pageIndex,
              plainText: plainText,
              words: words,
            );
          } finally {
            bindings.fzDropStextPage(ctx, stextPage);
          }
        } finally {
          bindings.fzDropPage(ctx, page);
        }
      } finally {
        if (doc != nullptr) {
          bindings.fzDropDocument(ctx, doc);
        }
        calloc.free(pathUtf8);
      }
    } finally {
      bindings.dropContext(ctx);
    }
  }
}
