export 'reader_navigation_drawer.dart';

import 'package:flutter/material.dart';

import '../providers/document_content_provider.dart';
import 'reader_navigation_drawer.dart';

/// Legacy alias for [ReaderNavigationDrawer], providing backward compatibility.
class TocDrawer extends StatelessWidget {
  const TocDrawer({
    super.key,
    this.documentId = '',
    required this.filePath,
    required this.currentPageIndex,
    required this.onSelectPage,
    this.onSelectAnchor,
    this.isPaginated,
    this.initialTab = NavigationDrawerTab.contents,
    this.autoFocusSearch = false,
  });

  final String documentId;
  final String filePath;
  final int currentPageIndex;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<ReadingAnchor>? onSelectAnchor;
  final bool? isPaginated;
  final NavigationDrawerTab initialTab;
  final bool autoFocusSearch;

  @override
  Widget build(BuildContext context) {
    return ReaderNavigationDrawer(
      documentId: documentId,
      filePath: filePath,
      currentPageIndex: currentPageIndex,
      onSelectPage: onSelectPage,
      onSelectAnchor: onSelectAnchor,
      isPaginated: isPaginated,
      initialTab: initialTab,
      autoFocusSearch: autoFocusSearch,
    );
  }
}
