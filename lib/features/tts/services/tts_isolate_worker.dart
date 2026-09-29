import 'dart:isolate';

import 'package:flutter/services.dart';

import '../models/tts_models.dart';
import 'tts_engine_bridge.dart';

/// Worker class running completely inside a dedicated background isolate.
///
/// Handles text tokenization, sentence chunking, queue sequencing,
/// and delegates speech synthesis & word-boundary emission to [TtsEngineBridge].
class TtsIsolateWorker {
  TtsIsolateWorker(this._toMainPort, [this._engineBridge]);

  final SendPort _toMainPort;
  final ReceivePort _fromMainPort = ReceivePort();

  TtsEngineBridge? _engineBridge;
  RootIsolateToken? _rootIsolateToken;
  List<SentenceChunk> _sentences = const [];
  int _currentIndex = 0;
  TtsState _state = const TtsState();

  /// Entry point called by [Isolate.spawn].
  static void entryPoint(SendPort mainSendPort) {
    final worker = TtsIsolateWorker(mainSendPort);
    worker._init();
  }

  void _init() {
    _toMainPort.send(IsolateReadyEvent(_fromMainPort.sendPort));

    _fromMainPort.listen((message) {
      if (message is TtsCommand) {
        _handleCommand(message);
      }
    });
  }

  void _handleCommand(TtsCommand command) {
    switch (command) {
      case InitIsolateCommand(:final rootIsolateToken):
        _rootIsolateToken = rootIsolateToken;
        if (rootIsolateToken != null) {
          try {
            BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
          } catch (_) {}
        }

      case ConfigureVoiceCommand(:final voice, :final rootIsolateToken):
        if (rootIsolateToken != null) {
          _rootIsolateToken = rootIsolateToken;
        }
        _configureVoice(voice);

      case LoadTextCommand(:final text, :final startSentenceIndex):
        _loadText(text, startSentenceIndex);

      case PlayCommand():
        _play();

      case PauseCommand():
        _pause();

      case StopCommand():
        _stop();

      case NextSentenceCommand():
        _nextSentence();

      case PreviousSentenceCommand():
        _previousSentence();

      case SeekSentenceCommand(:final sentenceIndex):
        _seekSentence(sentenceIndex);

      case SetRateCommand(:final rate):
        _state = _state.copyWith(speechRate: rate);
        _emitState();

      case SetPitchCommand(:final pitch):
        _state = _state.copyWith(pitch: pitch);
        _emitState();

      case UtteranceCompletedCommand():
        _onUtteranceCompleted();

      case UtteranceProgressCommand(:final word, :final start, :final end):
        _onUtteranceProgress(start, end, word);

      case DisposeCommand():
        _engineBridge?.dispose();
        _fromMainPort.close();
    }
  }

  Future<void> _configureVoice(TtsVoiceModel? voice) async {
    if (voice == null) {
      await _engineBridge?.stop();
      _engineBridge = null;
      _state = _state.copyWith(
        clearActiveVoice: true,
        hasInstalledModels: false,
      );
      _emitState();
      return;
    }

    await _engineBridge?.dispose();
    _engineBridge = createEngineBridge(voice.engineType);
    await _engineBridge!.initialize(
      voice: voice,
      rootIsolateToken: _rootIsolateToken,
    );

    _state = _state.copyWith(
      activeVoice: voice,
      hasInstalledModels: true,
    );
    _emitState();
  }

  void _loadText(String rawText, int startIndex) {
    _sentences = _splitIntoSentences(rawText);
    _currentIndex = _sentences.isEmpty
        ? 0
        : startIndex.clamp(0, _sentences.length - 1);

    final currentSentenceText =
        _sentences.isNotEmpty ? _sentences[_currentIndex].text : '';

    _state = _state.copyWith(
      playbackState: TtsPlaybackState.stopped,
      currentSentenceIndex: _currentIndex,
      totalSentences: _sentences.length,
      currentSentenceText: currentSentenceText,
      currentWord: '',
      activeWordStart: 0,
      activeWordEnd: 0,
    );

    _emitState();
  }

