import 'dart:isolate';

import 'package:flutter/services.dart';

import '../models/tts_models.dart';
import 'tts_engine_bridge.dart';
import 'tts_text_normalizer.dart';

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

  int? _prebufferingIndex;
  int _prebufferGeneration = 0;
  ({int index, Uint8List wavBytes, int durationMs, List<SentenceWord> words})?
      _prebufferedSentence;

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
        // ignore: avoid_print
        print('[TTS Worker] LoadTextCommand received with ${text.length} chars (startSentenceIndex: $startSentenceIndex)');
        _loadText(text, startSentenceIndex);

      case PlayCommand():
        // ignore: avoid_print
        print('[TTS Worker] PlayCommand received (sentences: ${_sentences.length}, currentIndex: $_currentIndex)');
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
        _prebufferGeneration++;
        _prebufferingIndex = null;
        _prebufferedSentence = null;
        _state = _state.copyWith(speechRate: rate);
        _emitState();
        if (_state.isPlaying) {
          _triggerPrebuffer();
        }

      case SetPitchCommand(:final pitch):
        _prebufferGeneration++;
        _prebufferingIndex = null;
        _prebufferedSentence = null;
        _state = _state.copyWith(pitch: pitch);
        _emitState();
        if (_state.isPlaying) {
          _triggerPrebuffer();
        }

      case UtteranceCompletedCommand(:final alreadyPlaying):
        _onUtteranceCompleted(alreadyPlaying: alreadyPlaying);

      case UtteranceProgressCommand(:final word, :final start, :final end):
        _onUtteranceProgress(start, end, word);

      case DisposeCommand():
        _prebufferGeneration++;
        _prebufferingIndex = null;
        _prebufferedSentence = null;
        _engineBridge?.dispose();
        _fromMainPort.close();
    }
  }

  Future<void> _configureVoice(TtsVoiceModel? voice) async {
    // ignore: avoid_print
    print('>>> [TTS ISOLATE] _configureVoice called (voice: ${voice?.name}, engine: ${voice?.engineType}) <<<');
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
    // ignore: avoid_print
    print('>>> [TTS ISOLATE] Created engine bridge: ${_engineBridge.runtimeType} <<<');
    try {
      await _engineBridge!.initialize(
        voice: voice,
        rootIsolateToken: _rootIsolateToken,
      );
      // ignore: avoid_print
      print('>>> [TTS ISOLATE] Engine bridge initialized successfully <<<');
    } catch (e, st) {
      // ignore: avoid_print
      print('>>> [TTS ISOLATE] Engine bridge initialization FAILED: $e <<<');
      // ignore: avoid_print
      print('>>> [TTS ISOLATE] Stack trace:\n$st <<<');
    }

    _state = _state.copyWith(
      activeVoice: voice,
      hasInstalledModels: true,
    );
    _emitState();
  }

  void _loadText(String rawText, int startSentenceIndex) {
    _prebufferGeneration++;
    _prebufferingIndex = null;
    _prebufferedSentence = null;

    final text = TtsTextNormalizer.flattenSoftLineBreaks(rawText);

    final sentenceRegex = RegExp(
      r'''(?<!\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|e\.g|i\.e)\.["'”’]?)(?<=[.!?]["'”’]?)\s+(?=[A-Z0-9“"‘'])|(?:\r?\n){2,}''',
    );

    final List<String> rawChunks = text
        .split(sentenceRegex)
        .map((s) => s.replaceFirst(RegExp(r'''^[”’»\)\]]+\s*'''), '').trim())
        .where((s) => s.isNotEmpty && RegExp(r'[a-zA-Z0-9]').hasMatch(s))
        .toList();

    // Populate _sentences with sanitized chunks
    _sentences = [
      for (var i = 0; i < rawChunks.length; i++)
        SentenceChunk(
          index: i,
          text: TtsTextNormalizer.normalizeAllCaps(rawChunks[i]),
          charStart: 0,
          charEnd: rawChunks[i].length,
          words: rawChunks[i]
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty && RegExp(r'[a-zA-Z0-9]').hasMatch(w))
              .toList(),
        ),
    ];

    _currentIndex = _sentences.isEmpty
        ? 0
        : startSentenceIndex.clamp(0, _sentences.length - 1);

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

  Future<void> _play() async {
    if (_sentences.isEmpty) {
      // ignore: avoid_print
      print('[TTS Worker] Play aborted: sentences list is empty.');
      return;
    }

    if (_currentIndex >= _sentences.length) {
      _stop();
      return;
    }

    // Zero-model safeguard: do not throw or crash if no voice is available
    if (_engineBridge == null && _state.activeVoice == null) {
      // ignore: avoid_print
      print('>>> [TTS ISOLATE] Play aborted: no engine bridge and no active voice <<<');
      _toMainPort.send(const TtsErrorEvent('No TTS engine downloaded.'));
      return;
    }

    final currentSentence = _sentences[_currentIndex];
    var cleanSentenceText =
        TtsTextNormalizer.filterPlaceholdersAndTags(currentSentence.text);
    cleanSentenceText = cleanSentenceText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanSentenceText.isEmpty || !TtsTextNormalizer.hasAlphanumeric(cleanSentenceText)) {
      _onUtteranceCompleted(alreadyPlaying: true);
      return;
    }
    // ignore: avoid_print
    print('>>> [TTS ISOLATE] Received synthesis command for: "${currentSentence.text}" (engine=${_engineBridge?.runtimeType}, index=${_currentIndex + 1}/${_sentences.length}) <<<');

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

    // If this sentence was already pre-buffered, dispatch it immediately!
    if (_prebufferedSentence != null && _prebufferedSentence!.index == _currentIndex) {
      final pre = _prebufferedSentence!;
      _prebufferedSentence = null;
      // ignore: avoid_print
      print('>>> [TTS ISOLATE] Sentence index $_currentIndex was pre-buffered! Dispatching immediately. <<<');
      _toMainPort.send(
        PlayAudioBytesEvent(
          sentenceIndex: _currentIndex,
          wavBytes: pre.wavBytes,
          durationMs: pre.durationMs,
          words: pre.words,
        ),
      );
      _triggerPrebuffer();
      return;
    }

    // If an engine bridge is present, speak through it
    if (_engineBridge != null) {
      try {
        await _engineBridge!.speak(
          currentSentence.text,
          rate: _state.speechRate,
          pitch: _state.pitch,
          onWordBoundary: _onUtteranceProgress,
          onDone: () {},
          onAudioBuffer: (samples, sampleRate) {
            _toMainPort.send(
              AudioBufferEvent(
                sentenceIndex: _currentIndex,
                samples: samples,
                sampleRate: sampleRate,
              ),
            );
          },
          onAudioBytes: (wavBytes, durationMs, [words = const []]) {
            // ignore: avoid_print
            print('>>> [TTS ISOLATE] onAudioBytes: ${wavBytes.length} bytes, ${durationMs}ms for sentence index $_currentIndex <<<');
            _toMainPort.send(
              PlayAudioBytesEvent(
                sentenceIndex: _currentIndex,
                wavBytes: wavBytes,
                durationMs: durationMs,
                words: words,
              ),
            );
            // While sentence _currentIndex is now playing on the main thread,
            // immediately trigger background synthesis for sentence _currentIndex + 1!
            _triggerPrebuffer();
          },
        );
      } catch (e, st) {
        // ignore: avoid_print
        print('>>> [TTS ISOLATE] ERROR in _engineBridge.speak(): $e <<<');
        // ignore: avoid_print
        print('>>> [TTS ISOLATE] Stack trace:\n$st <<<');
        _toMainPort.send(TtsErrorEvent('TTS synthesis failed: $e'));
      }
    } else {
      // ignore: avoid_print
      print('>>> [TTS ISOLATE] _engineBridge is null, no synthesis performed <<<');
    }
  }

  void _triggerPrebuffer() {
    if (!_state.isPlaying) return;
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _sentences.length) return;
    if (_prebufferingIndex == nextIndex) return;
    if (_prebufferedSentence?.index == nextIndex) return;
    if (_engineBridge == null) return;

    _prebufferingIndex = nextIndex;
    final currentGen = ++_prebufferGeneration;
    final nextSentence = _sentences[nextIndex];

    // ignore: avoid_print
    print('>>> [TTS ISOLATE] Lookahead: Pre-buffering sentence [${nextIndex + 1}/${_sentences.length}]: "${nextSentence.text}" <<<');

    _engineBridge!.speak(
      nextSentence.text,
      rate: _state.speechRate,
      pitch: _state.pitch,
      onWordBoundary: (_, _, _) {},
      onDone: () {},
      onAudioBytes: (wavBytes, durationMs, [words = const []]) {
        if (_prebufferGeneration != currentGen) {
          return;
        }
        _prebufferingIndex = null;
        _prebufferedSentence = (
          index: nextIndex,
          wavBytes: wavBytes,
          durationMs: durationMs,
          words: words,
        );

        // ignore: avoid_print
        print('>>> [TTS ISOLATE] Lookahead: Pre-buffering COMPLETE for sentence [${nextIndex + 1}/${_sentences.length}] (${wavBytes.length} bytes, ${durationMs}ms) <<<');

        if (_currentIndex == nextIndex) {
          _prebufferedSentence = null;
          // ignore: avoid_print
          print('>>> [TTS ISOLATE] In-flight prebuffer caught up with current sentence $nextIndex, dispatching PlayAudioBytesEvent <<<');
          _toMainPort.send(
            PlayAudioBytesEvent(
              sentenceIndex: nextIndex,
              wavBytes: wavBytes,
              durationMs: durationMs,
              words: words,
            ),
          );
          _triggerPrebuffer();
        } else {
          _toMainPort.send(
            PrebufferedAudioBytesEvent(
              sentenceIndex: nextIndex,
              wavBytes: wavBytes,
              durationMs: durationMs,
              words: words,
            ),
          );
        }
      },
    ).catchError((e, st) {
      if (_prebufferGeneration == currentGen) {
        _prebufferingIndex = null;
        // ignore: avoid_print
        print('>>> [TTS ISOLATE] Lookahead pre-buffering error: $e <<<');
        // ignore: avoid_print
        print('>>> [TTS ISOLATE] Stack trace:\n$st <<<');
      }
    });
  }

  void _pause() {
    _engineBridge?.pause();
    _state = _state.copyWith(playbackState: TtsPlaybackState.paused);
    _emitState();
    _toMainPort.send(const PauseAudioEvent());
  }

  void _stop() {
    _prebufferGeneration++;
    _prebufferingIndex = null;
    _prebufferedSentence = null;
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

    _prebufferGeneration++;
    _prebufferingIndex = null;
    _prebufferedSentence = null;
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

  void _onUtteranceCompleted({bool alreadyPlaying = false}) {
    if (_sentences.isEmpty) return;

    if (_currentIndex < _sentences.length - 1) {
      _currentIndex++;
      // ignore: avoid_print
      print('[TTS Worker] Utterance completed. Advancing to sentence [${_currentIndex + 1}/${_sentences.length}] (alreadyPlaying: $alreadyPlaying)');

      _state = _state.copyWith(
        playbackState: TtsPlaybackState.playing,
        currentSentenceIndex: _currentIndex,
        totalSentences: _sentences.length,
        currentSentenceText: _sentences[_currentIndex].text,
        currentWord: '',
        activeWordStart: 0,
        activeWordEnd: 0,
      );
      _emitState();

      _toMainPort.send(
        SpeakChunkEvent(
          sentenceIndex: _currentIndex,
          text: _sentences[_currentIndex].text,
        ),
      );

      if (alreadyPlaying) {
        // Main thread is already playing the pre-buffered audio!
        _prebufferedSentence = null;
        _triggerPrebuffer();
      } else {
        if (_prebufferedSentence != null && _prebufferedSentence!.index == _currentIndex) {
          final pre = _prebufferedSentence!;
          _prebufferedSentence = null;
          // ignore: avoid_print
          print('>>> [TTS ISOLATE] Using pre-buffered audio for sentence index $_currentIndex <<<');
          _toMainPort.send(
            PlayAudioBytesEvent(
              sentenceIndex: _currentIndex,
              wavBytes: pre.wavBytes,
              durationMs: pre.durationMs,
              words: pre.words,
            ),
          );
          _triggerPrebuffer();
        } else if (_prebufferingIndex == _currentIndex) {
          // ignore: avoid_print
          print('>>> [TTS ISOLATE] Pre-buffering in flight for active sentence $_currentIndex, will dispatch on finish <<<');
        } else {
          _play();
        }
      }
    } else {
      // ignore: avoid_print
      print('[TTS Worker] Utterance completed. All ${_sentences.length} sentences finished.');
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
}
