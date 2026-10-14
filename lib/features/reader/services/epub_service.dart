import 'dart:io';
import 'dart:isolate';

import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;

import '../models/document_models.dart';
import 'document_extractor.dart';
import 'document_service.dart';
import 'epub_parser.dart';

/// In-memory cache holding parsed metadata, table of contents, and chapter AST nodes.
class _CachedEpubBook {
  DocumentMetadata? metadata;
  List<TocEntry>? toc;
  final Map<int, List<DocumentNode>> chapterNodes = {};
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

  static final _LruCache<String, _CachedEpubBook> _bookCache =
      _LruCache<String, _CachedEpubBook>(10);
  static final Map<String, Future<DocumentMetadata>> _inFlightMetadataLoads = {};
  static final Map<String, Future<List<TocEntry>>> _inFlightTocLoads = {};
  static final Map<String, Future<Map<int, List<DocumentNode>>>>
      _inFlightChapterLoads = {};

  /// Clears the in-memory book and chapter cache.
  static void clearCache() {
    _bookCache.clear();
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

    final key = '$filePath:$includeCover';
    if (_inFlightMetadataLoads.containsKey(key)) {
      return _inFlightMetadataLoads[key]!;
    }

    final future = Isolate.run(() async {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('EPUB file not found: $filePath');
      }
      final bytes = await file.readAsBytes();
      final bookRef = await EpubParser.openBook(bytes);
      return EpubParser.extractMetadataFromRef(bookRef,
          includeCover: includeCover);
    });

    _inFlightMetadataLoads[key] = future;
    try {
      final metadata = await future;
      final book = _bookCache.get(filePath) ?? _CachedEpubBook();
      book.metadata = metadata;
      _bookCache.put(filePath, book);
      return metadata;
    } finally {
      _inFlightMetadataLoads.remove(key);
    }
  }

  @override
  Future<List<TocEntry>> extractTableOfContents(String filePath) async {
    final cached = _bookCache.get(filePath);
    if (cached?.toc != null) {
      return cached!.toc!;
    }

    if (_inFlightTocLoads.containsKey(filePath)) {
      return _inFlightTocLoads[filePath]!;
    }

    final future = Isolate.run(() async {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('EPUB file not found: $filePath');
      }
      final bytes = await file.readAsBytes();
      final bookRef = await EpubParser.openBook(bytes);
      return EpubParser.extractTableOfContentsFromRef(bookRef);
    });

    _inFlightTocLoads[filePath] = future;
    try {
      final toc = await future;
      final book = _bookCache.get(filePath) ?? _CachedEpubBook();
      book.toc = toc;
      _bookCache.put(filePath, book);
      return toc;
    } finally {
      _inFlightTocLoads.remove(filePath);
    }
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

    final key = '$filePath:$chapterIndex';
    Future<Map<int, List<DocumentNode>>>? inFlight = _inFlightChapterLoads[key];

    if (inFlight == null) {
      inFlight = Isolate.run(() {
        return _parseChaptersIsolate(filePath, chapterIndex);
      });
      _inFlightChapterLoads[key] = inFlight;
    }

    try {
      final parsedMap = await inFlight;
      final book = _bookCache.get(filePath) ?? _CachedEpubBook();
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
    final chapters = await bookRef.getChapters();
    if (chapters.isEmpty) return const {};

    if (requestedIndex < 0 || requestedIndex >= chapters.length) {
      return {requestedIndex: const <DocumentNode>[]};
    }

    final result = <int, List<DocumentNode>>{};

    // Parse all chapters if <= 50, otherwise parse a window around the requested chapter
    final int startIdx;
    final int endIdx;
    if (chapters.length <= 50) {
      startIdx = 0;
      endIdx = chapters.length;
    } else {
      startIdx = (requestedIndex - 2).clamp(0, chapters.length);
      endIdx = (requestedIndex + 4).clamp(0, chapters.length);
    }

    final imageRefs = bookRef.Content?.Images;
    for (var i = startIdx; i < endIdx; i++) {
      result[i] = await _parseChapterContent(chapters[i], imageRefs);
    }

    return result;
  }

  static Future<List<DocumentNode>> _parseChapterContent(
    EpubChapterRef chapter,
    Map<String, dynamic>? imageRefs,
  ) async {
    final html = await chapter.readHtmlContent();

    // Lazy load only images referenced in this chapter's html
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
