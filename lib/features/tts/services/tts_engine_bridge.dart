import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_kokoro_tts/flutter_kokoro_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:piper_tts/piper_tts.dart';

import '../../../core/utils/wav_encoder.dart';
import '../models/tts_models.dart';

typedef WordBoundaryCallback = void Function(int start, int end, String word);
typedef UtteranceDoneCallback = void Function();
typedef AudioBufferCallback = void Function(List<double> samples, int sampleRate);
typedef AudioBytesCallback = void Function(
  Uint8List wavBytes,
  int durationMs, [
  List<SentenceWord> words,
]);

/// Abstract engine bridge running strictly in the background TTS isolate context.
///
/// Synthesizes audio samples off the main UI thread and passes encoded WAV bytes
/// back to the worker for dispatch to the main UI thread.
/// DOES NOT initialize or invoke AudioPlayer or GStreamer.
abstract class TtsEngineBridge {
  bool get isInitialized;
  bool get isSpeaking;
  bool get isPaused;

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
/// Executes synthesis off the main UI thread in the background TTS isolate
/// and emits WAV byte arrays to the main thread for playback.
class KokoroEngineBridge implements TtsEngineBridge {
  KokoroTts? _kokoro;
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  String _voiceStyle = 'Default';
  String? _modelPath;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  bool get isPaused => _isPaused;

  Future<String?> _resolveKokoroModelPath() async {
    if (_modelPath != null && _modelPath!.isNotEmpty) {
      final f = File(_modelPath!);
      if (f.existsSync() && f.lengthSync() > 10 * 1024 * 1024) {
        return _modelPath;
      }
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final defaultFile = File(p.join(appDir.path, 'kokoro', 'Kokoro-82M-ONNX', 'model_quantized.onnx'));
      if (defaultFile.existsSync() && defaultFile.lengthSync() > 10 * 1024 * 1024) {
        _modelPath = defaultFile.path;
        return _modelPath;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _voiceStyle = voice.voiceStyle ?? 'Default';
    _modelPath = voice.localPath;

    if (rootIsolateToken != null) {
      try {
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
      } catch (_) {
        // May already be initialized in this isolate
      }
    }

    await _resolveKokoroModelPath();

    try {
      _kokoro ??= KokoroTts();
      await _kokoro!.initialize();
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
    // ignore: avoid_print
    print('>>> [KOKORO BRIDGE] speak() called with: "$text" (rate=$rate, modelPath=$_modelPath) <<<');
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

    final resolvedPath = await _resolveKokoroModelPath();
    final modelReady = resolvedPath != null;

    if (modelReady) {
      try {
        pcm = await _synthesize(
          text,
          voiceStyle: _voiceStyle,
          speed: rate,
        );
        final durationMs = (pcm.length / sampleRate * 1000).round();
        // ignore: avoid_print
        print('[TTS Worker] Kokoro finished inference: ${pcm.length} samples (${durationMs}ms) for sentence: "$text"');
        if (pcm.isNotEmpty) {
          onAudioBuffer?.call(pcm.toList(), sampleRate);
        }
      } catch (e) {
        debugPrint('[KokoroEngineBridge] Synthesis note: $e');
      }
    } else {
      debugPrint('[KokoroEngineBridge] Kokoro model file not ready.');
    }

    if (!_isSpeaking) return;

    if (pcm.isNotEmpty) {
      // 1. Encode raw Float32 PCM samples into standard WAV byte array (Uint8List)
      final wavBytes = encodeWav(samples: pcm, sampleRate: sampleRate);
      final durationMs = (pcm.length / sampleRate * 1000).round();

      // 2. Compute timed word boundaries aligned to actual duration
      final timedWords = _computeTimedWords(words, durationMs);

      // 3. Send WAV bytes and timed words back to the main thread via callback
      onAudioBytes?.call(wavBytes, durationMs, timedWords);
    } else {
      // Inference produced no samples. Do NOT trigger onDone fallback timer to advance sentences silently.
      _isSpeaking = false;
      debugPrint('[KokoroEngineBridge] No audio synthesized for sentence. Playback stopped.');
    }
  }

  /// Synthesizes raw speech samples off the UI thread.
  Future<Float32List> _synthesize(
    String text, {
    required String voiceStyle,
    required double speed,
  }) async {
    _kokoro ??= KokoroTts();
    await _kokoro!.initialize();
    return await _kokoro!.generate(text, voice: voiceStyle, speed: speed);
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
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
  String? _modelPath;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  bool get isPaused => _isPaused;

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
            final timedWords = _computeTimedWords(words, durationMs);
            onAudioBytes?.call(Uint8List.fromList(bytes), durationMs, timedWords);
            return;
          }
        }
      } catch (e) {
        debugPrint('[PiperEngineBridge] Piper generation: $e');
      }
    }

    // If no audio was generated, do not advance sentences on a fallback timer
    _isSpeaking = false;
    debugPrint('[PiperEngineBridge] Piper generation produced no audio.');
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
  }

  @override
  Future<void> stop() async {
    _isSpeaking = false;
    _isPaused = false;
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

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  bool get isPaused => _isPaused;

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

    final durationMs = max(100, (words.length * wordDurationMs / rate).round());
    final timedWords = _computeTimedWords(words, durationMs);

    const sampleRate = 22050;
    final sampleCount = (durationMs * sampleRate / 1000).round();
    final pcm = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      pcm[i] = (sin(2 * pi * 440 * i / sampleRate) * 0.05).clamp(-1.0, 1.0);
    }
    final wavBytes = encodeWav(samples: pcm, sampleRate: sampleRate);

    onAudioBuffer?.call(pcm.toList(), sampleRate);
    if (onAudioBytes != null) {
      onAudioBytes(wavBytes, durationMs, timedWords);
    } else {
      onDone();
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
  }

  @override
  Future<void> dispose() async {
    await stop();
    _initialized = false;
  }
}

List<SentenceWord> _extractWords(String text) {
  final result = <SentenceWord>[];
  final matches = RegExp(r'\S+').allMatches(text);
  for (final m in matches) {
    result.add(SentenceWord(
      word: m.group(0)!,
      start: m.start,
      end: m.end,
    ));
  }
  return result;
}

List<SentenceWord> _computeTimedWords(List<SentenceWord> words, int totalDurationMs) {
  if (words.isEmpty) return const [];
  final totalChars = words.fold<int>(0, (sum, w) => sum + w.word.length);
  var elapsedMs = 0;
  final result = <SentenceWord>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final proportion =
        totalChars > 0 ? (w.word.length / totalChars) : (1.0 / words.length);
    final wordDuration = (totalDurationMs * proportion).round().clamp(20, 5000);
    result.add(
      SentenceWord(
        word: w.word,
        start: w.start,
        end: w.end,
        startMs: elapsedMs,
        endMs: elapsedMs + wordDuration,
      ),
    );
    elapsedMs += wordDuration;
  }
  return result;
}

