import 'dart:isolate';
import 'package:flutter/services.dart';

/// Supported offline TTS engine families.
enum TtsEngineType {
  kokoro,
  piper,
  mock,
}

/// Represents a downloadable or installed TTS voice model.
class TtsVoiceModel {
  const TtsVoiceModel({
    required this.id,
    required this.name,
    required this.engineType,
    this.locale = 'en-US',
    this.isInstalled = false,
    this.isDefault = false,
    this.sizeBytes = 0,
    this.downloadUrl,
    this.localPath,
    this.description = '',
    this.voiceStyle,
  });

  final String id;
  final String name;
  final TtsEngineType engineType;
  final String locale;
  final bool isInstalled;
  final bool isDefault;
  final int sizeBytes;
  final String? downloadUrl;
  final String? localPath;
  final String description;
  final String? voiceStyle;

  TtsVoiceModel copyWith({
    String? id,
    String? name,
    TtsEngineType? engineType,
    String? locale,
    bool? isInstalled,
    bool? isDefault,
    int? sizeBytes,
    String? downloadUrl,
    String? localPath,
    String? description,
    String? voiceStyle,
  }) {
    return TtsVoiceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      engineType: engineType ?? this.engineType,
      locale: locale ?? this.locale,
      isInstalled: isInstalled ?? this.isInstalled,
      isDefault: isDefault ?? this.isDefault,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      localPath: localPath ?? this.localPath,
      description: description ?? this.description,
      voiceStyle: voiceStyle ?? this.voiceStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TtsVoiceModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'TtsVoiceModel(id: $id, name: $name, engine: $engineType, installed: $isInstalled)';
}

/// Playback states for the TTS engine.
enum TtsPlaybackState {
  stopped,
  playing,
  paused,
  completed,
}

/// Represents a parsed sentence chunk with word offsets.
class SentenceChunk {
  const SentenceChunk({
    required this.index,
    required this.text,
    required this.charStart,
    required this.charEnd,
    required this.words,
  });

  final int index;
  final String text;
  final int charStart;
  final int charEnd;
  final List<String> words;

  @override
  String toString() => 'SentenceChunk(index: $index, text: "$text")';
}

/// State of TTS playback exposed to the UI.
class TtsState {
  const TtsState({
    this.playbackState = TtsPlaybackState.stopped,
    this.currentSentenceIndex = 0,
    this.totalSentences = 0,
    this.currentSentenceText = '',
    this.currentWord = '',
    this.activeWordStart = 0,
    this.activeWordEnd = 0,
    this.speechRate = 1.0,
    this.pitch = 1.0,
    this.activeVoice,
    this.hasInstalledModels = false,
    this.errorMessage,
  });

  final TtsPlaybackState playbackState;
  final int currentSentenceIndex;
  final int totalSentences;
  final String currentSentenceText;
  final String currentWord;
  final int activeWordStart;
  final int activeWordEnd;
  final double speechRate;
  final double pitch;
  final TtsVoiceModel? activeVoice;
  final bool hasInstalledModels;
  final String? errorMessage;

  bool get isPlaying => playbackState == TtsPlaybackState.playing;
  bool get isPaused => playbackState == TtsPlaybackState.paused;
  bool get isStopped => playbackState == TtsPlaybackState.stopped;
  bool get isCompleted => playbackState == TtsPlaybackState.completed;

