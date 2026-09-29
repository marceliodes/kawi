import 'dart:typed_data';

/// Encodes raw PCM audio samples into a standard RIFF/WAVE file format byte array.
///
/// [samples] contains floating point audio samples normalized to the range [-1.0, 1.0].
/// [sampleRate] is the audio sample rate in Hz (e.g. 24000 for Kokoro, 22050 for Piper).
/// [numChannels] is 1 for mono (default), 2 for stereo.
/// Output is a standard 16-bit signed PCM WAV buffer (AudioFormat = 1).
Uint8List encodeWav({
  required List<double> samples,
  required int sampleRate,
  int numChannels = 1,
}) {
  final numSamples = samples.length;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  final subchunk2Size = numSamples * bytesPerSample;
  final chunkSize = 36 + subchunk2Size;
  final byteRate = sampleRate * numChannels * bytesPerSample;
  final blockAlign = numChannels * bytesPerSample;

  final data = ByteData(44 + subchunk2Size);

  // RIFF Chunk Descriptor
  // 'RIFF'
  data.setUint8(0, 0x52);
  data.setUint8(1, 0x49);
  data.setUint8(2, 0x46);
  data.setUint8(3, 0x46);
  data.setUint32(4, chunkSize, Endian.little);
  // 'WAVE'
  data.setUint8(8, 0x57);
  data.setUint8(9, 0x41);
  data.setUint8(10, 0x56);
  data.setUint8(11, 0x45);

  // 'fmt ' Subchunk
  data.setUint8(12, 0x66);
  data.setUint8(13, 0x6D);
  data.setUint8(14, 0x74);
  data.setUint8(15, 0x20);
  data.setUint32(16, 16, Endian.little); // Subchunk1Size for PCM
  data.setUint16(20, 1, Endian.little);  // AudioFormat 1 = PCM
  data.setUint16(22, numChannels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, blockAlign, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);

  // 'data' Subchunk
  data.setUint8(36, 0x64);
  data.setUint8(37, 0x61);
  data.setUint8(38, 0x74);
  data.setUint8(39, 0x61);
  data.setUint32(40, subchunk2Size, Endian.little);

  // Convert float samples [-1.0, 1.0] to 16-bit signed PCM
  var offset = 44;
  for (var i = 0; i < numSamples; i++) {
    final s = samples[i].clamp(-1.0, 1.0);
    final pcm16 = s < 0
        ? (s * 32768.0).round().clamp(-32768, 32767)
        : (s * 32767.0).round().clamp(-32768, 32767);
    data.setInt16(offset, pcm16, Endian.little);
    offset += 2;
  }

  return data.buffer.asUint8List();
}
