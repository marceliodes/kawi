import 'package:drift/drift.dart';

@DataClassName('Shelf')
class Shelves extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
