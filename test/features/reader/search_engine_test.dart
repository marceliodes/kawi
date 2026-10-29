import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/reader/models/search_models.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/search_provider.dart';
import 'package:kawi/features/reader/services/book_search_engine.dart';

void main() {
  group('Search Models Unit Tests', () {
    test('SearchQuery handles trimming, emptiness, and equality', () {
      const q1 = SearchQuery(query: '  hello world  ', caseSensitive: true);
      const q2 = SearchQuery(query: '  hello world  ', caseSensitive: true);
      const q3 = SearchQuery(query: 'hello world', wholeWord: true);
      const qEmpty = SearchQuery(query: '   ');

      expect(q1.isNotEmpty, isTrue);
      expect(qEmpty.isEmpty, isTrue);
      expect(q1, equals(q2));
      expect(q1.hashCode, equals(q2.hashCode));
      expect(q1, isNot(equals(q3)));
    });

    test('SearchMatch compares by startAnchor in order', () {
      const m1 = SearchMatch(
        id: 'c0_p0_o10',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 10),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 15),
        matchedText: 'hello',
        snippet: 'hello world',
        snippetMatchStart: 0,
        snippetMatchEnd: 5,
        matchIndexInBook: 0,
      );
      const m2 = SearchMatch(
        id: 'c0_p1_o5',
        chapterIndex: 0,
        paragraphIndex: 1,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 5),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 1, charOffset: 10),
        matchedText: 'hello',
        snippet: 'say hello again',
        snippetMatchStart: 4,
        snippetMatchEnd: 9,
        matchIndexInBook: 1,
      );

      expect(m1.compareTo(m2), isNegative);
      expect(m2.compareTo(m1), isPositive);
      expect(m1.compareTo(m1), isZero);
    });

    test('SearchState activeMatch, isEmpty, isNotEmpty, and copyWith', () {
      const state = SearchState();
      expect(state.isEmpty, isTrue);
      expect(state.isNotEmpty, isFalse);
      expect(state.activeMatch, isNull);

      const match = SearchMatch(
        id: 'c0_p0_o0',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        matchedText: 'test',
        snippet: 'test snippet',
        snippetMatchStart: 0,
        snippetMatchEnd: 4,
        matchIndexInBook: 0,
      );

      final populated = state.copyWith(
        query: 'test',
        matches: [match],
        activeMatchIndex: 0,
      );

      expect(populated.isEmpty, isFalse);
      expect(populated.isNotEmpty, isTrue);
      expect(populated.activeMatch, equals(match));
      expect(populated.totalMatches, 1);
    });
  });

  group('BookSearchEngine.extractSnippet Tests', () {
    test('extracts context around match with word boundaries and ellipses', () {
      const text =
          'The fundamental premise of computer science rests upon the elegant mathematics of computation and logic.';
      // "computer" begins at index 27, ends at 35
      final result = BookSearchEngine.extractSnippet(
        text: text,
        matchStart: 27,
        matchEnd: 35,
        contextRadius: 20,
      );

      expect(result.snippet, contains('computer'));
      // Snippet match offsets must match exact target substring
      final extracted = result.snippet.substring(
        result.matchStartInSnippet,
        result.matchEndInSnippet,
      );
      expect(extracted, 'computer');
      expect(result.snippet.startsWith('…'), isTrue);
      expect(result.snippet.endsWith('…'), isTrue);
    });

    test('match at beginning of string has no leading ellipsis', () {
      const text = 'FirstWord is here in this short sentence for testing.';
      final result = BookSearchEngine.extractSnippet(
        text: text,
        matchStart: 0,
        matchEnd: 9,
        contextRadius: 20,
      );

      expect(result.snippet.startsWith('FirstWord'), isTrue);
      expect(result.snippet.startsWith('…'), isFalse);
      final extracted = result.snippet.substring(
        result.matchStartInSnippet,
        result.matchEndInSnippet,
      );
      expect(extracted, 'FirstWord');
    });

    test('match at end of string has no trailing ellipsis', () {
      const text = 'This sentence concludes with LastWord';
      final matchStart = text.indexOf('LastWord');
      final matchEnd = matchStart + 'LastWord'.length;

      final result = BookSearchEngine.extractSnippet(
        text: text,
        matchStart: matchStart,
        matchEnd: matchEnd,
        contextRadius: 20,
      );

      expect(result.snippet.endsWith('LastWord'), isTrue);
      expect(result.snippet.endsWith('…'), isFalse);
      final extracted = result.snippet.substring(
        result.matchStartInSnippet,
        result.matchEndInSnippet,
      );
      expect(extracted, 'LastWord');
    });

    test('defensively handles out-of-range or invalid indices without exception', () {
      const text = 'Short text';
      final emptyResult = BookSearchEngine.extractSnippet(
        text: text,
        matchStart: -1,
        matchEnd: 5,
      );
      expect(emptyResult.snippet, isEmpty);

      final invertedResult = BookSearchEngine.extractSnippet(
        text: text,
        matchStart: 8,
        matchEnd: 4,
      );
      expect(invertedResult.snippet, isEmpty);

      final outOfBoundsResult = BookSearchEngine.extractSnippet(
        text: text,
        matchStart: 0,
        matchEnd: 50,
      );
      expect(outOfBoundsResult.snippet, isEmpty);
    });
  });

  group('SearchController State Management Tests', () {
    test('nextMatch and previousMatch wrap around correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const m1 = SearchMatch(
        id: 'c0_p0_o0',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 3),
        matchedText: 'one',
        snippet: 'one two three',
        snippetMatchStart: 0,
        snippetMatchEnd: 3,
        matchIndexInBook: 0,
      );
      const m2 = SearchMatch(
        id: 'c0_p0_o4',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 4),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 7),
        matchedText: 'two',
        snippet: 'one two three',
        snippetMatchStart: 4,
        snippetMatchEnd: 7,
        matchIndexInBook: 1,
      );
      const m3 = SearchMatch(
        id: 'c0_p0_o8',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 8),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 13),
        matchedText: 'three',
        snippet: 'one two three',
        snippetMatchStart: 8,
        snippetMatchEnd: 13,
        matchIndexInBook: 2,
      );

      final controller = container.read(searchControllerProvider.notifier);
      // Manually simulate matches being loaded into state
      // (Normally populated via onBatch during search)
      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'num',
        matches: [m1, m2, m3],
        groups: [
          SearchResultGroup(
            chapterIndex: 0,
            matches: [m1, m2, m3],
          ),
        ],
        activeMatchIndex: 0,
      );

      expect(container.read(searchControllerProvider).activeMatch, m1);

      // Next -> m2
      final next1 = controller.nextMatch();
      expect(next1, m2);
      expect(container.read(searchControllerProvider).activeMatchIndex, 1);

      // Next -> m3
      final next2 = controller.nextMatch();
      expect(next2, m3);
      expect(container.read(searchControllerProvider).activeMatchIndex, 2);

      // Next -> wraps to m1
      final nextWrap = controller.nextMatch();
      expect(nextWrap, m1);
      expect(container.read(searchControllerProvider).activeMatchIndex, 0);

      // Previous -> wraps to m3
      final prevWrap = controller.previousMatch();
      expect(prevWrap, m3);
      expect(container.read(searchControllerProvider).activeMatchIndex, 2);

      // Previous -> m2
      final prev1 = controller.previousMatch();
      expect(prev1, m2);
      expect(container.read(searchControllerProvider).activeMatchIndex, 1);

      // Direct select
      controller.selectMatch(m1);
      expect(container.read(searchControllerProvider).activeMatchIndex, 0);

      // Clear search
      controller.clearSearch();
      expect(container.read(searchControllerProvider).isEmpty, isTrue);
      expect(container.read(searchControllerProvider).activeMatch, isNull);
    });

    test('chapterSearchMatchesProvider filters matches by chapter index', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const mChap0 = SearchMatch(
        id: 'c0_p0_o0',
        chapterIndex: 0,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 5),
        matchedText: 'alpha',
        snippet: 'alpha',
        snippetMatchStart: 0,
        snippetMatchEnd: 5,
        matchIndexInBook: 0,
      );
      const mChap1 = SearchMatch(
        id: 'c1_p0_o0',
        chapterIndex: 1,
        paragraphIndex: 0,
        startAnchor: ReadingAnchor(chapterIndex: 1, paragraphIndex: 0, charOffset: 0),
        endAnchor: ReadingAnchor(chapterIndex: 1, paragraphIndex: 0, charOffset: 4),
        matchedText: 'beta',
        snippet: 'beta',
        snippetMatchStart: 0,
        snippetMatchEnd: 4,
        matchIndexInBook: 1,
      );

      container.read(searchControllerProvider.notifier).state = const SearchState(
        query: 'greek',
        matches: [mChap0, mChap1],
        groups: [
          SearchResultGroup(chapterIndex: 0, matches: [mChap0]),
          SearchResultGroup(chapterIndex: 1, matches: [mChap1]),
        ],
        activeMatchIndex: 0,
      );

      final matches0 = container.read(chapterSearchMatchesProvider(0));
      final matches1 = container.read(chapterSearchMatchesProvider(1));
      final matches2 = container.read(chapterSearchMatchesProvider(2));

      expect(matches0, [mChap0]);
      expect(matches1, [mChap1]);
      expect(matches2, isEmpty);
    });
  });
}
