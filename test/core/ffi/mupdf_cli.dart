import 'dart:io';

import 'package:kawi/features/reader/services/document_extractor.dart';

void main(List<String> args) async {
  final targetPath = args.isNotEmpty ? args.first : 'test_assets/sample.pdf';

  final file = File(targetPath);
  if (!file.existsSync()) {
    stdout.writeln('Error: File not found at $targetPath');
    exit(1);
  }

  stdout.writeln('====================================================');
  stdout.writeln('=== Kawi MuPDF Headless Extraction Test Console ===');
  stdout.writeln('====================================================');
  stdout.writeln('Target Document: ${file.absolute.path}');
  stdout.writeln(
    'File Size: ${(file.lengthSync() / 1024).toStringAsFixed(1)} KB\n',
  );

  // 1. Metadata
  stdout.writeln('--- [1/3] Extracting Metadata & Cover ---');
  final stopwatch = Stopwatch()..start();
  final meta = await DocumentExtractor.extractMetadata(file.absolute.path);
  stopwatch.stop();

  stdout.writeln('Title:       ${meta.title ?? "(none)"}');
  stdout.writeln('Author:      ${meta.author ?? "(none)"}');
  stdout.writeln('Page Count:  ${meta.pageCount}');
  stdout.writeln(
    'Cover:       ${meta.hasCover ? "${meta.coverWidth}x${meta.coverHeight} RGBA (${meta.coverRgba!.lengthInBytes} bytes)" : "Not present"}',
  );
  stdout.writeln('Elapsed:     ${stopwatch.elapsedMilliseconds}ms\n');

  // 2. Table of Contents
  stdout.writeln('--- [2/3] Extracting Table of Contents (Outline) ---');
  stopwatch.reset();
  stopwatch.start();
  final toc = await DocumentExtractor.extractTableOfContents(
    file.absolute.path,
  );
  stopwatch.stop();

  if (toc.isEmpty) {
    stdout.writeln('(No outline entries found)');
  } else {
    void printToc(List<TocEntry> items, int depth) {
      final indent = '  ' * depth;
      for (final item in items) {
        final pageStr = item.pageIndex >= 0 ? ' [page ${item.pageIndex}]' : '';
        stdout.writeln('$indent• ${item.title}$pageStr');
        if (item.children.isNotEmpty) {
          printToc(item.children, depth + 1);
        }
      }
    }

    printToc(toc, 0);
  }
  stdout.writeln('Elapsed:     ${stopwatch.elapsedMilliseconds}ms\n');

  // 3. Page Text and Word Bounding Coordinates
  stdout.writeln('--- [3/3] Extracting Page 0 Text & Word Coordinates ---');
  if (meta.pageCount > 0) {
    stopwatch.reset();
    stopwatch.start();
    final page = await DocumentExtractor.extractPageText(file.absolute.path, 0);
    stopwatch.stop();

    stdout.writeln('Word Count:  ${page.words.length}');
    stdout.writeln('First 5 Extracted Words with Bounding Boxes:');
    for (var i = 0; i < page.words.length && i < 5; i++) {
      final w = page.words[i];
      stdout.writeln(
        '  [${i + 1}] "${w.word}" -> bbox: (${w.x0.toStringAsFixed(1)}, ${w.y0.toStringAsFixed(1)}) to (${w.x1.toStringAsFixed(1)}, ${w.y1.toStringAsFixed(1)})',
      );
    }

    stdout.writeln('\nPlain Text Preview (first 250 characters):');
    final preview = page.plainText.trim().replaceAll('\n', ' ');
    stdout.writeln(
      '  "${preview.length > 250 ? '${preview.substring(0, 250)}...' : preview}"',
    );
    stdout.writeln('Elapsed:     ${stopwatch.elapsedMilliseconds}ms\n');
  }

  stdout.writeln('=== Extraction Completed Successfully ===');
}
