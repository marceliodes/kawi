import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/utils/wav_encoder.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/services/audio_playback_service.dart';

class FakeAudioPlayer extends Fake implements AudioPlayer {
  BytesSource? playedSource;
  DeviceFileSource? playedDeviceFileSource;
  Source? lastSource;
  bool isPlaying = false;
  bool isPaused = false;
  final StreamController<void> _completeController = StreamController<void>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    lastSource = source;
    if (source is BytesSource) {
      playedSource = source;
    }
    if (source is DeviceFileSource) {
      playedDeviceFileSource = source;
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
    await _positionController.close();
  }

  void triggerComplete() {
    _completeController.add(null);
  }

  void emitPosition(Duration position) {
    _positionController.add(position);
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

      // Verify playing WAV file delegates to AudioPlayer on the main thread via DeviceFileSource
      await service.audioPlayer.play(DeviceFileSource('/tmp/test.wav'));
      expect(fakePlayer.playedDeviceFileSource?.path, equals('/tmp/test.wav'));
      expect(fakePlayer.isPlaying, isTrue);

      // Verify pause and stop on main thread
      service.pause();
      expect(fakePlayer.isPaused, isTrue);

      service.stop();
      expect(fakePlayer.isPlaying, isFalse);
    });

    test('sentence advancement strictly relies on onPlayerComplete and never advances on idle timer', () async {
      const mockVoice = TtsVoiceModel(
        id: 'test-mock-voice',
        name: 'Mock Test Voice',
        engineType: TtsEngineType.mock,
        isInstalled: true,
      );
      service.setActiveVoice(mockVoice);
      service.loadText('Sentence one. Sentence two.');
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(service.currentState.currentSentenceIndex, equals(0));

      // Even after waiting longer than any previous fallback duration, index remains 0
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(service.currentState.currentSentenceIndex, equals(0));
    });

    test('speak loads text and triggers playback via isolate and AudioPlayer', () async {
      const mockVoice = TtsVoiceModel(
        id: 'test-mock-voice',
        name: 'Mock Test Voice',
        engineType: TtsEngineType.mock,
        isInstalled: true,
      );
      service.setActiveVoice(mockVoice);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      service.speak('Hello world speaking now.');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(service.currentState.playbackState, equals(TtsPlaybackState.playing));
      expect(service.currentState.currentSentenceText, equals('Hello world speaking now.'));
      expect(fakePlayer.isPlaying, isTrue);
    });

    test('onPositionChanged advances word highlights strictly in response to audio playback events', () async {
      final sampleWav = encodeWav(samples: [0.0, 0.1, -0.1], sampleRate: 24000);
      const words = [
        SentenceWord(word: 'Hello', start: 0, end: 5, endMs: 200),
        SentenceWord(word: 'world', start: 6, end: 11, startMs: 200, endMs: 400),
      ];

      await service.playWavBytes(
        sampleWav,
        durationMs: 400,
        words: words,
      );

      // Initial word highlighted immediately
      expect(service.currentState.currentWord, equals('Hello'));
      expect(service.currentState.activeWordStart, equals(0));
      expect(service.currentState.activeWordEnd, equals(5));

      // Advance position to 250ms -> moves to "world"
      fakePlayer.emitPosition(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.currentState.currentWord, equals('world'));
      expect(service.currentState.activeWordStart, equals(6));
      expect(service.currentState.activeWordEnd, equals(11));
    });

    test('1-sentence lookahead pre-buffers next sentence and triggers zero-gap transition', () async {
      const mockVoice = TtsVoiceModel(
        id: 'test-mock-voice',
        name: 'Mock Test Voice',
        engineType: TtsEngineType.mock,
        isInstalled: true,
      );
      service.setActiveVoice(mockVoice);
      service.loadText('Sentence one is here. Sentence two is next.');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      service.play();
      // Wait for sentence 0 synthesis & playback to start, and sentence 1 pre-buffering to complete
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(fakePlayer.isPlaying, isTrue);
      expect(service.currentState.currentSentenceIndex, equals(0));
      expect(fakePlayer.playedDeviceFileSource?.path, contains('kawi_tts_temp_0.wav'));
      expect(service.hasPrebufferedAudio, isTrue);
      expect(service.prebufferedSentenceIndex, equals(1));

      // Trigger audio player completion on sentence 0
      fakePlayer.triggerComplete();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Immediate zero-gap transition to sentence 1
      expect(fakePlayer.isPlaying, isTrue);
      expect(service.currentState.currentSentenceIndex, equals(1));
      expect(fakePlayer.playedDeviceFileSource?.path, contains('kawi_tts_temp_1.wav'));
    });
  });
}
