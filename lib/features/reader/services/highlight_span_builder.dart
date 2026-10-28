import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/reader_theme_data.dart';
import '../models/document_models.dart';
import '../models/highlight.dart';
import '../models/reader_settings.dart';
import '../../tts/models/tts_models.dart';

class HighlightSpanBuilder {
  const HighlightSpanBuilder._();

  /// Slices [node] into styled [TextSpan]s combining segment attributes (bold, italic),
  /// user highlights (background tint or underline), and optional TTS focus without altering font metrics.
  static TextSpan buildSpans({
    required DocumentNode node,
    required TextStyle baseStyle,
    required int chapterIndex,
    required int paragraphIndex,
    int sliceCharOffset = 0,
    required List<Highlight> highlights,
    required ReaderThemeData theme,
    TtsState? ttsState,
    TtsHighlightStyle ttsHighlightStyle = TtsHighlightStyle.background,
    void Function(Highlight highlight)? onHighlightTapped,
  }) {
    final plainText = node is ParagraphNode
        ? node.plainText
        : (node is HeadingNode ? node.plainText : '');
    final segments = node is ParagraphNode
        ? node.segments
        : (node is HeadingNode ? node.segments : const <TextSegment>[]);

    if (plainText.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    // 1. Identify active highlight slices intersecting this node
    final activeSlices = <({Highlight highlight, int start, int end})>[];
    for (final h in highlights) {
      final slice = h.getParagraphSlice(
        chapterIndex: chapterIndex,
        paragraphIndex: paragraphIndex,
        paragraphLength: plainText.length + sliceCharOffset,
      );
      if (slice == null) continue;

      final nodeStart =
          (slice.start - sliceCharOffset).clamp(0, plainText.length);
      final nodeEnd =
          (slice.end - sliceCharOffset).clamp(0, plainText.length);
      if (nodeStart < 0 ||
          nodeStart > plainText.length ||
          nodeEnd < 0 ||
          nodeEnd > plainText.length) {
        continue;
      }
      if (nodeStart < nodeEnd) {
        activeSlices.add((highlight: h, start: nodeStart, end: nodeEnd));
      }
    }

    // 2. Identify TTS range if active
    int ttsStart = -1;
    int ttsEnd = -1;
    if (ttsState != null && (ttsState.isPlaying || ttsState.isPaused)) {
      final sentence = ttsState.currentSentenceText.trim();
      if (sentence.isNotEmpty) {
        if (plainText.contains(sentence)) {
          ttsStart = plainText.indexOf(sentence);
          ttsEnd = ttsStart + sentence.length;
        } else {
          // Fallback to normalized word matching
          final normSentence =
              sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
          final words =
              normSentence.split(' ').where((w) => w.isNotEmpty).toList();
          if (words.isNotEmpty) {
            final pattern = RegExp(
              words.map(RegExp.escape).join(r'\s+'),
              caseSensitive: false,
            );
            final match = pattern.firstMatch(plainText);
            if (match != null) {
              ttsStart = match.start;
              ttsEnd = match.end;
            }
          }
        }
      }
    }

    final hasValidTts =
        ttsStart >= 0 && ttsEnd <= plainText.length && ttsStart < ttsEnd;

    // Fast path: If no user highlights and no TTS, return standard spans immediately
    if (activeSlices.isEmpty && !hasValidTts) {
      return TextSpan(
        style: baseStyle,
        children: [
          for (final s in segments)
            TextSpan(
              text: s.text,
              style: TextStyle(
                fontWeight: s.isBold ? FontWeight.bold : null,
                fontStyle: s.isItalic ? FontStyle.italic : null,
              ),
            ),
        ],
      );
    }

    // 3. Collect and sort all boundary points (from highlights, segments, and TTS)
    final boundaries = <int>{0, plainText.length};
    var segOffset = 0;
    for (final seg in segments) {
      segOffset += seg.text.length;
      if (segOffset > 0 && segOffset < plainText.length) {
        boundaries.add(segOffset);
      }
    }
    for (final s in activeSlices) {
      if (s.start >= 0 && s.start <= plainText.length) {
        boundaries.add(s.start);
      }
      if (s.end >= 0 && s.end <= plainText.length) {
        boundaries.add(s.end);
      }
    }
    if (ttsStart >= 0 && ttsEnd <= plainText.length && ttsStart < ttsEnd) {
      boundaries.add(ttsStart);
      boundaries.add(ttsEnd);
    }
    boundaries.removeWhere((b) => b < 0 || b > plainText.length);
    final sorted = boundaries.toList()..sort();

    // 4. Build spans for each interval [segStart, segEnd]
    final spans = <InlineSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final segStart = sorted[i].clamp(0, plainText.length);
      final segEnd = sorted[i + 1].clamp(0, plainText.length);
      if (segStart >= segEnd) continue;

      final chunkText = plainText.substring(segStart, segEnd);

      // Resolve underlying segment style
      final segmentProps = _resolveSegmentProperties(segments, segStart);

      // Check for user highlight in this interval (most recently created takes priority if overlapping)
      final matchedSlice = activeSlices
          .where((s) => s.start <= segStart && s.end >= segEnd)
          .lastOrNull;

      // Check for TTS in this interval
      final isTtsActive =
          hasValidTts && segStart >= ttsStart && segEnd <= ttsEnd;

      Color? background;
      TextDecoration? decoration;
      Color? decorationColor;
      double? decorationThickness;

      if (matchedSlice != null) {
        final hl = matchedSlice.highlight;
        if (hl.isUnderline) {
          decoration = TextDecoration.underline;
          decorationColor = hl.displayColor;
          decorationThickness = 2.0;
        } else {
          background = hl.getBackgroundTint(isDark: theme.isDark);
        }
      }

      if (isTtsActive) {
        if (ttsHighlightStyle == TtsHighlightStyle.underline) {
          decoration = TextDecoration.underline;
          decorationColor = theme.accent;
          decorationThickness = 2.0;
        } else {
          background = theme.ttsHighlight;
        }
      }

      final spanStyle = TextStyle(
        fontWeight: segmentProps.isBold ? FontWeight.bold : null,
        fontStyle: segmentProps.isItalic ? FontStyle.italic : null,
        backgroundColor: background,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationThickness: decorationThickness,
      );

      final recognizer = (matchedSlice != null && onHighlightTapped != null)
          ? (TapGestureRecognizer()
            ..onTap = () => onHighlightTapped(matchedSlice.highlight))
          : null;

      spans.add(TextSpan(
        text: chunkText,
        style: spanStyle,
        recognizer: recognizer,
        mouseCursor: matchedSlice != null ? SystemMouseCursors.click : null,
      ));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  static ({bool isBold, bool isItalic, String? href}) _resolveSegmentProperties(
    List<TextSegment> segments,
    int offset,
  ) {
    var accumulated = 0;
    for (final seg in segments) {
      final segLen = seg.text.length;
      if (offset >= accumulated && offset < accumulated + segLen) {
        return (isBold: seg.isBold, isItalic: seg.isItalic, href: seg.href);
      }
      accumulated += segLen;
    }
    return (isBold: false, isItalic: false, href: null);
  }
}
