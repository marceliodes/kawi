import 'package:drift/drift.dart';

import 'documents.dart';

@DataClassName('HighlightEntry')
class Highlights extends Table {
  TextColumn get id => text()();
  TextColumn get documentId =>
      text().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get startChapterIndex => integer()();
  IntColumn get startParagraphIndex => integer()();
  IntColumn get startCharOffset => integer()();
  IntColumn get endChapterIndex => integer()();
  IntColumn get endParagraphIndex => integer()();
  IntColumn get endCharOffset => integer()();
  TextColumn get highlightedText => text()();
  TextColumn get colorHex => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
