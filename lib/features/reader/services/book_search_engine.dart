import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/document_models.dart';
import '../models/search_models.dart';
import '../providers/document_content_provider.dart';
import 'document_extractor.dart';
import 'epub_parser.dart';

/// Represents an active in-book search operation backed by a background worker isolate.
class BookSearchSession {
  BookSearchSession({
    required this.isolate,
    required this.receivePort,
  });

  final Isolate isolate;
  final ReceivePort receivePort;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  /// Immediately terminates the background isolate and closes communication ports.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

/// Pure-Dart search coordinator that runs full-text EPUB scanning in a background isolate.
class BookSearchEngine {
  const BookSearchEngine._();

  /// Starts a full-text search across all chapters of an EPUB document in a background isolate.
  ///
  /// Matches are mapped to canonical [ReadingAnchor] coordinates and streamed per chapter
  /// via [onBatch] as each chapter completes scanning.
  static Future<BookSearchSession> startSearch({
    required String filePath,
    required SearchQuery query,
    required void Function(SearchResultGroup group) onBatch,
    required void Function(int scanned, int total) onProgress,
    required void Function(int totalMatches, int durationMs) onComplete,
    required void Function(Object error) onError,
  }) async {
    final receivePort = ReceivePort();

    final isolate = await Isolate.spawn(
      _searchWorkerEntryPoint,
      _SearchWorkerPayload(
        filePath: filePath,
        query: query.query,
        caseSensitive: query.caseSensitive,
        wholeWord: query.wholeWord,
        sendPort: receivePort.sendPort,
      ),
    );

    final session = BookSearchSession(
      isolate: isolate,
      receivePort: receivePort,
    );

    receivePort.listen(
      (message) {
        if (session.isCancelled) return;

        if (message is _BatchMessage) {
          onBatch(SearchResultGroup(
            chapterIndex: message.chapterIndex,
            chapterTitle: message.chapterTitle,
            matches: message.matches,
          ));
        } else if (message is _ProgressMessage) {
          onProgress(message.scannedChapters, message.totalChapters);
        } else if (message is _CompleteMessage) {
          onComplete(message.totalMatches, message.durationMs);
          session.cancel();
        } else if (message is _ErrorMessage) {
          onError(message.error);
          session.cancel();
        }
      },
      onError: (err) {
        if (!session.isCancelled) {
          onError(err);
          session.cancel();
        }
      },
    );

    return session;
  }

