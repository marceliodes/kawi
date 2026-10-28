import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/reader/models/highlight.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';

void main() {
  group('ReadingAnchor Comparisons', () {
    test('compares anchors positionally by chapter, paragraph, then offset', () {
      const a1 = ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 5);
      const a2 = ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 10);
      const a3 = ReadingAnchor(chapterIndex: 0, paragraphIndex: 2, charOffset: 0);
      const a4 = ReadingAnchor(chapterIndex: 1, paragraphIndex: 0, charOffset: 0);

      expect(a1 < a2, isTrue);
      expect(a1 <= a2, isTrue);
      expect(a2 > a1, isTrue);
      expect(a2 >= a1, isTrue);

      expect(a2 < a3, isTrue);
      expect(a3 < a4, isTrue);
      expect(a1.compareTo(a1), 0);
      expect(a1 <= a1, isTrue);
      expect(a1 >= a1, isTrue);
    });
  });

  group('Highlight Domain Model', () {
    final now = DateTime(2026, 10, 28, 10, 30);
    final highlight = Highlight(
      id: 'hl-1',
      documentId: 'doc-1',
      startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 2, charOffset: 10),
      endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 2, charOffset: 30),
      highlightedText: 'sample highlighted text',
      colorHex: '#FFD54F',
      note: 'My personal note',
      createdAt: now,
    );

    test('supports equality, hashCode, and copyWith', () {
      final copy = highlight.copyWith(colorHex: '#81C784');
      expect(copy.id, highlight.id);
      expect(copy.colorHex, '#81C784');
      expect(copy.note, highlight.note);
      expect(copy == highlight, isFalse);

      final same = highlight.copyWith();
      expect(same, highlight);
      expect(same.hashCode, highlight.hashCode);
    });

    test('serializes and deserializes to/from JSON cleanly', () {
      final json = highlight.toJson();
      final revived = Highlight.fromJson(json);

      expect(revived.id, highlight.id);
      expect(revived.documentId, highlight.documentId);
      expect(revived.startAnchor, highlight.startAnchor);
      expect(revived.endAnchor, highlight.endAnchor);
      expect(revived.highlightedText, highlight.highlightedText);
      expect(revived.colorHex, highlight.colorHex);
      expect(revived.note, highlight.note);
      expect(revived.createdAt, highlight.createdAt);
      expect(revived, highlight);
    });

    test('color resolution and background tinting', () {
      expect(highlight.isUnderline, isFalse);
      expect(highlight.displayColor, const Color(0xFFFFD54F));
      expect(highlight.getBackgroundTint(isDark: false).a, closeTo(0.35, 0.01));
      expect(highlight.getBackgroundTint(isDark: true).a, closeTo(0.42, 0.01));

      final underline = highlight.copyWith(colorHex: 'underline');
      expect(underline.isUnderline, isTrue);
    });

    test('paragraph overlap and slicing within single paragraph', () {
      expect(highlight.overlapsParagraph(0, 1), isFalse);
      expect(highlight.overlapsParagraph(0, 2), isTrue);
      expect(highlight.overlapsParagraph(0, 3), isFalse);
      expect(highlight.overlapsParagraph(1, 2), isFalse);

      final slice = highlight.getParagraphSlice(
        chapterIndex: 0,
        paragraphIndex: 2,
        paragraphLength: 100,
      );
      expect(slice, isNotNull);
      expect(slice!.start, 10);
      expect(slice.end, 30);
    });

    test('multi-paragraph slicing across boundaries', () {
      final multi = Highlight(
        id: 'hl-multi',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 50),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 3, charOffset: 20),
        highlightedText: 'multi paragraph text',
        colorHex: '#64B5F6',
        createdAt: now,
      );

      // Paragraph 1: from offset 50 to end of paragraph (length 100)
      final sliceP1 = multi.getParagraphSlice(
        chapterIndex: 0,
        paragraphIndex: 1,
        paragraphLength: 100,
      );
      expect(sliceP1?.start, 50);
      expect(sliceP1?.end, 100);

      // Paragraph 2: entire paragraph (length 80)
      final sliceP2 = multi.getParagraphSlice(
        chapterIndex: 0,
        paragraphIndex: 2,
        paragraphLength: 80,
      );
      expect(sliceP2?.start, 0);
      expect(sliceP2?.end, 80);

      // Paragraph 3: from start (0) to offset 20
      final sliceP3 = multi.getParagraphSlice(
        chapterIndex: 0,
        paragraphIndex: 3,
        paragraphLength: 120,
      );
      expect(sliceP3?.start, 0);
      expect(sliceP3?.end, 20);

      // Paragraph 4: not covered
      final sliceP4 = multi.getParagraphSlice(
        chapterIndex: 0,
        paragraphIndex: 4,
        paragraphLength: 50,
      );
      expect(sliceP4, isNull);
    });
  });
}
