import 'dart:io';
import 'dart:isolate';

import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/document_models.dart';
import 'document_extractor.dart';
import 'document_service.dart';
import 'epub_parser.dart';

/// In-memory cache holding parsed metadata, table of contents, and chapter AST nodes.
class CachedEpub {
  DocumentMetadata? metadata;
  List<TocEntry>? toc;
  final Map<int, List<DocumentNode>> chapterNodes = {};
}

class _InitialEpubData {
  const _InitialEpubData({
    required this.metadata,
    required this.toc,
    required this.chapterNodes,
  });

  final DocumentMetadata metadata;
  final List<TocEntry> toc;
  final Map<int, List<DocumentNode>> chapterNodes;
}

/// Simple Least-Recently-Used (LRU) cache.
class _LruCache<K, V> {
  _LruCache(this.maximumSize);

  final int maximumSize;
  final Map<K, V> _map = {};

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    if (_map.length >= maximumSize) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  bool containsKey(K key) => _map.containsKey(key);

  void clear() => _map.clear();
}

/// Pure-Dart implementation of [DocumentService] for reflowable EPUB documents.
///
/// Features an in-memory LRU cache keyed by file path and delegates heavy file
/// I/O and ZIP/XML parsing to background isolates via [Isolate.run].
class EpubService implements DocumentService {
  const EpubService();

  static const EpubService instance = EpubService();

  static final _LruCache<String, CachedEpub> _bookCache =
      _LruCache<String, CachedEpub>(10);
  static final Map<String, Future<CachedEpub>> _openingFutures = {};
  static final Map<String, int> _pendingChapterIndexes = {};
  static final Map<String, Future<Map<int, List<DocumentNode>>>>
      _inFlightChapterLoads = {};

  /// Clears the in-memory book and chapter cache as well as in-flight opening locks.
  static void clearCache() {
    _bookCache.clear();
    _openingFutures.clear();
    _pendingChapterIndexes.clear();
    _inFlightChapterLoads.clear();
  }

  /// Extracts the original cover image bytes (.jpg/.png/.webp) directly from the
  /// EPUB ZIP archive without decoding the image into raw pixels.
  Future<Uint8List?> extractEpubCoverBytes(String filePath) {
    return EpubParser.extractEpubCoverBytes(filePath);
  }

  /// Opens an EPUB with single-flight locking, parsing the OPF spine/TOC and only the initial chapter.
  Future<CachedEpub> openEpub(
    String filePath, {
    int initialChapterIndex = 0,
    bool includeCover = false,
  }) {
    _pendingChapterIndexes[filePath] ??= initialChapterIndex;
    if (initialChapterIndex != 0) {
      _pendingChapterIndexes[filePath] = initialChapterIndex;
    }

    final cached = _bookCache.get(filePath);
    if (cached != null &&
        cached.metadata != null &&
        (!includeCover || cached.metadata!.coverRgba != null) &&
        cached.toc != null &&
        cached.chapterNodes.containsKey(initialChapterIndex)) {
      return Future.value(cached);
    }

    final inFlight = _openingFutures[filePath];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _doOpenEpub(
      filePath,
      initialChapterIndex: initialChapterIndex,
      includeCover: includeCover,
    );
    _openingFutures[filePath] = future;
    return future;
  }

  Future<CachedEpub> _doOpenEpub(
    String filePath, {
    int initialChapterIndex = 0,
    bool includeCover = false,
  }) async {
    final sw = Stopwatch()..start();
    try {
      await Future.microtask(() {});
      final targetChapter =
          _pendingChapterIndexes[filePath] ?? initialChapterIndex;
      final initialData = await Isolate.run(() => _openInitialEpubIsolate(
            filePath,
            targetChapter,
            includeCover,
          ));

      final book = _bookCache.get(filePath) ?? CachedEpub();
      book.metadata = initialData.metadata;
      book.toc = initialData.toc;
      book.chapterNodes.addAll(initialData.chapterNodes);
      _bookCache.put(filePath, book);

      sw.stop();
      debugPrint('>>> [EPUB OPEN] Loaded initial chapter in ${sw.elapsedMilliseconds}ms');
      return book;
    } finally {
      _openingFutures.remove(filePath);
      _pendingChapterIndexes.remove(filePath);
    }
  }

