import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('can insert and stream documents', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-1',
        title: 'Alice in Wonderland',
        author: const Value('Lewis Carroll'),
        filePath: '/path/to/alice.epub',
        format: 'epub',
        pageCount: const Value(120),
        addedAt: now,
      ),
    );

    final docs = await db.watchAllDocuments().first;
    expect(docs.length, 1);
    expect(docs.first.title, 'Alice in Wonderland');
    expect(docs.first.author, 'Lewis Carroll');
  });

  test('can filter by shelf', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-1',
        title: 'Book 1',
        filePath: '/path/1',
        format: 'epub',
        addedAt: now,
      ),
    );
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-2',
        title: 'Book 2',
        filePath: '/path/2',
        format: 'pdf',
        addedAt: now,
      ),
    );

    await db.insertShelf(
      ShelvesCompanion.insert(
        id: 'shelf-fiction',
        name: 'Fiction',
        createdAt: now,
      ),
    );

    await db.addDocumentToShelf('doc-1', 'shelf-fiction');

    final fictionDocs = await db.watchDocumentsInShelf('shelf-fiction').first;
    expect(fictionDocs.length, 1);
    expect(fictionDocs.first.id, 'doc-1');
  });

  test('can update and watch reading progress', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-1',
        title: 'Book 1',
        filePath: '/path/1',
        format: 'epub',
        addedAt: now,
      ),
    );

    await db.updateProgress(
      ReadingProgressesCompanion.insert(
        documentId: 'doc-1',
        lastReadPageIndex: const Value(5),
        lastReadSentenceIndex: const Value(12),
        lastReadScrollOffset: const Value(120.5),
        updatedAt: now,
      ),
    );

    final progress = await db.watchProgressForDocument('doc-1').first;
    expect(progress, isNotNull);
    expect(progress!.lastReadPageIndex, 5);
    expect(progress.lastReadSentenceIndex, 12);
  });

  test('can set, get, and watch app settings', () async {
    expect(await db.getSetting('font_family'), isNull);

    await db.setSetting('font_family', 'Literata');
    expect(await db.getSetting('font_family'), 'Literata');

    final settingsStream = db.watchSetting('font_family');
    expect(await settingsStream.first, 'Literata');

    await db.setSetting('font_size', '18.0');
    final all = await db.getAllSettings();
    expect(all['font_family'], 'Literata');
    expect(all['font_size'], '18.0');
  });

  test('reading progress stores and updates currentChapter', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-chapter',
        title: 'Chapter Book',
        filePath: '/path/cb',
        format: 'epub',
        addedAt: now,
      ),
    );

    await db.updateProgress(
      ReadingProgressesCompanion.insert(
        documentId: 'doc-chapter',
        lastReadPageIndex: const Value(2),
        currentChapter: const Value('Chapter 2: Down the Rabbit Hole'),
        updatedAt: now,
      ),
    );

    final progress = await db.watchProgressForDocument('doc-chapter').first;
    expect(progress?.currentChapter, 'Chapter 2: Down the Rabbit Hole');
  });

  test('adding a document to a shelf includes it and excludes from "not in shelf"', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-1',
        title: 'Meditations',
        author: const Value('Marcus Aurelius'),
        filePath: '/sandbox/meditations.epub',
        format: 'epub',
        pageCount: const Value(150),
        addedAt: now,
      ),
    );
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-2',
        title: 'Nicomachean Ethics',
        author: const Value('Aristotle'),
        filePath: '/sandbox/ethics.epub',
        format: 'epub',
        pageCount: const Value(250),
        addedAt: now,
      ),
    );

    await db.insertShelf(
      ShelvesCompanion.insert(
        id: 'shelf-phil',
        name: 'Philosophy',
        createdAt: now,
      ),
    );

    await db.addDocumentToShelf('doc-1', 'shelf-phil');

    final shelfDocs = await db.watchDocumentsInShelf('shelf-phil').first;
    expect(shelfDocs.length, 1);
    expect(shelfDocs.first.id, 'doc-1');
    expect(shelfDocs.first.title, 'Meditations');

    final notInShelf = await db.getDocumentsNotInShelf('shelf-phil');
    expect(notInShelf.length, 1);
    expect(notInShelf.first.id, 'doc-2');
    expect(notInShelf.first.title, 'Nicomachean Ethics');

    final allDocs = await db.watchAllDocuments().first;
    expect(allDocs.length, 2);
  });

  test('removing a document from a shelf keeps it in all documents', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-1',
        title: 'Meditations',
        filePath: '/sandbox/meditations.epub',
        format: 'epub',
        addedAt: now,
      ),
    );

    await db.insertShelf(
      ShelvesCompanion.insert(
        id: 'shelf-phil',
        name: 'Philosophy',
        createdAt: now,
      ),
    );

    await db.addDocumentToShelf('doc-1', 'shelf-phil');
    var shelfDocs = await db.watchDocumentsInShelf('shelf-phil').first;
    expect(shelfDocs.length, 1);

    await db.removeDocumentFromShelf('doc-1', 'shelf-phil');

    shelfDocs = await db.watchDocumentsInShelf('shelf-phil').first;
    expect(shelfDocs, isEmpty);

    final allDocs = await db.watchAllDocuments().first;
    expect(allDocs.length, 1);
    expect(allDocs.first.id, 'doc-1');
  });

  test('getDocumentsNotInShelf returns all documents when shelf is empty', () async {
    final now = DateTime.now();
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-a',
        title: 'Book A',
        filePath: '/a.epub',
        format: 'epub',
        addedAt: now,
      ),
    );
    await db.insertOrUpdateDocument(
      DocumentsCompanion.insert(
        id: 'doc-b',
        title: 'Book B',
        filePath: '/b.epub',
        format: 'epub',
        addedAt: now,
      ),
    );

    await db.insertShelf(
      ShelvesCompanion.insert(
        id: 'shelf-empty',
        name: 'Empty Shelf',
        createdAt: now,
      ),
    );

    final notInShelf = await db.getDocumentsNotInShelf('shelf-empty');
    expect(notInShelf.length, 2);

    final ids = notInShelf.map((d) => d.id).toSet();
    expect(ids, containsAll(['doc-a', 'doc-b']));
  });
}
