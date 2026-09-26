import 'package:drift/drift.dart';

import 'documents.dart';

@DataClassName('ReadingProgress')
class ReadingProgresses extends Table {
  TextColumn get documentId => text().references(Documents, #id)();
  IntColumn get lastReadPageIndex => integer().withDefault(const Constant(0))();
  IntColumn get lastReadSentenceIndex =>
      integer().withDefault(const Constant(0))();
  RealColumn get lastReadScrollOffset =>
      real().withDefault(const Constant(0.0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {documentId};
}
