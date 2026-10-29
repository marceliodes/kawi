import 'package:flutter/foundation.dart';

import '../providers/document_content_provider.dart';

/// Configuration for a book search operation.
@immutable
class SearchQuery {
  const SearchQuery({
    required this.query,
    this.caseSensitive = false,
    this.wholeWord = false,
  });

  final String query;
  final bool caseSensitive;
  final bool wholeWord;

  bool get isEmpty => query.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQuery &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          caseSensitive == other.caseSensitive &&
          wholeWord == other.wholeWord;

  @override
  int get hashCode => Object.hash(query, caseSensitive, wholeWord);

  @override
  String toString() =>
      'SearchQuery("$query", caseSensitive: $caseSensitive, wholeWord: $wholeWord)';
}

/// A single matched occurrence of a search term within a chapter AST node.
@immutable
class SearchMatch implements Comparable<SearchMatch> {
  const SearchMatch({
    required this.id,
    required this.chapterIndex,
    this.chapterTitle,
    required this.paragraphIndex,
    required this.startAnchor,
    required this.endAnchor,
    required this.matchedText,
    required this.snippet,
    required this.snippetMatchStart,
    required this.snippetMatchEnd,
    required this.matchIndexInBook,
  });

  /// Unique identifier: `c${chapterIndex}_p${paragraphIndex}_o${charOffset}`
  final String id;

  /// Index of the chapter in the spine.
  final int chapterIndex;

  /// Human-readable title of the chapter.
  final String? chapterTitle;

  /// Index of the AST node within the chapter's document nodes.
  final int paragraphIndex;

  /// Reading anchor pointing to the start of the match.
  final ReadingAnchor startAnchor;

  /// Reading anchor pointing to the end of the match.
  final ReadingAnchor endAnchor;

  /// Exact text matched.
  final String matchedText;

  /// Surrounding sentence or phrase with word-boundary ellipsis.
  final String snippet;

  /// Start offset of the matched keyword within [snippet].
  final int snippetMatchStart;

  /// End offset of the matched keyword within [snippet].
  final int snippetMatchEnd;

  /// Sequential 0-based index of this match across the entire book.
  final int matchIndexInBook;

  @override
  int compareTo(SearchMatch other) => startAnchor.compareTo(other.startAnchor);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchMatch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          chapterIndex == other.chapterIndex &&
          paragraphIndex == other.paragraphIndex &&
          startAnchor == other.startAnchor &&
          endAnchor == other.endAnchor &&
          matchIndexInBook == other.matchIndexInBook;

  @override
  int get hashCode => Object.hash(id, chapterIndex, paragraphIndex, startAnchor, endAnchor);

  @override
  String toString() =>
      'SearchMatch(#$matchIndexInBook: "$matchedText" at $startAnchor)';
}

/// A cluster of search matches occurring within the same chapter.
@immutable
class SearchResultGroup {
  const SearchResultGroup({
    required this.chapterIndex,
    this.chapterTitle,
    required this.matches,
  });

  final int chapterIndex;
  final String? chapterTitle;
  final List<SearchMatch> matches;

  int get count => matches.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResultGroup &&
          runtimeType == other.runtimeType &&
          chapterIndex == other.chapterIndex &&
          listEquals(matches, other.matches);

  @override
  int get hashCode => Object.hash(chapterIndex, Object.hashAll(matches));
}

/// Immutable state snapshot of the active search session.
@immutable
class SearchState {
  const SearchState({
    this.query = '',
    this.isSearching = false,
    this.matches = const [],
    this.groups = const [],
    this.activeMatchIndex = -1,
    this.errorMessage,
  });

  final String query;
  final bool isSearching;
  final List<SearchMatch> matches;
  final List<SearchResultGroup> groups;
  final int activeMatchIndex;
  final String? errorMessage;

  int get totalMatches => matches.length;
  bool get hasMatches => matches.isNotEmpty;
  bool get isEmpty => query.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  SearchMatch? get activeMatch {
    if (activeMatchIndex >= 0 && activeMatchIndex < matches.length) {
      return matches[activeMatchIndex];
    }
    return null;
  }

  SearchState copyWith({
    String? query,
    bool? isSearching,
    List<SearchMatch>? matches,
    List<SearchResultGroup>? groups,
    int? activeMatchIndex,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      matches: matches ?? this.matches,
      groups: groups ?? this.groups,
      activeMatchIndex: activeMatchIndex ?? this.activeMatchIndex,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          isSearching == other.isSearching &&
          activeMatchIndex == other.activeMatchIndex &&
          errorMessage == other.errorMessage &&
          listEquals(matches, other.matches) &&
          listEquals(groups, other.groups);

  @override
  int get hashCode => Object.hash(
        query,
        isSearching,
        activeMatchIndex,
        errorMessage,
        Object.hashAll(matches),
        Object.hashAll(groups),
      );
}
