import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/models/highlight.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/widgets/reader_selection_toolbar.dart';

Widget _wrapWithTheme(Widget child) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return MaterialApp(
    home: Scaffold(
      body: ReaderTheme(
        data: themeData,
        child: child,
      ),
    ),
  );
}

void main() {
  group('ReaderSelectionToolbar Widget Tests', () {
    testWidgets('renders all 4 color chips, underline, note, and copy buttons',
        (tester) async {
      String? selectedColor;
      bool wasNoteClicked = false;
      bool wasClosed = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          ReaderSelectionToolbar(
            anchors: const TextSelectionToolbarAnchors(
              primaryAnchor: Offset(200, 200),
            ),
            selectedText: 'Selectable test text',
            startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
            endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 20),
            onColorSelected: (c) => selectedColor = c,
            onAddOrEditNote: () => wasNoteClicked = true,
            onClose: () => wasClosed = true,
          ),
        ),
      );

      // Verify color chips exist
      expect(find.byTooltip('Amber'), findsOneWidget);
      expect(find.byTooltip('Mint'), findsOneWidget);
      expect(find.byTooltip('Sky'), findsOneWidget);
      expect(find.byTooltip('Coral'), findsOneWidget);
      expect(find.byTooltip('Underline'), findsOneWidget);

      // Verify action buttons
      expect(find.byTooltip('Add Note'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);

      await tester.tap(find.byTooltip('Add Note'));
      await tester.pump();
      expect(wasNoteClicked, isTrue);

      // Tap Mint chip
      await tester.tap(find.byTooltip('Mint'));
      await tester.pump();

      expect(selectedColor, '#81C784');
      expect(wasClosed, isTrue);
    });

    testWidgets('underline chip selects underline style and invokes onClose',
        (tester) async {
      String? selectedColor;
      bool wasClosed = false;

      await tester.pumpWidget(
        _wrapWithTheme(
          ReaderSelectionToolbar(
            anchors: const TextSelectionToolbarAnchors(
              primaryAnchor: Offset(200, 200),
            ),
            selectedText: 'Underline test text',
            startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
            endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 19),
            onColorSelected: (c) => selectedColor = c,
            onAddOrEditNote: () {},
            onClose: () => wasClosed = true,
          ),
        ),
      );

      await tester.tap(find.byTooltip('Underline'));
      await tester.pump();

      expect(selectedColor, 'underline');
      expect(wasClosed, isTrue);
    });

    testWidgets('shows delete button when editing an existing highlight',
        (tester) async {
      bool wasDeleted = false;

      final existing = Highlight(
        id: 'hl-existing',
        documentId: 'doc-1',
        startAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 0),
        endAnchor: const ReadingAnchor(chapterIndex: 0, paragraphIndex: 0, charOffset: 10),
        highlightedText: 'existing',
        colorHex: '#FFD54F',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        _wrapWithTheme(
          ReaderSelectionToolbar(
            anchors: const TextSelectionToolbarAnchors(
              primaryAnchor: Offset(200, 200),
            ),
            selectedText: 'existing',
            startAnchor: existing.startAnchor,
            endAnchor: existing.endAnchor,
            existingHighlight: existing,
            onColorSelected: (_) {},
            onAddOrEditNote: () {},
            onClose: () {},
            onDeleteHighlight: () => wasDeleted = true,
          ),
        ),
      );

      expect(find.byTooltip('Delete highlight'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete highlight'));
      await tester.pump();

      expect(wasDeleted, isTrue);
    });
  });
}
