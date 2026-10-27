import 'package:drift/drift.dart';

import 'documents.dart';

@DataClassName('BookmarkEntry')
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text().references(Documents, #id)();
  IntColumn get chapterIndex => integer()();
  IntColumn get paragraphIndex => integer()();
  IntColumn get charOffset => integer()();
  TextColumn get chapterTitle => text().nullable()();
  TextColumn get snippet => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
