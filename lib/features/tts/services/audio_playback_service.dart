import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/tts_models.dart';
import 'tts_isolate_worker.dart';
import 'tts_text_normalizer.dart';

class _PrebufferedAudio {
  final int sentenceIndex;
  final Uint8List wavBytes;
  final int durationMs;
  final List<SentenceWord> words;
  final Future<String> filePathFuture;

  _PrebufferedAudio({
    required this.sentenceIndex,
    required this.wavBytes,
    required this.durationMs,
    required this.words,
    required this.filePathFuture,
  });
}

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
  StreamSubscription<Duration>? _playerPositionSubscription;
  bool _isAudioPlaying = false;
  List<SentenceWord> _currentSentenceWords = const [];
  _PrebufferedAudio? _prebufferedAudio;

  bool get hasPrebufferedAudio => _prebufferedAudio != null;
  int? get prebufferedSentenceIndex => _prebufferedAudio?.sentenceIndex;

  AudioPlayer get audioPlayer => _audioPlayer;

  Isolate? _isolate;
  SendPort? _toIsolatePort;
  final ReceivePort _fromIsolatePort = ReceivePort();
  final List<TtsCommand> _pendingCommands = [];

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

  void _sendCommand(TtsCommand command) {
    if (_toIsolatePort != null) {
      _toIsolatePort!.send(command);
    } else {
      _pendingCommands.add(command);
    }
  }

  /// Initializes the background isolate and registers audio player listeners on the main UI thread.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Listen for audio completion strictly on the main UI thread
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      _onAudioPlaybackComplete();
    });

    _playerPositionSubscription =
        _audioPlayer.onPositionChanged.listen(_onAudioPositionChanged);

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

        for (final cmd in _pendingCommands) {
          _toIsolatePort?.send(cmd);
        }
        _pendingCommands.clear();

        if (!completer.isCompleted) {
          completer.complete();
        }
      } else if (message is PlayAudioBytesEvent) {
        playWavBytes(
          message.wavBytes,
          sentenceIndex: message.sentenceIndex,
          durationMs: message.durationMs,
          words: message.words,
        );
      } else if (message is PrebufferedAudioBytesEvent) {
        _handlePrebufferedAudio(message);
      } else if (message is StateUpdatedEvent) {
        stateNotifier.value = message.state;
      } else if (message is WordBoundaryEvent) {
        stateNotifier.value = currentState.copyWith(
          currentWord: message.word,
          activeWordStart: message.start,
          activeWordEnd: message.end,
        );
        _wordBoundaryController.add(message);
      } else if (message is AudioBufferEvent) {
        _audioBufferController.add(message);
      } else if (message is PauseAudioEvent) {
        try {
          _audioPlayer.pause();
        } catch (_) {}
      } else if (message is StopAudioEvent) {
        _isAudioPlaying = false;
        _prebufferedAudio = null;
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

  Future<File> _getTempWavFile(int sentenceIndex) async {
    Directory tempDir;
    try {
      tempDir = await getTemporaryDirectory();
    } catch (_) {
      tempDir = Directory.systemTemp;
    }
    return File('${tempDir.path}/kawi_tts_temp_${sentenceIndex % 2}.wav');
  }

  void _handlePrebufferedAudio(PrebufferedAudioBytesEvent message) {
    // ignore: avoid_print
    print('>>> [Kawi TTS] Received prebuffered audio for sentence index ${message.sentenceIndex} (${message.wavBytes.length} bytes) <<<');
    final fileFuture = () async {
      try {
        final tempFile = await _getTempWavFile(message.sentenceIndex);
        await tempFile.writeAsBytes(message.wavBytes, flush: true);
        return tempFile.path;
      } catch (e) {
        debugPrint('[AudioPlaybackService] Error caching prebuffered audio: $e');
        rethrow;
      }
    }();

    _prebufferedAudio = _PrebufferedAudio(
      sentenceIndex: message.sentenceIndex,
      wavBytes: message.wavBytes,
      durationMs: message.durationMs,
      words: message.words,
      filePathFuture: fileFuture,
    );
  }

  /// Plays synthesized WAV bytes on the main thread via AudioPlayer.
  Future<void> playWavBytes(
    Uint8List wavBytes, {
    int sentenceIndex = 0,
    int durationMs = 0,
    List<SentenceWord> words = const [],
  }) async {
    final currentIndex = sentenceIndex;
    // ignore: avoid_print
    print('[Kawi TTS] Received ${wavBytes.length} bytes for sentence index $currentIndex');

    if (wavBytes.isEmpty) {
      debugPrint('[Kawi TTS] Error: audio bytes are empty for sentence index $currentIndex');
      _isAudioPlaying = false;
      stop();
      return;
    }

    if (_prebufferedAudio?.sentenceIndex == currentIndex) {
      _prebufferedAudio = null;
    }

    _currentSentenceWords = words;
    if (words.isNotEmpty) {
      final first = words.first;
      stateNotifier.value = currentState.copyWith(
        currentSentenceIndex: currentIndex,
        currentWord: first.word,
        activeWordStart: first.start,
        activeWordEnd: first.end,
      );
      _wordBoundaryController.add(
        WordBoundaryEvent(
          sentenceIndex: currentIndex,
          word: first.word,
          start: first.start,
          end: first.end,
        ),
      );
    } else {
      stateNotifier.value = currentState.copyWith(
        currentSentenceIndex: currentIndex,
      );
    }

    _isAudioPlaying = true;
    try {
      final tempFile = await _getTempWavFile(currentIndex);
      await tempFile.writeAsBytes(wavBytes, flush: true);
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      debugPrint('[AudioPlaybackService] AudioPlayer.play: $e');
      _isAudioPlaying = false;
      stop();
    }
  }

  void _onAudioPositionChanged(Duration position) {
    if (!_isAudioPlaying || _currentSentenceWords.isEmpty) return;

    final posMs = position.inMilliseconds;
    SentenceWord? matched;
    for (final w in _currentSentenceWords) {
      if (posMs >= w.startMs && posMs < w.endMs) {
        matched = w;
        break;
      }
    }
    matched ??= _currentSentenceWords.last;

    if (matched.word.isNotEmpty &&
        (matched.word != currentState.currentWord ||
            matched.start != currentState.activeWordStart ||
            matched.end != currentState.activeWordEnd)) {
      stateNotifier.value = currentState.copyWith(
        currentWord: matched.word,
        activeWordStart: matched.start,
        activeWordEnd: matched.end,
      );

      _wordBoundaryController.add(
        WordBoundaryEvent(
          sentenceIndex: currentState.currentSentenceIndex,
          word: matched.word,
          start: matched.start,
          end: matched.end,
        ),
      );
    }
  }

  Future<void> _onAudioPlaybackComplete() async {
    if (!_isAudioPlaying) return;

    final nextIndex = currentState.currentSentenceIndex + 1;
    if (_prebufferedAudio != null && _prebufferedAudio!.sentenceIndex == nextIndex) {
      final pre = _prebufferedAudio!;
      _prebufferedAudio = null;
      // ignore: avoid_print
      print('>>> [Kawi TTS] Instant zero-gap transition to pre-buffered sentence index $nextIndex <<<');

      _isAudioPlaying = true;
      _currentSentenceWords = pre.words;
      if (pre.words.isNotEmpty) {
        final first = pre.words.first;
        stateNotifier.value = currentState.copyWith(
          currentSentenceIndex: pre.sentenceIndex,
          currentWord: first.word,
          activeWordStart: first.start,
          activeWordEnd: first.end,
        );
        _wordBoundaryController.add(
          WordBoundaryEvent(
            sentenceIndex: pre.sentenceIndex,
            word: first.word,
            start: first.start,
            end: first.end,
          ),
        );
      } else {
        stateNotifier.value = currentState.copyWith(
          currentSentenceIndex: pre.sentenceIndex,
          currentWord: '',
          activeWordStart: 0,
          activeWordEnd: 0,
        );
      }

      try {
        final filePath = await pre.filePathFuture;
        if (!_isAudioPlaying) return;
        await _audioPlayer.play(DeviceFileSource(filePath));
      } catch (e) {
        debugPrint('[AudioPlaybackService] AudioPlayer.play prebuffered: $e');
        _isAudioPlaying = false;
        stop();
        return;
      }

      _sendCommand(const UtteranceCompletedCommand(alreadyPlaying: true));
    } else {
      _isAudioPlaying = false;
      _sendCommand(const UtteranceCompletedCommand());
    }
  }

  /// Sets the active voice model and informs the isolate.
  void setActiveVoice(TtsVoiceModel? voice) {
    // ignore: avoid_print
    print('>>> [Kawi TTS] setActiveVoice called (voice: ${voice?.name}, engine: ${voice?.engineType}, installed: ${voice?.isInstalled}) <<<');
    _activeVoice = voice;
    stateNotifier.value = stateNotifier.value.copyWith(
      activeVoice: voice,
      hasInstalledModels: voice != null,
    );

    _sendCommand(
      ConfigureVoiceCommand(
        voice: voice,
        rootIsolateToken: RootIsolateToken.instance,
      ),
    );
  }

  /// Loads text into the worker queue, replacing soft line breaks within paragraphs.
  void loadText(String text, {int startSentenceIndex = 0}) {
    _prebufferedAudio = null;
    final normalized = TtsTextNormalizer.normalizeParagraphWhitespace(text);
    // ignore: avoid_print
    print('[Kawi TTS] loadText called with ${normalized.length} chars (startSentenceIndex: $startSentenceIndex)');
    _sendCommand(
      LoadTextCommand(normalized, startSentenceIndex: startSentenceIndex),
    );
  }

  /// Loads text and immediately starts playback.
  void speak(String text, {int startSentenceIndex = 0}) {
    loadText(text, startSentenceIndex: startSentenceIndex);
    play();
  }

  /// Starts or resumes playback.
  ///
  /// Zero-Model state guarantee: If no voice is available,
  /// this is a safe no-op that updates the error message without crashing.
  void play() {
    // ignore: avoid_print
    print('[Kawi TTS] play called (hasVoice: ${_activeVoice != null}, isPaused: ${currentState.isPaused})');
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

    _sendCommand(const PlayCommand());
  }

  /// Pauses playback on the main thread and instructs the isolate.
  void pause() {
    try {
      _audioPlayer.pause();
    } catch (_) {}
    _sendCommand(const PauseCommand());
  }

  /// Stops playback on the main thread and instructs the isolate.
  void stop() {
    _isAudioPlaying = false;
    _currentSentenceWords = const [];
    _prebufferedAudio = null;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _sendCommand(const StopCommand());
  }

  /// Advances to the next sentence chunk.
  void nextSentence() {
    _isAudioPlaying = false;
    _prebufferedAudio = null;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _sendCommand(const NextSentenceCommand());
  }

  /// Rewinds to the previous sentence chunk.
  void previousSentence() {
    _isAudioPlaying = false;
    _prebufferedAudio = null;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _sendCommand(const PreviousSentenceCommand());
  }

  /// Seeks to a specific sentence chunk by index.
  void seekSentence(int sentenceIndex) {
    _isAudioPlaying = false;
    _prebufferedAudio = null;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _sendCommand(SeekSentenceCommand(sentenceIndex));
  }

  /// Adjusts speech rate (0.5 to 2.0).
  void setSpeechRate(double rate) {
    _prebufferedAudio = null;
    _sendCommand(SetRateCommand(rate));
  }

  /// Adjusts pitch (0.5 to 2.0).
  void setPitch(double pitch) {
    _prebufferedAudio = null;
    _sendCommand(SetPitchCommand(pitch));
  }

  /// Cleans up player resources and isolates.
  void dispose() {
    _isAudioPlaying = false;
    _prebufferedAudio = null;
    _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = null;
    _playerPositionSubscription?.cancel();
    _playerPositionSubscription = null;
    try {
      _audioPlayer.stop();
      _audioPlayer.dispose();
    } catch (_) {}
    _sendCommand(const DisposeCommand());
    _fromIsolatePort.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _wordBoundaryController.close();
    _audioBufferController.close();
    stateNotifier.dispose();
  }
}
