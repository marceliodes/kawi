import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
// ignore: implementation_imports
import 'package:flutter_kokoro_tts/src/model_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/tts_models.dart';

/// Service for managing local TTS voice models (downloading, switching, deleting).
class VoiceManagerService {
  VoiceManagerService();

  final KokoroModelManager _kokoroManager = KokoroModelManager();

  // Curated list of downloadable Piper models from huggingface/rhasspy
  static const List<TtsVoiceModel> _catalogPiperVoices = [
    TtsVoiceModel(
      id: 'piper-en_US-lessac-medium',
      name: 'Piper - Lessac',
      engineType: TtsEngineType.piper,
      sizeBytes: 36 * 1024 * 1024,
      downloadUrl:
          'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx',
      description: 'Clear, natural American English female voice (VITS, ~36 MB).',
    ),
    TtsVoiceModel(
      id: 'piper-en_US-amy-medium',
      name: 'Piper - Amy',
      engineType: TtsEngineType.piper,
      sizeBytes: 35 * 1024 * 1024,
      downloadUrl:
          'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/medium/en_US-amy-medium.onnx',
      description: 'Warm, expressive American English female voice (VITS, ~35 MB).',
    ),
    TtsVoiceModel(
      id: 'piper-en_US-ryan-medium',
      name: 'Piper - Ryan',
      engineType: TtsEngineType.piper,
      sizeBytes: 35 * 1024 * 1024,
      downloadUrl:
          'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/medium/en_US-ryan-medium.onnx',
      description: 'Articulate American English male voice (VITS, ~35 MB).',
    ),
    TtsVoiceModel(
      id: 'piper-en_GB-alba-medium',
      name: 'Piper - Alba',
      engineType: TtsEngineType.piper,
      locale: 'en-GB',
      sizeBytes: 34 * 1024 * 1024,
      downloadUrl:
          'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_GB/alba/medium/en_GB-alba-medium.onnx',
      description: 'Crisp British English female voice (VITS, ~34 MB).',
    ),
  ];

  static const List<TtsVoiceModel> _catalogKokoroVoices = [
    TtsVoiceModel(
      id: 'kokoro-default',
      name: 'Kokoro - Default (af)',
      engineType: TtsEngineType.kokoro,
      isDefault: true,
      voiceStyle: 'Default',
      sizeBytes: 86 * 1024 * 1024,
      description: 'Default Kokoro 82M quantized neural diffusion voice (~86 MB).',
    ),
    TtsVoiceModel(
      id: 'kokoro-bella',
      name: 'Kokoro - Bella (af_bella)',
      engineType: TtsEngineType.kokoro,
      voiceStyle: 'Bella',
      sizeBytes: 86 * 1024 * 1024,
      description: 'Expressive American English female voice (af_bella).',
    ),
    TtsVoiceModel(
      id: 'kokoro-nicole',
      name: 'Kokoro - Nicole (af_nicole)',
      engineType: TtsEngineType.kokoro,
      voiceStyle: 'Nicole',
      sizeBytes: 86 * 1024 * 1024,
      description: 'Warm American English female voice (af_nicole).',
    ),
    TtsVoiceModel(
      id: 'kokoro-sarah',
      name: 'Kokoro - Sarah (af_sarah)',
      engineType: TtsEngineType.kokoro,
      voiceStyle: 'Sarah',
      sizeBytes: 86 * 1024 * 1024,
      description: 'Clear American English female voice (af_sarah).',
    ),
    TtsVoiceModel(
      id: 'kokoro-adam',
      name: 'Kokoro - Adam (am_adam)',
      engineType: TtsEngineType.kokoro,
      voiceStyle: 'Adam',
      sizeBytes: 86 * 1024 * 1024,
      description: 'Articulate American English male voice (am_adam).',
    ),
    TtsVoiceModel(
      id: 'kokoro-michael',
      name: 'Kokoro - Michael (am_michael)',
      engineType: TtsEngineType.kokoro,
      voiceStyle: 'Michael',
      sizeBytes: 86 * 1024 * 1024,
      description: 'Natural American English male voice (am_michael).',
    ),
  ];

  Future<String> _getPiperDirectoryPath() async {
    final appDir = await getApplicationSupportDirectory();
    final piperDir = Directory(p.join(appDir.path, 'piper_models'));
    if (!piperDir.existsSync()) {
      piperDir.createSync(recursive: true);
    }
    return piperDir.path;
  }

