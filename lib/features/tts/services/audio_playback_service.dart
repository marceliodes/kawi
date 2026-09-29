import 'dart:async';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/tts_models.dart';
import 'tts_isolate_worker.dart';

/// Coordinator service managing the TTS isolate, voice configuration,
/// playback state, word-boundary events, and main UI thread audio playback.
///
/// Communicates with [TtsIsolateWorker] via two-way port messaging.
/// Strictly enforces that [AudioPlayer] runs on the main UI thread,
/// receiving raw WAV byte arrays synthesized in the background isolate.
class AudioPlaybackService {
  AudioPlaybackService({AudioPlayer? audioPlayer})
      : _audioPlayer = audioPlayer ?? AudioPlayer();

  final AudioPlayer _audioPlayer;
  StreamSubscription<void>? _playerCompleteSubscription;
  Timer? _playbackFallbackTimer;
  bool _isAudioPlaying = false;

  AudioPlayer get audioPlayer => _audioPlayer;

  Isolate? _isolate;
  SendPort? _toIsolatePort;
  final ReceivePort _fromIsolatePort = ReceivePort();

  final ValueNotifier<TtsState> stateNotifier =
      ValueNotifier<TtsState>(const TtsState());

  final StreamController<WordBoundaryEvent> _wordBoundaryController =
      StreamController<WordBoundaryEvent>.broadcast();
  Stream<WordBoundaryEvent> get wordBoundaryStream =>
      _wordBoundaryController.stream;

  final StreamController<AudioBufferEvent> _audioBufferController =
      StreamController<AudioBufferEvent>.broadcast();
  Stream<AudioBufferEvent> get audioBufferStream =>
      _audioBufferController.stream;

  bool _isInitialized = false;
  TtsVoiceModel? _activeVoice;

  TtsState get currentState => stateNotifier.value;

