import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tts_models.dart';
import '../services/audio_playback_service.dart';

/// Provider for the singleton [AudioPlaybackService].
final ttsServiceProvider = Provider<AudioPlaybackService>((ref) {
  final service = AudioPlaybackService();
  service.initialize();
  ref.onDispose(service.dispose);
  return service;
});

/// Alias provider for readability.
final audioPlaybackServiceProvider = ttsServiceProvider;

/// Notifier exposing reactive [TtsState] to the UI.
class TtsStateNotifier extends Notifier<TtsState> {
  @override
  TtsState build() {
    final service = ref.watch(ttsServiceProvider);

    void listener() {
      state = service.stateNotifier.value;
    }

    service.stateNotifier.addListener(listener);
    ref.onDispose(() {
      service.stateNotifier.removeListener(listener);
    });

    return service.currentState;
  }

  void loadText(String text, {int startSentenceIndex = 0}) {
    // ignore: avoid_print
    print('>>> [TTS NOTIFIER] loadText (${text.length} chars) <<<');
    ref.read(ttsServiceProvider).loadText(text, startSentenceIndex: startSentenceIndex);
  }

  void speak(String text, {int startSentenceIndex = 0}) {
    // ignore: avoid_print
    print('>>> [TTS NOTIFIER] speak (${text.length} chars) <<<');
    ref.read(ttsServiceProvider).speak(text, startSentenceIndex: startSentenceIndex);
  }

  void play() {
    // ignore: avoid_print
    print('>>> [TTS NOTIFIER] play() <<<');
    ref.read(ttsServiceProvider).play();
  }

  void pause() {
    // ignore: avoid_print
    print('>>> [TTS NOTIFIER] pause() <<<');
    ref.read(ttsServiceProvider).pause();
  }

  void stop() {
    // ignore: avoid_print
    print('>>> [TTS NOTIFIER] stop() <<<');
    ref.read(ttsServiceProvider).stop();
  }

  void nextSentence() {
    ref.read(ttsServiceProvider).nextSentence();
  }

  void previousSentence() {
    ref.read(ttsServiceProvider).previousSentence();
  }

  void seekSentence(int index) {
    ref.read(ttsServiceProvider).seekSentence(index);
  }

  void setRate(double rate) {
    ref.read(ttsServiceProvider).setSpeechRate(rate);
  }

  void setPitch(double pitch) {
    ref.read(ttsServiceProvider).setPitch(pitch);
  }
}

final ttsStateProvider = NotifierProvider<TtsStateNotifier, TtsState>(
  TtsStateNotifier.new,
);

/// Alias provider for ttsStateProvider to support ttsNotifierProvider naming.
final ttsNotifierProvider = ttsStateProvider;

/// Stream provider for word boundary events for fine-grained highlighting.
final ttsWordBoundaryProvider = StreamProvider.autoDispose<WordBoundaryEvent>((ref) {
  final service = ref.watch(ttsServiceProvider);
  return service.wordBoundaryStream;
});