  /// Scans local disk and returns all voices with their installed status.
  Future<List<TtsVoiceModel>> loadAllVoices() async {
    final list = <TtsVoiceModel>[];

    // Non-blocking Kokoro model status check (checks existence & size rather than hashing 85MB on UI thread)
    bool kokoroReady = false;
    try {
      final modelPath = _kokoroManager.modelPath;
      if (modelPath.isNotEmpty) {
        final modelFile = File(modelPath);
        if (modelFile.existsSync() && modelFile.lengthSync() > 10 * 1024 * 1024) {
          kokoroReady = true;
        }
      }
    } catch (_) {
      kokoroReady = false;
    }

    for (final kv in _catalogKokoroVoices) {
      list.add(
        kv.copyWith(
          isInstalled: kokoroReady,
          localPath: kokoroReady ? _kokoroManager.modelPath : null,
        ),
      );
    }

    // Check Piper models on disk
    final piperDir = await _getPiperDirectoryPath();
    for (final pv in _catalogPiperVoices) {
      final modelFile = File(p.join(piperDir, '${pv.id}.onnx'));
      final isInstalled = modelFile.existsSync() && modelFile.lengthSync() > 0;
      final actualSize = isInstalled ? modelFile.lengthSync() : pv.sizeBytes;

      list.add(
        pv.copyWith(
          isInstalled: isInstalled,
          sizeBytes: actualSize,
          localPath: isInstalled ? modelFile.path : null,
        ),
      );
    }

    return list;
  }

  /// Downloads the Kokoro model assets (INT8 quantized ONNX model + voice vectors).
  Future<void> downloadKokoroModel({
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.05, 'Downloading Kokoro 82M INT8 (~85 MB)...');
    await _kokoroManager.download(
      onProgress: (p, status) {
        onProgress?.call(p * 0.9, status);
      },
    );
    onProgress?.call(0.92, 'Configuring phoneme dictionaries...');
    await _kokoroManager.ensureEspeakData();
    onProgress?.call(1.0, 'Kokoro engine ready');
  }

  /// Downloads a Piper ONNX model with progress tracking.
  Future<void> downloadPiperModel(
    TtsVoiceModel model, {
    void Function(double progress, String status)? onProgress,
  }) async {
    if (model.downloadUrl == null) {
      throw ArgumentError('Model has no downloadUrl');
    }

    final piperDir = await _getPiperDirectoryPath();
    final targetFile = File(p.join(piperDir, '${model.id}.onnx'));
    final partFile = File('${targetFile.path}.part');

    if (partFile.existsSync()) {
      partFile.deleteSync();
    }

    onProgress?.call(0.05, 'Starting download...');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(model.downloadUrl!));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? model.sizeBytes;
      var receivedBytes = 0;

      final sink = partFile.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.05, 0.95);
          onProgress?.call(
            progress,
            'Downloading ${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB...',
          );
        }
      }
      await sink.flush();
      await sink.close();

      // Download the json config if available
      final configUrl = '${model.downloadUrl!}.json';
      try {
        final configResp = await http.get(Uri.parse(configUrl));
        if (configResp.statusCode == 200) {
          final configFile = File(p.join(piperDir, '${model.id}.onnx.json'));
          await configFile.writeAsBytes(configResp.bodyBytes);
        }
      } catch (_) {
        // Optional config
      }

      if (targetFile.existsSync()) targetFile.deleteSync();
      partFile.renameSync(targetFile.path);

      onProgress?.call(1.0, 'Download complete');
    } catch (e) {
      if (partFile.existsSync()) partFile.deleteSync();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Deletes a voice model from disk to reclaim storage.
  /// Works for both Piper models and the default Kokoro model.
  Future<void> deleteVoiceModel(TtsVoiceModel model) async {
    if (model.engineType == TtsEngineType.kokoro) {
      // Delete Kokoro model directory entirely
      final baseDir = _kokoroManager.modelDir;
      if (baseDir.isNotEmpty) {
        final dir = Directory(baseDir);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      }
      // Also delete any ready marker or espeak data if desired
      final kokoroBase = Directory(_kokoroManager.kokoroBaseDir);
      if (kokoroBase.existsSync()) {
        try {
          kokoroBase.deleteSync(recursive: true);
        } catch (_) {}
      }
    } else if (model.engineType == TtsEngineType.piper) {
      final piperDir = await _getPiperDirectoryPath();
      final modelFile = File(p.join(piperDir, '${model.id}.onnx'));
      final configFile = File(p.join(piperDir, '${model.id}.onnx.json'));

      if (modelFile.existsSync()) {
        modelFile.deleteSync();
      }
      if (configFile.existsSync()) {
        configFile.deleteSync();
      }
    }
  }

  /// Calculates total disk space in bytes used by all installed models.
  Future<int> calculateTotalDiskUsage() async {
    var total = 0;
    try {
      final piperDir = Directory(await _getPiperDirectoryPath());
      if (piperDir.existsSync()) {
        for (final file in piperDir.listSync(recursive: true)) {
          if (file is File) {
            total += file.lengthSync();
          }
        }
      }

      if (_kokoroManager.modelDir.isNotEmpty) {
        final kokoroDir = Directory(_kokoroManager.modelDir);
        if (kokoroDir.existsSync()) {
          for (final file in kokoroDir.listSync(recursive: true)) {
            if (file is File) {
              total += file.lengthSync();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[VoiceManagerService] Error calculating disk usage: $e');
    }
    return total;
  }
}
