import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../providers/document_content_provider.dart';

@immutable
class Highlight {
  const Highlight({
    required this.id,
    required this.documentId,
    required this.startAnchor,
    required this.endAnchor,
    required this.highlightedText,
    required this.colorHex,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final ReadingAnchor startAnchor;
  final ReadingAnchor endAnchor;
  final String highlightedText;
  final String colorHex;
  final String? note;
  final DateTime createdAt;

  bool get isUnderline => colorHex.toLowerCase() == 'underline';

  Color get displayColor {
    if (isUnderline) return const Color(0xFF64B5F6);
    final cleanHex = colorHex.replaceFirst('#', '');
    final intVal = int.tryParse(cleanHex, radix: 16);
    if (intVal != null) {
      return cleanHex.length == 6 ? Color(intVal | 0xFF000000) : Color(intVal);
    }
    return const Color(0xFFFFD54F);
  }

  Color getBackgroundTint({required bool isDark}) {
    return displayColor.withValues(alpha: isDark ? 0.42 : 0.35);
  }

  bool overlapsParagraph(int chapterIndex, int paragraphIndex) {
    final paraStart = ReadingAnchor(
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      charOffset: 0,
    );
    final paraEnd = ReadingAnchor(
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      charOffset: 0x7FFFFFFF,
    );
    return !(endAnchor < paraStart || startAnchor > paraEnd);
  }

  ({int start, int end})? getParagraphSlice({
    required int chapterIndex,
    required int paragraphIndex,
    required int paragraphLength,
  }) {
    if (!overlapsParagraph(chapterIndex, paragraphIndex)) return null;

    int localStart = 0;
    if (startAnchor.chapterIndex == chapterIndex &&
        startAnchor.paragraphIndex == paragraphIndex) {
      localStart = startAnchor.charOffset.clamp(0, paragraphLength);
    }

    int localEnd = paragraphLength;
    if (endAnchor.chapterIndex == chapterIndex &&
        endAnchor.paragraphIndex == paragraphIndex) {
      localEnd = endAnchor.charOffset.clamp(0, paragraphLength);
    }

    if (localStart >= localEnd) return null;
    return (start: localStart, end: localEnd);
  }

  factory Highlight.fromEntry(HighlightEntry entry) {
    return Highlight(
      id: entry.id,
      documentId: entry.documentId,
      startAnchor: ReadingAnchor(
        chapterIndex: entry.startChapterIndex,
        paragraphIndex: entry.startParagraphIndex,
        charOffset: entry.startCharOffset,
      ),
      endAnchor: ReadingAnchor(
        chapterIndex: entry.endChapterIndex,
        paragraphIndex: entry.endParagraphIndex,
        charOffset: entry.endCharOffset,
      ),
      highlightedText: entry.highlightedText,
      colorHex: entry.colorHex,
      note: entry.note,
      createdAt: entry.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'startAnchor': startAnchor.toJson(),
    'endAnchor': endAnchor.toJson(),
    'highlightedText': highlightedText,
    'colorHex': colorHex,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
    id: json['id'] as String,
    documentId: json['documentId'] as String,
    startAnchor: ReadingAnchor.fromJson(
      (json['startAnchor'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
    ),
    endAnchor: ReadingAnchor.fromJson(
      (json['endAnchor'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
    ),
    highlightedText: json['highlightedText'] as String,
    colorHex: json['colorHex'] as String,
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Highlight copyWith({
    String? id,
    String? documentId,
    ReadingAnchor? startAnchor,
    ReadingAnchor? endAnchor,
    String? highlightedText,
    String? colorHex,
    String? note,
    DateTime? createdAt,
  }) {
    return Highlight(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      startAnchor: startAnchor ?? this.startAnchor,
      endAnchor: endAnchor ?? this.endAnchor,
      highlightedText: highlightedText ?? this.highlightedText,
      colorHex: colorHex ?? this.colorHex,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Highlight &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          documentId == other.documentId &&
          startAnchor == other.startAnchor &&
          endAnchor == other.endAnchor &&
          highlightedText == other.highlightedText &&
          colorHex == other.colorHex &&
          note == other.note &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    documentId,
    startAnchor,
    endAnchor,
    highlightedText,
    colorHex,
    note,
    createdAt,
  );

  @override
  String toString() =>
      'Highlight(id: $id, doc: $documentId, range: $startAnchor->$endAnchor, color: $colorHex, text: $highlightedText)';
}
