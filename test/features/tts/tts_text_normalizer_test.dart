import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/tts/services/tts_text_normalizer.dart';

void main() {
  group('TtsTextNormalizer - Paragraph Whitespace Normalization', () {
    test('replaces isolated single newlines surrounded by text with a single space', () {
      const input = 'This is line one\nof a paragraph that continues\non line three.';
      final result = TtsTextNormalizer.normalizeParagraphWhitespace(input);
      expect(result, equals('This is line one of a paragraph that continues on line three.'));
    });

    test('replaces CRLF isolated newlines surrounded by text with a single space', () {
      const input = 'First line.\r\nSecond line.\r\nThird line.';
      final result = TtsTextNormalizer.normalizeParagraphWhitespace(input);
      expect(result, equals('First line. Second line. Third line.'));
    });

    test('preserves double newlines as paragraph boundaries', () {
      const input = 'Paragraph one line one\nline two.\n\nParagraph two line one\nline two.';
      final result = TtsTextNormalizer.normalizeParagraphWhitespace(input);
      expect(result, equals('Paragraph one line one line two.\n\nParagraph two line one line two.'));
    });

    test('collapses multiple horizontal spaces inside paragraphs', () {
      const input = 'Word one    word two  \t  word three.';
      final result = TtsTextNormalizer.normalizeParagraphWhitespace(input);
      expect(result, equals('Word one word two word three.'));
    });
  });

  group('TtsTextNormalizer - Sentence Splitting & Dialog Preservation', () {
    test('does not break mid-sentence on isolated newlines inside EPUB dialog', () {
      const input = '“Consult Nanahoshi,”\nshe said.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(1));
      expect(chunks.first.text, equals('“Consult Nanahoshi,” she said.'));
    });

    test('preserves dialog quotes with internal commas from splitting', () {
      const input = '“Consult Nanahoshi,” she said. “We need her guidance.”';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('“Consult Nanahoshi,” she said.'));
      expect(chunks[1].text, equals('“We need her guidance.”'));
    });

    test('preserves exclamation or question in dialog with lowercase speech tag', () {
      const input = '“Wait!” he shouted. “Where are you going?” she asked.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('“Wait!” he shouted.'));
      expect(chunks[1].text, equals('“Where are you going?” she asked.'));
    });

    test('splits sentences on terminal punctuation followed by closing quotes and capital letter', () {
      const input = '“Consult Nanahoshi.” Rudeus turned away.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('“Consult Nanahoshi.”'));
      expect(chunks[1].text, equals('Rudeus turned away.'));
    });

    test('splits on paragraph breaks without terminal punctuation', () {
      const input = 'CHAPTER 1\n\nIt was a quiet morning.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('Chapter 1'));
      expect(chunks[1].text, equals('It was a quiet morning.'));
    });

    test('does not split on abbreviations or honorifics', () {
      const input = 'Dr. Smith and Mr. Jones met at 5 p.m. to discuss the plan.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, contains('Dr. Smith and Mr. Jones'));
    });
  });

  group('TtsTextNormalizer - All-Caps Acronym Resolution', () {
    test('normalizes leading all-caps opener "IT WAS THE MORNING"', () {
      const input = 'IT WAS THE MORNING of the third day.';
      final normalized = TtsTextNormalizer.normalizeAllCaps(input);
      expect(normalized, equals('It was the morning of the third day.'));
    });

    test('normalizes chapter titles like "CHAPTER 1" and "CHAPTER 1: THE BEGINNING"', () {
      expect(TtsTextNormalizer.normalizeAllCaps('CHAPTER 1'), equals('Chapter 1'));
      expect(
        TtsTextNormalizer.normalizeAllCaps('CHAPTER 1: THE BEGINNING'),
        equals('Chapter 1: the beginning'),
      );
    });

    test('normalizes isolated leading common words THE, HE, SHE, IT', () {
      expect(TtsTextNormalizer.normalizeAllCaps('THE world is vast.'), equals('The world is vast.'));
      expect(TtsTextNormalizer.normalizeAllCaps('HE walked into town.'), equals('He walked into town.'));
      expect(TtsTextNormalizer.normalizeAllCaps('SHE smiled softly.'), equals('She smiled softly.'));
      expect(TtsTextNormalizer.normalizeAllCaps('IT was cold outside.'), equals('It was cold outside.'));
    });

    test('normalizes common all-caps pronouns and prepositions inside sentences', () {
      const input = 'Give IT to US at ONCE and tell ME.';
      final normalized = TtsTextNormalizer.normalizeAllCaps(input);
      expect(normalized, equals('Give it to us at once and tell me.'));
    });

    test('preserves recognized abbreviations like USA, FBI, ID', () {
      const input = 'He showed his ID to the FBI agent in the USA.';
      final normalized = TtsTextNormalizer.normalizeAllCaps(input);
      expect(normalized, equals('He showed his ID to the FBI agent in the USA.'));
    });

    test('handles quotes and punctuation surrounding all-caps words', () {
      const input = '“IT WAS THE MORNING,” she said.';
      final normalized = TtsTextNormalizer.normalizeAllCaps(input);
      expect(normalized, equals('“It was the morning,” she said.'));
    });

    test('splits sentences and normalizes all-caps tokens seamlessly', () {
      const input = 'IT WAS THE MORNING.\n\nCHAPTER 1\n\nShe gave IT to US in the USA.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(3));
      expect(chunks[0].text, equals('It was the morning.'));
      expect(chunks[1].text, equals('Chapter 1'));
      expect(chunks[2].text, equals('She gave it to us in the USA.'));
    });

    test('normalizes chapter opener "IT WAS" to "It was" to prevent pronunciation as "I.T."', () {
      expect(TtsTextNormalizer.normalizeAllCaps('IT WAS'), equals('It was'));
      expect(
        TtsTextNormalizer.normalizeAllCaps('IT WAS a cold and stormy night.'),
        equals('It was a cold and stormy night.'),
      );
      expect(
        TtsTextNormalizer.normalizeAllCaps('“IT WAS,” he murmured.'),
        equals('“It was,” he murmured.'),
      );
    });

    test('replaces soft line breaks within paragraphs with space so clauses are not cut', () {
      const rawChapter =
          'IT WAS the best of times,\n'
          'it was the worst of times,\n'
          'it was the age of wisdom,\n'
          'it was the age of foolishness.\n\n'
          'Here is the second paragraph,\n'
          'which also has soft line breaks!';

      final chunks = TtsTextNormalizer.splitIntoSentences(rawChapter);
      expect(chunks.length, equals(2));
      expect(
        chunks[0].text,
        equals(
          'It was the best of times, '
          'it was the worst of times, '
          'it was the age of wisdom, '
          'it was the age of foolishness.',
        ),
      );
      expect(
        chunks[1].text,
        equals('Here is the second paragraph, which also has soft line breaks!'),
      );
    });

    test('only splits on terminal punctuation (. ! ?) followed by whitespace or quotes or double newlines', () {
      const text =
          'Clause one, not ending;\n'
          'clause two: still not ending.\n\n'
          '“Is that so?” asked Alice. “Yes!” replied Bob.';

      final chunks = TtsTextNormalizer.splitIntoSentences(text);
      expect(chunks.length, equals(3));
      expect(chunks[0].text, equals('Clause one, not ending; clause two: still not ending.'));
      expect(chunks[1].text, equals('“Is that so?” asked Alice.'));
      expect(chunks[2].text, equals('“Yes!” replied Bob.'));
    });

    test('filterPlaceholdersAndTags strips [image], [image:...], and raw HTML tags', () {
      expect(TtsTextNormalizer.filterPlaceholdersAndTags('[image]'), equals(''));
      expect(TtsTextNormalizer.filterPlaceholdersAndTags('[IMAGE:1]'), equals(''));
      expect(TtsTextNormalizer.filterPlaceholdersAndTags('[image:cover.jpg]'), equals(''));
      expect(
        TtsTextNormalizer.filterPlaceholdersAndTags('<p>Hello <b>world</b>!</p>'),
        equals('Hello world!'),
      );
      expect(
        TtsTextNormalizer.filterPlaceholdersAndTags('Look at this [image:header.png] picture.'),
        equals('Look at this  picture.'),
      );
    });

    test('splitIntoSentences filters out image placeholders and raw HTML tags without creating empty sentences', () {
      const input =
          '[image:cover]\n\n'
          '<p>IT WAS a dark and stormy night.</p>\n\n'
          '[image:1]\n\n'
          '<div><span>The wind began to howl.</span></div>\n\n'
          '[image]';

      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(2));
      expect(chunks[0].text, equals('It was a dark and stormy night.'));
      expect(chunks[1].text, equals('The wind began to howl.'));
    });

    test('splitIntoSentences drops whitespace-only and tag-only chunks completely', () {
      const input = '   [image:1]   \n\n<p>   </p>\n\n   \n\nValid sentence.';
      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(1));
      expect(chunks[0].text, equals('Valid sentence.'));
    });

    test('discards non-alphanumeric chunks so sentence 1 begins directly with actual text', () {
      const input =
          '[image:cover.jpg] [image:1]\n\n'
          '[]\n\n'
          '* * *\n\n'
          'Chapter 1: The Diary (Part 1)\n\n'
          'It was a quiet evening.';

      final chunks = TtsTextNormalizer.splitIntoSentences(input);
      expect(chunks.length, equals(2));
      expect(chunks[0].index, equals(0));
      expect(chunks[0].text, equals('Chapter 1: The Diary (Part 1)'));
      expect(chunks[1].index, equals(1));
      expect(chunks[1].text, equals('It was a quiet evening.'));
    });

    test('hasAlphanumeric correctly identifies strings with or without alphanumeric chars', () {
      expect(TtsTextNormalizer.hasAlphanumeric(''), isFalse);
      expect(TtsTextNormalizer.hasAlphanumeric('   '), isFalse);
      expect(TtsTextNormalizer.hasAlphanumeric('[]'), isFalse);
      expect(TtsTextNormalizer.hasAlphanumeric('* * *'), isFalse);
      expect(TtsTextNormalizer.hasAlphanumeric('---'), isFalse);
      expect(TtsTextNormalizer.hasAlphanumeric('. ! ?'), isFalse);
      expect(TtsTextNormalizer.hasAlphanumeric('Chapter 1'), isTrue);
      expect(TtsTextNormalizer.hasAlphanumeric('42'), isTrue);
      expect(TtsTextNormalizer.hasAlphanumeric('a'), isTrue);
    });

    test('normalizeSentenceWhitespace strips tags, orphan brackets, and collapses whitespace', () {
      const input = '  [image:test.png]   <p>Hello</p>  []   world!   ';
      final result = TtsTextNormalizer.normalizeSentenceWhitespace(input);
      expect(result, equals('Hello world!'));
    });
  });
}
