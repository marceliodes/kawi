import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../providers/library_provider.dart';
import '../widgets/add_from_library_dialog.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final filter = ref.watch(libraryFilterProvider);
    final documentsAsync = ref.watch(documentsStreamProvider);

    return documentsAsync.when(
      data: (documents) {
        if (documents.isEmpty) {
          return _buildEmptyState(context, ref, theme, filter);
        }
        return _buildDocumentGrid(context, ref, theme, filter, documents);
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: theme.accent)),
      error: (error, _) => Center(
        child: Text(
          'Error loading documents: $error',
          style: AppTypography.body.copyWith(color: theme.textMuted),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    ReaderThemeData theme,
    LibraryFilterState filter,
  ) {
    final isFiltered = filter.category != LibraryFilterCategory.all;
    final isShelf =
        filter.category == LibraryFilterCategory.shelf &&
        filter.shelfId != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIconsLight.books,
              size: 64,
              color: theme.textMuted,
            ),
          const SizedBox(height: Spacing.lg),
          Text(
            isFiltered ? 'No documents in this view' : 'Your library is empty',
            style: AppTypography.largeTitle.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            isFiltered
                ? 'Documents added to this shelf will appear here.'
                : 'Drag and drop documents here, or click import.',
            style: AppTypography.body.copyWith(color: theme.textMuted),
          ),
          const SizedBox(height: Spacing.xl),
          if (isShelf)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => _openAddFromLibraryDialog(
                    context,
                    ref,
                    filter.shelfId!,
                    filter.shelfName ?? 'Shelf',
                  ),
                  icon: const PhosphorIcon(PhosphorIconsLight.books, size: 18),
                  label: const Text('Add from Library'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: theme.isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.sm,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _importDocuments(context, ref, shelfId: filter.shelfId),
                  icon: const PhosphorIcon(
                    PhosphorIconsLight.folderSimplePlus,
                    size: 18,
                  ),
                  label: const Text('Import from Disk'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accent.withValues(alpha: 0.15),
                    foregroundColor: theme.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.sm,
                    ),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: () => _importDocuments(context, ref),
              icon: const PhosphorIcon(PhosphorIconsLight.plus, size: 18),
              label: const Text('Import Document'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.sm,
                ),
              ),
            ),
        ],
      ),
    ),
  );
  }

  Widget _buildDocumentGrid(
    BuildContext context,
    WidgetRef ref,
    ReaderThemeData theme,
    LibraryFilterState filter,
    List<DocumentEntry> documents,
  ) {
    final title = switch (filter.category) {
      LibraryFilterCategory.all => 'All Documents',
      LibraryFilterCategory.reading => 'Currently Reading',
      LibraryFilterCategory.completed => 'Completed',
      LibraryFilterCategory.shelf => filter.shelfName ?? 'Shelf',
    };
    final isShelf =
        filter.category == LibraryFilterCategory.shelf &&
        filter.shelfId != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar with Section Title and Import Action
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.headline.copyWith(
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      '(${documents.length})',
                      style: AppTypography.headline.copyWith(
                        color: theme.textMuted,
                      ),
                    ),
                  ],
                ),
                if (isShelf)
                  Wrap(
                    spacing: Spacing.xs,
                    runSpacing: Spacing.xs,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _openAddFromLibraryDialog(
                          context,
                          ref,
                          filter.shelfId!,
                          filter.shelfName ?? 'Shelf',
                        ),
                        icon: const PhosphorIcon(
                          PhosphorIconsLight.books,
                          size: 16,
                        ),
                        label: const Text('Add from Library'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.accent.withValues(alpha: 0.15),
                          foregroundColor: theme.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: Spacing.xs,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _importDocuments(
                          context,
                          ref,
                          shelfId: filter.shelfId,
                        ),
                        icon: const PhosphorIcon(
                          PhosphorIconsLight.folderSimplePlus,
                          size: 16,
                        ),
                        label: const Text('Import from Disk'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.accent.withValues(alpha: 0.15),
                          foregroundColor: theme.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: Spacing.xs,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: () => _importDocuments(context, ref),
                    icon: const PhosphorIcon(
                      PhosphorIconsLight.folderSimplePlus,
                      size: 16,
                    ),
                    label: const Text('Import'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent.withValues(alpha: 0.15),
                      foregroundColor: theme.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            // Responsive Card Grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: Spacing.xl),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 0.46,
                  crossAxisSpacing: Spacing.md,
                  mainAxisSpacing: Spacing.md,
                ),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final doc = documents[index];
                  return BookCard(
                    document: doc,
                    shelfName: isShelf ? filter.shelfName : null,
                    onRemoveFromShelf: isShelf && filter.shelfId != null
                        ? () => _removeDocumentFromShelf(
                            context,
                            ref,
                            doc,
                            filter.shelfId!,
                            filter.shelfName ?? 'Shelf',
                          )
                        : null,
                    onTap: () {
                      // Reader integration will be hooked up in next phase
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAddFromLibraryDialog(
    BuildContext context,
    WidgetRef ref,
    String shelfId,
    String shelfName,
  ) async {
    final count = await showDialog<int>(
      context: context,
      builder: (context) => AddFromLibraryDialog(
        shelfId: shelfId,
        shelfName: shelfName,
        onImportFromDisk: () =>
            _importDocuments(context, ref, shelfId: shelfId),
      ),
    );
    if (count != null && count > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $count document${count == 1 ? '' : 's'} to $shelfName',
          ),
        ),
      );
    }
  }

  Future<void> _removeDocumentFromShelf(
    BuildContext context,
    WidgetRef ref,
    DocumentEntry doc,
    String shelfId,
    String shelfName,
  ) async {
    try {
      final db = ref.read(databaseProvider);
      await db.removeDocumentFromShelf(doc.id, shelfId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "${doc.title}" from $shelfName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove document from shelf: $e')),
        );
      }
    }
  }

  Future<void> _importDocuments(
    BuildContext context,
    WidgetRef ref, {
    String? shelfId,
  }) async {
    try {
      final service = ref.read(ingestionServiceProvider);
      final imported = await service.pickAndIngestDocuments(shelfId: shelfId);
      if (imported.isNotEmpty && context.mounted) {
        final shelfName = ref.read(libraryFilterProvider).shelfName;
        final target = shelfId != null && shelfName != null
            ? ' and added to $shelfName'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${imported.length} document${imported.length == 1 ? '' : 's'}$target',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import document: $e')),
        );
      }
    }
  }
}
