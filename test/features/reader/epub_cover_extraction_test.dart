import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawi/features/reader/services/epub_parser.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kawi_cover_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String writeEpubZip(String fileName, Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, content) {
      archive.addFile(ArchiveFile(name, content.length, content));
    });
    final zipBytes = ZipEncoder().encode(archive);
    final file = File('${tempDir.path}/$fileName');
    file.writeAsBytesSync(zipBytes);
    return file.path;
  }

  group('EPUB Cover Extraction Tests', () {
    test('Strategy A: Extracts cover via properties="cover-image" (EPUB 3)', () async {
      final mockImageBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

      final path = writeEpubZip('epub3_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'EPUB/package.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cov-img" href="images/front_cover.jpg" media-type="image/jpeg" properties="cover-image"/>
  </manifest>
  <spine>
    <itemref idref="nav"/>
  </spine>
</package>'''),
        'EPUB/images/front_cover.jpg': mockImageBytes,
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNotNull);
      expect(extracted, equals(mockImageBytes));
    });

    test('Strategy B: Extracts cover via <meta name="cover" content="..."> (EPUB 2)', () async {
      final mockImageBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 10, 20, 30, 40]);

      final path = writeEpubZip('epub2_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'content.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <meta name="cover" content="cover-image-id"/>
  </metadata>
  <manifest>
    <item id="cover-image-id" href="assets/cover.png" media-type="image/png"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>'''),
        'assets/cover.png': mockImageBytes,
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNotNull);
      expect(extracted, equals(mockImageBytes));
    });

    test('Strategy C: Extracts cover when manifest id/href contains "cover" and media-type is image', () async {
      final mockImageBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 50, 60, 70, 80]);

      final path = writeEpubZip('manifest_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'OEBPS/content.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <manifest>
    <item id="book-cover-image" href="images/main_cover.webp" media-type="image/webp"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>'''),
        'OEBPS/images/main_cover.webp': mockImageBytes,
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNotNull);
      expect(extracted, equals(mockImageBytes));
    });

    test('Strategy D: Extracts SVG <image xlink:href="..."> with relative path from first spine XHTML', () async {
      final mockImageBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 99, 88, 77, 66]);

      final path = writeEpubZip('svg_spine_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'OEBPS/content.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <manifest>
    <item id="coverpage" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="coverimg" href="Images/Cover.jpg" media-type="image/jpeg"/>
  </manifest>
  <spine>
    <itemref idref="coverpage"/>
  </spine>
</package>'''),
        'OEBPS/Text/cover.xhtml': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:xlink="http://www.w3.org/1999/xlink">
<head><title>Cover</title></head>
<body>
  <div>
    <svg xmlns="http://www.w3.org/2000/svg" height="100%" width="100%" version="1.1" viewBox="0 0 1000 1500">
      <image width="1000" height="1500" xlink:href="../Images/Cover.jpg"/>
    </svg>
  </div>
</body>
</html>'''),
        'OEBPS/Images/Cover.jpg': mockImageBytes,
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNotNull);
      expect(extracted, equals(mockImageBytes));
    });

    test('Strategy D: Extracts <img src="..."> with URL encoded relative path from first spine XHTML', () async {
      final mockImageBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 11, 22, 33, 44]);

      final path = writeEpubZip('img_spine_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'OPS/package.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <manifest>
    <item id="titlepage" href="xhtml/title.xhtml" media-type="application/xhtml+xml"/>
    <item id="myimg" href="images/Special%20Cover.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="titlepage"/>
  </spine>
</package>'''),
        'OPS/xhtml/title.xhtml': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<body>
  <div class="cover">
    <img src="../images/Special%20Cover.png" alt="Book Cover"/>
  </div>
</body>
</html>'''),
        'OPS/images/Special Cover.png': mockImageBytes,
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNotNull);
      expect(extracted, equals(mockImageBytes));
    });

    test('Extracts cover from manifest HTML item with "cover" id when spine is empty or points elsewhere', () async {
      final mockImageBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 100, 101, 102, 103]);

      final path = writeEpubZip('html_manifest_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'content.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <manifest>
    <item id="cover-html" href="cover_page.html" media-type="text/html"/>
    <item id="ch1" href="ch1.html" media-type="text/html"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>'''),
        'ch1.html': utf8.encode('<html><body><p>Chapter 1 without images</p></body></html>'),
        'cover_page.html': utf8.encode('''<html><body><img src="artwork/front.jpg"/></body></html>'''),
        'artwork/front.jpg': mockImageBytes,
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNotNull);
      expect(extracted, equals(mockImageBytes));
    });

    test('Returns null when no cover image exists in archive', () async {
      final path = writeEpubZip('no_cover.epub', {
        'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
        'content.opf': utf8.encode('''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <manifest>
    <item id="ch1" href="ch1.html" media-type="text/html"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>'''),
        'ch1.html': utf8.encode('<html><body><p>Just text</p></body></html>'),
      });

      final extracted = await EpubParser.extractEpubCoverBytes(path);
      expect(extracted, isNull);
    });
  });
}
