import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../services/document_ingestion_service.dart';

enum LibraryFilterCategory { all, reading, completed, shelf }

class LibraryFilterState {
  const LibraryFilterState({
    required this.category,
    this.shelfId,
    this.shelfName,
  });

  final LibraryFilterCategory category;
  final String? shelfId;
  final String? shelfName;

  static const all = LibraryFilterState(category: LibraryFilterCategory.all);
  static const reading = LibraryFilterState(
    category: LibraryFilterCategory.reading,
  );
  static const completed = LibraryFilterState(
    category: LibraryFilterCategory.completed,
  );

  factory LibraryFilterState.shelf(String id, String name) =>
      LibraryFilterState(
        category: LibraryFilterCategory.shelf,
        shelfId: id,
        shelfName: name,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryFilterState &&
          runtimeType == other.runtimeType &&
          category == other.category &&
          shelfId == other.shelfId &&
          shelfName == other.shelfName;

  @override
  int get hashCode => Object.hash(category, shelfId, shelfName);
}

class LibraryFilterNotifier extends Notifier<LibraryFilterState> {
  @override
  LibraryFilterState build() => LibraryFilterState.all;

  void setFilter(LibraryFilterState filter) => state = filter;
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilterState>(
      LibraryFilterNotifier.new,
    );

final ingestionServiceProvider = Provider<DocumentIngestionService>((ref) {
  final db = ref.watch(databaseProvider);
  return DocumentIngestionService(db);
});

final documentsStreamProvider = StreamProvider.autoDispose<List<DocumentEntry>>(
  (ref) {
    final db = ref.watch(databaseProvider);
    final filter = ref.watch(libraryFilterProvider);

    return switch (filter.category) {
      LibraryFilterCategory.all => db.watchAllDocuments(),
      LibraryFilterCategory.reading => db.watchCurrentlyReading(),
      LibraryFilterCategory.completed => db.watchCompleted(),
      LibraryFilterCategory.shelf => db.watchDocumentsInShelf(
        filter.shelfId ?? '',
      ),
    };
  },
);

final shelvesStreamProvider = StreamProvider.autoDispose<List<Shelf>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllShelves();
});

final documentProgressProvider = StreamProvider.autoDispose
    .family<ReadingProgress?, String>((ref, docId) {
      final db = ref.watch(databaseProvider);
      return db.watchProgressForDocument(docId);
    });