  void _play() {
    if (_sentences.isEmpty) return;

    // Zero-model safeguard: do not throw or crash if no voice is available
    if (_engineBridge == null && _state.activeVoice == null) {
      _toMainPort.send(const TtsErrorEvent('No TTS engine downloaded.'));
      return;
    }

    final currentSentence = _sentences[_currentIndex];

    _state = _state.copyWith(
      playbackState: TtsPlaybackState.playing,
      currentSentenceIndex: _currentIndex,
      totalSentences: _sentences.length,
      currentSentenceText: currentSentence.text,
    );
    _emitState();

    // Also notify main isolate of current chunk
    _toMainPort.send(
      SpeakChunkEvent(
        sentenceIndex: _currentIndex,
        text: currentSentence.text,
      ),
    );

    // If an engine bridge is present, speak through it
    if (_engineBridge != null) {
      _engineBridge!.speak(
        currentSentence.text,
        rate: _state.speechRate,
        pitch: _state.pitch,
        onWordBoundary: _onUtteranceProgress,
        onDone: _onUtteranceCompleted,
        onAudioBuffer: (samples, sampleRate) {
          _toMainPort.send(
            AudioBufferEvent(
              sentenceIndex: _currentIndex,
              samples: samples,
              sampleRate: sampleRate,
            ),
          );
        },
        onAudioBytes: (wavBytes, durationMs) {
          _toMainPort.send(
            PlayAudioBytesEvent(
              sentenceIndex: _currentIndex,
              wavBytes: wavBytes,
              durationMs: durationMs,
            ),
          );
        },
      );
    }
  }

  void _pause() {
    _engineBridge?.pause();
    _state = _state.copyWith(playbackState: TtsPlaybackState.paused);
    _emitState();
    _toMainPort.send(const PauseAudioEvent());
  }

  void _stop() {
    _engineBridge?.stop();
    _state = _state.copyWith(
      playbackState: TtsPlaybackState.stopped,
      currentWord: '',
      activeWordStart: 0,
      activeWordEnd: 0,
    );
    _emitState();
    _toMainPort.send(const StopAudioEvent());
  }

  void _nextSentence() {
    if (_sentences.isEmpty) return;

    if (_currentIndex < _sentences.length - 1) {
      _seekSentence(_currentIndex + 1);
    } else {
      _stop();
    }
  }

  void _previousSentence() {
    if (_sentences.isEmpty) return;

    if (_currentIndex > 0) {
      _seekSentence(_currentIndex - 1);
    } else {
      _seekSentence(0);
    }
  }

  void _seekSentence(int index) {
    if (_sentences.isEmpty) return;

    _engineBridge?.stop();
    final wasPlaying = _state.isPlaying;
    _currentIndex = index.clamp(0, _sentences.length - 1);

    _state = _state.copyWith(
      currentSentenceIndex: _currentIndex,
      currentSentenceText: _sentences[_currentIndex].text,
      currentWord: '',
      activeWordStart: 0,
      activeWordEnd: 0,
      playbackState: wasPlaying ? TtsPlaybackState.playing : TtsPlaybackState.stopped,
    );
    _emitState();

    if (wasPlaying) {
      _play();
    }
  }

  void _onUtteranceCompleted() {
    if (_sentences.isEmpty) return;

    if (_currentIndex < _sentences.length - 1) {
      _currentIndex++;
      _play();
    } else {
      _state = _state.copyWith(
        playbackState: TtsPlaybackState.completed,
        currentWord: '',
        activeWordStart: 0,
        activeWordEnd: 0,
      );
      _emitState();
    }
  }

  void _onUtteranceProgress(int start, int end, String word) {
    _state = _state.copyWith(
      currentWord: word,
      activeWordStart: start,
      activeWordEnd: end,
    );
    _emitState();

    _toMainPort.send(
      WordBoundaryEvent(
        sentenceIndex: _currentIndex,
        word: word,
        start: start,
        end: end,
      ),
    );
  }

  void _emitState() {
    _toMainPort.send(StateUpdatedEvent(_state));
  }

  /// Sentence-splitting logic using boundary punctuation (. ! ? \n).
  static List<SentenceChunk> _splitIntoSentences(String text) {
    if (text.trim().isEmpty) return const [];

    final sentences = <SentenceChunk>[];
    final regex = RegExp(r'[^.!?\n]+[.!?\n]+|[^.!?\n]+$');
    final matches = regex.allMatches(text);

    var index = 0;
    for (final match in matches) {
      final chunkText = match.group(0)?.trim() ?? '';
      if (chunkText.isEmpty) continue;

      final words = chunkText
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      sentences.add(
        SentenceChunk(
          index: index,
          text: chunkText,
          charStart: match.start,
          charEnd: match.end,
          words: words,
        ),
      );
      index++;
    }

    return sentences;
  }
}
