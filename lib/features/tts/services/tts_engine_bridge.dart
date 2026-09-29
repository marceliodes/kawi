import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_kokoro_tts/flutter_kokoro_tts.dart';
// ignore: implementation_imports
import 'package:flutter_kokoro_tts/src/model_manager.dart';
import 'package:piper_tts/piper_tts.dart';

import '../../../core/utils/wav_encoder.dart';
import '../models/tts_models.dart';

typedef WordBoundaryCallback = void Function(int start, int end, String word);
typedef UtteranceDoneCallback = void Function();
typedef AudioBufferCallback = void Function(List<double> samples, int sampleRate);
typedef AudioBytesCallback = void Function(Uint8List wavBytes, int durationMs);

/// Abstract engine bridge running strictly in the background TTS isolate context.
///
/// Synthesizes audio samples off the main UI thread and passes encoded WAV bytes
/// back to the worker for dispatch to the main UI thread.
/// DOES NOT initialize or invoke AudioPlayer or GStreamer.
abstract class TtsEngineBridge {
  bool get isInitialized;

  /// Initializes the engine with the provided voice model and optional isolate token.
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  });

  /// Synthesizes speech for [text], firing [onWordBoundary] as each word is reached,
  /// calling [onAudioBytes] when encoded WAV data is ready for main thread playback,
  /// and calling [onDone] if there is no audio playback to await.
  Future<void> speak(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    required WordBoundaryCallback onWordBoundary,
    required UtteranceDoneCallback onDone,
    AudioBufferCallback? onAudioBuffer,
    AudioBytesCallback? onAudioBytes,
  });

  /// Pauses current word boundaries / generation.
  Future<void> pause();

  /// Stops current speech generation and cancels word boundary timers.
  Future<void> stop();

  /// Disposes of any resources, file handles, or ONNX sessions.
  Future<void> dispose();
}

/// Factory function to create an engine bridge matching the given engine type.
TtsEngineBridge createEngineBridge(TtsEngineType engineType) {
  switch (engineType) {
    case TtsEngineType.kokoro:
      return KokoroEngineBridge();
    case TtsEngineType.piper:
      return PiperEngineBridge();
    case TtsEngineType.mock:
      return MockTtsEngineBridge();
  }
}

/// Kokoro 82M TTS Engine implementation.
///
/// Executes synthesis off the main UI thread (via dedicated isolate / Isolate.run)
/// and emits WAV byte arrays to the main thread for playback.
class KokoroEngineBridge implements TtsEngineBridge {
  KokoroTts? _kokoro;
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  String _voiceStyle = 'Default';
  RootIsolateToken? _rootIsolateToken;
  final List<Timer> _wordTimers = [];

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _voiceStyle = voice.voiceStyle ?? 'Default';
    _rootIsolateToken = rootIsolateToken;

    if (rootIsolateToken != null) {
      try {
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
      } catch (_) {
        // May already be initialized in this isolate
      }
    }

