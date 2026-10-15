import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/platform_window_service.dart';
import '../../../core/utils/bmp_encoder.dart';
import '../../reader/services/document_extractor.dart';
import '../../reader/services/epub_service.dart';

class DocumentIngestionService {
  DocumentIngestionService(this._database);

  final AppDatabase _database;

  static const supportedExtensions = {'.epub', '.pdf', '.mobi', '.azw'};
  static final Set<String> _healingDocumentIds = {};

  /// Checks whether an uncompressed 24-bit or 32-bit BMP raster file contains only black (RGB: 0,0,0) pixels.
  static bool isAllBlackBmp(Uint8List bytes) {
    if (bytes.length < 54) return false;
    if (bytes[0] != 0x42 || bytes[1] != 0x4D) return false;

    var pixelOffset =
        bytes[10] | (bytes[11] << 8) | (bytes[12] << 16) | (bytes[13] << 24);
    if (pixelOffset < 54 || pixelOffset >= bytes.length) {
      pixelOffset = 54;
    }

    final pixelBytesLength = bytes.length - pixelOffset;
    if (pixelBytesLength <= 0) return false;

    final bpp = bytes[28] | (bytes[29] << 8);
    final bytesPerPixel = (bpp == 24 || bpp == 32) ? (bpp ~/ 8) : 4;

    final numPixels = pixelBytesLength ~/ bytesPerPixel;
    if (numPixels <= 0) return false;

    final step = (numPixels ~/ 50).clamp(1, numPixels);
    for (var p = 0; p < numPixels; p += step) {
      final offset = pixelOffset + p * bytesPerPixel;
      if (offset + 2 >= bytes.length) break;
      final b = bytes[offset];
      final g = bytes[offset + 1];
      final r = bytes[offset + 2];
      if (r > 5 || g > 5 || b > 5) {
        return false;
      }
    }
    return true;
  }

  /// Detects image extension (.png, .jpg, .webp) from binary file magic bytes.
  static String detectImageExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }
    return '.jpg';
  }

  /// Self-heals a document's cover by extracting the real cover image from the EPUB archive.
  static Future<String?> healEpubCover({
    required AppDatabase db,
    required DocumentEntry document,
  }) async {
    if (_healingDocumentIds.contains(document.id)) return null;
    _healingDocumentIds.add(document.id);
    try {
      final epubFile = File(document.filePath);
      if (!epubFile.existsSync()) return null;

      final coverBytes =
          await EpubService.instance.extractEpubCoverBytes(document.filePath);
      if (coverBytes == null || coverBytes.isEmpty) return null;

      final appDocDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(appDocDir.path, 'kawi', 'covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final ext = detectImageExtension(coverBytes);
      final newCoverFile = File(p.join(coversDir.path, '${document.id}$ext'));
      await newCoverFile.writeAsBytes(coverBytes);

      if (document.coverPath != null) {
        try {
          final oldFile = File(document.coverPath!);
          await FileImage(oldFile).evict();
          if (oldFile.existsSync() && oldFile.path != newCoverFile.path) {
            await oldFile.delete();
          }
        } catch (_) {}
      }
      await FileImage(newCoverFile).evict();

      await db.updateDocumentCover(document.id, newCoverFile.path);
      return newCoverFile.path;
    } catch (_) {
      return null;
    } finally {
      _healingDocumentIds.remove(document.id);
    }
  }

  /// Self-heals all existing EPUB books in the database whose cover is missing or all-black.
  Future<void> selfHealLibraryCovers() async {
    try {
      final docs = await _database.select(_database.documents).get();
      for (final doc in docs) {
        if (doc.format.toLowerCase() == 'epub' &&
            File(doc.filePath).existsSync()) {
          final hasCover =
              doc.coverPath != null && File(doc.coverPath!).existsSync();
          bool isBlack = false;
          if (hasCover) {
            final isBmp = doc.coverPath!.toLowerCase().endsWith('.bmp');
            if (isBmp) {
              isBlack = true;
            } else {
              try {
                final bytes = await File(doc.coverPath!).readAsBytes();
                isBlack = isAllBlackBmp(bytes);
              } catch (_) {}
            }
          }
          if (!hasCover || isBlack) {
            await healEpubCover(db: _database, document: doc);
          }
        }
      }
    } catch (_) {}
  }

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
    if (cleanExt == 'epub') {
      try {
        final coverBytes =
            await EpubService.instance.extractEpubCoverBytes(targetDocPath);
        if (coverBytes != null && coverBytes.isNotEmpty) {
          final ext = detectImageExtension(coverBytes);
          final targetCoverPath = p.join(sandboxedCoversDir.path, '$hash$ext');
          await File(targetCoverPath).writeAsBytes(coverBytes);
          coverPath = targetCoverPath;
        }
      } catch (_) {
        coverPath = null;
      }
    }

    if (coverPath == null && metadata.hasCover) {
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
