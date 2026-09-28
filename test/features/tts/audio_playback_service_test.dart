import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/services/audio_playback_service.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('AudioPlaybackService Tests', () {
    late AudioPlaybackService service;

    setUp(() async {
      service = AudioPlaybackService();
      await service.initialize();
    });

    tearDown(() {
      service.dispose();
    });

    test('initializes and loads text into isolate', () async {
      const text = 'First sentence. Second sentence! Third sentence.';
      service.loadText(text);

      // Wait for isolate to process and emit updated state
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final state = service.currentState;
      expect(state.totalSentences, equals(3));
      expect(state.currentSentenceIndex, equals(0));
      expect(state.currentSentenceText, equals('First sentence.'));
      expect(state.playbackState, equals(TtsPlaybackState.stopped));
    });

    test('zero-model state handles play safely without crashing', () async {
      // No active voice set
      service.loadText('This should not crash.');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      service.play();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(service.currentState.playbackState, equals(TtsPlaybackState.stopped));
      expect(service.currentState.errorMessage, contains('No TTS engine downloaded.'));
    });

    test('play, pause, stop lifecycle with configured voice', () async {
      const mockVoice = TtsVoiceModel(
        id: 'test-mock-voice',
        name: 'Mock Test Voice',
        engineType: TtsEngineType.mock,
        isInstalled: true,
      );
      service.setActiveVoice(mockVoice);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      const text = 'Alpha sentence with multiple words to ensure playback duration. Beta sentence.';
      service.loadText(text);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Play
      service.play();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(service.currentState.playbackState, equals(TtsPlaybackState.playing));

      // Pause
      service.pause();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.currentState.playbackState, equals(TtsPlaybackState.paused));

      // Stop
      service.stop();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.currentState.playbackState, equals(TtsPlaybackState.stopped));
    });

    test('next and previous sentence navigation', () async {
      const mockVoice = TtsVoiceModel(
        id: 'test-mock-voice',
        name: 'Mock Test Voice',
        engineType: TtsEngineType.mock,
        isInstalled: true,
      );
      service.setActiveVoice(mockVoice);

      const text = 'Part 1. Part 2. Part 3.';
      service.loadText(text);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Next
      service.nextSentence();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.currentState.currentSentenceIndex, equals(1));
      expect(service.currentState.currentSentenceText, equals('Part 2.'));

      // Previous
      service.previousSentence();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.currentState.currentSentenceIndex, equals(0));
      expect(service.currentState.currentSentenceText, equals('Part 1.'));
    });
  });
}
