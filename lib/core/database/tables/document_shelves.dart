import 'package:drift/drift.dart';

import 'documents.dart';
import 'shelves.dart';

@DataClassName('DocumentShelf')
class DocumentShelves extends Table {
  TextColumn get documentId => text().references(Documents, #id)();
  TextColumn get shelfId => text().references(Shelves, #id)();

  @override
  Set<Column> get primaryKey => {documentId, shelfId};
}
