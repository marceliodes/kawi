import '../models/tts_models.dart';

/// Preprocessing and sentence tokenization utility for TTS.
///
/// Normalizes paragraph whitespace, eliminates mid-sentence splits from EPUB line wraps,
/// preserves dialog quotes and attribution tags, and resolves all-caps acronym confusion
/// (e.g. converting chapter opener "IT WAS THE MORNING" or words like "IT", "US" to phonetic casing).
class TtsTextNormalizer {
  const TtsTextNormalizer._();

  /// Common English pronouns, prepositions, articles, and chapter keywords that
  /// TTS phonemizers commonly misinterpret as acronyms (e.g. spelling out "I. T." or "U. S.").
  static const Set<String> commonWordsToNormalize = {
    // English pronouns, prepositions, articles:
    'IT', 'US', 'IN', 'ON', 'AT', 'THE', 'A', 'AN', 'HE', 'SHE', 'WE', 'ME', 'MY',
    // Additional common pronouns, prepositions, articles, verbs:
    'HIM', 'HER', 'HIS', 'THEY', 'THEM', 'THEIR', 'THEIRS', 'ITS', 'OUR', 'OURS',
    'YOU', 'YOUR', 'YOURS', 'WHO', 'WHOM', 'WHOSE', 'WHICH', 'WHAT',
    'OF', 'TO', 'FOR', 'WITH', 'FROM', 'BY', 'AS', 'INTO', 'ONTO', 'UPON', 'ABOUT',
    'IS', 'AM', 'ARE', 'WAS', 'WERE', 'BE', 'BEEN', 'BEING',
    'HAVE', 'HAS', 'HAD', 'DO', 'DOES', 'DID', 'WILL', 'WOULD', 'SHALL', 'SHOULD',
    'CAN', 'COULD', 'MAY', 'MIGHT', 'MUST',
    'AND', 'BUT', 'OR', 'NOR', 'SO', 'YET', 'IF', 'THEN', 'THAN',
    'THIS', 'THAT', 'THESE', 'THOSE', 'THERE', 'HERE',
    'ONCE', 'NOW', 'ONE', 'TWO', 'ALL', 'ANY', 'SOME', 'EVERY',
    'WHEN', 'WHERE', 'WHY', 'HOW', 'NOT', 'NO', 'YES',
    'CHAPTER', 'PROLOGUE', 'EPILOGUE', 'INTERLUDE', 'ACT', 'SCENE', 'PART', 'BOOK',
  };

  /// Well-known all-caps acronyms and initialisms that SHOULD be preserved as-is.
  static const Set<String> recognizedAbbreviations = {
    'USA', 'USAF', 'UK', 'EU', 'UN', 'NATO', 'NASA', 'FBI', 'CIA', 'NSA', 'IRS',
    'ID', 'AI', 'UI', 'UX', 'CPU', 'GPU', 'RAM', 'ROM', 'OS', 'PDF', 'HTML', 'XML',
    'API', 'SDK', 'URL', 'URI', 'HTTP', 'HTTPS', 'FTP', 'SSH', 'SQL',
    'VIP', 'TV', 'DVD', 'CD', 'PC', 'DJ', 'MC', 'OK', 'KO',
    'CEO', 'CTO', 'CFO', 'COO', 'CIO', 'VP', 'PR', 'HR',
    'AM', 'PM', 'BC', 'AD', 'BCE', 'CE',
    'DNA', 'RNA', 'COVID', 'AIDS', 'HIV',
    'RPG', 'NPC', 'XP', 'HP', 'MP',
    'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
  };

  /// Normalizes whitespace inside paragraphs before sentence tokenization:
  /// - Standardizes CRLF and CR to LF.
  /// - Standardizes paragraph breaks (\n\n+) to clean '\n\n'.
  /// - Replaces isolated single newlines surrounded by text with a single space ' ',
  ///   preventing hard line breaks in EPUBs from breaking sentences mid-clause.
  /// - Preserves double newlines (\n\n) as paragraph boundaries.
  static String normalizeParagraphWhitespace(String text) {
    if (text.isEmpty) return text;

    // 1. Convert all line break styles to standard \n
    var result = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 2. Standardize multiple newlines (paragraph boundaries) with optional horizontal spaces
    result = result.replaceAll(RegExp(r'\n[ \t]*\n+'), '\n\n');

    // 3. Replace isolated single newlines (surrounded by text / horizontal spaces) with a single space
    result = result.replaceAll(RegExp(r'[ \t]*(?<!\n)\n(?!\n)[ \t]*'), ' ');

    // 4. Collapse multiple horizontal spaces/tabs within a paragraph into a single space
    result = result.replaceAll(RegExp(r'[ \t]+'), ' ');

    return result.trim();
  }

