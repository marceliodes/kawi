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
  });
}
