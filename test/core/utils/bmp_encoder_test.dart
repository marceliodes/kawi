import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/core/utils/bmp_encoder.dart';

void main() {
  test('BmpEncoder produces valid BMP decoded by dart:ui', () async {
    const width = 16;
    const height = 16;
    final rgba = Uint8List(width * height * 4);
    // Fill with solid red (R=255, G=0, B=0, A=255)
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 255;
      rgba[i + 1] = 0;
      rgba[i + 2] = 0;
      rgba[i + 3] = 255;
    }

    final bmp = BmpEncoder.encodeRgba(rgba, width, height);
    expect(bmp.length, 54 + (width * height * 4));

    final codec = await ui.instantiateImageCodec(bmp);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, width);
    expect(frame.image.height, height);
  });
}
