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
    'HIM', 'HER', 'HIS', 'THEY', 'THEM', 'THEIR', 'THEIRS', 'ITS', "IT'S", 'IT’S', 'OUR', 'OURS',
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

  /// Filters out image placeholder tags and raw HTML tags:
  /// - Strips image placeholders like [image] or [image:1] or [image:cover.jpg]
  /// - Strips raw HTML tags like <p>, </span>, etc.
  /// - Strips residual orphan brackets like [] or [ ]
  static String filterPlaceholdersAndTags(String text) {
    if (text.isEmpty) return text;
    var result = text.replaceAll(
      RegExp(r'\[image[^\]]*\]', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'<[^>]*>'), '');
    result = result.replaceAll(RegExp(r'\[\s*\]'), '');
    return result;
  }

  /// Checks if a string contains any alphanumeric character ([a-zA-Z0-9]).
  static bool hasAlphanumeric(String text) {
    return RegExp(r'[a-zA-Z0-9]').hasMatch(text);
  }

  /// Normalizes whitespace in an individual sentence or chunk:
  /// - Strips image placeholders, HTML tags, orphan brackets
  /// - Collapses any sequence of whitespace to a single space
  /// - Trims leading and trailing whitespace
  static String normalizeSentenceWhitespace(String text) {
    var result = filterPlaceholdersAndTags(text);
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  /// Completely flattens soft line wraps within paragraphs and removes image/HTML artifacts:
  /// - Step A: Removes image placeholders and HTML artifacts
  /// - Step B: Replaces soft line breaks (single \n surrounded by text) with a single space.
  ///   Does NOT touch double newlines (\n\n) which represent paragraph breaks.
  /// - Step C: Collapses consecutive whitespace/tabs into a single space and trims.
  static String flattenSoftLineBreaks(String rawText) {
    if (rawText.isEmpty) return rawText;

    // A. Strip image tokens and tags
    String cleaned = rawText
        .replaceAll(RegExp(r'\[image[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '');

    // Reattach closing quotes/brackets wrapped onto a new line to preceding terminal punctuation
    cleaned = cleaned.replaceAllMapped(
      RegExp(r"""([.!?…])[ \t]*(?:\r?\n(?!\r?\n)[ \t]*|[ \t]+)(["'”’»\)\]]+)"""),
      (m) => '${m[1]}${m[2]}',
    );

    // B. Normalize Windows/Mac line endings to \n
    cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // C. Split into paragraphs by double-newlines
    final paragraphs = cleaned.split(RegExp(r'\n{2,}'));

    // D. In each paragraph, replace every single \n with a space and collapse whitespace
    final flattenedParagraphs = paragraphs.map((p) {
      return p
          .replaceAll('\n', ' ')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .trim();
    }).where((p) => p.isNotEmpty);

    // E. Rejoin paragraphs with double newlines
    return flattenedParagraphs.join('\n\n');
  }

  /// Splits text into sanitized sentence strings according to literary typography rules:
  /// 1. Flattens soft line wraps within paragraphs while preserving double newlines (\n\n).
  /// 2. Splits ONLY on true terminal punctuation (. ! ?) followed by whitespace/quotes,
  ///    OR on true paragraph breaks (\n\n).
  /// 3. Discards orphan punctuation tokens without alphanumeric characters.
  static List<String> extractSanitizedSentenceList(String rawText) {
    final text = flattenSoftLineBreaks(rawText);
    if (text.isEmpty) return const [];

    final sentenceRegex = RegExp(
      r'''(?<!\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|e\.g|i\.e)\.["'”’]?)(?<=[.!?]["'”’]?)\s+(?=[A-Z0-9“"‘'])|(?:\r?\n){2,}''',
    );

    return text
        .split(sentenceRegex)
        .map((s) => s.replaceFirst(RegExp(r'''^[”’»\)\]]+\s*'''), '').trim())
        .where((s) => s.isNotEmpty && RegExp(r'[a-zA-Z0-9]').hasMatch(s))
        .toList();
  }

  /// Normalizes whitespace inside paragraphs before sentence tokenization:
  /// - Strips image markers and HTML tags.
  /// - Standardizes CRLF and CR to LF.
  /// - Standardizes paragraph breaks (\n\n+) to clean '\n\n'.
  /// - Replaces isolated single newlines surrounded by text with a single space ' ',
  ///   preventing hard line breaks in EPUBs from breaking sentences mid-clause.
  /// - Preserves double newlines (\n\n) as paragraph boundaries.
  static String normalizeParagraphWhitespace(String text) {
    return flattenSoftLineBreaks(text);
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
  ///    as boundaries.
  /// 3. Preserves dialog quotes (e.g. “Consult Nanahoshi,”) so they don't prematurely
  ///    split on internal quotation punctuation or dialog tags.
  /// 4. Discards any resulting token that has no alphanumeric characters.
  /// 5. Normalizes all-caps chapter openers and words in each sentence chunk.
  static List<SentenceChunk> splitIntoSentences(String text) {
    final rawSentences = extractSanitizedSentenceList(text);
    if (rawSentences.isEmpty) return const [];

    final sentences = <SentenceChunk>[];
    for (var i = 0; i < rawSentences.length; i++) {
      final rawSentence = rawSentences[i];
      final processedText = normalizeAllCaps(rawSentence).trim();
      var cleanSentence = filterPlaceholdersAndTags(processedText);
      cleanSentence = cleanSentence.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleanSentence.isNotEmpty && hasAlphanumeric(cleanSentence)) {
        final words = cleanSentence
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty && hasAlphanumeric(w))
            .toList();

        sentences.add(
          SentenceChunk(
            index: sentences.length,
            text: cleanSentence,
            charStart: 0,
            charEnd: cleanSentence.length,
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