    try {
      _kokoro ??= KokoroTts();
      _initialized = true;
    } catch (e) {
      debugPrint('[KokoroEngineBridge] Initialization note: $e');
      _initialized = true; // Allow graceful fallback
    }
  }

  @override
  Future<void> speak(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    required WordBoundaryCallback onWordBoundary,
    required UtteranceDoneCallback onDone,
    AudioBufferCallback? onAudioBuffer,
    AudioBytesCallback? onAudioBytes,
  }) async {
    await stop();
    _isSpeaking = true;
    _isPaused = false;

    final words = _extractWords(text);
    if (words.isEmpty) {
      onDone();
      return;
    }

    Float32List pcm = Float32List(0);
    final sampleRate = _kokoro?.sampleRate ?? 24000;

    // Check if Kokoro model is available on disk before running inference
    bool modelReady = false;
    try {
      final modelPath = KokoroModelManager().modelPath;
      if (modelPath.isNotEmpty) {
        final modelFile = File(modelPath);
        if (modelFile.existsSync() && modelFile.lengthSync() > 10 * 1024 * 1024) {
          modelReady = true;
        }
      }
    } catch (_) {
      modelReady = false;
    }

    if (modelReady) {
      try {
        pcm = await _synthesizeInIsolate(
          text,
          voiceStyle: _voiceStyle,
          speed: rate,
        );
        if (pcm.isNotEmpty) {
          onAudioBuffer?.call(pcm.toList(), sampleRate);
        }
      } catch (e) {
        debugPrint('[KokoroEngineBridge] Synthesis note: $e');
      }
    }

    if (!_isSpeaking) return;

    if (pcm.isNotEmpty) {
      // 1. Encode raw Float32 PCM samples into standard WAV byte array (Uint8List)
      final wavBytes = encodeWav(samples: pcm, sampleRate: sampleRate);
      final durationMs = (pcm.length / sampleRate * 1000).round();

      // 2. Schedule synchronized word boundaries based on actual audio duration
      _scheduleWordBoundaries(
        words: words,
        totalDurationMs: durationMs,
        onWordBoundary: onWordBoundary,
      );

      // 3. Send WAV bytes back to the main thread via callback
      onAudioBytes?.call(wavBytes, durationMs);
    } else {
      // Fallback word scheduling if no samples were synthesized
      final fallbackDurationMs = _estimateDurationMs(words, rate);
      _scheduleWordBoundaries(
        words: words,
        totalDurationMs: fallbackDurationMs,
        onWordBoundary: onWordBoundary,
        onComplete: () {
          if (_isSpeaking) {
            _isSpeaking = false;
            onDone();
          }
        },
      );
    }
  }

  /// Synthesizes raw speech samples off the UI thread.
  Future<Float32List> _synthesizeInIsolate(
    String text, {
    required String voiceStyle,
    required double speed,
  }) async {
    final token = _rootIsolateToken;
    if (token != null) {
      try {
        return await Isolate.run(() async {
          BackgroundIsolateBinaryMessenger.ensureInitialized(token);
          final kokoro = KokoroTts();
          await kokoro.initialize();
          final result = await kokoro.generate(text, voice: voiceStyle, speed: speed);
          await kokoro.dispose();
          return result;
        });
      } catch (e) {
        debugPrint('[KokoroEngineBridge] Isolate.run note: $e');
      }
    }

    _kokoro ??= KokoroTts();
    await _kokoro!.initialize();
    return await _kokoro!.generate(text, voice: voiceStyle, speed: speed);
  }

  void _scheduleWordBoundaries({
    required List<_WordToken> words,
    required int totalDurationMs,
    required WordBoundaryCallback onWordBoundary,
    VoidCallback? onComplete,
  }) {
    _cancelWordTimers();
    if (words.isEmpty) {
      onComplete?.call();
      return;
    }

    final totalChars = words.fold<int>(0, (sum, w) => sum + w.word.length);
    var elapsedMs = 0;

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final proportion = totalChars > 0 ? (word.word.length / totalChars) : (1.0 / words.length);
      final wordDuration = (totalDurationMs * proportion).round().clamp(40, 5000);

      final delayMs = elapsedMs;
      final timer = Timer(Duration(milliseconds: delayMs), () {
        if (_isSpeaking && !_isPaused) {
          onWordBoundary(word.start, word.end, word.word);
        }
      });
      _wordTimers.add(timer);

      elapsedMs += wordDuration;
    }

    if (onComplete != null) {
      final doneTimer = Timer(Duration(milliseconds: totalDurationMs), () {
        if (_isSpeaking && !_isPaused) {
          onComplete();
        }
      });
      _wordTimers.add(doneTimer);
    }
  }

  void _cancelWordTimers() {
    for (final timer in _wordTimers) {
      timer.cancel();
    }
    _wordTimers.clear();
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
    _cancelWordTimers();
  }

  @override
  Future<void> dispose() async {
    await stop();
    _kokoro = null;
    _initialized = false;
  }
}

