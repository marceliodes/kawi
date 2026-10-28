import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/widgets/apple_marquee_text.dart';

void main() {
  group('AppleMarqueeText Widget Tests', () {
    testWidgets('renders standard Text without ShaderMask when text fits within constraints',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: AppleMarqueeText(
                text: 'Short',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Short'), findsOneWidget);
      // ShaderMask is only used when text overflows
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('renders ShaderMask and OverflowBox when text overflows available width',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 50,
              child: AppleMarqueeText(
                text: 'Extremely Long Text That Will Definitely Overflow Available Constraints',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );

      // Verify widget renders text
      expect(find.text('Extremely Long Text That Will Definitely Overflow Available Constraints'),
          findsOneWidget);
      // When overflowing, ShaderMask provides horizontal gradient alpha fade masks
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byType(OverflowBox), findsOneWidget);
    });

    testWidgets('smoothly animates marquee scroll on overflow',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 60,
              child: AppleMarqueeText(
                text: 'Super Long Headline For Marquee Testing',
                style: TextStyle(fontSize: 14),
                pauseDuration: Duration(milliseconds: 100),
                velocity: 100.0,
              ),
            ),
          ),
        ),
      );

      // Initially at offset 0
      final transformFinder = find.descendant(
        of: find.byType(AppleMarqueeText),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
      final initialTransform = tester.widget<Transform>(transformFinder);
      expect(initialTransform.transform.getTranslation().x, 0.0);

      // Advance past initial pause (100ms) and part of the scroll animation
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 100));

      final movedTransform = tester.widget<Transform>(transformFinder);
      // Offset should have shifted negatively to the left
      expect(movedTransform.transform.getTranslation().x, lessThan(0.0));
    });

    testWidgets('disposing overflowing marquee cancels timers cleanly without leaks',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 50,
              child: AppleMarqueeText(
                text: 'Overflowing Text That Will Be Disposed Quickly',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );

      // Advance slightly during initial pause
      await tester.pump(const Duration(milliseconds: 200));

      // Replace with empty container (disposes AppleMarqueeText)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(),
          ),
        ),
      );

      // Pump remaining frame; no timers or exceptions should leak
      await tester.pump();
      expect(find.byType(AppleMarqueeText), findsNothing);
    });
  });
}