  /// Normalizes all-caps words to avoid TTS acronym confusion (e.g. "IT" pronounced "I. T."):
  /// - Detects all-caps leading words common in chapter openers (e.g. "IT WAS THE MORNING", "CHAPTER 1", "THE", "HE", "SHE", "IT").
  /// - Converts all-caps common English pronouns/prepositions/articles (IT, US, IN, ON, AT, THE, A, AN, HE, SHE, WE, ME, MY)
  ///   to sentence-case (at start of sentence) or lowercase (elsewhere), unless recognized as abbreviations (e.g. USA, FBI, ID).
  static String normalizeAllCaps(String text) {
    if (text.isEmpty) return text;

    // Fast check: if string contains no uppercase ASCII characters, return as-is
    if (!text.contains(RegExp(r'[A-Z]'))) return text;

    // Extract word tokens matching non-whitespace runs
    final matches = RegExp(r'\S+').allMatches(text).toList();
    if (matches.isEmpty) return text;

    final tokens = <_TokenMatch>[];
    for (final m in matches) {
      final tokenStr = m.group(0)!;
      final parsed = _parseToken(tokenStr, m.start, m.end);
      tokens.add(parsed);
    }

    // Identify run of all-caps leading words (chapter openers like "IT WAS THE MORNING", "CHAPTER 1")
    var leadingRunEnd = 0;
    while (leadingRunEnd < tokens.length) {
      final t = tokens[leadingRunEnd];
      if (t.isAllCaps || (leadingRunEnd > 0 && t.isDigit)) {
        leadingRunEnd++;
      } else {
        break;
      }
    }

    final buffer = StringBuffer();
    var lastIdx = 0;

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      // Append non-word text (whitespace) between previous token and current
      buffer.write(text.substring(lastIdx, t.start));

      String newCore = t.core;
      if (!t.isDigit && t.core.isNotEmpty && !recognizedAbbreviations.contains(t.core)) {
        if (leadingRunEnd >= 2 && i < leadingRunEnd) {
          // Multi-token leading all-caps run (e.g. "IT WAS THE MORNING", "CHAPTER 1")
          if (i == 0) {
            newCore = _toTitleCase(t.core);
          } else {
            newCore = t.core.toLowerCase();
          }
        } else if (i == 0 && leadingRunEnd == 1 && commonWordsToNormalize.contains(t.core)) {
          // Single leading all-caps word from common set (e.g. "IT was cold", "SHE smiled")
          newCore = _toTitleCase(t.core);
        } else if (commonWordsToNormalize.contains(t.core)) {
          // All-caps word in common set appearing elsewhere in the sentence
          newCore = (i == 0) ? _toTitleCase(t.core) : t.core.toLowerCase();
        }
      }

      buffer.write(t.prefix);
      buffer.write(newCore);
      buffer.write(t.suffix);
      lastIdx = t.end;
    }

    if (lastIdx < text.length) {
      buffer.write(text.substring(lastIdx));
    }

