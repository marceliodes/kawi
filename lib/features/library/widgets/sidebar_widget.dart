import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/inset_grouped_card.dart';
import '../providers/library_provider.dart';

class SidebarWidget extends ConsumerWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final activeFilter = ref.watch(libraryFilterProvider);
    final shelvesAsync = ref.watch(shelvesStreamProvider);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: theme.bgCanvas,
        border: Border(right: BorderSide(color: theme.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.lg),
            Text(
              'LIBRARY',
              style: AppTypography.sectionHeader.copyWith(
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            InsetGroupedCard(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
              child: Column(
                children: [
                  _SidebarRow(
                    icon: PhosphorIconsLight.books,
                    label: 'All Documents',
                    isSelected:
                        activeFilter.category == LibraryFilterCategory.all,
                    onTap: () {
                      ref
                          .read(libraryFilterProvider.notifier)
                          .setFilter(LibraryFilterState.all);
                    },
                  ),
                  _SidebarRow(
                    icon: PhosphorIconsLight.bookOpen,
                    label: 'Currently Reading',
                    isSelected:
                        activeFilter.category == LibraryFilterCategory.reading,
                    onTap: () {
                      ref
                          .read(libraryFilterProvider.notifier)
                          .setFilter(LibraryFilterState.reading);
                    },
                  ),
                  _SidebarRow(
                    icon: PhosphorIconsLight.checkCircle,
                    label: 'Completed',
                    isSelected:
                        activeFilter.category ==
                        LibraryFilterCategory.completed,
                    onTap: () {
                      ref
                          .read(libraryFilterProvider.notifier)
                          .setFilter(LibraryFilterState.completed);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'COLLECTIONS',
              style: AppTypography.sectionHeader.copyWith(
                color: theme.textMuted,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Expanded(
              child: InsetGroupedCard(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xxs),
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    shelvesAsync.when(
                      data: (shelves) {
                        return Column(
                          children: [
                            for (final shelf in shelves)
                              _SidebarRow(
                                icon: PhosphorIconsLight.folder,
                                label: shelf.name,
                                isSelected:
                                    activeFilter.category ==
                                        LibraryFilterCategory.shelf &&
                                    activeFilter.shelfId == shelf.id,
                                onTap: () {
                                  ref
                                      .read(libraryFilterProvider.notifier)
                                      .setFilter(
                                        LibraryFilterState.shelf(
                                          shelf.id,
                                          shelf.name,
                                        ),
                                      );
                                },
                              ),
                          ],
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                    _SidebarRow(
                      icon: PhosphorIconsLight.plus,
                      label: 'New Shelf',
                      onTap: () => _showCreateShelfDialog(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateShelfDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final theme = ReaderTheme.of(context);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.bgCard,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: BorderSide(color: theme.borderSubtle),
          ),
          title: Text(
            'New Shelf',
            style: AppTypography.headline.copyWith(color: theme.textPrimary),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Shelf name (e.g. Science Fiction)',
              hintStyle: TextStyle(color: theme.textMuted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.borderSubtle),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.accent),
              ),
            ),
            style: TextStyle(color: theme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: theme.textMuted)),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final db = ref.read(databaseProvider);
                  final id = 'shelf_${DateTime.now().millisecondsSinceEpoch}';
                  await db.insertShelf(
                    ShelvesCompanion.insert(
                      id: id,
                      name: name,
                      createdAt: DateTime.now(),
                    ),
                  );
                  ref
                      .read(libraryFilterProvider.notifier)
                      .setFilter(LibraryFilterState.shelf(id, name));
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.icon,
    required this.label,
    this.isSelected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    return Material(
      color: isSelected
          ? theme.accent.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        hoverColor: theme.hoverOverlay,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Row(
            children: [
              PhosphorIcon(
                icon,
                size: 18,
                color: isSelected ? theme.accent : theme.textMuted,
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: isSelected ? theme.accent : theme.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
