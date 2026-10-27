import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/features/reader/models/bookmark.dart';
import 'package:kawi/features/reader/models/document_models.dart';
import 'package:kawi/features/reader/providers/bookmarks_provider.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-provider-test',
        title: 'Provider Test Doc',
        filePath: '/test/provider.epub',
        format: 'epub',
        addedAt: DateTime.now(),
      ),
    );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('Bookmarks Provider & Controller Tests', () {
    test('BookmarksController toggleBookmark adds bookmark when none exists', () async {
      final controller = container.read(bookmarksControllerProvider);
      const anchor = ReadingAnchor(chapterIndex: 0, paragraphIndex: 2, charOffset: 0);

      final result = await controller.toggleBookmark(
        documentId: 'doc-provider-test',
        anchor: anchor,
        chapterTitle: 'Chapter 1',
        snippet: 'A lovely preview snippet',
      );

      expect(result, 'added');

      final list = await db.getBookmarksForDocument('doc-provider-test');
      expect(list.length, 1);
      expect(list.first.chapterIndex, 0);
      expect(list.first.paragraphIndex, 2);
      expect(list.first.snippet, 'A lovely preview snippet');
    });

    test('BookmarksController toggleBookmark removes bookmark when existing on page', () async {
      final controller = container.read(bookmarksControllerProvider);
      const anchor = ReadingAnchor(chapterIndex: 0, paragraphIndex: 2, charOffset: 0);

      // Add
      await controller.toggleBookmark(
        documentId: 'doc-provider-test',
        anchor: anchor,
        chapterTitle: 'Chapter 1',
        snippet: 'A lovely preview snippet',
      );

      final existingList = await db.getBookmarksForDocument('doc-provider-test');
      expect(existingList.length, 1);
      final existingBookmark = Bookmark.fromEntry(existingList.first);

      // Toggle again with existingBookmark
      final result = await controller.toggleBookmark(
        documentId: 'doc-provider-test',
        anchor: anchor,
        existingBookmarkOnPage: existingBookmark,
        snippet: 'Ignored snippet',
      );

      expect(result, 'removed');
      final afterList = await db.getBookmarksForDocument('doc-provider-test');
      expect(afterList, isEmpty);
    });

    test('BookmarksController toggleBookmark removes by matching anchor if no existingBookmark passed', () async {
      final controller = container.read(bookmarksControllerProvider);
      const anchor = ReadingAnchor(chapterIndex: 1, paragraphIndex: 4, charOffset: 0);

      // Add
      await controller.toggleBookmark(
        documentId: 'doc-provider-test',
        anchor: anchor,
        snippet: 'Snippet 1',
      );

      expect((await db.getBookmarksForDocument('doc-provider-test')).length, 1);

      // Toggle again with same anchor
      final result = await controller.toggleBookmark(
        documentId: 'doc-provider-test',
        anchor: anchor,
        snippet: 'Snippet 1',
      );

      expect(result, 'removed');
      expect(await db.getBookmarksForDocument('doc-provider-test'), isEmpty);
    });

    test('BookmarksController removeBookmark deletes by ID', () async {
      final controller = container.read(bookmarksControllerProvider);
      const anchor = ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 0);

      await controller.toggleBookmark(
        documentId: 'doc-provider-test',
        anchor: anchor,
        snippet: 'Snippet to remove',
      );

      final list = await db.getBookmarksForDocument('doc-provider-test');
      expect(list.length, 1);

      await controller.removeBookmark(list.first.id);
      expect(await db.getBookmarksForDocument('doc-provider-test'), isEmpty);
    });

    group('findBookmarkForActivePage Detection Tests', () {
      final bookmarkAtP6 = Bookmark(
        id: 'bm-p6',
        bookId: 'doc-test',
        anchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 6, charOffset: 10),
        snippet: 'Snippet at P6',
        createdAt: DateTime.now(),
      );
      final bookmarkAtP12 = Bookmark(
        id: 'bm-p12',
        bookId: 'doc-test',
        anchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 12, charOffset: 0),
        snippet: 'Snippet at P12',
        createdAt: DateTime.now(),
      );

      const pageChunkP4toP8 = PageChunk(
        pageIndexInChapter: 1,
        chapterIndex: 0,
        nodes: [ParagraphNode([TextSegment('Test')])],
        startParagraphIndex: 4,
        endParagraphIndex: 8,
        startCharOffset: 0,
        endCharOffset: 100,
      );

      test('detects bookmark inside Paginated PageChunk range', () {
        final detected = findBookmarkForActivePage(
          bookmarks: [bookmarkAtP6, bookmarkAtP12],
          chapterIndex: 0,
          activePageChunk: pageChunkP4toP8,
          activeAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 4, charOffset: 0),
          isPaginated: true,
          isEpub: true,
        );

        expect(detected, isNotNull);
        expect(detected!.id, 'bm-p6');
      });

      test('returns null when Paginated PageChunk does not span bookmark', () {
        final detected = findBookmarkForActivePage(
          bookmarks: [bookmarkAtP12],
          chapterIndex: 0,
          activePageChunk: pageChunkP4toP8,
          activeAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 4, charOffset: 0),
          isPaginated: true,
          isEpub: true,
        );

        expect(detected, isNull);
      });

      test('detects bookmark in Continuous mode matching leading anchor', () {
        final detected = findBookmarkForActivePage(
          bookmarks: [bookmarkAtP6, bookmarkAtP12],
          chapterIndex: 0,
          activeAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 12, charOffset: 0),
          isPaginated: false,
          isEpub: true,
        );

        expect(detected, isNotNull);
        expect(detected!.id, 'bm-p12');
      });

      test('detects bookmark in PDF mode matching chapter/page index', () {
        final pdfBookmark = Bookmark(
          id: 'bm-pdf',
          bookId: 'doc-pdf',
          anchor: const ReadingAnchor(chapterIndex: 3, paragraphIndex: 0, charOffset: 0),
          snippet: 'Page 4 content',
          createdAt: DateTime.now(),
        );

        final detected = findBookmarkForActivePage(
          bookmarks: [pdfBookmark],
          chapterIndex: 3,
          isPaginated: true,
          isEpub: false,
        );

        expect(detected, isNotNull);
        expect(detected!.id, 'bm-pdf');

        final notDetected = findBookmarkForActivePage(
          bookmarks: [pdfBookmark],
          chapterIndex: 2,
          isPaginated: true,
          isEpub: false,
        );
        expect(notDetected, isNull);
      });
    });
  });
}
