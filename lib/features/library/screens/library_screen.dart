import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../providers/library_provider.dart';
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

    return Center(
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
    );
  }

  Widget _buildDocumentGrid(
    BuildContext context,
    WidgetRef ref,
    ReaderThemeData theme,
    LibraryFilterState filter,
    List<dynamic> documents,
  ) {
    final title = switch (filter.category) {
      LibraryFilterCategory.all => 'All Documents',
      LibraryFilterCategory.reading => 'Currently Reading',
      LibraryFilterCategory.completed => 'Completed',
      LibraryFilterCategory.shelf => filter.shelfName ?? 'Shelf',
    };

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
            Row(
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
                const Spacer(),
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

  Future<void> _importDocuments(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(ingestionServiceProvider);
      await service.pickAndIngestDocuments();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import document: $e')),
        );
      }
    }
  }
}