  /// Worker isolate entry point.
  static Future<void> _searchWorkerEntryPoint(_SearchWorkerPayload payload) async {
    final sw = Stopwatch()..start();
    final sendPort = payload.sendPort;

    try {
      final file = File(payload.filePath);
      if (!file.existsSync()) {
        sendPort.send(_ErrorMessage('File not found: ${payload.filePath}'));
        return;
      }

      final bytes = file.readAsBytesSync();
      final bookRef = await EpubParser.openBook(bytes);
      final toc = await EpubParser.extractTableOfContentsFromRef(bookRef);

      // Resolve chapter list
      final chapters = await bookRef.getChapters();
      final spineItems = bookRef.Schema?.Package?.Spine?.Items ?? const [];
      final totalChapters = chapters.isNotEmpty
          ? chapters.length
          : (spineItems.isNotEmpty ? spineItems.length : 1);

      // Build regex pattern
      final escaped = RegExp.escape(payload.query);
      final patternStr = payload.wholeWord ? r'\b' + escaped + r'\b' : escaped;
      final regex = RegExp(patternStr, caseSensitive: payload.caseSensitive);

      var globalMatchIndex = 0;

      for (var chIdx = 0; chIdx < totalChapters; chIdx++) {
        final chapterTitle = _resolveChapterTitle(toc, chIdx);
        String? html;

        if (chapters.isNotEmpty && chIdx < chapters.length) {
          html = await chapters[chIdx].readHtmlContent();
        } else if (chIdx < spineItems.length) {
          final idRef = spineItems[chIdx].IdRef;
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

        if (html != null && html.trim().isNotEmpty) {
          // Parse HTML text nodes only (passing null for images avoids decompressing image bytes)
          final nodes = EpubParser.parseChapterHtml(html, null);
          final chapterMatches = <SearchMatch>[];

          // Iterate the full node list by index to guarantee exact parity with ReadingAnchor coordinates
          for (var i = 0; i < nodes.length; i++) {
            final node = nodes[i];
            if (node is! ParagraphNode && node is! HeadingNode) {
              continue;
            }

            final plainText = node is ParagraphNode
                ? node.plainText
                : (node as HeadingNode).plainText;
            if (plainText.isEmpty) continue;

            final allMatches = regex.allMatches(plainText);
            for (final m in allMatches) {
              final startOffset = m.start;
              final endOffset = m.end;
              final matchedText = plainText.substring(startOffset, endOffset);

              final snippetData = extractSnippet(
                text: plainText,
                matchStart: startOffset,
                matchEnd: endOffset,
              );

              chapterMatches.add(SearchMatch(
                id: 'c${chIdx}_p${i}_o$startOffset',
                chapterIndex: chIdx,
                chapterTitle: chapterTitle,
                paragraphIndex: i,
                startAnchor: ReadingAnchor(
                  chapterIndex: chIdx,
                  paragraphIndex: i,
                  charOffset: startOffset,
                ),
                endAnchor: ReadingAnchor(
                  chapterIndex: chIdx,
                  paragraphIndex: i,
                  charOffset: endOffset,
                ),
                matchedText: matchedText,
                snippet: snippetData.snippet,
                snippetMatchStart: snippetData.matchStartInSnippet,
                snippetMatchEnd: snippetData.matchEndInSnippet,
                matchIndexInBook: globalMatchIndex++,
              ));
            }
          }

          if (chapterMatches.isNotEmpty) {
            sendPort.send(_BatchMessage(
              chapterIndex: chIdx,
              chapterTitle: chapterTitle,
              matches: chapterMatches,
            ));
          }
        }

        sendPort.send(_ProgressMessage(
          scannedChapters: chIdx + 1,
          totalChapters: totalChapters,
        ));
      }

      sw.stop();
      sendPort.send(_CompleteMessage(
        totalMatches: globalMatchIndex,
        durationMs: sw.elapsedMilliseconds,
      ));
    } catch (e) {
      sendPort.send(_ErrorMessage(e.toString()));
    }
  }

  static String? _resolveChapterTitle(List<TocEntry> toc, int chapterIndex) {
    if (chapterIndex >= 0 && chapterIndex < toc.length) {
      return toc[chapterIndex].title;
    }
    return null;
  }

  /// Extracts contextual text around [matchStart..matchEnd] within [text],
  /// adhering to word boundaries so words are not severed abruptly.
  static ({String snippet, int matchStartInSnippet, int matchEndInSnippet}) extractSnippet({
    required String text,
    required int matchStart,
    required int matchEnd,
    int contextRadius = 40,
  }) {
    if (text.isEmpty ||
        matchStart < 0 ||
        matchEnd > text.length ||
        matchStart >= matchEnd) {
      return (snippet: '', matchStartInSnippet: 0, matchEndInSnippet: 0);
    }

    // 1. Determine snippet start boundary (snap to nearest whitespace if not at start)
    var start = matchStart - contextRadius;
    bool hasLeadingEllipsis = false;
    if (start <= 0) {
      start = 0;
    } else {
      hasLeadingEllipsis = true;
      // Search forward up to 15 chars for whitespace to avoid cutting a word in half
      final searchWindowEnd = (start + 15).clamp(start, matchStart);
      final spaceIdx = text.indexOf(' ', start);
      if (spaceIdx != -1 && spaceIdx <= searchWindowEnd) {
        start = spaceIdx + 1;
      }
    }

    // 2. Determine snippet end boundary (snap to nearest whitespace if not at end)
    var end = matchEnd + contextRadius;
    bool hasTrailingEllipsis = false;
    if (end >= text.length) {
      end = text.length;
    } else {
      hasTrailingEllipsis = true;
      // Search backward up to 15 chars for whitespace
      final searchWindowStart = (end - 15).clamp(matchEnd, end);
      final spaceIdx = text.lastIndexOf(' ', end);
      if (spaceIdx != -1 && spaceIdx >= searchWindowStart) {
        end = spaceIdx;
      }
    }

    final prefix = hasLeadingEllipsis ? '…' : '';
    final suffix = hasTrailingEllipsis ? '…' : '';
    final coreText = text.substring(start, end);
    final snippet = '$prefix$coreText$suffix';

    final matchStartInSnippet = prefix.length + (matchStart - start);
    final matchEndInSnippet = matchStartInSnippet + (matchEnd - matchStart);

    return (
      snippet: snippet,
      matchStartInSnippet: matchStartInSnippet,
      matchEndInSnippet: matchEndInSnippet,
    );
  }
}

class _SearchWorkerPayload {
  const _SearchWorkerPayload({
    required this.filePath,
    required this.query,
    required this.caseSensitive,
    required this.wholeWord,
    required this.sendPort,
  });

  final String filePath;
  final String query;
  final bool caseSensitive;
  final bool wholeWord;
  final SendPort sendPort;
}

class _BatchMessage {
  const _BatchMessage({
    required this.chapterIndex,
    this.chapterTitle,
    required this.matches,
  });

  final int chapterIndex;
  final String? chapterTitle;
  final List<SearchMatch> matches;
}

class _ProgressMessage {
  const _ProgressMessage({
    required this.scannedChapters,
    required this.totalChapters,
  });

  final int scannedChapters;
  final int totalChapters;
}

class _CompleteMessage {
  const _CompleteMessage({
    required this.totalMatches,
    required this.durationMs,
  });

  final int totalMatches;
  final int durationMs;
}

class _ErrorMessage {
  const _ErrorMessage(this.error);
  final String error;
}
