import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/theme/reader_theme.dart';
import 'package:kawi/core/theme/reader_theme_preset.dart';
import 'package:kawi/core/theme/reader_theme_tokens.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/providers/voice_manager_provider.dart';
import 'package:kawi/features/tts/screens/voice_manager_screen.dart';
import 'package:kawi/features/tts/services/voice_manager_service.dart';

class FakeVoiceManagerService extends VoiceManagerService {
  FakeVoiceManagerService({List<TtsVoiceModel>? initialVoices})
      : _voices = initialVoices ??
            [
              const TtsVoiceModel(
                id: 'kokoro-default',
                name: 'Kokoro - Default (af)',
                engineType: TtsEngineType.kokoro,
                isInstalled: true,
                isDefault: true,
                sizeBytes: 86 * 1024 * 1024,
              ),
              const TtsVoiceModel(
                id: 'piper-en_US-lessac-medium',
                name: 'Piper - Lessac',
                engineType: TtsEngineType.piper,
                sizeBytes: 36 * 1024 * 1024,
              ),
            ];

  List<TtsVoiceModel> _voices;
  bool deleteCalled = false;
  TtsVoiceModel? lastDeleted;

  @override
  Future<List<TtsVoiceModel>> loadAllVoices() async => List.from(_voices);

  @override
  Future<int> calculateTotalDiskUsage() async {
    return _voices
        .where((v) => v.isInstalled)
        .fold<int>(0, (sum, v) => sum + v.sizeBytes);
  }

  @override
  Future<void> deleteVoiceModel(TtsVoiceModel model) async {
    deleteCalled = true;
    lastDeleted = model;
    _voices = _voices.map((v) {
      if (v.id == model.id) {
        return v.copyWith(isInstalled: false);
      }
      return v;
    }).toList();
  }

  bool downloadCalled = false;
  bool downloadKokoroCalled = false;
  TtsVoiceModel? lastDownloaded;

  @override
  Future<void> downloadKokoroModel({
    void Function(double progress, String status)? onProgress,
  }) async {
    downloadKokoroCalled = true;
    onProgress?.call(0.5, 'Downloading...');
    _voices = _voices.map((v) {
      if (v.engineType == TtsEngineType.kokoro) {
        return v.copyWith(isInstalled: true);
      }
      return v;
    }).toList();
  }

