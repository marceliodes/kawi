import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/services/tts_engine_bridge.dart';

void main() {
  group('PiperEngineBridge Tests', () {
    test('initial state has correct defaults', () {
      final bridge = PiperEngineBridge();
      expect(bridge.isInitialized, isFalse);
      expect(bridge.isSpeaking, isFalse);
      expect(bridge.isPaused, isFalse);
    });

    test('initialize sets isInitialized to true', () async {
      final bridge = PiperEngineBridge();
      const voice = TtsVoiceModel(
        id: 'piper-en_US-lessac-medium',
        name: 'Piper - Lessac',
        engineType: TtsEngineType.piper,
        localPath: '/tmp/nonexistent_model.onnx',
      );

      await bridge.initialize(voice: voice);
      expect(bridge.isInitialized, isTrue);
    });

    test('pause and stop toggle state correctly', () async {
      final bridge = PiperEngineBridge();
      await bridge.pause();
      expect(bridge.isPaused, isTrue);

      await bridge.stop();
      expect(bridge.isSpeaking, isFalse);
      expect(bridge.isPaused, isFalse);
    });

    test('dispose resets state and clears model session', () async {
      final bridge = PiperEngineBridge();
      const voice = TtsVoiceModel(
        id: 'piper-en_US-lessac-medium',
        name: 'Piper - Lessac',
        engineType: TtsEngineType.piper,
      );

      await bridge.initialize(voice: voice);
      expect(bridge.isInitialized, isTrue);

      await bridge.dispose();
      expect(bridge.isInitialized, isFalse);
    });

    test('speak with empty text invokes onDone immediately', () async {
      final bridge = PiperEngineBridge();
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
  });
}
