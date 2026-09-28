import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/tts_models.dart';
import 'tts_isolate_worker.dart';

/// Coordinator service managing the TTS isolate, voice configuration,
/// playback state, and word-boundary events.
///
/// Communicates with [TtsIsolateWorker] via two-way port messaging.
/// Does not depend on `flutter_tts`.
class AudioPlaybackService {
  AudioPlaybackService();

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

  /// Initializes the background isolate.
  Future<void> initialize() async {
    if (_isInitialized) return;

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
      } else if (message is StateUpdatedEvent) {
        stateNotifier.value = message.state;
      } else if (message is WordBoundaryEvent) {
        _wordBoundaryController.add(message);
      } else if (message is AudioBufferEvent) {
        _audioBufferController.add(message);
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

    _toIsolatePort?.send(const PlayCommand());
  }

  /// Pauses playback.
  void pause() {
    _toIsolatePort?.send(const PauseCommand());
  }

  /// Stops playback.
  void stop() {
    _toIsolatePort?.send(const StopCommand());
  }

  /// Advances to the next sentence chunk.
  void nextSentence() {
    _toIsolatePort?.send(const NextSentenceCommand());
  }

  /// Rewinds to the previous sentence chunk.
  void previousSentence() {
    _toIsolatePort?.send(const PreviousSentenceCommand());
  }

  /// Seeks to a specific sentence chunk by index.
  void seekSentence(int sentenceIndex) {
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

  /// Cleans up resources.
  void dispose() {
    _toIsolatePort?.send(const DisposeCommand());
    _fromIsolatePort.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _wordBoundaryController.close();
    _audioBufferController.close();
    stateNotifier.dispose();
  }
}
