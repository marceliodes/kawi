import 'dart:async';
import 'dart:ffi';
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
import 'tts_text_normalizer.dart';

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
  String? _resolvedModelPath;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  bool get isPaused => _isPaused;

  Future<String?> _resolveKokoroModelPath() async {
    if (_resolvedModelPath != null && File(_resolvedModelPath!).existsSync()) {
      return _resolvedModelPath;
    }
    if (_modelPath != null && _modelPath!.isNotEmpty) {
      final f = File(_modelPath!);
      if (f.existsSync() && f.lengthSync() > 10 * 1024 * 1024) {
        _resolvedModelPath = _modelPath;
        return _resolvedModelPath;
      }
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final defaultFile = File(p.join(appDir.path, 'kokoro', 'Kokoro-82M-ONNX', 'model_quantized.onnx'));
      if (defaultFile.existsSync() && defaultFile.lengthSync() > 10 * 1024 * 1024) {
        _resolvedModelPath = defaultFile.path;
        return _resolvedModelPath;
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

    _resolvedModelPath = await _resolveKokoroModelPath();

    try {
      if (_kokoro == null) {
        _kokoro = KokoroTts();
        // ignore: avoid_print
        print('>>> [KOKORO BRIDGE] Initializing persistent ONNX session (style: $_voiceStyle, model: $_resolvedModelPath)... <<<');
        await _kokoro!.initialize();
        // ignore: avoid_print
        print('>>> [KOKORO BRIDGE] Persistent ONNX session initialized successfully <<<');
      }
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
    print('>>> [KOKORO BRIDGE] speak() called with: "$text" (rate=$rate, modelPath=$_resolvedModelPath) <<<');
    await stop();
    _isSpeaking = true;
    _isPaused = false;

    final normalizedText = TtsTextNormalizer.normalizeAllCaps(text);
    final words = _extractWords(normalizedText);
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
          normalizedText,
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

  /// Synthesizes raw speech samples off the UI thread reusing the persistent ONNX session.
  Future<Float32List> _synthesize(
    String text, {
    required String voiceStyle,
    required double speed,
  }) async {
    if (_kokoro == null) {
      _kokoro = KokoroTts();
      // ignore: avoid_print
      print('>>> [KOKORO BRIDGE] Creating initial ONNX session... <<<');
      await _kokoro!.initialize();
    } else {
      // ignore: avoid_print
      print('>>> [KOKORO BRIDGE] Reusing existing persistent ONNX session for synthesis (no reload) <<<');
    }
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
    _resolvedModelPath = null;
    _initialized = false;
  }
}

/// Piper VITS TTS Engine implementation.
class PiperEngineBridge implements TtsEngineBridge {
  bool _initialized = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  String? _activeVoiceId;
  String? _modelPath;
  String? _resolvedModelPath;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isSpeaking => _isSpeaking;

  @override
  bool get isPaused => _isPaused;

  Future<String?> _resolvePiperModelPath(String? voiceId) async {
    if (_resolvedModelPath != null && File(_resolvedModelPath!).existsSync()) {
      return _resolvedModelPath;
    }
    if (_modelPath != null && _modelPath!.isNotEmpty && File(_modelPath!).existsSync()) {
      _resolvedModelPath = _modelPath;
      return _resolvedModelPath;
    }
    try {
      final appDir = await getApplicationSupportDirectory();
      final piperDir = p.join(appDir.path, 'piper_models');
      if (voiceId != null) {
        final f = File(p.join(piperDir, '$voiceId.onnx'));
        if (f.existsSync()) {
          _resolvedModelPath = f.path;
          return _resolvedModelPath;
        }
      }
      final dir = Directory(piperDir);
      if (dir.existsSync()) {
        final onnxFiles = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.onnx'))
            .toList();
        if (onnxFiles.isNotEmpty) {
          _resolvedModelPath = onnxFiles.first.path;
          return _resolvedModelPath;
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _nativeLibsLoaded = false;

  static void _ensureNativeLibrariesLoaded() {
    if (_nativeLibsLoaded) return;
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isAndroid) return;

    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final searchDirs = [
        p.join(exeDir, 'lib'),
        p.join(exeDir, 'data', 'lib'),
        p.join(exeDir, '..', 'bundle', 'lib'),
        '/home/iruku/Dev/main/kawi/build/linux/x64/debug/bundle/lib',
      ];

      for (final dir in searchDirs) {
        if (!Directory(dir).existsSync()) continue;

        if (Platform.isLinux) {
          final onnx = File(p.join(dir, 'libonnxruntime.so.1.14.1'));
          if (onnx.existsSync()) {
            try {
              DynamicLibrary.open(onnx.path);
              // ignore: avoid_print
              print('>>> [PIPER BRIDGE] Pre-loaded onnxruntime from: ${onnx.path} <<<');
            } catch (e) {
              // ignore: avoid_print
              print('>>> [PIPER BRIDGE] Note on loading ${onnx.path}: $e <<<');
            }
          }

          final piper = File(p.join(dir, 'libpiper.so'));
          if (piper.existsSync()) {
            try {
              DynamicLibrary.open(piper.path);
              // ignore: avoid_print
              print('>>> [PIPER BRIDGE] Pre-loaded piper from: ${piper.path} <<<');
            } catch (e) {
              // ignore: avoid_print
              print('>>> [PIPER BRIDGE] Note on loading ${piper.path}: $e <<<');
            }
          }
        }
      }
      _nativeLibsLoaded = true;
    } catch (e) {
      // ignore: avoid_print
      print('>>> [PIPER BRIDGE] Error during native library pre-loading: $e <<<');
    }
  }

  @override
  Future<void> initialize({
    required TtsVoiceModel voice,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _ensureNativeLibrariesLoaded();
    _activeVoiceId = voice.id;
    _modelPath = voice.localPath;
    _resolvedModelPath = await _resolvePiperModelPath(voice.id);
    try {
      if (_resolvedModelPath != null && _resolvedModelPath!.isNotEmpty) {
        Piper.modelPath = _resolvedModelPath!;
      }
      // ignore: avoid_print
      print('>>> [PIPER BRIDGE] initialize() for voice: ${voice.name} (id: ${voice.id}), resolvedPath: $_resolvedModelPath (exists: ${_resolvedModelPath != null && File(_resolvedModelPath!).existsSync()}) <<<');
      _initialized = true;
    } catch (e, st) {
      // ignore: avoid_print
      print('>>> [PIPER BRIDGE] Native initialization error: $e\n$st <<<');
      rethrow;
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
    _ensureNativeLibrariesLoaded();
    await stop();
    _isSpeaking = true;
    _isPaused = false;

    final modelPath = await _resolvePiperModelPath(_activeVoiceId);
    // ignore: avoid_print
    print('>>> [PIPER BRIDGE] speak() called with text: "$text", model: "$modelPath" <<<');

    final normalizedText = TtsTextNormalizer.normalizeAllCaps(text);
    final words = _extractWords(normalizedText);
    if (words.isEmpty) {
      onDone();
      return;
    }

    if (modelPath != null && File(modelPath).existsSync()) {
      try {
        Piper.modelPath = modelPath;
        // ignore: avoid_print
        print('>>> [PIPER BRIDGE] Starting Piper speech generation with model: $modelPath <<<');
        final file = await Piper.generateSpeech(normalizedText);
        // ignore: avoid_print
        print('>>> [PIPER BRIDGE] Piper generateSpeech returned file: ${file.path} (exists: ${file.existsSync()}) <<<');
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
            // ignore: avoid_print
            print('>>> [PIPER BRIDGE] Piper finished synthesis: ${bytes.length} bytes (${durationMs}ms) for sentence: "$text" <<<');
            final timedWords = _computeTimedWords(words, durationMs);
            onAudioBytes?.call(Uint8List.fromList(bytes), durationMs, timedWords);
            return;
          }
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('>>> [PIPER BRIDGE] ERROR in Piper synthesis: $e\n$st <<<');
      }
    } else {
      // ignore: avoid_print
      print('>>> [PIPER BRIDGE] Piper model file not found at: $modelPath <<<');
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
    _resolvedModelPath = null;
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