  TtsState copyWith({
    TtsPlaybackState? playbackState,
    int? currentSentenceIndex,
    int? totalSentences,
    String? currentSentenceText,
    String? currentWord,
    int? activeWordStart,
    int? activeWordEnd,
    double? speechRate,
    double? pitch,
    TtsVoiceModel? activeVoice,
    bool clearActiveVoice = false,
    bool? hasInstalledModels,
    String? errorMessage,
  }) {
    return TtsState(
      playbackState: playbackState ?? this.playbackState,
      currentSentenceIndex: currentSentenceIndex ?? this.currentSentenceIndex,
      totalSentences: totalSentences ?? this.totalSentences,
      currentSentenceText: currentSentenceText ?? this.currentSentenceText,
      currentWord: currentWord ?? this.currentWord,
      activeWordStart: activeWordStart ?? this.activeWordStart,
      activeWordEnd: activeWordEnd ?? this.activeWordEnd,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      activeVoice: clearActiveVoice ? null : (activeVoice ?? this.activeVoice),
      hasInstalledModels: hasInstalledModels ?? this.hasInstalledModels,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// -------------------------------------------------------------
// Message passing: Main UI Thread -> Background Isolate
// -------------------------------------------------------------

sealed class TtsCommand {
  const TtsCommand();
}

class InitIsolateCommand extends TtsCommand {
  const InitIsolateCommand(this.mainSendPort, {this.rootIsolateToken});
  final SendPort mainSendPort;
  final RootIsolateToken? rootIsolateToken;
}

class ConfigureVoiceCommand extends TtsCommand {
  const ConfigureVoiceCommand({
    required this.voice,
    this.rootIsolateToken,
  });
  final TtsVoiceModel? voice;
  final RootIsolateToken? rootIsolateToken;
}

class LoadTextCommand extends TtsCommand {
  const LoadTextCommand(this.text, {this.startSentenceIndex = 0});
  final String text;
  final int startSentenceIndex;
}

class PlayCommand extends TtsCommand {
  const PlayCommand();
}

class PauseCommand extends TtsCommand {
  const PauseCommand();
}

class StopCommand extends TtsCommand {
  const StopCommand();
}

class NextSentenceCommand extends TtsCommand {
  const NextSentenceCommand();
}

class PreviousSentenceCommand extends TtsCommand {
  const PreviousSentenceCommand();
}

class SeekSentenceCommand extends TtsCommand {
  const SeekSentenceCommand(this.sentenceIndex);
  final int sentenceIndex;
}

class SetRateCommand extends TtsCommand {
  const SetRateCommand(this.rate);
  final double rate;
}

class SetPitchCommand extends TtsCommand {
  const SetPitchCommand(this.pitch);
  final double pitch;
}

class UtteranceCompletedCommand extends TtsCommand {
  const UtteranceCompletedCommand();
}

class UtteranceProgressCommand extends TtsCommand {
  const UtteranceProgressCommand({
    required this.word,
    required this.start,
    required this.end,
  });

  final String word;
  final int start;
  final int end;
}

class DisposeCommand extends TtsCommand {
  const DisposeCommand();
}

// -------------------------------------------------------------
// Message passing: Background Isolate -> Main UI Thread
// -------------------------------------------------------------

sealed class TtsEvent {
  const TtsEvent();
}

class IsolateReadyEvent extends TtsEvent {
  const IsolateReadyEvent(this.isolateSendPort);
  final SendPort isolateSendPort;
}

class SpeakChunkEvent extends TtsEvent {
  const SpeakChunkEvent({
    required this.sentenceIndex,
    required this.text,
  });

  final int sentenceIndex;
  final String text;
}

class PauseAudioEvent extends TtsEvent {
  const PauseAudioEvent();
}

class StopAudioEvent extends TtsEvent {
  const StopAudioEvent();
}

class StateUpdatedEvent extends TtsEvent {
  const StateUpdatedEvent(this.state);
  final TtsState state;
}

class WordBoundaryEvent extends TtsEvent {
  const WordBoundaryEvent({
    required this.sentenceIndex,
    required this.word,
    required this.start,
    required this.end,
  });

  final int sentenceIndex;
  final String word;
  final int start;
  final int end;
}

class AudioBufferEvent extends TtsEvent {
  const AudioBufferEvent({
    required this.sentenceIndex,
    required this.samples,
    this.sampleRate = 24000,
  });

  final int sentenceIndex;
  final List<double> samples;
  final int sampleRate;
}

class TtsErrorEvent extends TtsEvent {
  const TtsErrorEvent(this.errorMessage);
  final String errorMessage;
}