  static Future<_InitialEpubData> _openInitialEpubIsolate(
    String filePath,
    int initialChapterIndex,
    bool includeCover,
  ) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('EPUB file not found: $filePath');
    }
    final bytes = await file.readAsBytes();
    final bookRef = await EpubParser.openBook(bytes);

    final metadata = await EpubParser.extractMetadataFromRef(
      bookRef,
      includeCover: includeCover,
    );
    final toc = await EpubParser.extractTableOfContentsFromRef(bookRef);

    final chapterMap = await _extractSingleChapterFromRef(
      bookRef,
      initialChapterIndex,
    );

    return _InitialEpubData(
      metadata: metadata,
      toc: toc,
      chapterNodes: chapterMap,
    );
  }

  @override
  Future<DocumentMetadata> extractMetadata(
    String filePath, {
    bool includeCover = true,
  }) async {
    final cached = _bookCache.get(filePath);
    if (cached?.metadata != null &&
        (!includeCover ||
            cached!.metadata!.hasCover ||
            cached.metadata!.coverRgba != null)) {
      return cached!.metadata!;
    }

    final book = await openEpub(
      filePath,
      includeCover: includeCover,
    );
    return book.metadata ??
        const DocumentMetadata(
          title: null,
          author: null,
          pageCount: 1,
        );
  }

  @override
  Future<List<TocEntry>> extractTableOfContents(String filePath) async {
    final cached = _bookCache.get(filePath);
    if (cached?.toc != null) {
      return cached!.toc!;
    }

    final book = await openEpub(filePath);
    return book.toc ?? const <TocEntry>[];
  }

  @override
  Future<List<DocumentNode>> extractChapterNodes(
    String filePath,
    int chapterIndex,
  ) async {
    final cached = _bookCache.get(filePath);
    if (cached != null && cached.chapterNodes.containsKey(chapterIndex)) {
      return cached.chapterNodes[chapterIndex]!;
    }

    _pendingChapterIndexes[filePath] = chapterIndex;
    if (!_bookCache.containsKey(filePath) &&
        !_openingFutures.containsKey(filePath)) {
      final book = await openEpub(filePath, initialChapterIndex: chapterIndex);
      return book.chapterNodes[chapterIndex] ?? const <DocumentNode>[];
    }

    if (_openingFutures.containsKey(filePath)) {
      final book = await _openingFutures[filePath]!;
      if (book.chapterNodes.containsKey(chapterIndex)) {
        return book.chapterNodes[chapterIndex]!;
      }
    }

    final key = '$filePath:$chapterIndex';
    Future<Map<int, List<DocumentNode>>>? inFlight = _inFlightChapterLoads[key];

    if (inFlight == null) {
      inFlight = Isolate.run(() => _parseChaptersIsolate(filePath, chapterIndex));
      _inFlightChapterLoads[key] = inFlight;
    }

    try {
      final parsedMap = await inFlight;
      final book = _bookCache.get(filePath) ?? CachedEpub();
      book.chapterNodes.addAll(parsedMap);
      _bookCache.put(filePath, book);
      return book.chapterNodes[chapterIndex] ?? const <DocumentNode>[];
    } finally {
      _inFlightChapterLoads.remove(key);
    }
  }

  static Future<Map<int, List<DocumentNode>>> _parseChaptersIsolate(
    String filePath,
    int requestedIndex,
  ) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('EPUB file not found: $filePath');
    }
    final bytes = await file.readAsBytes();
    final bookRef = await EpubParser.openBook(bytes);
    return _extractSingleChapterFromRef(bookRef, requestedIndex);
  }

  static Future<Map<int, List<DocumentNode>>> _extractSingleChapterFromRef(
    EpubBookRef bookRef,
    int requestedIndex,
  ) async {
    final chapters = await bookRef.getChapters();
    String? html;

    if (chapters.isNotEmpty &&
        requestedIndex >= 0 &&
        requestedIndex < chapters.length) {
      html = await chapters[requestedIndex].readHtmlContent();
    } else {
      final spineItems = bookRef.Schema?.Package?.Spine?.Items ?? const [];
      if (requestedIndex >= 0 && requestedIndex < spineItems.length) {
        final idRef = spineItems[requestedIndex].IdRef;
        final manifestItem = bookRef.Schema?.Package?.Manifest?.Items
            ?.where((m) => m.Id == idRef)
            .firstOrNull;
        if (manifestItem != null && manifestItem.Href != null) {
          final href = manifestItem.Href!;
          final cleanHref = href.split('?').first.split('#').first;
          final decoded = Uri.decodeFull(cleanHref);
          final base = p.basename(decoded).toLowerCase();
          final htmlFiles = bookRef.Content?.Html ?? const {};
          final fileRef = htmlFiles[href] ??
              htmlFiles[cleanHref] ??
              htmlFiles[decoded] ??
              htmlFiles.values.where((f) =>
                  f.FileName == href ||
                  f.FileName == cleanHref ||
                  f.FileName == decoded ||
                  (f.FileName != null &&
                      p.basename(f.FileName!).toLowerCase() == base)).firstOrNull;
          if (fileRef != null) {
            html = await fileRef.readContentAsText();
          }
        }
      }
    }

    if (html == null || html.trim().isEmpty) {
      return {requestedIndex: const <DocumentNode>[]};
    }

    final imageRefs = bookRef.Content?.Images;
    final result = <int, List<DocumentNode>>{};
    result[requestedIndex] = await _parseChapterContent(html, imageRefs);
    return result;
  }

  static Future<List<DocumentNode>> _parseChapterContent(
    String html,
    Map<String, dynamic>? imageRefs,
  ) async {
    // Lazy-decompress ONLY images directly referenced inside this single chapter's HTML
    final imageBytesMap = <String, List<int>>{};
    if (imageRefs != null && imageRefs.isNotEmpty) {
      final imageRegex = RegExp(
        r'''(?:src|href|xlink:href)\s*=\s*["']([^"']+\.(?:png|jpe?g|gif|webp|svg|bmp)(?:\?[^"']*)?)["']''',
        caseSensitive: false,
      );

      final matches = imageRegex.allMatches(html);
      if (matches.isNotEmpty) {
        final referencedSrcs = <String>{};
        for (final m in matches) {
          final src = m.group(1);
          if (src != null && src.trim().isNotEmpty) {
            referencedSrcs.add(src.trim());
          }
        }

        for (final src in referencedSrcs) {
          final clean = src.split('?').first.split('#').first.trim();
          final decoded = Uri.decodeFull(clean);
          final base = p.basename(decoded);
          final lowerBase = base.toLowerCase();
          final lowerClean = clean.toLowerCase();
          final lowerDecoded = decoded.toLowerCase();

          dynamic matchedRef = imageRefs[src] ??
              imageRefs[clean] ??
              imageRefs[decoded];

          if (matchedRef == null) {
            for (final entry in imageRefs.entries) {
              final key = entry.key;
              final lowerKey = key.toLowerCase();
              if (lowerKey == lowerClean ||
                  lowerKey == lowerDecoded ||
                  lowerKey.endsWith('/$lowerClean') ||
                  lowerKey.endsWith('/$lowerDecoded') ||
                  p.basename(key).toLowerCase() == lowerBase) {
                matchedRef = entry.value;
                break;
              }
            }
          }

          if (matchedRef != null) {
            try {
              final bytes = await matchedRef.readContentAsBytes();
              imageBytesMap[src] = bytes;
              imageBytesMap[clean] = bytes;
              imageBytesMap[decoded] = bytes;
              imageBytesMap[base] = bytes;
              imageBytesMap[lowerBase] = bytes;
            } catch (_) {}
          }
        }
      }
    }

    return EpubParser.parseChapterHtml(
      html,
      null,
      imageBytes: imageBytesMap,
    );
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
