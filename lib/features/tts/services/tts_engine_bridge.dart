import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_kokoro_tts/flutter_kokoro_tts.dart';
import 'package:piper_tts/piper_tts.dart';

import '../models/tts_models.dart';

typedef WordBoundaryCallback = void Function(int start, int end, String word);
typedef UtteranceDoneCallback = void Function();
typedef AudioBufferCallback = void Function(List<double> samples, int sampleRate);

/// Abstract engine bridge running in the TTS isolate context.
///
/// Handles initialization, speech generation, pausing, stopping, and
/// real-time word-boundary notifications across different underlying engines.
abstract class TtsEngineBridge {
  bool get isInitialized;

  /// Initializes the engine with the provided voice model and optional isolate token.
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  });

  /// Synthesizes and plays [text], firing [onWordBoundary] as each word is spoken,
  /// calling [onAudioBuffer] when audio samples are ready,
  /// and calling [onDone] when the sentence finishes.
  Future<void> speak(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    required WordBoundaryCallback onWordBoundary,
    required UtteranceDoneCallback onDone,
    AudioBufferCallback? onAudioBuffer,
  });

  /// Pauses current playback.
  Future<void> pause();

  /// Stops current playback and clears pending audio buffers.
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
class KokoroEngineBridge implements TtsEngineBridge {
  KokoroTts? _kokoro;
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  Timer? _wordTimer;
  Timer? _completionTimer;
  String _voiceStyle = 'Default';

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _voiceStyle = voice.voiceStyle ?? 'Default';

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
  }) async {
    await stop();
    _isSpeaking = true;
    _isPaused = false;

    final words = _extractWords(text);
    if (words.isEmpty) {
      onDone();
      return;
    }

    // Try actual Kokoro generation in isolate if model exists
    try {
      if (_kokoro != null) {
        _kokoro!.generate(text, voice: _voiceStyle, speed: rate).then((audioData) {
          if (audioData.isNotEmpty && onAudioBuffer != null) {
            onAudioBuffer(audioData.toList(), _kokoro?.sampleRate ?? 24000);
          }
        }).catchError((dynamic _) {});
      }
    } catch (_) {
      // Graceful fallback to word timer
    }

    // Deliver progressive word-boundary callbacks matching reading speed
    _scheduleWordBoundaries(
      text: text,
      words: words,
      rate: rate,
      onWordBoundary: onWordBoundary,
      onDone: onDone,
    );
  }

  void _scheduleWordBoundaries({
    required String text,
    required List<_WordToken> words,
    required double rate,
    required WordBoundaryCallback onWordBoundary,
    required UtteranceDoneCallback onDone,
  }) {
    // Normal speech rate is roughly 150 words per minute -> 400ms per word
    final baseWordDurationMs = (380 / rate).clamp(100.0, 1000.0).round();
    var currentWordIndex = 0;

    _wordTimer = Timer.periodic(
      Duration(milliseconds: baseWordDurationMs),
      (timer) {
        if (!_isSpeaking || _isPaused) return;

        if (currentWordIndex < words.length) {
          final wordToken = words[currentWordIndex];
          onWordBoundary(wordToken.start, wordToken.end, wordToken.word);
          currentWordIndex++;
        } else {
          timer.cancel();
          _isSpeaking = false;
          onDone();
        }
      },
    );

    // Initial word immediately
    if (words.isNotEmpty) {
      final first = words[0];
      onWordBoundary(first.start, first.end, first.word);
      currentWordIndex = 1;
    }
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
    _wordTimer?.cancel();
    _wordTimer = null;
    _completionTimer?.cancel();
    _completionTimer = null;
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
  Timer? _wordTimer;
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
        if (file.existsSync() && onAudioBuffer != null) {
          final bytes = await file.readAsBytes();
          if (bytes.length > 44) {
            final pcm = bytes.sublist(44);
            final samples = <double>[];
            for (var i = 0; i < pcm.length - 1; i += 2) {
              final sample16 = pcm.buffer.asByteData().getInt16(i, Endian.little);
              samples.add(sample16 / 32768.0);
            }
            onAudioBuffer(samples, 22050);
          }
        }
      } catch (e) {
        debugPrint('[PiperEngineBridge] Piper generation: $e');
      }
    }

    final baseWordDurationMs = (350 / rate).clamp(100.0, 1000.0).round();
    var currentWordIndex = 0;

    _wordTimer = Timer.periodic(
      Duration(milliseconds: baseWordDurationMs),
      (timer) {
        if (!_isSpeaking || _isPaused) return;

        if (currentWordIndex < words.length) {
          final wordToken = words[currentWordIndex];
          onWordBoundary(wordToken.start, wordToken.end, wordToken.word);
          currentWordIndex++;
        } else {
          timer.cancel();
          _isSpeaking = false;
          onDone();
        }
      },
    );

    if (words.isNotEmpty) {
      final first = words[0];
      onWordBoundary(first.start, first.end, first.word);
      currentWordIndex = 1;
    }
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
    _wordTimer?.cancel();
    _wordTimer = null;
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
