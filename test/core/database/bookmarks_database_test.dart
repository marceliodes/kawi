import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Insert a parent document
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-parent',
        title: 'Test Document',
        filePath: '/test/doc.epub',
        format: 'epub',
        addedAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Bookmarks Drift Database Operations', () {
    test('database schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('can insert and watch bookmarks for a document', () async {
      final now = DateTime.now();
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-1',
          documentId: 'doc-parent',
          chapterIndex: 0,
          paragraphIndex: 3,
          charOffset: 10,
          chapterTitle: const Value('Chapter 1'),
          snippet: 'First paragraph preview text...',
          createdAt: now,
        ),
      );

      final bookmarks = await db.watchBookmarksForDocument('doc-parent').first;
      expect(bookmarks.length, 1);
      expect(bookmarks.first.id, 'bm-1');
      expect(bookmarks.first.documentId, 'doc-parent');
      expect(bookmarks.first.chapterIndex, 0);
      expect(bookmarks.first.paragraphIndex, 3);
      expect(bookmarks.first.charOffset, 10);
      expect(bookmarks.first.chapterTitle, 'Chapter 1');
      expect(bookmarks.first.snippet, 'First paragraph preview text...');
    });

    test('watchBookmarksForDocument orders bookmarks by createdAt descending', () async {
      final t1 = DateTime(2026, 10, 27, 10);
      final t2 = DateTime(2026, 10, 27, 11);

      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-old',
          documentId: 'doc-parent',
          chapterIndex: 0,
          paragraphIndex: 1,
          charOffset: 0,
          snippet: 'Old bookmark',
          createdAt: t1,
        ),
      );

      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-new',
          documentId: 'doc-parent',
          chapterIndex: 1,
          paragraphIndex: 5,
          charOffset: 0,
          snippet: 'New bookmark',
          createdAt: t2,
        ),
      );

      final bookmarks = await db.watchBookmarksForDocument('doc-parent').first;
      expect(bookmarks.length, 2);
      expect(bookmarks[0].id, 'bm-new');
      expect(bookmarks[1].id, 'bm-old');
    });

    test('deleteBookmark removes bookmark by ID', () async {
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-to-delete',
          documentId: 'doc-parent',
          chapterIndex: 2,
          paragraphIndex: 0,
          charOffset: 0,
          snippet: 'To be deleted',
          createdAt: DateTime.now(),
        ),
      );

      var list = await db.getBookmarksForDocument('doc-parent');
      expect(list.length, 1);

      await db.deleteBookmark('bm-to-delete');

      list = await db.getBookmarksForDocument('doc-parent');
      expect(list, isEmpty);
    });

    test('deleteBookmarkByAnchor removes matching bookmark', () async {
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-anchor',
          documentId: 'doc-parent',
          chapterIndex: 3,
          paragraphIndex: 7,
          charOffset: 12,
          snippet: 'Matching anchor',
          createdAt: DateTime.now(),
        ),
      );

      await db.deleteBookmarkByAnchor(
        documentId: 'doc-parent',
        chapterIndex: 3,
        paragraphIndex: 7,
        charOffset: 12,
      );

      final list = await db.getBookmarksForDocument('doc-parent');
      expect(list, isEmpty);
    });

    test('deleting document cascades and removes associated bookmarks', () async {
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bm-cascade',
          documentId: 'doc-parent',
          chapterIndex: 0,
          paragraphIndex: 0,
          charOffset: 0,
          snippet: 'Cascaded snippet',
          createdAt: DateTime.now(),
        ),
      );

      expect((await db.getBookmarksForDocument('doc-parent')).length, 1);

      await db.deleteDocumentById('doc-parent');

      expect(await db.getBookmarksForDocument('doc-parent'), isEmpty);
    });
  });
}
