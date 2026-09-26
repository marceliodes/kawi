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
                coverRgba = Uint8List.fromList(
                  samplesPtr.asTypedList(sampleBytesCount),
                );
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
          return _parseOutlineList(outline);
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

  static List<TocEntry> _parseOutlineList(Pointer<FzOutline> outline) {
    final entries = <TocEntry>[];
    var current = outline;

    while (current != nullptr) {
      final ref = current.ref;
      final title = ref.title != nullptr ? ref.title.toDartString() : '';
      final uri = ref.uri != nullptr ? ref.uri.toDartString() : null;
      final pageIndex = ref.page.page;

      final children = ref.down != nullptr
          ? _parseOutlineList(ref.down)
          : const <TocEntry>[];

      entries.add(
        TocEntry(
          title: title,
          pageIndex: pageIndex,
          uri: uri,
          children: children,
        ),
      );

      current = ref.next;
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
          throw ArgumentError('Invalid page index: $pageIndex');
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

            // 2. Structured word coordinates
            final words = _extractWordsFromStext(stextPage);

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

  static List<WordBounds> _extractWordsFromStext(
    Pointer<FzStextPage> stextPage,
  ) {
    final words = <WordBounds>[];
    final structPtr = stextPage.cast<FzStextPageStruct>();
    var blockPtr = structPtr.ref.firstBlock;

    while (blockPtr != nullptr) {
      final block = blockPtr.ref;
      if (block.type == 0) {
        // Text block
        var linePtr = block.firstLine;
        while (linePtr != nullptr) {
          final line = linePtr.ref;
          var charPtr = line.firstChar;

          final currentWordChars = <int>[];
          double wordX0 = double.infinity;
          double wordY0 = double.infinity;
          double wordX1 = -double.infinity;
          double wordY1 = -double.infinity;

          void flushWord() {
            if (currentWordChars.isNotEmpty) {
              final wordStr = String.fromCharCodes(currentWordChars).trim();
              if (wordStr.isNotEmpty) {
                words.add(
                  WordBounds(
                    word: wordStr,
                    x0: wordX0,
                    y0: wordY0,
                    x1: wordX1,
                    y1: wordY1,
                  ),
                );
              }
              currentWordChars.clear();
              wordX0 = double.infinity;
              wordY0 = double.infinity;
              wordX1 = -double.infinity;
              wordY1 = -double.infinity;
            }
          }

          while (charPtr != nullptr) {
            final ch = charPtr.ref;
            final c = ch.c;

            if (c <= 32) {
              // Space or whitespace delimiter
              flushWord();
            } else {
              currentWordChars.add(c);
              final q = ch.quad;
              final minX = _min4(q.ul.x, q.ur.x, q.ll.x, q.lr.x);
              final maxX = _max4(q.ul.x, q.ur.x, q.ll.x, q.lr.x);
              final minY = _min4(q.ul.y, q.ur.y, q.ll.y, q.lr.y);
              final maxY = _max4(q.ul.y, q.ur.y, q.ll.y, q.lr.y);

              if (minX < wordX0) wordX0 = minX;
              if (minY < wordY0) wordY0 = minY;
              if (maxX > wordX1) wordX1 = maxX;
              if (maxY > wordY1) wordY1 = maxY;
            }
            charPtr = ch.next;
          }
          flushWord();

          linePtr = line.next;
        }
      }
      blockPtr = block.next;
    }

    return words;
  }

  static double _min4(double a, double b, double c, double d) {
    double m = a < b ? a : b;
    if (c < m) m = c;
    if (d < m) m = d;
    return m;
  }

  static double _max4(double a, double b, double c, double d) {
    double m = a > b ? a : b;
    if (c > m) m = c;
    if (d > m) m = d;
    return m;
  }
}
