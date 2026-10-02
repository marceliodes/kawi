import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/tts/models/tts_models.dart';
import 'package:kawi/features/tts/services/tts_isolate_worker.dart';

void main() {
  group('TtsIsolateWorker & Message Bridge', () {
    late ReceivePort fromWorkerPort;
    late StreamController<dynamic> broadcastController;
    late SendPort toWorkerPort;
    late Isolate isolate;

    setUp(() async {
      fromWorkerPort = ReceivePort();
      broadcastController = StreamController<dynamic>.broadcast();
      fromWorkerPort.listen(broadcastController.add);

      final readyCompleter = Completer<SendPort>();

      broadcastController.stream.listen((message) {
        if (message is IsolateReadyEvent) {
          readyCompleter.complete(message.isolateSendPort);
        }
      });

      isolate = await Isolate.spawn(
        TtsIsolateWorker.entryPoint,
        fromWorkerPort.sendPort,
      );

      toWorkerPort = await readyCompleter.future;
    });

    tearDown(() {
      toWorkerPort.send(const DisposeCommand());
      isolate.kill(priority: Isolate.immediate);
      fromWorkerPort.close();
      broadcastController.close();
    });

    test('splits text into sentences and emits updated totalSentences', () async {
      final stateCompleter = Completer<TtsState>();

      broadcastController.stream.listen((message) {
        if (message is StateUpdatedEvent) {
          if (!stateCompleter.isCompleted) {
            stateCompleter.complete(message.state);
          }
        }
      });

      const sampleText =
          'Hello world! This is Dr. Smith speaking. '
          'We have 3.14 units left.\n\nHere is a new paragraph.';

      toWorkerPort.send(const LoadTextCommand(sampleText));

      final state = await stateCompleter.future;
      expect(state.totalSentences, equals(4));
      expect(state.currentSentenceIndex, equals(0));
      expect(state.currentSentenceText, equals('Hello world!'));
      expect(state.playbackState, equals(TtsPlaybackState.stopped));
    });

    test('zero-model safeguard: play without voice emits TtsErrorEvent', () async {
      toWorkerPort.send(const LoadTextCommand('Test sentence.'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final errorCompleter = Completer<TtsErrorEvent>();
      final sub = broadcastController.stream.listen((msg) {
        if (msg is TtsErrorEvent && !errorCompleter.isCompleted) {
          errorCompleter.complete(msg);
        }
      });

      toWorkerPort.send(const PlayCommand());
      final error = await errorCompleter.future;
      expect(error.errorMessage, contains('No TTS engine downloaded.'));
      await sub.cancel();
    });

    test('play, pause, next, and utterance completion cycle', () async {
      final events = <TtsEvent>[];
      final subscription = broadcastController.stream.listen((msg) {
        if (msg is TtsEvent) {
          events.add(msg);
        }
      });

      const mockVoice = TtsVoiceModel(
        id: 'test-mock-voice',
        name: 'Mock Test Voice',
        engineType: TtsEngineType.mock,
        isInstalled: true,
      );
      toWorkerPort.send(const ConfigureVoiceCommand(voice: mockVoice));

      // Wait until voice is configured
      while (!events.any((e) => e is StateUpdatedEvent && e.state.hasInstalledModels)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      const sampleText = 'Sentence one. Sentence two! Sentence three?';
      toWorkerPort.send(const LoadTextCommand(sampleText));

      // Wait until text is loaded
      while (!events.any((e) => e is StateUpdatedEvent && e.state.totalSentences == 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // 1. Play
      toWorkerPort.send(const PlayCommand());
      while (!events.any((e) => e is SpeakChunkEvent && e.sentenceIndex == 0)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final speakEvent1 = events.whereType<SpeakChunkEvent>().last;
      expect(speakEvent1.sentenceIndex, equals(0));
      expect(speakEvent1.text, equals('Sentence one.'));

      // 2. Utterance completion moves to sentence two
      toWorkerPort.send(const UtteranceCompletedCommand());
      while (!events.any((e) => e is SpeakChunkEvent && e.sentenceIndex == 1)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final speakEvent2 = events.whereType<SpeakChunkEvent>().last;
      expect(speakEvent2.sentenceIndex, equals(1));
      expect(speakEvent2.text, equals('Sentence two!'));

      // 3. Pause
      toWorkerPort.send(const PauseCommand());
      while (!events.any((e) => e is PauseAudioEvent)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(events.whereType<PauseAudioEvent>().isNotEmpty, isTrue);

      // 4. Next sentence
      toWorkerPort.send(const NextSentenceCommand());
      while (!events.any((e) => e is StateUpdatedEvent && e.state.currentSentenceIndex == 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final stateUpdated = events.whereType<StateUpdatedEvent>().last;
      expect(stateUpdated.state.currentSentenceIndex, equals(2));
      expect(stateUpdated.state.currentSentenceText, equals('Sentence three?'));

      // 5. Utterance completion at end marks completed
      toWorkerPort.send(const PlayCommand());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      toWorkerPort.send(const UtteranceCompletedCommand());
      while (!events.any((e) => e is StateUpdatedEvent && e.state.playbackState == TtsPlaybackState.completed)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final finalState = events.whereType<StateUpdatedEvent>().last;
      expect(finalState.state.playbackState, equals(TtsPlaybackState.completed));

      await subscription.cancel();
    });

    test('word boundary progress mapping', () async {
      const sampleText = 'The quick brown fox.';
      toWorkerPort.send(const LoadTextCommand(sampleText));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final boundaryCompleter = Completer<WordBoundaryEvent>();
      broadcastController.stream.listen((message) {
        if (message is WordBoundaryEvent && !boundaryCompleter.isCompleted) {
          boundaryCompleter.complete(message);
        }
      });

      toWorkerPort.send(
        const UtteranceProgressCommand(
          word: 'quick',
          start: 4,
          end: 9,
        ),
      );

      final event = await boundaryCompleter.future;
      expect(event.word, equals('quick'));
      expect(event.start, equals(4));
      expect(event.end, equals(9));
      expect(event.sentenceIndex, equals(0));
    });
  });
}
