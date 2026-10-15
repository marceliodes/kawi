import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/services/tts_engine_bridge.dart';
import 'package:kawi/features/tts/services/voice_manager_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  final Directory _tempDir = Directory.systemTemp.createTempSync('kawi_tts_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => _tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => _tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('KokoroEngineBridge Tests', () {
    setUp(KokoroEngineBridge.resetAvailability);

    tearDown(KokoroEngineBridge.resetAvailability);

    test('initial state has correct defaults', () {
      final bridge = KokoroEngineBridge();
      expect(bridge.isInitialized, isFalse);
      expect(bridge.isSpeaking, isFalse);
      expect(bridge.isPaused, isFalse);
      expect(KokoroEngineBridge.isKokoroSupported, isTrue);
      expect(KokoroEngineBridge.isAvailable, isTrue);
    });

    test('fallback to Piper when Kokoro ONNX session initialization fails', () async {
      final bridge = KokoroEngineBridge();
      const voice = TtsVoiceModel(
        id: 'kokoro-default',
        name: 'Kokoro - Default (af)',
        engineType: TtsEngineType.kokoro,
        localPath: '/tmp/nonexistent_kokoro_model.onnx',
      );

      // In unit test environment, Kokoro ONNX native library is not available,
      // simulating an invalid opset / missing library failure.
      await bridge.initialize(voice: voice);

      // It should mark Kokoro as unsupported and fall back to Piper
      expect(KokoroEngineBridge.isKokoroSupported, isFalse);
      expect(KokoroEngineBridge.isAvailable, isFalse);
      expect(bridge.isInitialized, isTrue);
    });

    test('when isKokoroSupported is false, initialize directly falls back to Piper', () async {
      KokoroEngineBridge.isKokoroSupported = false;

      final bridge = KokoroEngineBridge();
      const voice = TtsVoiceModel(
        id: 'kokoro-default',
        name: 'Kokoro - Default (af)',
        engineType: TtsEngineType.kokoro,
      );

      await bridge.initialize(voice: voice);
      expect(bridge.isInitialized, isTrue);
    });

    test('pause, stop, and dispose handle fallback state cleanly', () async {
      final bridge = KokoroEngineBridge();
      const voice = TtsVoiceModel(
        id: 'kokoro-default',
        name: 'Kokoro - Default (af)',
        engineType: TtsEngineType.kokoro,
      );

      await bridge.initialize(voice: voice);

      await bridge.pause();
      expect(bridge.isPaused, isTrue);

      await bridge.stop();
      expect(bridge.isSpeaking, isFalse);
      expect(bridge.isPaused, isFalse);

      await bridge.dispose();
      expect(bridge.isInitialized, isFalse);
    });

    test('speak with empty text delegates and invokes onDone immediately', () async {
      final bridge = KokoroEngineBridge();
      const voice = TtsVoiceModel(
        id: 'kokoro-default',
        name: 'Kokoro - Default (af)',
        engineType: TtsEngineType.kokoro,
      );
      await bridge.initialize(voice: voice);

      var doneCalled = false;
      await bridge.speak(
        '   ',
        onWordBoundary: (_, _, _) {},
        onDone: () {
          doneCalled = true;
        },
      );

      expect(doneCalled, isTrue);
    });

    test('when Kokoro is unsupported, VoiceManagerService marks Kokoro voices as not installed', () async {
      KokoroEngineBridge.isKokoroSupported = false;

      final service = VoiceManagerService();
      final voices = await service.loadAllVoices();

      final kokoroVoices = voices.where((v) => v.engineType == TtsEngineType.kokoro);
      for (final kv in kokoroVoices) {
        expect(kv.isInstalled, isFalse);
        expect(kv.description, contains('Piper fallback active'));
      }
    });
  });
}
