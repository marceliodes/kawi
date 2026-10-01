import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/reader/widgets/tts_control_bar.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/tts_provider.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';

class MockTtsNotifier extends TtsStateNotifier {
  MockTtsNotifier(this._initial);
  final TtsState _initial;

  bool playCalled = false;
  bool pauseCalled = false;
  bool stopCalled = false;
  bool nextCalled = false;
  bool prevCalled = false;
  double? rateSet;

  @override
  TtsState build() => _initial;

  @override
  void play() {
    playCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.playing);
  }

  @override
  void pause() {
    pauseCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.paused);
  }

  @override
  void stop() {
    stopCalled = true;
    state = state.copyWith(playbackState: TtsPlaybackState.stopped);
  }

  @override
  void nextSentence() {
    nextCalled = true;
  }

  @override
  void previousSentence() {
    prevCalled = true;
  }

  @override
  void setRate(double rate) {
    rateSet = rate;
    state = state.copyWith(speechRate: rate);
  }
}

void main() {
  group('TtsControlBar Widget Tests', () {
    testWidgets('renders all control buttons and displays sentence count', (tester) async {
      var closed = false;
      final mockNotifier = MockTtsNotifier(
        const TtsState(
          playbackState: TtsPlaybackState.playing,
          currentSentenceIndex: 2,
          totalSentences: 10,
          currentSentenceText: 'This is a test sentence.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ttsStateProvider.overrideWith(() => mockNotifier),
            hasInstalledTtsModelsProvider.overrideWithValue(true),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: TtsControlBar(
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        ),
      );

      // Verify progress text
      expect(find.text('3/10'), findsOneWidget);

      // Verify speech rate text
      expect(find.text('1x'), findsOneWidget);

      // Verify buttons exist
      expect(find.byTooltip('Previous Sentence'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byTooltip('Next Sentence'), findsOneWidget);
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(find.byTooltip('Voice Settings'), findsOneWidget);
      expect(find.byTooltip('Close TTS Bar'), findsOneWidget);

      // Tap Pause
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(mockNotifier.pauseCalled, isTrue);

      // Tap Next
      await tester.tap(find.byTooltip('Next Sentence'));
      await tester.pump();
      expect(mockNotifier.nextCalled, isTrue);

      // Tap Previous
      await tester.tap(find.byTooltip('Previous Sentence'));
      await tester.pump();
      expect(mockNotifier.prevCalled, isTrue);

      // Tap Close
      await tester.tap(find.byTooltip('Close TTS Bar'));
      await tester.pump();
      expect(closed, isTrue);
      expect(mockNotifier.stopCalled, isTrue);
    });

    testWidgets('cycles through speeds on tap', (tester) async {
      final mockNotifier = MockTtsNotifier(
        const TtsState(
          playbackState: TtsPlaybackState.playing,
          totalSentences: 5,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ttsStateProvider.overrideWith(() => mockNotifier),
            hasInstalledTtsModelsProvider.overrideWithValue(true),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: TtsControlBar(onClose: () {}),
              ),
            ),
          ),
        ),
      );

      // Tap speed toggle (initially 1x)
      await tester.tap(find.text('1x'));
      await tester.pump();
      expect(mockNotifier.rateSet, equals(1.25));
    });

    testWidgets('zero-model state displays informative tooltip and disables play', (tester) async {
      final mockNotifier = MockTtsNotifier(
        const TtsState(
          totalSentences: 5,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ttsStateProvider.overrideWith(() => mockNotifier),
            hasInstalledTtsModelsProvider.overrideWithValue(false),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: TtsControlBar(onClose: () {}),
              ),
            ),
          ),
        ),
      );

      // Button has disabled zero-model tooltip
      expect(find.byTooltip('No TTS engine downloaded.'), findsOneWidget);
    });

    testWidgets('calls onPlay when Play tapped with 0 sentences', (tester) async {
      var onPlayCalled = false;
      final mockNotifier = MockTtsNotifier(
        const TtsState(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ttsStateProvider.overrideWith(() => mockNotifier),
            hasInstalledTtsModelsProvider.overrideWithValue(true),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: MaterialApp(
              home: Scaffold(
                body: TtsControlBar(
                  onClose: () {},
                  onPlay: () => onPlayCalled = true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(onPlayCalled, isTrue);
    });
  });
}
