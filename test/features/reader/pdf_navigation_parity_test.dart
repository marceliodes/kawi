import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/database/app_database.dart';
import 'package:kawi/core/database/database_provider.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/models/reader_settings.dart';
import 'package:kawi/features/reader/providers/document_content_provider.dart';
import 'package:kawi/features/reader/providers/reader_settings_provider.dart';
import 'package:kawi/features/reader/screens/reader_screen.dart';
import 'package:kawi/features/reader/services/document_extractor.dart';
import 'package:kawi/features/reader/widgets/reader_canvas.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';

class _TestReaderSettingsNotifier extends ReaderSettingsNotifier {
  _TestReaderSettingsNotifier(this._initial);
  final ReaderSettings _initial;

  @override
  ReaderSettings build() => _initial;
}

Widget _createPdfTestApp({
  required ProviderContainer container,
  required DocumentEntry document,
  Widget? topWidget,
}) {
  final themeData = ReaderThemeTokens.fromPreset(ReaderThemePreset.paper);
  return UncontrolledProviderScope(
    container: container,
    child: ReaderTheme(
      data: themeData,
      child: MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: themeData.bgCanvas),
        home: Scaffold(
          body: Column(
            children: [
              ?topWidget,
              Expanded(child: ReaderScreen(document: document)),
            ],
          ),
        ),
      ),
    ),
  );
}

PageContent _mockPdfPage(int pageIndex) {
  return PageContent(
    pageIndex: pageIndex,
    plainText: 'PDF Content on Page ${pageIndex + 1}.',
    words: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentEntry testPdfDoc;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    testPdfDoc = DocumentEntry(
      id: 'doc-pdf-parity-1',
      title: 'Navigation Parity Test PDF',
      author: 'Author',
      filePath: File('test_assets/sample.pdf').absolute.path,
      format: 'pdf',
      pageCount: 5,
      addedAt: DateTime.now(),
      isCompleted: false,
      fileSizeBytes: 10240,
    );
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        hasInstalledTtsModelsProvider.overrideWithValue(true),
        documentPageContentProvider.overrideWith(
          (ref, arg) => Future.value(_mockPdfPage(arg.pageIndex)),
        ),
        readerSettingsProvider.overrideWith(
          () => _TestReaderSettingsNotifier(
            const ReaderSettings(
              mode: ReadingMode.paginated,
              fontSize: 16.0,
              lineHeight: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  group('PDF Desktop Keyboard Navigation Parity', () {
    testWidgets(
      'Space, Shift + Space, Arrow keys, PageDown/Up, Home, and End navigate PDF pages with clamping',
      (tester) async {
        final container = createContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _createPdfTestApp(container: container, document: testPdfDoc),
        );
        await tester.pumpAndSettle();

        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        // 1. Space -> Next Page (Page 2)
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // 2. Shift + Space -> Previous Page (Page 1)
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        // 3. ArrowRight -> Next Page (Page 2)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // 4. ArrowDown -> Next Page (Page 3)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 3.'), findsOneWidget);

        // 5. ArrowLeft -> Previous Page (Page 2)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // 6. ArrowUp -> Previous Page (Page 1)
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        // 7. PageDown -> Next Page (Page 2)
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // 8. PageUp -> Previous Page (Page 1)
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        // 9. End -> Last Page (Page 5)
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 5.'), findsOneWidget);

        // 10. Clamping at last page: Space/ArrowRight/ArrowDown/PageDown should NOT exceed Page 5
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 5.'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 5.'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 5.'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 5.'), findsOneWidget);

        // 11. Home -> First Page (Page 1)
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        // 12. Clamping at first page: Shift+Space/ArrowLeft/ArrowUp/PageUp should NOT go below Page 1
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);
      },
    );
  });

  group('PDF Two-Finger Trackpad Gesture Momentum Latching', () {
    testWidgets(
      'Horizontal trackpad swipe latching prevents multiple page turns from a single momentum burst',
      (tester) async {
        final container = createContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _createPdfTestApp(container: container, document: testPdfDoc),
        );
        await tester.pumpAndSettle();

        expect(find.text('PDF Content on Page 1.'), findsOneWidget);
        final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

        // Start gesture and exceed threshold (delta > 40.0) -> triggers Page 2
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(position: canvasCenter),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(-55.0, 0.0),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // Immediate subsequent momentum updates in the same burst must be latched and absorbed
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(-60.0, 0.0),
          ),
        );
        await tester.pump();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(-80.0, 0.0),
          ),
        );
        await tester.pump();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(-45.0, 0.0),
          ),
        );
        await tester.pumpAndSettle();
        // Still on Page 2, momentum did not skip to Page 3 or 4
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // End the gesture, resetting latch
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(position: canvasCenter),
        );
        await tester.pumpAndSettle();

        // Now a new swipe right gesture navigates back to Page 1
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(position: canvasCenter),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(55.0, 0.0),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 1.'), findsOneWidget);

        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(position: canvasCenter),
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Vertical trackpad pan gesture triggers page turns with momentum latching',
      (tester) async {
        final container = createContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _createPdfTestApp(container: container, document: testPdfDoc),
        );
        await tester.pumpAndSettle();

        expect(find.text('PDF Content on Page 1.'), findsOneWidget);
        final canvasCenter = tester.getCenter(find.byType(ReaderCanvas));

        // Panning upwards (panDelta.dy < 0) advances to next page
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(position: canvasCenter),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(0.0, -55.0),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        // Lingering momentum in vertical gesture is absorbed
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: canvasCenter,
            panDelta: const Offset(0.0, -70.0),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);

        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(position: canvasCenter),
        );
        await tester.pumpAndSettle();
      },
    );
  });

  group('PDF Focus Reclamation', () {
    testWidgets(
      'Clicking anywhere on PDF canvas requests and reclaims primary focus node',
      (tester) async {
        final container = createContainer();
        addTearDown(container.dispose);

        final externalFocusNode = FocusNode();
        addTearDown(externalFocusNode.dispose);

        await tester.pumpWidget(
          _createPdfTestApp(
            container: container,
            document: testPdfDoc,
            topWidget: TextField(
              focusNode: externalFocusNode,
              decoration: const InputDecoration(hintText: 'External Input'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final canvasState = tester.state<ReaderCanvasState>(
          find.byType(ReaderCanvas),
        );

        // 1. Give focus to external text field
        externalFocusNode.requestFocus();
        await tester.pump();
        expect(externalFocusNode.hasFocus, isTrue);
        expect(canvasState.focusNode.hasPrimaryFocus, isFalse);

        // 2. Click on the PDF canvas to reclaim focus
        await tester.tap(find.byType(ReaderCanvas));
        await tester.pump();

        // 3. Verify primary focus node has been reclaimed immediately
        expect(canvasState.focusNode.hasPrimaryFocus, isTrue);

        // 4. Verify keys register immediately on canvas without tab navigation
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('PDF Content on Page 2.'), findsOneWidget);
      },
    );
  });
}
