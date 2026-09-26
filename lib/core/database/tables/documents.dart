import 'package:drift/drift.dart';

@DataClassName('DocumentEntry')
class Documents extends Table {
  TextColumn get id => text()(); // SHA-256 hash
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get filePath => text()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get format => text()(); // 'epub', 'pdf', 'mobi', 'azw'
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