/// Piper VITS TTS Engine implementation.
class PiperEngineBridge implements TtsEngineBridge {
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  final List<Timer> _wordTimers = [];
  String? _modelPath;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _modelPath = voice.localPath;
    if (_modelPath != null && _modelPath!.isNotEmpty) {
      Piper.modelPath = _modelPath!;
    }
    _initialized = true;
  }

  @override
  Future<void> speak(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    required WordBoundaryCallback onWordBoundary,
    required UtteranceDoneCallback onDone,
    AudioBufferCallback? onAudioBuffer,
    AudioBytesCallback? onAudioBytes,
  }) async {
    await stop();
    _isSpeaking = true;
    _isPaused = false;

    final words = _extractWords(text);
    if (words.isEmpty) {
      onDone();
      return;
    }

    // If Piper binary and model file exist, attempt generation
    if (_modelPath != null && File(_modelPath!).existsSync()) {
      try {
        Piper.modelPath = _modelPath!;
        final file = await Piper.generateSpeech(text);
        if (file.existsSync() && _isSpeaking) {
          final bytes = await file.readAsBytes();
          if (bytes.length > 44) {
            final pcm = bytes.sublist(44);
            final samples = <double>[];
            for (var i = 0; i < pcm.length - 1; i += 2) {
              final sample16 = pcm.buffer.asByteData().getInt16(i, Endian.little);
              samples.add(sample16 / 32768.0);
            }
            onAudioBuffer?.call(samples, 22050);

            final durationMs = ((pcm.length / (22050 * 2)) * 1000).round();
            _scheduleWordBoundaries(
              words: words,
              totalDurationMs: durationMs,
              onWordBoundary: onWordBoundary,
            );

            onAudioBytes?.call(Uint8List.fromList(bytes), durationMs);
            return;
          }
        }
      } catch (e) {
        debugPrint('[PiperEngineBridge] Piper generation: $e');
      }
    }

    // Fallback if no model file or in test environment
    final fallbackDurationMs = _estimateDurationMs(words, rate);
    _scheduleWordBoundaries(
      words: words,
      totalDurationMs: fallbackDurationMs,
      onWordBoundary: onWordBoundary,
      onComplete: () {
        if (_isSpeaking) {
          _isSpeaking = false;
          onDone();
        }
      },
    );
  }

  void _scheduleWordBoundaries({
    required List<_WordToken> words,
    required int totalDurationMs,
    required WordBoundaryCallback onWordBoundary,
    VoidCallback? onComplete,
  }) {
    _cancelWordTimers();
    if (words.isEmpty) {
      onComplete?.call();
      return;
    }

    final totalChars = words.fold<int>(0, (sum, w) => sum + w.word.length);
    var elapsedMs = 0;

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final proportion = totalChars > 0 ? (word.word.length / totalChars) : (1.0 / words.length);
      final wordDuration = (totalDurationMs * proportion).round().clamp(40, 5000);

      final delayMs = elapsedMs;
      final timer = Timer(Duration(milliseconds: delayMs), () {
        if (_isSpeaking && !_isPaused) {
          onWordBoundary(word.start, word.end, word.word);
        }
      });
      _wordTimers.add(timer);

      elapsedMs += wordDuration;
    }

    if (onComplete != null) {
      final doneTimer = Timer(Duration(milliseconds: totalDurationMs), () {
        if (_isSpeaking && !_isPaused) {
          onComplete();
        }
      });
      _wordTimers.add(doneTimer);
    }
  }

  void _cancelWordTimers() {
    for (final timer in _wordTimers) {
      timer.cancel();
    }
    _wordTimers.clear();
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
    _cancelWordTimers();
  }

  @override
  Future<void> dispose() async {
    await stop();
    _initialized = false;
  }
}

/// Lightweight mock engine bridge for fast unit testing and zero-binary environments.
class MockTtsEngineBridge implements TtsEngineBridge {
  MockTtsEngineBridge({this.wordDurationMs = 20});

  final int wordDurationMs;
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  Timer? _timer;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _initialized = true;
  }

  @override
  Future<void> speak(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    required WordBoundaryCallback onWordBoundary,
    required UtteranceDoneCallback onDone,
    AudioBufferCallback? onAudioBuffer,
    AudioBytesCallback? onAudioBytes,
  }) async {
    await stop();
    _isSpeaking = true;
    _isPaused = false;

    final words = _extractWords(text);
    if (words.isEmpty) {
      onDone();
      return;
    }

    var currentWordIndex = 0;
    final delay = max(5, (wordDurationMs / rate).round());

    _timer = Timer.periodic(Duration(milliseconds: delay), (timer) {
      if (!_isSpeaking || _isPaused) return;

      if (currentWordIndex < words.length) {
        final w = words[currentWordIndex];
        onWordBoundary(w.start, w.end, w.word);
        currentWordIndex++;
      } else {
        timer.cancel();
        _isSpeaking = false;
        onDone();
      }
    });

    final first = words[0];
    onWordBoundary(first.start, first.end, first.word);
    currentWordIndex = 1;
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    _initialized = false;
  }
}

class _WordToken {
  const _WordToken(this.word, this.start, this.end);
  final String word;
  final int start;
  final int end;
}

List<_WordToken> _extractWords(String text) {
  final result = <_WordToken>[];
  final matches = RegExp(r'\S+').allMatches(text);
  for (final m in matches) {
    result.add(_WordToken(m.group(0)!, m.start, m.end));
  }
  return result;
}

int _estimateDurationMs(List<_WordToken> words, double rate) {
  final baseWordDurationMs = (360 / rate).clamp(100.0, 1000.0).round();
  return max(100, words.length * baseWordDurationMs);
}
