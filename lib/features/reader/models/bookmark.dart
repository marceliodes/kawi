import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../providers/document_content_provider.dart';

@immutable
class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.anchor,
    this.chapterTitle,
    required this.snippet,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String bookId;
  final ReadingAnchor anchor;
  final String? chapterTitle;
  final String snippet;
  final DateTime createdAt;
  final String? note;

  Bookmark copyWith({
    String? id,
    String? bookId,
    ReadingAnchor? anchor,
    String? chapterTitle,
    String? snippet,
    DateTime? createdAt,
    String? note,
  }) {
    return Bookmark(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      anchor: anchor ?? this.anchor,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      snippet: snippet ?? this.snippet,
      createdAt: createdAt ?? this.createdAt,
      note: note ?? this.note,
    );
  }

  factory Bookmark.fromEntry(BookmarkEntry entry) {
    return Bookmark(
      id: entry.id,
      bookId: entry.documentId,
      anchor: ReadingAnchor(
        chapterIndex: entry.chapterIndex,
        paragraphIndex: entry.paragraphIndex,
        charOffset: entry.charOffset,
      ),
      chapterTitle: entry.chapterTitle,
      snippet: entry.snippet,
      createdAt: entry.createdAt,
      note: entry.note,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'anchor': anchor.toJson(),
    'chapterTitle': chapterTitle,
    'snippet': snippet,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    bookId: json['bookId'] as String,
    anchor: ReadingAnchor.fromJson(
      (json['anchor'] as Map<dynamic, dynamic>).cast<String, dynamic>(),
    ),
    chapterTitle: json['chapterTitle'] as String?,
    snippet: json['snippet'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    note: json['note'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          bookId == other.bookId &&
          anchor == other.anchor &&
          chapterTitle == other.chapterTitle &&
          snippet == other.snippet &&
          createdAt == other.createdAt &&
          note == other.note;

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    anchor,
    chapterTitle,
    snippet,
    createdAt,
    note,
  );

  @override
  String toString() =>
      'Bookmark(id: $id, bookId: $bookId, anchor: $anchor, title: $chapterTitle, snippet: $snippet)';
}
