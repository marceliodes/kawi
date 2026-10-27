import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../models/bookmark.dart';
import '../models/document_models.dart';
import 'document_content_provider.dart';

/// Reactive stream of bookmarks for a specific document, ordered chronologically (newest first).
final bookmarksStreamProvider =
    StreamProvider.family<List<Bookmark>, String>((ref, documentId) {
  final db = ref.watch(databaseProvider);
  return db.watchBookmarksForDocument(documentId).map(
        (rows) => rows.map(Bookmark.fromEntry).toList(),
      );
});

/// Controller handling bookmark operations (toggle, add, remove).
class BookmarksController {
  BookmarksController(this._ref);
  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  /// Toggles bookmark state for the current active position.
  /// If [existingBookmarkOnPage] is provided or a bookmark exists at [anchor], it is removed.
  /// Otherwise a new bookmark is created with [snippet] and [chapterTitle].
  Future<String> toggleBookmark({
    required String documentId,
    required ReadingAnchor anchor,
    Bookmark? existingBookmarkOnPage,
    String? chapterTitle,
    required String snippet,
    String? note,
  }) async {
    if (existingBookmarkOnPage != null) {
      await _db.deleteBookmark(existingBookmarkOnPage.id);
      return 'removed';
    }

    final bookmarks = await _db.getBookmarksForDocument(documentId);
    final existing = bookmarks.where((b) =>
        b.chapterIndex == anchor.chapterIndex &&
        b.paragraphIndex == anchor.paragraphIndex).firstOrNull;

    if (existing != null) {
      await _db.deleteBookmark(existing.id);
      return 'removed';
    } else {
      final id =
          'bm_${DateTime.now().millisecondsSinceEpoch}_${anchor.chapterIndex}_${anchor.paragraphIndex}';
      await _db.insertBookmark(
        BookmarksCompanion.insert(
          id: id,
          documentId: documentId,
          chapterIndex: anchor.chapterIndex,
          paragraphIndex: anchor.paragraphIndex,
          charOffset: anchor.charOffset,
          chapterTitle: Value(chapterTitle),
          snippet: snippet,
          createdAt: DateTime.now(),
          note: Value(note),
        ),
      );
      return 'added';
    }
  }

  Future<void> removeBookmark(String bookmarkId) async {
    await _db.deleteBookmark(bookmarkId);
  }
}

final bookmarksControllerProvider = Provider<BookmarksController>((ref) {
  return BookmarksController(ref);
});

/// Helper utility to find a bookmark within the active viewport or page chunk.
Bookmark? findBookmarkForActivePage({
  required List<Bookmark> bookmarks,
  required int chapterIndex,
  PageChunk? activePageChunk,
  ReadingAnchor? activeAnchor,
  required bool isPaginated,
  required bool isEpub,
}) {
  if (bookmarks.isEmpty) return null;

  if (!isEpub) {
    // PDF mode: chapterIndex corresponds directly to page index
    return bookmarks.where((b) => b.anchor.chapterIndex == chapterIndex).firstOrNull;
  }

  if (isPaginated && activePageChunk != null) {
    // Paginated EPUB mode: check if any bookmark falls within active PageChunk
    return bookmarks.where((b) {
      if (b.anchor.chapterIndex != chapterIndex) return false;
      return activePageChunk.containsAnchor(
        paragraphIndex: b.anchor.paragraphIndex,
        charOffset: b.anchor.charOffset,
      ) ||
      (b.anchor.paragraphIndex >= activePageChunk.startParagraphIndex &&
       b.anchor.paragraphIndex <= activePageChunk.endParagraphIndex);
    }).firstOrNull;
  }

  if (activeAnchor != null) {
    // Continuous mode: match leading visible paragraph/anchor
    return bookmarks.where((b) =>
        b.anchor.chapterIndex == activeAnchor.chapterIndex &&
        b.anchor.paragraphIndex == activeAnchor.paragraphIndex).firstOrNull;
  }

  return null;
}
