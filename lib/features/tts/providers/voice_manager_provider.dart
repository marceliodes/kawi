import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../models/tts_models.dart';
import '../services/tts_engine_bridge.dart';
import '../services/voice_manager_service.dart';
import 'tts_provider.dart';

/// State of voice model management.
class VoiceManagerState {
  const VoiceManagerState({
    this.voices = const [],
    this.activeVoice,
    this.isLoading = false,
    this.downloadingModelId,
    this.downloadProgress = 0.0,
    this.downloadStatus = '',
    this.totalDiskUsageBytes = 0,
    this.errorMessage,
  });

  final List<TtsVoiceModel> voices;
  final TtsVoiceModel? activeVoice;
  final bool isLoading;
  final String? downloadingModelId;
  final double downloadProgress;
  final String downloadStatus;
  final int totalDiskUsageBytes;
  final String? errorMessage;

  bool get hasInstalledModels => voices.any((v) => v.isInstalled);
  List<TtsVoiceModel> get installedVoices => voices.where((v) => v.isInstalled).toList();
  List<TtsVoiceModel> get availableVoices => voices.where((v) => !v.isInstalled).toList();

  bool get isKokoroInstalled =>
      voices.any((v) => v.engineType == TtsEngineType.kokoro && v.isInstalled);
  bool get isKokoroDownloading =>
      downloadingModelId == 'kokoro-engine' ||
      downloadingModelId?.startsWith('kokoro') == true;
  List<TtsVoiceModel> get kokoroVoices =>
      voices.where((v) => v.engineType == TtsEngineType.kokoro).toList();
  List<TtsVoiceModel> get piperVoices =>
      voices.where((v) => v.engineType == TtsEngineType.piper).toList();
  String get downloadPercentage =>
      '${(downloadProgress * 100).clamp(0, 100).toInt()}%';

  VoiceManagerState copyWith({
    List<TtsVoiceModel>? voices,
    TtsVoiceModel? activeVoice,
    bool clearActiveVoice = false,
    bool? isLoading,
    String? downloadingModelId,
    bool clearDownloading = false,
    double? downloadProgress,
    String? downloadStatus,
    int? totalDiskUsageBytes,
    String? errorMessage,
  }) {
    return VoiceManagerState(
      voices: voices ?? this.voices,
      activeVoice: clearActiveVoice ? null : (activeVoice ?? this.activeVoice),
      isLoading: isLoading ?? this.isLoading,
      downloadingModelId: clearDownloading
          ? null
          : (downloadingModelId ?? this.downloadingModelId),
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      totalDiskUsageBytes: totalDiskUsageBytes ?? this.totalDiskUsageBytes,
      errorMessage: errorMessage,
    );
  }
}

/// Service provider.
final voiceManagerServiceProvider = Provider<VoiceManagerService>((ref) {
  return VoiceManagerService();
});

/// Voice manager notifier.
class VoiceManagerNotifier extends Notifier<VoiceManagerState> {
  @override
  VoiceManagerState build() {
    // Initial scan triggered asynchronously
    Future.microtask(refresh);
    return const VoiceManagerState(isLoading: true);
  }

  VoiceManagerService get _service => ref.read(voiceManagerServiceProvider);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final voices = await _service.loadAllVoices();
      final diskUsage = await _service.calculateTotalDiskUsage();
      if (!ref.mounted) return;

      String? savedVoiceId;
      try {
        final db = ref.read(databaseProvider);
        savedVoiceId = await db.getSetting('active_voice_id');
      } catch (e) {
        debugPrint('Failed to read active voice setting: $e');
      }
      if (!ref.mounted) return;

      TtsVoiceModel? active;
      if (savedVoiceId != null) {
        active = voices.where((v) => v.id == savedVoiceId && v.isInstalled).firstOrNull;
      }

      if (active == null) {
        final currentActiveId = state.activeVoice?.id;
        if (currentActiveId != null && voices.any((v) => v.id == currentActiveId && v.isInstalled)) {
          active = voices.firstWhere((v) => v.id == currentActiveId);
        }
      }

