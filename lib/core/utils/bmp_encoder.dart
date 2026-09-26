import 'dart:typed_data';

abstract final class BmpEncoder {
  /// Encodes raw RGBA bytes to an uncompressed 32-bit BMP file with top-down row order.
  static Uint8List encodeRgba(Uint8List rgba, int width, int height) {
    final rowSize = width * 4;
    final pixelArraySize = rowSize * height;
    final fileSize = 54 + pixelArraySize;

    final data = ByteData(fileSize);

    // 14-byte BMP Header
    data.setUint8(0, 0x42); // 'B'
    data.setUint8(1, 0x4D); // 'M'
    data.setUint32(2, fileSize, Endian.little);
    data.setUint32(6, 0, Endian.little); // Reserved
    data.setUint32(10, 54, Endian.little); // Offset to pixel data

    // 40-byte DIB Header (BITMAPINFOHEADER)
    data.setUint32(14, 40, Endian.little); // Header size
    data.setInt32(18, width, Endian.little);
    data.setInt32(22, -height, Endian.little); // Negative height = top-down
    data.setUint16(26, 1, Endian.little); // Color planes
    data.setUint16(28, 32, Endian.little); // Bits per pixel (32-bit BGRA)
    data.setUint32(30, 0, Endian.little); // Compression BI_RGB (uncompressed)
    data.setUint32(34, pixelArraySize, Endian.little);
    data.setInt32(38, 2835, Endian.little); // ~72 DPI horizontal
    data.setInt32(42, 2835, Endian.little); // ~72 DPI vertical
    data.setUint32(46, 0, Endian.little); // Colors in color table
    data.setUint32(50, 0, Endian.little); // Important color count

    final bytes = data.buffer.asUint8List();
    var dest = 54;
    for (var i = 0; i < rgba.length; i += 4) {
      bytes[dest++] = rgba[i + 2]; // B
      bytes[dest++] = rgba[i + 1]; // G
      bytes[dest++] = rgba[i]; // R
      bytes[dest++] = rgba[i + 3]; // A
    }

    return bytes;
  }
}
