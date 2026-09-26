import 'package:drift/drift.dart' hide isNotNull;
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
}
