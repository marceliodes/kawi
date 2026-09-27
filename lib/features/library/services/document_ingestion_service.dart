import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/platform_window_service.dart';
import '../../../core/utils/bmp_encoder.dart';
import '../../reader/services/document_extractor.dart';

class DocumentIngestionService {
  DocumentIngestionService(this._database);

  final AppDatabase _database;

  static const supportedExtensions = {'.epub', '.pdf', '.mobi', '.azw'};

  /// Opens the native system file picker and ingests selected documents.
  /// If [shelfId] is specified, documents are automatically added to that shelf.
  Future<List<DocumentEntry>> pickAndIngestDocuments({String? shelfId}) async {
    String? parentWindow;
    if (Platform.isLinux) {
      parentWindow = await PlatformWindowService.getWindowHandle();
    }

    final files = await FilePicker.pickFiles(
      dialogTitle: 'Import Documents',
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'mobi', 'azw'],
      linuxOptions: FilePickerLinuxOptions(
        parentWindow: parentWindow,
        lockParentWindow: true,
      ),
    );

    if (files.isEmpty) {
      return const [];
    }

    final filePaths = files.map((f) => f.path).whereType<String>();
    return ingestFiles(filePaths, shelfId: shelfId);
  }

  /// Ingests a collection of file paths (from drag-and-drop or file picker).
  /// If [shelfId] is specified, documents are also added to that shelf.
  Future<List<DocumentEntry>> ingestFiles(
    Iterable<String> paths, {
    String? shelfId,
  }) async {
    final ingested = <DocumentEntry>[];

    for (final rawPath in paths) {
      final file = File(rawPath);
      if (!await file.exists()) continue;

      final ext = p.extension(rawPath).toLowerCase();
      if (!supportedExtensions.contains(ext)) continue;

      final doc = await ingestSingleFile(file);
      if (doc != null) {
        ingested.add(doc);
        if (shelfId != null) {
          await _database.addDocumentToShelf(doc.id, shelfId);
        }
      }
    }

    return ingested;
  }

  /// Ingests a single file: hashes, sandboxes, extracts metadata/cover, and stores in SQLite.
  Future<DocumentEntry?> ingestSingleFile(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final ext = p.extension(sourceFile.path).toLowerCase();
    final cleanExt = ext.startsWith('.') ? ext.substring(1) : ext;

    final appDocDir = await getApplicationDocumentsDirectory();
    final sandboxedDocsDir = Directory(
      p.join(appDocDir.path, 'kawi', 'documents'),
    );
    final sandboxedCoversDir = Directory(
      p.join(appDocDir.path, 'kawi', 'covers'),
    );

    if (!await sandboxedDocsDir.exists()) {
      await sandboxedDocsDir.create(recursive: true);
    }
    if (!await sandboxedCoversDir.exists()) {
      await sandboxedCoversDir.create(recursive: true);
    }

    final targetDocPath = p.join(sandboxedDocsDir.path, '$hash$ext');
    final targetDocFile = File(targetDocPath);
    if (!await targetDocFile.exists()) {
      await targetDocFile.writeAsBytes(bytes);
    }

    // Check if record already exists in database
    final existing = await _database.getDocumentById(hash);
    if (existing != null) {
      return existing;
    }

    // Extract metadata & cover raster via background isolate (MuPDF)
    DocumentMetadata metadata;
    try {
      metadata = await DocumentExtractor.extractMetadata(targetDocPath);
    } catch (_) {
      metadata = const DocumentMetadata(
        title: null,
        author: null,
        pageCount: 0,
      );
    }

    String? coverPath;
    if (metadata.hasCover) {
      try {
        final bmpBytes = BmpEncoder.encodeRgba(
          metadata.coverRgba!,
          metadata.coverWidth!,
          metadata.coverHeight!,
        );
        final targetCoverPath = p.join(sandboxedCoversDir.path, '$hash.bmp');
        await File(targetCoverPath).writeAsBytes(bmpBytes);
        coverPath = targetCoverPath;
      } catch (_) {
        coverPath = null;
      }
    }

    final originalName = p.basenameWithoutExtension(sourceFile.path);
    final finalTitle =
        (metadata.title != null && metadata.title!.trim().isNotEmpty)
        ? metadata.title!.trim()
        : originalName;

    final companion = DocumentsCompanion.insert(
      id: hash,
      title: finalTitle,
      author: Value(metadata.author?.trim()),
      filePath: targetDocPath,
      coverPath: coverPath != null ? Value(coverPath) : const Value.absent(),
      format: cleanExt,
      pageCount: Value(metadata.pageCount),
      addedAt: DateTime.now(),
      fileSizeBytes: Value(bytes.length),
    );

    await _database.insertOrUpdateDocument(companion);
    return _database.getDocumentById(hash);
  }
}
