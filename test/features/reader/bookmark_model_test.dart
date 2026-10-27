import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/features/reader/models/bookmark.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';

void main() {
  group('Bookmark Model Tests', () {
    final now = DateTime(2026, 10, 27, 12);
    const anchor = ReadingAnchor(
      chapterIndex: 2,
      paragraphIndex: 5,
      charOffset: 42,
    );

    test('creates Bookmark instance with valid fields', () {
      final bookmark = Bookmark(
        id: 'bm-1',
        bookId: 'doc-1',
        anchor: anchor,
        chapterTitle: 'Chapter 3: The Rabbit Hole',
        snippet: 'Alice was beginning to get very tired of sitting by her sister...',
        createdAt: now,
        note: 'Important quote',
      );

      expect(bookmark.id, 'bm-1');
      expect(bookmark.bookId, 'doc-1');
      expect(bookmark.anchor.chapterIndex, 2);
      expect(bookmark.anchor.paragraphIndex, 5);
      expect(bookmark.anchor.charOffset, 42);
      expect(bookmark.chapterTitle, 'Chapter 3: The Rabbit Hole');
      expect(bookmark.snippet, contains('Alice was beginning'));
      expect(bookmark.createdAt, now);
      expect(bookmark.note, 'Important quote');
    });

    test('serialization toJson and fromJson roundtrip preserves all data', () {
      final original = Bookmark(
        id: 'bm-roundtrip',
        bookId: 'book-abc',
        anchor: const ReadingAnchor(
          chapterIndex: 4,
          paragraphIndex: 12,
          charOffset: 80,
        ),
        chapterTitle: 'Chapter 5',
        snippet: 'Curiouser and curiouser!',
        createdAt: now,
        note: 'Note here',
      );

      final json = original.toJson();
      final restored = Bookmark.fromJson(json);

      expect(restored, equals(original));
      expect(restored.id, original.id);
      expect(restored.bookId, original.bookId);
      expect(restored.anchor.chapterIndex, original.anchor.chapterIndex);
      expect(restored.anchor.paragraphIndex, original.anchor.paragraphIndex);
      expect(restored.anchor.charOffset, original.anchor.charOffset);
      expect(restored.chapterTitle, original.chapterTitle);
      expect(restored.snippet, original.snippet);
      expect(restored.createdAt, original.createdAt);
      expect(restored.note, original.note);
    });

    test('fromEntry correctly maps Drift BookmarkEntry table row', () {
      final entry = BookmarkEntry(
        id: 'bm-drift',
        documentId: 'doc-drift',
        chapterIndex: 1,
        paragraphIndex: 3,
        charOffset: 15,
        chapterTitle: 'Title from DB',
        snippet: 'Snippet from DB',
        createdAt: now,
      );

      final bookmark = Bookmark.fromEntry(entry);
      expect(bookmark.id, 'bm-drift');
      expect(bookmark.bookId, 'doc-drift');
      expect(bookmark.anchor.chapterIndex, 1);
      expect(bookmark.anchor.paragraphIndex, 3);
      expect(bookmark.anchor.charOffset, 15);
      expect(bookmark.chapterTitle, 'Title from DB');
      expect(bookmark.snippet, 'Snippet from DB');
      expect(bookmark.createdAt, now);
      expect(bookmark.note, isNull);
    });

    test('copyWith updates specified fields only', () {
      final original = Bookmark(
        id: 'bm-orig',
        bookId: 'book-1',
        anchor: anchor,
        snippet: 'Original snippet',
        createdAt: now,
      );

      final updated = original.copyWith(
        snippet: 'Updated snippet',
        note: 'New note',
      );

      expect(updated.id, original.id);
      expect(updated.bookId, original.bookId);
      expect(updated.anchor, original.anchor);
      expect(updated.snippet, 'Updated snippet');
      expect(updated.note, 'New note');
      expect(updated.createdAt, original.createdAt);
    });

    test('equality and hashCode adhere to value semantics', () {
      final b1 = Bookmark(
        id: 'bm-same',
        bookId: 'b-1',
        anchor: anchor,
        snippet: 'Same',
        createdAt: now,
      );
      final b2 = Bookmark(
        id: 'bm-same',
        bookId: 'b-1',
        anchor: anchor,
        snippet: 'Same',
        createdAt: now,
      );
      final b3 = Bookmark(
        id: 'bm-different',
        bookId: 'b-1',
        anchor: anchor,
        snippet: 'Same',
        createdAt: now,
      );

      expect(b1, equals(b2));
      expect(b1.hashCode, equals(b2.hashCode));
      expect(b1, isNot(equals(b3)));
    });
  });
}
