import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/search_models.dart';
import '../services/book_search_engine.dart';

/// Controller managing in-book search state, isolate execution, debouncing, and match navigation.
class BookSearchController extends Notifier<SearchState> {
  Timer? _debounceTimer;
  BookSearchSession? _currentSession;
  String? _currentFilePath;
  bool _isDisposed = false;

  @override
  SearchState build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _debounceTimer?.cancel();
      _currentSession?.cancel();
    });
    return const SearchState();
  }

  /// Sets the active document file path. Clears search if the document changed.
  void setDocumentFilePath(String filePath) {
    if (_currentFilePath != filePath) {
      _currentFilePath = filePath;
      clearSearch();
    }
  }

  /// Updates search query with 250ms debouncing.
  /// If [immediate] is true, triggers search instantly without waiting for debounce.
  void onQueryChanged(String query, {bool immediate = false}) {
    _debounceTimer?.cancel();
    final clean = query.trim();
    if (clean.isEmpty) {
      clearSearch();
      return;
    }

    if (immediate) {
      _executeSearch(clean);
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 250), () {
        _executeSearch(clean);
      });
    }
  }

  void _executeSearch(String query) {
    final filePath = _currentFilePath;
    if (filePath == null || filePath.isEmpty) return;

    _currentSession?.cancel();
    _currentSession = null;

    state = state.copyWith(
      query: query,
      isSearching: true,
      matches: const [],
      groups: const [],
      activeMatchIndex: -1,
      clearError: true,
    );

    BookSearchEngine.startSearch(
      filePath: filePath,
      query: SearchQuery(query: query),
      onBatch: (newGroup) {
        if (_isDisposed) return;
        final updatedGroups = List<SearchResultGroup>.from(state.groups)..add(newGroup);
        final updatedMatches = List<SearchMatch>.from(state.matches)..addAll(newGroup.matches);

        var nextActive = state.activeMatchIndex;
        if (nextActive == -1 && updatedMatches.isNotEmpty) {
          nextActive = 0;
        }

        state = state.copyWith(
          groups: updatedGroups,
          matches: updatedMatches,
          activeMatchIndex: nextActive,
        );
      },
      onProgress: (scanned, total) {},
      onComplete: (total, durationMs) {
        if (_isDisposed) return;
        state = state.copyWith(isSearching: false);
      },
      onError: (err) {
        if (_isDisposed) return;
        state = state.copyWith(
          isSearching: false,
          errorMessage: err.toString(),
        );
      },
    ).then((session) {
      _currentSession = session;
    });
  }

  /// Advances to the next search match (wrapping around to the first).
  SearchMatch? nextMatch() {
    if (state.matches.isEmpty) return null;
    final nextIndex = (state.activeMatchIndex + 1) % state.matches.length;
    state = state.copyWith(activeMatchIndex: nextIndex);
    return state.activeMatch;
  }

  /// Navigates to the previous search match (wrapping around to the last).
  SearchMatch? previousMatch() {
    if (state.matches.isEmpty) return null;
    final prevIndex = state.activeMatchIndex <= 0
        ? state.matches.length - 1
        : state.activeMatchIndex - 1;
    state = state.copyWith(activeMatchIndex: prevIndex);
    return state.activeMatch;
  }

  /// Selects a specific search match directly.
  void selectMatch(SearchMatch match) {
    final idx = state.matches.indexWhere((m) => m.id == match.id);
    if (idx != -1) {
      state = state.copyWith(activeMatchIndex: idx);
    }
  }

  /// Clears active search session and results.
  void clearSearch() {
    _debounceTimer?.cancel();
    _currentSession?.cancel();
    _currentSession = null;
    try {
      state = const SearchState();
    } catch (_) {}
  }
}

/// Provider exposing the search controller.
final searchControllerProvider =
    NotifierProvider<BookSearchController, SearchState>(BookSearchController.new);

/// Provider exposing the active search state snapshot.
final searchStateProvider = searchControllerProvider;

/// Provider exposing the currently active/focused search match.
final activeSearchMatchProvider = Provider<SearchMatch?>((ref) {
  return ref.watch(searchControllerProvider).activeMatch;
});

/// Provider exposing search matches for a specific chapter index.
final chapterSearchMatchesProvider =
    Provider.family<List<SearchMatch>, int>((ref, chapterIndex) {
  final state = ref.watch(searchControllerProvider);
  for (final group in state.groups) {
    if (group.chapterIndex == chapterIndex) {
      return group.matches;
    }
  }
  return const [];
});