  /// Initializes the background isolate and registers audio player listeners on the main UI thread.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Listen for audio completion strictly on the main UI thread
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      _onAudioPlaybackComplete();
    });

    final completer = Completer<void>();

    _fromIsolatePort.listen((message) {
      if (message is IsolateReadyEvent) {
        _toIsolatePort = message.isolateSendPort;

        final rootToken = RootIsolateToken.instance;
        _toIsolatePort?.send(
          InitIsolateCommand(_fromIsolatePort.sendPort, rootIsolateToken: rootToken),
        );

        if (_activeVoice != null) {
          _toIsolatePort?.send(
            ConfigureVoiceCommand(
              voice: _activeVoice,
              rootIsolateToken: rootToken,
            ),
          );
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      } else if (message is PlayAudioBytesEvent) {
        _playWavBytes(message.wavBytes, durationMs: message.durationMs);
      } else if (message is StateUpdatedEvent) {
        stateNotifier.value = message.state;
      } else if (message is WordBoundaryEvent) {
        _wordBoundaryController.add(message);
      } else if (message is AudioBufferEvent) {
        _audioBufferController.add(message);
      } else if (message is PauseAudioEvent) {
        _playbackFallbackTimer?.cancel();
        _playbackFallbackTimer = null;
        try {
          _audioPlayer.pause();
        } catch (_) {}
      } else if (message is StopAudioEvent) {
        _playbackFallbackTimer?.cancel();
        _playbackFallbackTimer = null;
        _isAudioPlaying = false;
        try {
          _audioPlayer.stop();
        } catch (_) {}
      } else if (message is TtsErrorEvent) {
        debugPrint('[AudioPlaybackService] TTS Isolate Error: ${message.errorMessage}');
        stateNotifier.value = stateNotifier.value.copyWith(
          errorMessage: message.errorMessage,
          playbackState: TtsPlaybackState.stopped,
        );
      }
    });

    _isolate = await Isolate.spawn(
      TtsIsolateWorker.entryPoint,
      _fromIsolatePort.sendPort,
    );

    await completer.future;
    _isInitialized = true;
  }

  /// Plays synthesized WAV bytes on the main thread via AudioPlayer.
  Future<void> _playWavBytes(Uint8List wavBytes, {int durationMs = 0}) async {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;

    if (wavBytes.isEmpty) {
      _onAudioPlaybackComplete();
      return;
    }

    _isAudioPlaying = true;
    try {
      await _audioPlayer.play(BytesSource(wavBytes));
    } catch (e) {
      debugPrint('[AudioPlaybackService] AudioPlayer.play: $e');
    }

    // Safety fallback timer ensuring utterance completion even in headless or audio-disabled environments
    if (durationMs > 0) {
      _playbackFallbackTimer =
          Timer(Duration(milliseconds: durationMs + 250), _onAudioPlaybackComplete);
    }
  }

  void _onAudioPlaybackComplete() {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    if (!_isAudioPlaying) return;
    _isAudioPlaying = false;
    _toIsolatePort?.send(const UtteranceCompletedCommand());
  }

  /// Sets the active voice model and informs the isolate.
  void setActiveVoice(TtsVoiceModel? voice) {
    _activeVoice = voice;
    stateNotifier.value = stateNotifier.value.copyWith(
      activeVoice: voice,
      hasInstalledModels: voice != null,
    );

    _toIsolatePort?.send(
      ConfigureVoiceCommand(
        voice: voice,
        rootIsolateToken: RootIsolateToken.instance,
      ),
    );
  }

  /// Loads text into the worker queue.
  void loadText(String text, {int startSentenceIndex = 0}) {
    _toIsolatePort?.send(
      LoadTextCommand(text, startSentenceIndex: startSentenceIndex),
    );
  }

  /// Starts or resumes playback.
  ///
  /// Zero-Model state guarantee: If no voice is available,
  /// this is a safe no-op that updates the error message without crashing.
  void play() {
    if (_activeVoice == null && !currentState.hasInstalledModels) {
      debugPrint('[AudioPlaybackService] Play aborted: No TTS engine downloaded.');
      stateNotifier.value = stateNotifier.value.copyWith(
        errorMessage: 'No TTS engine downloaded.',
        playbackState: TtsPlaybackState.stopped,
      );
      return;
    }

    if (currentState.isPaused) {
      try {
        _audioPlayer.resume();
      } catch (_) {}
    }

    _toIsolatePort?.send(const PlayCommand());
  }

  /// Pauses playback on the main thread and instructs the isolate.
  void pause() {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    try {
      _audioPlayer.pause();
    } catch (_) {}
    _toIsolatePort?.send(const PauseCommand());
  }

  /// Stops playback on the main thread and instructs the isolate.
  void stop() {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    _isAudioPlaying = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _toIsolatePort?.send(const StopCommand());
  }

  /// Advances to the next sentence chunk.
  void nextSentence() {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    _isAudioPlaying = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _toIsolatePort?.send(const NextSentenceCommand());
  }

  /// Rewinds to the previous sentence chunk.
  void previousSentence() {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    _isAudioPlaying = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _toIsolatePort?.send(const PreviousSentenceCommand());
  }

  /// Seeks to a specific sentence chunk by index.
  void seekSentence(int sentenceIndex) {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    _isAudioPlaying = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _toIsolatePort?.send(SeekSentenceCommand(sentenceIndex));
  }

  /// Adjusts speech rate (0.5 to 2.0).
  void setSpeechRate(double rate) {
    _toIsolatePort?.send(SetRateCommand(rate));
  }

  /// Adjusts pitch (0.5 to 2.0).
  void setPitch(double pitch) {
    _toIsolatePort?.send(SetPitchCommand(pitch));
  }

  /// Cleans up player resources and isolates.
  void dispose() {
    _playbackFallbackTimer?.cancel();
    _playbackFallbackTimer = null;
    _isAudioPlaying = false;
    _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = null;
    try {
      _audioPlayer.stop();
      _audioPlayer.dispose();
    } catch (_) {}
    _toIsolatePort?.send(const DisposeCommand());
    _fromIsolatePort.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _wordBoundaryController.close();
    _audioBufferController.close();
    stateNotifier.dispose();
  }
}
