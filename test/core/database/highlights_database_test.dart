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

  group('Highlights Drift Database Operations', () {
    test('database schemaVersion is 4', () {
      expect(db.schemaVersion, 4);
    });

    test('can insert and watch highlights for a document', () async {
      final now = DateTime.now();
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-1',
          documentId: 'doc-parent',
          startChapterIndex: 0,
          startParagraphIndex: 2,
          startCharOffset: 5,
          endChapterIndex: 0,
          endParagraphIndex: 2,
          endCharOffset: 25,
          highlightedText: 'highlighted sample text',
          colorHex: '#FFD54F',
          note: const Value('Important study note'),
          createdAt: now,
        ),
      );

      final highlights =
          await db.watchHighlightsForDocument('doc-parent').first;
      expect(highlights.length, 1);
      expect(highlights.first.id, 'hl-1');
      expect(highlights.first.documentId, 'doc-parent');
      expect(highlights.first.startChapterIndex, 0);
      expect(highlights.first.startParagraphIndex, 2);
      expect(highlights.first.startCharOffset, 5);
      expect(highlights.first.endChapterIndex, 0);
      expect(highlights.first.endParagraphIndex, 2);
      expect(highlights.first.endCharOffset, 25);
      expect(highlights.first.highlightedText, 'highlighted sample text');
      expect(highlights.first.colorHex, '#FFD54F');
      expect(highlights.first.note, 'Important study note');
    });

    test('watchHighlightsForDocument orders positionally', () async {
      final now = DateTime.now();

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-later',
          documentId: 'doc-parent',
          startChapterIndex: 1,
          startParagraphIndex: 0,
          startCharOffset: 0,
          endChapterIndex: 1,
          endParagraphIndex: 0,
          endCharOffset: 10,
          highlightedText: 'later chapter',
          colorHex: '#81C784',
          createdAt: now,
        ),
      );

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-earlier',
          documentId: 'doc-parent',
          startChapterIndex: 0,
          startParagraphIndex: 1,
          startCharOffset: 10,
          endChapterIndex: 0,
          endParagraphIndex: 1,
          endCharOffset: 20,
          highlightedText: 'earlier chapter',
          colorHex: '#64B5F6',
          createdAt: now,
        ),
      );

      final list = await db.watchHighlightsForDocument('doc-parent').first;
      expect(list.length, 2);
      expect(list[0].id, 'hl-earlier');
      expect(list[1].id, 'hl-later');
    });

    test('getHighlightsForChapter filters correctly', () async {
      final now = DateTime.now();

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-ch0',
          documentId: 'doc-parent',
          startChapterIndex: 0,
          startParagraphIndex: 1,
          startCharOffset: 0,
          endChapterIndex: 0,
          endParagraphIndex: 1,
          endCharOffset: 10,
          highlightedText: 'ch 0 text',
          colorHex: '#FFD54F',
          createdAt: now,
        ),
      );

      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-ch1',
          documentId: 'doc-parent',
          startChapterIndex: 1,
          startParagraphIndex: 3,
          startCharOffset: 0,
          endChapterIndex: 1,
          endParagraphIndex: 3,
          endCharOffset: 15,
          highlightedText: 'ch 1 text',
          colorHex: '#81C784',
          createdAt: now,
        ),
      );

      final ch0 = await db.getHighlightsForChapter(
        documentId: 'doc-parent',
        chapterIndex: 0,
      );
      expect(ch0.length, 1);
      expect(ch0.first.id, 'hl-ch0');

      final ch1 = await db.getHighlightsForChapter(
        documentId: 'doc-parent',
        chapterIndex: 1,
      );
      expect(ch1.length, 1);
      expect(ch1.first.id, 'hl-ch1');
    });

    test('can update note and color', () async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-edit',
          documentId: 'doc-parent',
          startChapterIndex: 0,
          startParagraphIndex: 0,
          startCharOffset: 0,
          endChapterIndex: 0,
          endParagraphIndex: 0,
          endCharOffset: 10,
          highlightedText: 'text to edit',
          colorHex: '#FFD54F',
          createdAt: DateTime.now(),
        ),
      );

      await db.updateHighlightNote('hl-edit', 'Added user note');
      await db.updateHighlightColor('hl-edit', '#FF8A80');

      final list = await db.getHighlightsForDocument('doc-parent');
      expect(list.first.note, 'Added user note');
      expect(list.first.colorHex, '#FF8A80');
    });

    test('deleteHighlight removes highlight by ID', () async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-delete',
          documentId: 'doc-parent',
          startChapterIndex: 0,
          startParagraphIndex: 0,
          startCharOffset: 0,
          endChapterIndex: 0,
          endParagraphIndex: 0,
          endCharOffset: 10,
          highlightedText: 'text',
          colorHex: '#FFD54F',
          createdAt: DateTime.now(),
        ),
      );

      var list = await db.getHighlightsForDocument('doc-parent');
      expect(list.length, 1);

      await db.deleteHighlight('hl-delete');
      list = await db.getHighlightsForDocument('doc-parent');
      expect(list, isEmpty);
    });

    test('deleting document cascades and removes associated highlights',
        () async {
      await db.insertHighlight(
        HighlightsCompanion.insert(
          id: 'hl-cascade',
          documentId: 'doc-parent',
          startChapterIndex: 0,
          startParagraphIndex: 0,
          startCharOffset: 0,
          endChapterIndex: 0,
          endParagraphIndex: 0,
          endCharOffset: 10,
          highlightedText: 'will be cascaded',
          colorHex: '#FFD54F',
          createdAt: DateTime.now(),
        ),
      );

      expect((await db.getHighlightsForDocument('doc-parent')).length, 1);

      await db.deleteDocumentById('doc-parent');

      expect(await db.getHighlightsForDocument('doc-parent'), isEmpty);
    });
  });
}
