import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../models/highlight.dart';
import 'document_content_provider.dart';

/// Reactive stream of all highlights for a document, ordered positionally.
final highlightsStreamProvider =
    StreamProvider.family<List<Highlight>, String>((ref, documentId) {
  final db = ref.watch(databaseProvider);
  return db.watchHighlightsForDocument(documentId).map(
        (rows) => rows.map(Highlight.fromEntry).toList(),
      );
});

/// Synchronous derived provider filtering highlights active in a specific chapter.
final chapterHighlightsProvider =
    Provider.family<List<Highlight>, ({String documentId, int chapterIndex})>((
  ref,
  arg,
) {
  final allHighlights =
      ref.watch(highlightsStreamProvider(arg.documentId)).asData?.value ??
          const [];
  return allHighlights
      .where(
        (h) =>
            h.startAnchor.chapterIndex <= arg.chapterIndex &&
            h.endAnchor.chapterIndex >= arg.chapterIndex,
      )
      .toList();
});

/// Controller handling highlight and note mutations.
class HighlightsController {
  HighlightsController(this._ref);
  final Ref _ref;

  AppDatabase get _db => _ref.read(databaseProvider);

  Future<Highlight> createHighlight({
    required String documentId,
    required ReadingAnchor startAnchor,
    required ReadingAnchor endAnchor,
    required String highlightedText,
    required String colorHex,
    String? note,
  }) async {
    // Ensure offsets are strictly non-negative (>= 0)
    final safeStartAnchor = startAnchor.charOffset < 0
        ? ReadingAnchor(
            chapterIndex: startAnchor.chapterIndex,
            paragraphIndex: startAnchor.paragraphIndex,
            charOffset: 0,
          )
        : startAnchor;
    final safeEndAnchor = endAnchor.charOffset < 0
        ? ReadingAnchor(
            chapterIndex: endAnchor.chapterIndex,
            paragraphIndex: endAnchor.paragraphIndex,
            charOffset: 0,
          )
        : endAnchor;

    // Ensure canonical ordering (start <= end)
    final canonicalStart =
        safeStartAnchor <= safeEndAnchor ? safeStartAnchor : safeEndAnchor;
    final canonicalEnd =
        safeStartAnchor <= safeEndAnchor ? safeEndAnchor : safeStartAnchor;

    final id =
        'hl_${DateTime.now().millisecondsSinceEpoch}_${canonicalStart.chapterIndex}_${canonicalStart.paragraphIndex}_${canonicalStart.charOffset}';
    final now = DateTime.now();

    await _db.insertHighlight(
      HighlightsCompanion.insert(
        id: id,
        documentId: documentId,
        startChapterIndex: canonicalStart.chapterIndex,
        startParagraphIndex: canonicalStart.paragraphIndex,
        startCharOffset: canonicalStart.charOffset,
        endChapterIndex: canonicalEnd.chapterIndex,
        endParagraphIndex: canonicalEnd.paragraphIndex,
        endCharOffset: canonicalEnd.charOffset,
        highlightedText: highlightedText,
        colorHex: colorHex,
        note: Value(note),
        createdAt: now,
      ),
    );

    return Highlight(
      id: id,
      documentId: documentId,
      startAnchor: canonicalStart,
      endAnchor: canonicalEnd,
      highlightedText: highlightedText,
      colorHex: colorHex,
      note: note,
      createdAt: now,
    );
  }

  Future<void> updateNote(String id, String? note) async {
    await _db.updateHighlightNote(id, note);
  }

  Future<void> updateColor(String id, String colorHex) async {
    await _db.updateHighlightColor(id, colorHex);
  }

  Future<void> deleteHighlight(String id) async {
    await _db.deleteHighlight(id);
  }
}

final highlightsControllerProvider = Provider<HighlightsController>((ref) {
  return HighlightsController(ref);
});
