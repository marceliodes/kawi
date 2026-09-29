import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/utils/wav_encoder.dart';

void main() {
  group('WavEncoder Tests', () {
    test('encodes empty samples list to valid 44-byte WAV header', () {
      final wav = encodeWav(samples: const [], sampleRate: 24000);
      expect(wav.length, equals(44));

      // RIFF header
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));
      expect(String.fromCharCodes(wav.sublist(36, 40)), equals('data'));

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint16(20, Endian.little), equals(1)); // AudioFormat = PCM
      expect(byteData.getUint16(22, Endian.little), equals(1)); // Mono
      expect(byteData.getUint32(24, Endian.little), equals(24000)); // Sample rate
      expect(byteData.getUint16(34, Endian.little), equals(16)); // Bits per sample
      expect(byteData.getUint32(40, Endian.little), equals(0)); // Subchunk2Size (data size)
    });

    test('encodes normalized float samples to 16-bit PCM correctly', () {
      // 0.0 -> 0
      // 1.0 -> 32767
      // -1.0 -> -32768
      final samples = [0.0, 1.0, -1.0, 0.5, -0.5];
      final wav = encodeWav(samples: samples, sampleRate: 22050);

      expect(wav.length, equals(44 + samples.length * 2));

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getUint32(24, Endian.little), equals(22050));
      expect(byteData.getUint32(40, Endian.little), equals(10));

      expect(byteData.getInt16(44, Endian.little), equals(0));
      expect(byteData.getInt16(46, Endian.little), equals(32767));
      expect(byteData.getInt16(48, Endian.little), equals(-32768));
      expect(byteData.getInt16(50, Endian.little), inInclusiveRange(16380, 16385));
      expect(byteData.getInt16(52, Endian.little), inInclusiveRange(-16385, -16380));
    });

    test('clamps out-of-range float values safely', () {
      final samples = [2.5, -3.0];
      final wav = encodeWav(samples: samples, sampleRate: 24000);

      final byteData = ByteData.sublistView(wav);
      expect(byteData.getInt16(44, Endian.little), equals(32767));
      expect(byteData.getInt16(46, Endian.little), equals(-32768));
    });
  });
}
