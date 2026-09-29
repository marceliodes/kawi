import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/utils/wav_encoder.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/services/audio_playback_service.dart';

class FakeAudioPlayer extends Fake implements AudioPlayer {
  BytesSource? playedSource;
  bool isPlaying = false;
  bool isPaused = false;
  final StreamController<void> _completeController = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    if (source is BytesSource) {
      playedSource = source;
    }
    isPlaying = true;
    isPaused = false;
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    isPaused = true;
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
    isPaused = false;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    isPaused = false;
  }

  @override
  Future<void> dispose() async {
    isPlaying = false;
    await _completeController.close();
  }

  void triggerComplete() {
    _completeController.add(null);
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('AudioPlaybackService Tests', () {
    late AudioPlaybackService service;
    late FakeAudioPlayer fakePlayer;

    setUp(() async {
      fakePlayer = FakeAudioPlayer();
      service = AudioPlaybackService(audioPlayer: fakePlayer);
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

    test('audio bytes playback via AudioPlayer on main UI thread', () async {
      final sampleWav = encodeWav(samples: [0.0, 0.1, -0.1], sampleRate: 24000);
      expect(sampleWav, isNotEmpty);
      expect(service.audioPlayer, isNotNull);

      // Verify playing WAV bytes delegates to AudioPlayer on the main thread
      await service.audioPlayer.play(BytesSource(sampleWav));
      expect(fakePlayer.playedSource?.bytes, equals(sampleWav));
      expect(fakePlayer.isPlaying, isTrue);

      // Verify pause and stop on main thread
      service.pause();
      expect(fakePlayer.isPaused, isTrue);

      service.stop();
      expect(fakePlayer.isPlaying, isFalse);
    });
  });
}
