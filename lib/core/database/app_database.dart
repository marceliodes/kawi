import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/document_shelves.dart';
import 'tables/documents.dart';
import 'tables/reading_progress.dart';
import 'tables/shelves.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Documents, ReadingProgresses, Shelves, DocumentShelves])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  Stream<List<DocumentEntry>> watchAllDocuments() {
    return (select(documents)..orderBy([
          (t) => OrderingTerm(expression: t.addedAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Stream<List<DocumentEntry>> watchCurrentlyReading() {
    return (select(documents)
          ..where((t) => t.lastReadAt.isNotNull() & t.isCompleted.equals(false))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.lastReadAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<DocumentEntry>> watchCompleted() {
    return (select(documents)
          ..where((t) => t.isCompleted.equals(true))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.lastReadAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<DocumentEntry>> watchDocumentsInShelf(String shelfId) {
    final query =
        select(documents).join([
            innerJoin(
              documentShelves,
              documentShelves.documentId.equalsExp(documents.id),
            ),
          ])
          ..where(documentShelves.shelfId.equals(shelfId))
          ..orderBy([
            OrderingTerm(
              expression: documents.addedAt,
              mode: OrderingMode.desc,
            ),
          ]);

    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(documents)).toList(),
    );
  }

  Stream<List<Shelf>> watchAllShelves() {
    return (select(
      shelves,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Future<DocumentEntry?> getDocumentById(String id) {
    return (select(documents)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertOrUpdateDocument(DocumentsCompanion doc) {
    return into(documents).insertOnConflictUpdate(doc);
  }

  Future<void> deleteDocumentById(String id) async {
    await (delete(documentShelves)..where((t) => t.documentId.equals(id))).go();
    await (delete(
      readingProgresses,
    )..where((t) => t.documentId.equals(id))).go();
    await (delete(documents)..where((t) => t.id.equals(id))).go();
  }

  Future<void> insertShelf(ShelvesCompanion shelf) {
    return into(shelves).insert(shelf);
  }

  Future<void> deleteShelf(String id) async {
    await (delete(documentShelves)..where((t) => t.shelfId.equals(id))).go();
    await (delete(shelves)..where((t) => t.id.equals(id))).go();
  }

  Future<void> addDocumentToShelf(String documentId, String shelfId) {
    return into(documentShelves).insertOnConflictUpdate(
      DocumentShelvesCompanion(
        documentId: Value(documentId),
        shelfId: Value(shelfId),
      ),
    );
  }

  Future<void> removeDocumentFromShelf(String documentId, String shelfId) {
    return (delete(documentShelves)..where(
          (t) => t.documentId.equals(documentId) & t.shelfId.equals(shelfId),
        ))
        .go();
  }

  Future<List<DocumentEntry>> getDocumentsNotInShelf(String shelfId) async {
    final assignedDocs = await (select(
      documentShelves,
    )..where((t) => t.shelfId.equals(shelfId))).get();
    final assignedIds = assignedDocs.map((d) => d.documentId).toSet();
    final all =
        await (select(documents)..orderBy([
              (t) =>
                  OrderingTerm(expression: t.addedAt, mode: OrderingMode.desc),
            ]))
            .get();
    return all.where((d) => !assignedIds.contains(d.id)).toList();
  }

  Stream<ReadingProgress?> watchProgressForDocument(String documentId) {
    return (select(
      readingProgresses,
    )..where((t) => t.documentId.equals(documentId))).watchSingleOrNull();
  }

  Future<void> updateProgress(ReadingProgressesCompanion progress) {
    return into(readingProgresses).insertOnConflictUpdate(progress);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'kawi', 'kawi.db'));
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return NativeDatabase.createInBackground(file);
  });
}