      // If active voice is Kokoro but Kokoro is unsupported, fall back to installed Piper
      if (active != null && active.engineType == TtsEngineType.kokoro && !KokoroEngineBridge.isKokoroSupported) {
        final installed = voices.where((v) => v.isInstalled).toList();
        final piperVoice = installed.where((v) => v.engineType == TtsEngineType.piper).firstOrNull;
        if (piperVoice != null) {
          active = piperVoice;
          try {
            final db = ref.read(databaseProvider);
            db.setSetting('active_voice_id', active.id);
            db.setSetting('active_voice_engine', active.engineType.name);
          } catch (_) {}
        }
      }

      if (active == null) {
        // Fallback: Piper ('piper-en_US-lessac-medium') if installed, or any installed Piper, or null
        final installed = voices.where((v) => v.isInstalled).toList();
        active = installed.where((v) => v.id == 'piper-en_US-lessac-medium').firstOrNull;
        active ??= installed.where((v) => v.engineType == TtsEngineType.piper).firstOrNull;
      }

      state = state.copyWith(
        voices: voices,
        activeVoice: active,
        clearActiveVoice: active == null,
        totalDiskUsageBytes: diskUsage,
        isLoading: false,
      );
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to scan voice models: $e',
        );
      }
    }
  }

  void selectVoice(TtsVoiceModel voice, {bool initializeImmediately = false}) {
    if (!voice.isInstalled) return;
    state = state.copyWith(activeVoice: voice);
    ref.read(audioPlaybackServiceProvider).setActiveVoice(voice, initializeImmediately: initializeImmediately);
    try {
      final db = ref.read(databaseProvider);
      db.setSetting('active_voice_id', voice.id);
      db.setSetting('active_voice_engine', voice.engineType.name);
    } catch (e) {
      debugPrint('Failed to persist active voice setting: $e');
    }
  }

  Future<void> downloadVoice(TtsVoiceModel voice) async {
    if (state.downloadingModelId != null) return;

    state = state.copyWith(
      downloadingModelId: voice.id,
      downloadProgress: 0.05,
      downloadStatus: 'Starting download...',
    );

    try {
      if (voice.engineType == TtsEngineType.kokoro) {
        await _service.downloadKokoroModel(
          onProgress: (progress, status) {
            state = state.copyWith(
              downloadProgress: progress,
              downloadStatus: status,
            );
          },
        );
      } else {
        await _service.downloadPiperModel(
          voice,
          onProgress: (progress, status) {
            state = state.copyWith(
              downloadProgress: progress,
              downloadStatus: status,
            );
          },
        );
      }

      state = state.copyWith(clearDownloading: true);
      await refresh();

      // Auto-select downloaded voice if no active voice
      if (state.activeVoice == null) {
        final updatedVoice =
            state.voices.where((v) => v.id == voice.id).firstOrNull;
        if (updatedVoice != null && updatedVoice.isInstalled) {
          selectVoice(updatedVoice);
        }
      }
    } catch (e) {
      state = state.copyWith(
        clearDownloading: true,
        errorMessage: 'Download failed: $e',
      );
    }
  }

  Future<void> deleteVoice(TtsVoiceModel voice) async {
    try {
      await _service.deleteVoiceModel(voice);
      await refresh();
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete voice: $e');
    }
  }

  Future<void> downloadKokoroEngine() async {
    final kokoroVoice = state.kokoroVoices.firstOrNull ??
        const TtsVoiceModel(
          id: 'kokoro-default',
          name: 'Kokoro - Default (af)',
          engineType: TtsEngineType.kokoro,
        );
    await downloadVoice(kokoroVoice);
  }

  Future<void> deleteKokoroEngine() async {
    final kokoroVoice = state.kokoroVoices.where((v) => v.isInstalled).firstOrNull ??
        state.kokoroVoices.firstOrNull;
    if (kokoroVoice != null) {
      await deleteVoice(kokoroVoice);
    }
  }
}

final voiceManagerProvider =
    NotifierProvider<VoiceManagerNotifier, VoiceManagerState>(
  VoiceManagerNotifier.new,
);

final hasInstalledTtsModelsProvider = Provider<bool>((ref) {
  return ref.watch(voiceManagerProvider).hasInstalledModels;
});