    return buffer.toString();
  }

  /// Splits [text] into sentences according to literary typography rules:
  /// 1. Normalizes paragraph whitespace (single newlines become spaces).
  /// 2. Treats double newlines (\n\n) or terminal punctuation followed by whitespace
  ///    ([.!?]["'”’]?\s+) as boundaries.
  /// 3. Preserves dialog quotes (e.g. “Consult Nanahoshi,”) so they don't prematurely
  ///    split on internal quotation punctuation or dialog tags.
  /// 4. Normalizes all-caps chapter openers and words in each sentence chunk.
  static List<SentenceChunk> splitIntoSentences(String text) {
    final normalized = normalizeParagraphWhitespace(text);
    if (normalized.trim().isEmpty) return const [];

    final sentences = <SentenceChunk>[];

    // Boundary regex:
    // - Negative lookbehind for common honorifics and abbreviations (Mr., Mrs., Dr., etc.)
    // - Terminal punctuation (. ! ? or …) followed by optional closing quotes/brackets,
    //   followed by whitespace (\s+ which includes \n\n), not followed by a lowercase letter
    //   (preserving dialogue tags like: “Wait!” he said.)
    // - OR double newlines (\n\n+), which demarcate paragraph boundaries even without punctuation.
    final boundaryRegex = RegExp(
      r'(?:'
      r'(?<!\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|e\.g|i\.e))'
      r'''([.!?]+["'”’»\)]*)\s+(?![a-z])'''
      r'|'
      r'\n\n+'
      r')',
    );

    var currentStart = 0;
    var sentenceIndex = 0;

    for (final match in boundaryRegex.allMatches(normalized)) {
      final punctGroup = match.group(1);
      final int sentenceEnd;
      if (punctGroup != null) {
        sentenceEnd = match.start + punctGroup.length;
      } else {
        sentenceEnd = match.start;
      }

      final chunkStart = currentStart;
      final chunkEnd = sentenceEnd;
      currentStart = match.end;

      final slice = normalized.substring(chunkStart, chunkEnd);
      final rawSentence = slice.trim();

      if (rawSentence.isNotEmpty) {
        final processedText = normalizeAllCaps(rawSentence);
        final words = processedText
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();

        final leadingSpaces = slice.indexOf(rawSentence);
        final actualStart = chunkStart + (leadingSpaces >= 0 ? leadingSpaces : 0);
        final actualEnd = actualStart + rawSentence.length;

        sentences.add(
          SentenceChunk(
            index: sentenceIndex++,
            text: processedText,
            charStart: actualStart,
            charEnd: actualEnd,
            words: words,
          ),
        );
      }
    }

    // Remainder after the last matched boundary
    if (currentStart < normalized.length) {
      final slice = normalized.substring(currentStart);
      final rawSentence = slice.trim();
      if (rawSentence.isNotEmpty) {
        final processedText = normalizeAllCaps(rawSentence);
        final words = processedText
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();

        final leadingSpaces = slice.indexOf(rawSentence);
        final actualStart = currentStart + (leadingSpaces >= 0 ? leadingSpaces : 0);
        final actualEnd = actualStart + rawSentence.length;

        sentences.add(
          SentenceChunk(
            index: sentenceIndex,
            text: processedText,
            charStart: actualStart,
            charEnd: actualEnd,
            words: words,
          ),
        );
      }
    }

    return sentences;
  }

  static _TokenMatch _parseToken(String token, int start, int end) {
    final match = RegExp(r"^([^a-zA-Z0-9]*)([a-zA-Z0-9]+(?:['’][a-zA-Z0-9]+)*)([^a-zA-Z0-9]*)$").firstMatch(token);
    if (match == null) {
      return _TokenMatch(
        start: start,
        end: end,
        original: token,
        prefix: '',
        core: token,
        suffix: '',
        isAllCaps: false,
        isDigit: false,
      );
    }

    final prefix = match.group(1)!;
    final core = match.group(2)!;
    final suffix = match.group(3)!;
    final isDigit = RegExp(r'^\d+$').hasMatch(core);
    final isAllCaps = !isDigit && core == core.toUpperCase() && core != core.toLowerCase();

    return _TokenMatch(
      start: start,
      end: end,
      original: token,
      prefix: prefix,
      core: core,
      suffix: suffix,
      isAllCaps: isAllCaps,
      isDigit: isDigit,
    );
  }

  static String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    if (text.length == 1) return text.toUpperCase();
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}

class _TokenMatch {
  final int start;
  final int end;
  final String original;
  final String prefix;
  final String core;
  final String suffix;
  final bool isAllCaps;
  final bool isDigit;

  const _TokenMatch({
    required this.start,
    required this.end,
    required this.original,
    required this.prefix,
    required this.core,
    required this.suffix,
    required this.isAllCaps,
    required this.isDigit,
  });
}
