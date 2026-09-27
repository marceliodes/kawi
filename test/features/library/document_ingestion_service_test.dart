import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/features/library/services/document_ingestion_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory.systemTemp.createTempSync('kawi_test_');
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentIngestionService service;

  setUp(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    db = AppDatabase(NativeDatabase.memory());
    service = DocumentIngestionService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('ingests sample epub and pdf files into database', () async {
    final epubFile = File('test_assets/alice.epub');
    final pdfFile = File('test_assets/sample.pdf');

    if (!epubFile.existsSync() || !pdfFile.existsSync()) {
      return;
    }

    final docs = await service.ingestFiles([epubFile.path, pdfFile.path]);
    expect(docs.length, 2);

    final storedDocs = await db.watchAllDocuments().first;
    expect(storedDocs.length, 2);

    final epubDoc = storedDocs.firstWhere((d) => d.format == 'epub');
    expect(epubDoc.title, contains('Alice'));
    expect(epubDoc.pageCount, greaterThan(0));
    expect(File(epubDoc.filePath).existsSync(), isTrue);

    final pdfDoc = storedDocs.firstWhere((d) => d.format == 'pdf');
    expect(pdfDoc.pageCount, greaterThan(0));
    expect(File(pdfDoc.filePath).existsSync(), isTrue);
  });

  test('ingestion is idempotent for duplicate files', () async {
    final pdfFile = File('test_assets/sample.pdf');
    if (!pdfFile.existsSync()) return;

    final first = await service.ingestSingleFile(pdfFile);
    final second = await service.ingestSingleFile(pdfFile);

    expect(first?.id, second?.id);
    final stored = await db.watchAllDocuments().first;
    expect(stored.length, 1);
  });

  test(
    'ingests files and automatically assigns them to shelf if shelfId provided',
    () async {
      final pdfFile = File('test_assets/sample.pdf');
      if (!pdfFile.existsSync()) return;

      await db.insertShelf(
        ShelvesCompanion.insert(
          id: 'shelf-fantasy',
          name: 'Fantasy',
          createdAt: DateTime.now(),
        ),
      );

      final docs = await service.ingestFiles([
        pdfFile.path,
      ], shelfId: 'shelf-fantasy');
      expect(docs.length, 1);

      final shelfDocs = await db.watchDocumentsInShelf('shelf-fantasy').first;
      expect(shelfDocs.length, 1);
      expect(shelfDocs.first.id, docs.first.id);
    },
  );
}