  @override
  Future<void> downloadPiperModel(
    TtsVoiceModel model, {
    void Function(double progress, String status)? onProgress,
  }) async {
    downloadCalled = true;
    lastDownloaded = model;
    onProgress?.call(0.5, 'Downloading...');
    _voices = _voices.map((v) {
      if (v.id == model.id) {
        return v.copyWith(isInstalled: true);
      }
      return v;
    }).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (MethodCall methodCall) async => 1,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (MethodCall methodCall) async => 1,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          null,
        );
  });

  group('VoiceManager Tests', () {
    test('VoiceManagerState computed properties', () {
      const v1 = TtsVoiceModel(
        id: 'v1',
        name: 'Voice 1',
        engineType: TtsEngineType.kokoro,
        isInstalled: true,
      );
      const v2 = TtsVoiceModel(
        id: 'v2',
        name: 'Voice 2',
        engineType: TtsEngineType.piper,
      );

      const stateWithModels = VoiceManagerState(
        voices: [v1, v2],
        downloadProgress: 0.45,
      );
      expect(stateWithModels.hasInstalledModels, isTrue);
      expect(stateWithModels.isKokoroInstalled, isTrue);
      expect(stateWithModels.installedVoices.length, equals(1));
      expect(stateWithModels.availableVoices.length, equals(1));
      expect(stateWithModels.kokoroVoices.length, equals(1));
      expect(stateWithModels.piperVoices.length, equals(1));
      expect(stateWithModels.downloadPercentage, equals('45%'));

      const emptyState = VoiceManagerState(voices: [v2]);
      expect(emptyState.hasInstalledModels, isFalse);
      expect(emptyState.isKokoroInstalled, isFalse);
      expect(emptyState.installedVoices.isEmpty, isTrue);
    });

    test('VoiceManagerNotifier loads voices and auto-selects default active voice', () async {
      final fakeService = FakeVoiceManagerService();
      final container = ProviderContainer(
        overrides: [
          voiceManagerServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(voiceManagerProvider.notifier).refresh();

      final state = container.read(voiceManagerProvider);
      expect(state.voices.length, equals(2));
      expect(state.hasInstalledModels, isTrue);
      expect(state.activeVoice?.id, equals('kokoro-default'));
      expect(state.totalDiskUsageBytes, equals(86 * 1024 * 1024));
    });

    test('deleting active model updates activeVoice and transitions to zero-model state', () async {
      final fakeService = FakeVoiceManagerService(
        initialVoices: [
          const TtsVoiceModel(
            id: 'kokoro-default',
            name: 'Kokoro - Default (af)',
            engineType: TtsEngineType.kokoro,
            isInstalled: true,
            isDefault: true,
            sizeBytes: 86 * 1024 * 1024,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          voiceManagerServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(voiceManagerProvider.notifier).refresh();
      expect(container.read(voiceManagerProvider).hasInstalledModels, isTrue);

      final modelToDelete = container.read(voiceManagerProvider).activeVoice!;
      await container.read(voiceManagerProvider.notifier).deleteVoice(modelToDelete);

      final stateAfterDelete = container.read(voiceManagerProvider);
      expect(fakeService.deleteCalled, isTrue);
      expect(fakeService.lastDeleted?.id, equals('kokoro-default'));
      expect(stateAfterDelete.hasInstalledModels, isFalse);
      expect(stateAfterDelete.activeVoice, isNull);
      expect(container.read(hasInstalledTtsModelsProvider), isFalse);
    });

    test('downloadKokoroEngine downloads entire engine and selects it', () async {
      final fakeService = FakeVoiceManagerService(
        initialVoices: [
          const TtsVoiceModel(
            id: 'kokoro-default',
            name: 'Kokoro - Default (af)',
            engineType: TtsEngineType.kokoro,
            isDefault: true,
            sizeBytes: 86 * 1024 * 1024,
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          voiceManagerServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await container.read(voiceManagerProvider.notifier).refresh();
      expect(container.read(voiceManagerProvider).hasInstalledModels, isFalse);

      await container.read(voiceManagerProvider.notifier).downloadKokoroEngine();
      expect(fakeService.downloadKokoroCalled, isTrue);
      expect(container.read(voiceManagerProvider).hasInstalledModels, isTrue);
      expect(container.read(voiceManagerProvider).isKokoroInstalled, isTrue);
    });

    testWidgets('VoiceManagerScreen renders zero-model warning and single Kokoro download button', (tester) async {
      final fakeService = FakeVoiceManagerService(
        initialVoices: [
          const TtsVoiceModel(
            id: 'kokoro-default',
            name: 'Kokoro - Default (af)',
            engineType: TtsEngineType.kokoro,
            sizeBytes: 86 * 1024 * 1024,
          ),
          const TtsVoiceModel(
            id: 'piper-en_US-lessac-medium',
            name: 'Piper - Lessac',
            engineType: TtsEngineType.piper,
            sizeBytes: 36 * 1024 * 1024,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceManagerServiceProvider.overrideWithValue(fakeService),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(
              home: Scaffold(
                body: VoiceManagerScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Zero-model warning banner
      expect(
        find.textContaining('No TTS engine downloaded'),
        findsOneWidget,
      );

      // Single Kokoro card header
      expect(find.text('Kokoro 82M Neural TTS'), findsOneWidget);

      // Only ONE download engine button for Kokoro
      expect(find.text('Download Engine'), findsOneWidget);

      // Piper model with separate download button
      expect(find.text('Piper - Lessac'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('VoiceManagerScreen renders voice style dropdown when Kokoro is installed', (tester) async {
      final fakeService = FakeVoiceManagerService(
        initialVoices: [
          const TtsVoiceModel(
            id: 'kokoro-default',
            name: 'Kokoro - Default (af)',
            engineType: TtsEngineType.kokoro,
            isInstalled: true,
            isDefault: true,
            sizeBytes: 86 * 1024 * 1024,
          ),
          const TtsVoiceModel(
            id: 'kokoro-bella',
            name: 'Kokoro - Bella (af_bella)',
            engineType: TtsEngineType.kokoro,
            isInstalled: true,
            sizeBytes: 86 * 1024 * 1024,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceManagerServiceProvider.overrideWithValue(fakeService),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(
              home: Scaffold(
                body: VoiceManagerScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Kokoro installed status
      expect(find.text('Voice Style:'), findsOneWidget);
      expect(find.text('Kokoro - Default (af)'), findsOneWidget);

      // Delete engine button is available
      expect(find.byTooltip('Delete Kokoro engine (~85 MB)'), findsOneWidget);
    });

    testWidgets('VoiceManagerScreen displays visible percentage during download', (tester) async {
      const stateWithDownload = VoiceManagerState(
        voices: [
          TtsVoiceModel(
            id: 'kokoro-default',
            name: 'Kokoro - Default (af)',
            engineType: TtsEngineType.kokoro,
          ),
        ],
        downloadingModelId: 'kokoro-default',
        downloadProgress: 0.65,
        downloadStatus: 'Downloading 55.2 / 85.0 MB...',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceManagerProvider.overrideWith(
              () => _StaticVoiceManagerNotifier(stateWithDownload),
            ),
          ],
          child: ReaderTheme(
            data: ReaderThemeTokens.fromPreset(ReaderThemePreset.paper),
            child: const MaterialApp(
              home: Scaffold(
                body: VoiceManagerScreen(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Percentage visible
      expect(find.text('65%'), findsWidgets);
      expect(find.text('Downloading 55.2 / 85.0 MB...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}

class _StaticVoiceManagerNotifier extends VoiceManagerNotifier {
  _StaticVoiceManagerNotifier(this._initialState);
  final VoiceManagerState _initialState;

  @override
  VoiceManagerState build() => _initialState;

  @override
  Future<void> refresh() async {}
}
