import 'dart:async';
import 'dart:ui';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/logger.dart';
import '../constants/reader_layout_constants.dart';
import '../models/document_models.dart';
import '../providers/document_content_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../services/document_extractor.dart';
import '../widgets/reader_canvas.dart';
import '../widgets/toc_drawer.dart';
import '../widgets/typography_settings_sheet.dart';
import '../widgets/tts_control_bar.dart';
import '../../tts/models/tts_models.dart';
import '../../tts/providers/tts_provider.dart';
import '../../tts/providers/voice_manager_provider.dart';
import '../../tts/screens/voice_manager_screen.dart';
import '../../tts/services/tts_text_normalizer.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.document});

  final DocumentEntry document;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ReaderCanvasState> _canvasKey =
      GlobalKey<ReaderCanvasState>();
  late final ScrollController _scrollController;
  late final PageController _pageController;
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _itemPositionsListener;

  bool _isChromeVisible = true;
  bool _isTtsBarVisible = false;
  Timer? _autoHideTimer;
  Timer? _progressSaveDebounce;

  int _currentPageIndex = 0;
  int _currentChapterIndex = 0;

  int _currentPageIndexInChapter = 0;
  List<PageChunk> _currentChapterPages = const [];
  double _currentScrollOffset = 0.0;
  String? _currentChapterTitle;
  bool _isRestoring = false;
  bool _isUserDesyncedFromTts = false;
  int? _speakingChapterIndex;
  int? _speakingPageIndexInChapter;

  double? _currentColumnWidth;
  double? _currentColumnHeight;

  bool get _isEpub => widget.document.isEpub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _pageController = PageController();
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();

    _loadInitialProgress();
  }

  Future<void> _loadInitialProgress() async {
    try {
      final db = ref.read(databaseProvider);

      // Update lastReadAt for the document
      await db.insertOrUpdateDocument(
        widget.document
            .toCompanion(true)
            .copyWith(lastReadAt: Value(DateTime.now())),
      );

      // Retrieve saved progress
      final progress = await db.getProgressForDocument(widget.document.id);
      if (progress != null && mounted) {
        _isRestoring = true;
        setState(() {
          _currentPageIndex = progress.lastReadPageIndex.clamp(
            0,
            widget.document.pageCount > 0 ? widget.document.pageCount - 1 : 0,
          );
          _currentChapterIndex = _currentPageIndex;
          _currentPageIndexInChapter = progress.lastReadSentenceIndex;
          _currentScrollOffset = progress.lastReadScrollOffset;
          _currentChapterTitle = progress.currentChapter;
        });

        _resolveChapterTitle(_currentChapterIndex);

        // Restore scroll or page position after layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final settings = ref.read(readerSettingsProvider);
          if (_isEpub) {
            _canvasKey.currentState?.jumpToPageInChapter(_currentPageIndexInChapter);
          } else if (_pageController.hasClients &&
              _pageController.positions.length == 1 &&
              _currentPageIndexInChapter > 0) {
            _pageController.jumpToPage(_currentPageIndexInChapter);
          }
          if (!settings.isPaginated) {
            _canvasKey.currentState?.scrollToPage(_currentPageIndex);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _isRestoring = false;
          });
        });
      } else if (mounted) {
        _resolveChapterTitle(0);
      }
    } catch (_) {
      // Ignored: fallback to initial page
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _flushSaveProgress();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSaveProgress();
    _autoHideTimer?.cancel();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() {
      _isChromeVisible = !_isChromeVisible;
    });
  }

  void _showChrome() {
    if (!_isChromeVisible) {
      setState(() => _isChromeVisible = true);
    }
  }

  void _onPageOrScrollChanged(int pageIndex, double offset) {
    if (_isRestoring) return;

    final pageChanged = _currentPageIndex != pageIndex || _currentChapterIndex != pageIndex;
    final offsetChanged = (_currentScrollOffset - offset).abs() > 0.05;

    if (pageChanged) {
      setState(() {
        _currentPageIndex = pageIndex;
        _currentChapterIndex = pageIndex;
        _currentPageIndexInChapter = 0;
        _currentScrollOffset = offset;
      });

      _resolveChapterTitle(pageIndex);
      _debounceSaveProgress(pageIndex, offset);
    } else if (offsetChanged) {
      _currentScrollOffset = offset;
      _debounceSaveProgress(pageIndex, offset);
    }
  }

  void _onEpubPageChanged(int chapterIndex, int pageIndexInChapter) {
    if (_isRestoring) return;
    final chapterChanged = _currentChapterIndex != chapterIndex;
    setState(() {
      _currentPageIndex = chapterIndex;
      _currentChapterIndex = chapterIndex;
      if (pageIndexInChapter >= 0) {
        _currentPageIndexInChapter = pageIndexInChapter;
      }
    });
    if (chapterChanged || _currentChapterTitle == null) {
      _resolveChapterTitle(chapterIndex);
    }
    _debounceSaveProgress(chapterIndex, 0.0, pageIndexInChapter: pageIndexInChapter);
  }

  void _navigateToNextChapter() {
    final totalChapters =
        widget.document.pageCount > 0 ? widget.document.pageCount : 1;
    if (_currentChapterIndex < totalChapters - 1) {
      final targetChapter = _currentChapterIndex + 1;
      final settings = ref.read(readerSettingsProvider);
      if (widget.document.isEpub && settings.isPaginated) {
        setState(() {
          _currentChapterIndex = targetChapter;
          _currentPageIndex = targetChapter;
          _currentPageIndexInChapter = 0;
          _currentScrollOffset = 0.0;
        });
        _resolveChapterTitle(targetChapter);
        _debounceSaveProgress(targetChapter, 0.0, pageIndexInChapter: 0);
      } else {
        _navigateToPage(targetChapter);
      }
    }
  }

  void _navigateToPreviousChapter() {
    if (_currentChapterIndex <= 0) return;

    final targetChapter = _currentChapterIndex - 1;
    final settings = ref.read(readerSettingsProvider);

    if (widget.document.isEpub && settings.isPaginated) {
      setState(() {
        _currentChapterIndex = targetChapter;
        _currentPageIndex = targetChapter;
        _currentPageIndexInChapter = -1; // Sentinel: resolve to pages.length - 1 once paginated
        _currentScrollOffset = 0.0;
      });

      _resolveChapterTitle(targetChapter);
      _debounceSaveProgress(targetChapter, 0.0, pageIndexInChapter: -1);
    } else {
      _navigateToPage(targetChapter);
    }
  }

  Future<void> _resolveChapterTitle(int chapterIndex) async {
    try {
      final title = await ref.read(
        documentChapterTitleProvider((
          filePath: widget.document.filePath,
          chapterIndex: chapterIndex,
        )).future,
      );
      if (mounted) {
        final resolved = (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : (widget.document.isEpub
                ? 'Chapter ${chapterIndex + 1}'
                : 'Page ${chapterIndex + 1}');
        if (_currentChapterTitle != resolved) {
          setState(() => _currentChapterTitle = resolved);
        }
      }
    } catch (_) {}
  }

  Future<void> _flushSaveProgress({
    int? pageIndex,
    double? offset,
    int? pageIndexInChapter,
  }) async {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = null;
    try {
      final db = ref.read(databaseProvider);
      final resolvedPageIndex = pageIndex ?? _currentPageIndex;
      final resolvedSentenceIndex =
          pageIndexInChapter ?? _currentPageIndexInChapter;
      final resolvedOffset = offset ?? _currentScrollOffset;

      await db.updateProgress(
        ReadingProgressesCompanion.insert(
          documentId: widget.document.id,
          lastReadPageIndex: Value(resolvedPageIndex),
          lastReadSentenceIndex: Value(resolvedSentenceIndex),
          lastReadScrollOffset: Value(resolvedOffset),
          currentChapter: Value(_currentChapterTitle),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e, st) {
      AppLogger.w('Failed to flush reading progress: $e', e, st);
    }
  }

  void _debounceSaveProgress(int pageIndex, double offset, {int? pageIndexInChapter}) {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      _flushSaveProgress(
        pageIndex: pageIndex,
        offset: offset,
        pageIndexInChapter: pageIndexInChapter,
      );
    });
  }

  void _navigateToPage(int pageIndex) {
    if (pageIndex < 0) return;
    final total = widget.document.pageCount > 0 ? widget.document.pageCount : 1;
    final clampedPage = pageIndex.clamp(0, total - 1);
    final isEpub = widget.document.isEpub;

    setState(() {
      _currentPageIndex = clampedPage;
      _currentChapterIndex = clampedPage;
      _currentPageIndexInChapter = 0;
      _currentScrollOffset = 0.0;
    });

    final settings = ref.read(readerSettingsProvider);
    if (settings.isPaginated) {
      if (isEpub) {
        _canvasKey.currentState?.jumpToPageInChapter(0);
      } else if (_pageController.hasClients && _pageController.positions.length == 1) {
        _pageController.jumpToPage(clampedPage);
      }
    } else {
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: clampedPage);
      } else {
        _canvasKey.currentState?.scrollToPage(clampedPage);
      }
    }

    if (isEpub) {
      ref.read(activeReadingAnchorProvider.notifier).updateAnchor(
            chapterIndex: clampedPage,
            paragraphIndex: 0,
            charOffset: 0,
          );
    }

    _resolveChapterTitle(clampedPage);
    _debounceSaveProgress(clampedPage, _currentScrollOffset, pageIndexInChapter: 0);
  }

  void _openTypographySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const TypographySettingsSheet(),
    );
  }

  Future<void> _startTts({String? fromSentence}) async {
    if (fromSentence == null) {
      final visibleSnippet =
          _canvasKey.currentState?.getFirstVisibleTextSnippet();
      if (visibleSnippet != null && visibleSnippet.trim().isNotEmpty) {
        fromSentence = visibleSnippet.trim();
        AppLogger.d('>>> [TTS UI] _startTts resolved visible snippet: "$fromSentence" <<<');
      }
    }

    AppLogger.d('>>> [TTS UI] _startTts called (fromSentence: ${fromSentence != null}) <<<');
    setState(() {
      _isUserDesyncedFromTts = false;
    });
    try {
      if (widget.document.isEpub) {
        final settings = ref.read(readerSettingsProvider);
        String textToRead = '';

        if (settings.isPaginated) {
          List<PageChunk> pages = _currentChapterPages;
          if (pages.isEmpty) {
            final width = _currentColumnWidth ??
                (MediaQuery.sizeOf(context).width - (settings.horizontalPadding * 2))
                    .clamp(100.0, settings.contentMaxWidth);
            final height = _currentColumnHeight ??
                (MediaQuery.sizeOf(context).height - (Spacing.xl * 2 + 80.0) - 32.0)
                    .clamp(100.0, MediaQuery.sizeOf(context).height);
            final theme = ReaderTheme.of(context);
            final paginationParams = PaginationParams(
              filePath: widget.document.filePath,
              chapterIndex: _currentPageIndex,
              maxWidth: width,
              maxHeight: height,
              textStyle: TextStyle(
                fontFamily: settings.fontFamily,
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                color: theme.textPrimary,
              ),
              paragraphSpacing: 16.0,
            );
            try {
              pages = await ref.read(chapterPagesProvider(paginationParams).future);
              _currentChapterPages = pages;
            } catch (_) {}
          }

          var chunkIdx = 0;
          final canvas = _canvasKey.currentState;
          if (_isEpub) {
            final safePage = canvas?.safeGetEpubPage();
            if (safePage != null) {
              chunkIdx = safePage.round();
            } else {
              chunkIdx = _currentPageIndexInChapter;
            }
          } else {
            final safePage = canvas?.safeGetPage();
            if (safePage != null) {
              chunkIdx = safePage.round();
            } else {
              chunkIdx = _currentPageIndexInChapter;
            }
          }
          chunkIdx = chunkIdx.clamp(0, pages.isNotEmpty ? pages.length - 1 : 0);

          if (fromSentence != null && fromSentence.trim().isNotEmpty && pages.isNotEmpty) {
            final lowerFrom = fromSentence.toLowerCase().trim();
            for (var p = 0; p < pages.length; p++) {
              if (pages[p].plainText.toLowerCase().contains(lowerFrom)) {
                chunkIdx = p;
                break;
              }
            }
          }

          // If the current page is an image or has no text, advance to the first subsequent page with text
          while (chunkIdx < pages.length &&
              pages[chunkIdx].plainText.trim().isEmpty) {
            chunkIdx++;
          }
          if (chunkIdx >= pages.length) {
            // No text in remainder of chapter
            return;
          }
          if (chunkIdx != _currentPageIndexInChapter) {
            if (_isEpub) {
              _canvasKey.currentState?.animateToPageInChapter(chunkIdx);
            } else if (_pageController.hasClients &&
                _pageController.positions.length == 1) {
              final curP = _canvasKey.currentState?.safeGetPage();
              if (curP?.round() != chunkIdx) {
                _pageController.animateToPage(
                  chunkIdx,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              }
            }
            setState(() {
              _currentPageIndexInChapter = chunkIdx;
            });
          }

          final buffer = StringBuffer();
          for (var i = chunkIdx; i < pages.length; i++) {
            final t = pages[i].plainText.trim();
            if (t.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.write('\n\n');
              buffer.write(t);
            }
          }
          textToRead = buffer.toString();
        } else {
          // Continuous mode or fallback: extract from semantic AST nodes
          final chapterNodes = await ref.read(
            documentChapterNodesProvider((
              filePath: widget.document.filePath,
              chapterIndex: _currentPageIndex,
            )).future,
          );

          final texts = <String>[];
          for (final node in chapterNodes) {
            if (node is ParagraphNode) {
              final t = node.plainText.trim();
              if (t.isNotEmpty) texts.add(t);
            } else if (node is HeadingNode) {
              final t = node.plainText.trim();
              if (t.isNotEmpty) texts.add(t);
            }
          }
          textToRead = texts.join('\n\n');
        }

        if (fromSentence != null && fromSentence.trim().isNotEmpty) {
          final needle = fromSentence.replaceAll(RegExp(r'\s+'), ' ').trim();
          final words = needle
              .replaceAll(RegExp(r'[“”"’‘\.,;:!?\(\)\[\]]'), ' ')
              .split(RegExp(r'\s+'))
              .where((w) => w.length > 1)
              .toList();

          int matchStart = -1;

          // 1. Direct contains check
          final directIdx = textToRead.indexOf(needle);
          if (directIdx != -1) {
            matchStart = directIdx;
          } else {
            // 2. Normalized word sequence match (first 3-6 significant words)
            final searchWords = words.length >= 3 ? words.take(5).toList() : words;
            if (searchWords.isNotEmpty) {
              final pattern = RegExp(
                searchWords.map(RegExp.escape).join(r'[\s\S]{1,15}?'),
                caseSensitive: false,
              );
              final match = pattern.firstMatch(textToRead);
              if (match != null) {
                var sStart = match.start;
                while (sStart > 0 &&
                    textToRead[sStart - 1] != '\n' &&
                    textToRead[sStart - 1] != '.' &&
                    textToRead[sStart - 1] != '!' &&
                    textToRead[sStart - 1] != '?') {
                  sStart--;
                }
                while (sStart < match.start &&
                    (textToRead[sStart].trim().isEmpty ||
                        textToRead[sStart] == '.' ||
                        textToRead[sStart] == '"' ||
                        textToRead[sStart] == '”' ||
                        textToRead[sStart] == '’' ||
                        textToRead[sStart] == "'")) {
                  sStart++;
                }
                matchStart = sStart;
              }
            }
          }

          if (matchStart != -1 && matchStart < textToRead.length) {
            textToRead = textToRead.substring(matchStart).trim();
            AppLogger.d(
                '>>> [TTS UI] _startTts sliced textToRead to ${textToRead.length} chars (starts with: "${textToRead.substring(0, textToRead.length.clamp(0, 50))}") <<<');
          }
        } else if (!settings.isPaginated) {
          // If starting without a selected sentence in continuous mode, start from the active reading anchor if on this chapter
          final anchor = ref.read(activeReadingAnchorProvider);
          if (anchor != null &&
              anchor.chapterIndex == _currentPageIndex &&
              (anchor.paragraphIndex > 0 || anchor.charOffset > 0)) {
            final chapterNodes = await ref.read(
              documentChapterNodesProvider((
                filePath: widget.document.filePath,
                chapterIndex: _currentPageIndex,
              )).future,
            );
            var charCount = 0;
            var startIndex = 0;
            for (var i = 0; i < chapterNodes.length; i++) {
              final node = chapterNodes[i];
              final nodeText = (node is ParagraphNode)
                  ? node.plainText.trim()
                  : (node is HeadingNode)
                      ? node.plainText.trim()
                      : '';
              if (nodeText.isEmpty) continue;

              if (i == anchor.paragraphIndex) {
                startIndex =
                    charCount + anchor.charOffset.clamp(0, nodeText.length);
                break;
              }
              charCount += nodeText.length + 2; // +2 for '\n\n'
            }
            if (startIndex > 0 && startIndex < textToRead.length) {
              textToRead = textToRead.substring(startIndex).trim();
            }
          }
        }

        textToRead = textToRead.trim();
        if (textToRead.isEmpty || !TtsTextNormalizer.hasAlphanumeric(textToRead)) return;

        final ttsNotifier = ref.read(ttsStateProvider.notifier);
        setState(() {
          _isTtsBarVisible = true;
        });

        AppLogger.d('>>> [TTS UI] calling ttsNotifier.speak() with ${textToRead.length} chars (EPUB chapter $_currentPageIndex) <<<');
        ttsNotifier.speak(textToRead);
        return;
      }

      final totalPageCount =
          widget.document.pageCount > 0 ? widget.document.pageCount : 1;

      // 1. Determine chapter page range [chapterStartPage, chapterEndPage) from TOC
      int chapterStartPage = _currentPageIndex;
      int chapterEndPage = _currentPageIndex + 1;

      try {
        final tocAsync = ref.read(documentTocProvider(widget.document.filePath));
        final entries = tocAsync.asData?.value;
        if (entries != null && entries.isNotEmpty) {
          final flatList = <TocEntry>[];
          void flatten(List<TocEntry> list) {
            for (final item in list) {
              flatList.add(item);
              if (item.children.isNotEmpty) flatten(item.children);
            }
          }
          flatten(entries);
          flatList.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

          TocEntry? currentChapter;
          int? nextChapterStart;
          for (var i = 0; i < flatList.length; i++) {
            if (flatList[i].pageIndex <= _currentPageIndex) {
              currentChapter = flatList[i];
              for (var j = i + 1; j < flatList.length; j++) {
                if (flatList[j].pageIndex > currentChapter.pageIndex) {
                  nextChapterStart = flatList[j].pageIndex;
                  break;
                }
              }
            }
          }

          if (currentChapter != null) {
            chapterStartPage = currentChapter.pageIndex;
            if (nextChapterStart != null && nextChapterStart > chapterStartPage) {
              chapterEndPage = nextChapterStart;
            } else {
              chapterEndPage = totalPageCount;
            }
          }
        }
      } catch (_) {}

      // 2. Also take into account visible items if continuous scroll is active
      final settings = ref.read(readerSettingsProvider);
      var effectiveEndPage = chapterEndPage;
      if (!settings.isPaginated &&
          _itemPositionsListener.itemPositions.value.isNotEmpty) {
        for (final pos in _itemPositionsListener.itemPositions.value) {
          if (pos.itemTrailingEdge > 0.0 && pos.itemLeadingEdge < 1.0) {
            if (pos.index + 1 > effectiveEndPage) {
              effectiveEndPage = pos.index + 1;
            }
          }
        }
      }

      // 3. Collect page text blocks across the full chapter / visible range
      final pageTexts = <String>[];
      final startIdx = _currentPageIndex;
      final targetEnd = effectiveEndPage > startIdx ? effectiveEndPage : (startIdx + 1);

      for (var idx = startIdx; idx < targetEnd && idx < totalPageCount; idx++) {
        final pageContent = await ref.read(
          documentPageContentProvider((
            filePath: widget.document.filePath,
            pageIndex: idx,
          )).future,
        );
        var raw = pageContent.plainText.trim();
        if (raw.isNotEmpty) {
          raw = TtsTextNormalizer.flattenSoftLineBreaks(raw);
          if (raw.isNotEmpty) {
            pageTexts.add(raw);
          }
        }
      }

      // If the collected text is short (e.g. only a heading < 1500 chars) and more pages exist in the chapter/document,
      // continue collecting subsequent pages so the complete chapter text is passed.
      var nextIdx = targetEnd;
      while (nextIdx < totalPageCount) {
        var currentCombined = pageTexts.join('\n\n');
        currentCombined = TtsTextNormalizer.filterPlaceholdersAndTags(currentCombined);
        if (currentCombined.trim().length >= 1500) break;

        final nextContent = await ref.read(
          documentPageContentProvider((
            filePath: widget.document.filePath,
            pageIndex: nextIdx,
          )).future,
        );
        var raw = nextContent.plainText.trim();
        if (raw.isNotEmpty) {
          raw = TtsTextNormalizer.flattenSoftLineBreaks(raw);
          if (raw.isNotEmpty) {
            pageTexts.add(raw);
          }
        }
        nextIdx++;
      }

      var textToRead = pageTexts.join('\n\n');

      // 4. Filter out [image] placeholders and non-text tokens
      textToRead = TtsTextNormalizer.filterPlaceholdersAndTags(textToRead);

      // Normalize line breaks into paragraph structure
      textToRead = TtsTextNormalizer.flattenSoftLineBreaks(textToRead);

      if (fromSentence != null && fromSentence.trim().isNotEmpty) {
        final needle = fromSentence.replaceAll(RegExp(r'\s+'), ' ').trim();
        final words = needle.split(' ').where((w) => w.isNotEmpty).toList();
        if (words.isNotEmpty) {
          final needlePattern = RegExp(
            words.map(RegExp.escape).join(r'\s+'),
            caseSensitive: false,
          );
          final match = needlePattern.firstMatch(textToRead);
          if (match != null) {
            textToRead = textToRead.substring(match.start);
          } else {
            // If needle was not found in visible text, search subsequent pages
            for (var i = nextIdx; i < totalPageCount; i++) {
              final content = await ref.read(
                documentPageContentProvider((
                  filePath: widget.document.filePath,
                  pageIndex: i,
                )).future,
              );
              var pText = content.plainText;
              pText = TtsTextNormalizer.filterPlaceholdersAndTags(pText);
              pText = TtsTextNormalizer.flattenSoftLineBreaks(pText);
              final pMatch = needlePattern.firstMatch(pText);
              if (pMatch != null) {
                textToRead = pText.substring(pMatch.start);
                break;
              }
            }
          }
        }
      }

      // Final cleanup of residual orphan brackets and whitespace check
      textToRead = textToRead.replaceAll(RegExp(r'\[image[^\]]*\]', caseSensitive: false), '');
      textToRead = textToRead.replaceAll(RegExp(r'<[^>]*>'), '');
      textToRead = textToRead.replaceAll(RegExp(r'\[\s*\]'), '');
      textToRead = textToRead.trim();

      if (textToRead.isEmpty || !TtsTextNormalizer.hasAlphanumeric(textToRead)) return;

      final ttsNotifier = ref.read(ttsStateProvider.notifier);
      setState(() {
        _isTtsBarVisible = true;
      });

      AppLogger.d('>>> [TTS UI] calling ttsNotifier.speak() with ${textToRead.length} chars <<<');
      ttsNotifier.speak(textToRead);
    } catch (e, st) {
      AppLogger.e('Error starting TTS: $e', e, st);
    }
  }

  void _toggleTts() {
    AppLogger.d('>>> [TTS UI] _toggleTts called <<<');
    final hasInstalledModels = ref.read(hasInstalledTtsModelsProvider);
    if (!hasInstalledModels) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No TTS engine downloaded.'),
          duration: Duration(seconds: 2),
        ),
      );
      VoiceManagerScreen.show(context);
      return;
    }

    final ttsState = ref.read(ttsStateProvider);
    if (ttsState.isPlaying) {
      ref.read(ttsStateProvider.notifier).pause();
    } else if (ttsState.isPaused) {
      ref.read(ttsStateProvider.notifier).play();
      setState(() => _isTtsBarVisible = true);
    } else {
      if (_isTtsBarVisible) {
        setState(() => _isTtsBarVisible = false);
      } else {
        _startTts();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final settings = ref.watch(readerSettingsProvider);
    final isTtsPlaying = ref.watch(ttsProvider.select((s) => s.isPlaying));
    final isEpub = widget.document.isEpub;

    // Auto-advance to next chapter when TTS completes the current chapter
    ref.listen<TtsState>(ttsStateProvider, (previous, next) {
      if (previous?.playbackState != TtsPlaybackState.completed &&
          next.playbackState == TtsPlaybackState.completed) {
        if (_isTtsBarVisible) {
          final totalChapters =
              widget.document.pageCount > 0 ? widget.document.pageCount : 1;
          if (_currentChapterIndex < totalChapters - 1) {
            _navigateToNextChapter();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _startTts();
              }
            });
          }
        }
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.bgCanvas,
      drawer: TocDrawer(
        filePath: widget.document.filePath,
        currentPageIndex: _currentChapterIndex,
        isPaginated: settings.isPaginated,
        onSelectPage: (pageIndex) {
          Navigator.of(context).pop();
          setState(() {
            _currentPageIndexInChapter = 0;
          });
          _navigateToPage(pageIndex);
        },
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columnWidth = EpubPaginationMetrics.computeColumnWidth(
            viewportWidth: constraints.maxWidth,
            horizontalPadding: settings.horizontalPadding,
            maxContentWidth: settings.contentMaxWidth,
          );
          final columnHeight = EpubPaginationMetrics.computeColumnHeight(
            constraints.maxHeight,
          );
          _currentColumnWidth = columnWidth;
          _currentColumnHeight = columnHeight;

          List<PageChunk>? epubChunks;
          List<DocumentNode>? epubNodes;

          if (isEpub) {
            if (settings.isPaginated) {
              final paginationParams = PaginationParams(
                filePath: widget.document.filePath,
                chapterIndex: _currentChapterIndex,
                maxWidth: columnWidth,
                maxHeight: columnHeight,
                textStyle: TextStyle(
                  fontFamily: settings.fontFamily,
                  fontSize: settings.fontSize,
                  height: settings.lineHeight,
                  color: theme.textPrimary,
                ),
                paragraphSpacing: EpubPaginationMetrics.paragraphSpacing,
              );
              final pagesAsync =
                  ref.watch(chapterPagesProvider(paginationParams));
              epubChunks = pagesAsync.asData?.value;
              if (epubChunks != null && epubChunks.isNotEmpty) {
                _currentChapterPages = epubChunks;
              }
            } else {
              final nodesAsync = ref.watch(
                documentChapterNodesProvider((
                  filePath: widget.document.filePath,
                  chapterIndex: _currentChapterIndex,
                )),
              );
              epubNodes = nodesAsync.asData?.value;
            }
          }

          return Stack(
            children: [
              // Top edge hover detector to reveal chrome
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 32,
                child: MouseRegion(
                  onHover: (_) => _showChrome(),
                  child: const SizedBox.expand(),
                ),
              ),

              // Main Reading Canvas
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey(
                    '${widget.document.id}_${isEpub ? (settings.isPaginated ? "paginated" : "continuous") : "pdf"}',
                  ),
                  child: ReaderCanvas(
                      key: _canvasKey,
                      filePath: widget.document.filePath,
                      pageCount: widget.document.pageCount,
                      settings: settings,
                      initialPageIndex: _currentChapterIndex,
                      initialChapterIndex: _currentChapterIndex,
                      initialScrollOffset: _currentScrollOffset,
                      scrollController: _scrollController,
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      pageController: _pageController,
                      onPageChanged: _onPageOrScrollChanged,
                      onToggleChrome: _toggleChrome,
                      onPlayFromHere: (sentence) {
                        _startTts(fromSentence: sentence);
                      },
                      epubChunks: epubChunks,
                      epubNodes: settings.isPaginated ? null : epubNodes,
                      isEpub: isEpub,
                      chapterIndex: _currentChapterIndex,
                      pageIndexInChapter: _currentPageIndexInChapter,
                      onNextChapter: _navigateToNextChapter,
                      onPreviousChapter: _navigateToPreviousChapter,
                      onEpubPageChanged: _onEpubPageChanged,
                      onChapterChanged: (newChapterIndex) {
                        if (_currentChapterIndex != newChapterIndex) {
                          setState(() {
                            _currentChapterIndex = newChapterIndex;
                            _currentPageIndex = newChapterIndex;
                            _currentPageIndexInChapter = 0;
                          });
                          _resolveChapterTitle(newChapterIndex);
                          _debounceSaveProgress(newChapterIndex, 0.0);
                        }
                      },
                      isUserDesyncedFromTts: _isUserDesyncedFromTts,
                      onUserNavigated: () {
                        if (!_isUserDesyncedFromTts) {
                          setState(() {
                            _isUserDesyncedFromTts = true;
                          });
                        }
                      },
                      onSpeakingPageDiscovered: (ch, page) {
                        _speakingChapterIndex = ch;
                        _speakingPageIndexInChapter = page;
                      },
                    ),
                  ),
                ),

              // Auto-hiding Top Navigation Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  offset: _isChromeVisible ? Offset.zero : const Offset(0, -1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isChromeVisible ? 1.0 : 0.0,
                    child: _buildTopAppBar(theme, isTtsPlaying),
                  ),
                ),
              ),

              // Jump to speaking sentence chip
              if (_isUserDesyncedFromTts && isTtsPlaying)
                Positioned(
                  bottom: Spacing.xl + MediaQuery.paddingOf(context).bottom + 76,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ActionChip(
                      avatar: PhosphorIcon(
                        PhosphorIconsLight.arrowBendUpLeft,
                        size: 16,
                        color: theme.accent,
                      ),
                      label: const Text('Jump to speaking sentence'),
                      onPressed: () {
                        setState(() {
                          _isUserDesyncedFromTts = false;
                        });
                        if (_speakingChapterIndex != null &&
                            _speakingChapterIndex != _currentChapterIndex) {
                          setState(() {
                            _currentChapterIndex = _speakingChapterIndex!;
                            _currentPageIndex = _speakingChapterIndex!;
                            _currentPageIndexInChapter =
                                _speakingPageIndexInChapter ?? 0;
                          });
                          _resolveChapterTitle(_currentChapterIndex);
                          _debounceSaveProgress(_currentChapterIndex, 0.0);
                        } else if (_speakingPageIndexInChapter != null &&
                            _speakingPageIndexInChapter !=
                                _currentPageIndexInChapter) {
                          setState(() {
                            _currentPageIndexInChapter =
                                _speakingPageIndexInChapter!;
                          });
                          if (_isEpub) {
                            _canvasKey.currentState?.animateToPageInChapter(
                              _speakingPageIndexInChapter!,
                            );
                          } else if (_pageController.hasClients &&
                              _pageController.positions.length == 1) {
                            _pageController.animateToPage(
                              _speakingPageIndexInChapter!,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),

              // Floating Media Control Bar for TTS
              if (_isTtsBarVisible || isTtsPlaying)
                Positioned(
                  bottom:
                      Spacing.xl + MediaQuery.paddingOf(context).bottom + 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: TtsControlBar(
                      onPlay: _startTts,
                      onClose: () {
                        setState(() => _isTtsBarVisible = false);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopAppBar(ReaderThemeData theme, bool isTtsPlaying) {
    final hasInstalledModels = ref.watch(hasInstalledTtsModelsProvider);

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + Spacing.xs,
        bottom: Spacing.xs,
        left: Spacing.md,
        right: Spacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.bgCard.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: theme.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back to Library Button
          IconButton(
            tooltip: 'Back to Library',
            icon: PhosphorIcon(
              PhosphorIconsLight.arrowLeft,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),

          // Table of Contents Toggle
          IconButton(
            tooltip: 'Table of Contents',
            icon: PhosphorIcon(
              PhosphorIconsLight.listBullets,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),

          const SizedBox(width: Spacing.xs),

          // Document Title and Active Chapter
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.document.title,
                  style: AppTypography.headline.copyWith(
                    color: theme.textPrimary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                Text(
                  (_currentChapterTitle != null &&
                          _currentChapterTitle!.isNotEmpty)
                      ? _currentChapterTitle!
                      : (widget.document.isEpub
                          ? 'Chapter ${_currentChapterIndex + 1}'
                          : 'Page ${_currentPageIndex + 1}'),
                  style: AppTypography.micro.copyWith(
                    color: theme.textMuted,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(width: Spacing.xs),

          // Read Aloud (TTS) Toggle
          IconButton(
            tooltip: hasInstalledModels
                ? 'Read Aloud (TTS)'
                : 'No TTS engine downloaded.',
            icon: PhosphorIcon(
              _isTtsBarVisible || isTtsPlaying
                  ? PhosphorIconsFill.speakerHigh
                  : PhosphorIconsLight.speakerHigh,
              size: 20,
              color: !hasInstalledModels
                  ? theme.textMuted.withValues(alpha: 0.35)
                  : (_isTtsBarVisible || isTtsPlaying
                      ? theme.accent
                      : theme.textPrimary),
            ),
            onPressed: _toggleTts,
          ),

          // Voice Manager / TTS Voices Settings
          IconButton(
            tooltip: 'Voice Settings',
            icon: PhosphorIcon(
              PhosphorIconsLight.waveform,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: () => VoiceManagerScreen.show(context),
          ),

          // Typography & Appearance Settings Toggle
          IconButton(
            tooltip: 'Appearance & Typography',
            icon: PhosphorIcon(
              PhosphorIconsLight.textAa,
              size: 20,
              color: theme.textPrimary,
            ),
            onPressed: _openTypographySheet,
          ),
        ],
      ),
    );
  }
}

/// Alias for [ReaderScreen] to support both naming conventions.
typedef DocumentViewerScreen = ReaderScreen;
