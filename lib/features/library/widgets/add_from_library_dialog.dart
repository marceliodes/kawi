import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';

class AddFromLibraryDialog extends ConsumerStatefulWidget {
  const AddFromLibraryDialog({
    required this.shelfId,
    required this.shelfName,
    this.onImportFromDisk,
    super.key,
  });

  final String shelfId;
  final String shelfName;
  final VoidCallback? onImportFromDisk;

  @override
  ConsumerState<AddFromLibraryDialog> createState() =>
      _AddFromLibraryDialogState();
}

class _AddFromLibraryDialogState extends ConsumerState<AddFromLibraryDialog> {
  final Set<String> _selectedIds = {};
  late Future<List<DocumentEntry>> _availableDocsFuture;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableDocuments();
  }

  void _loadAvailableDocuments() {
    final db = ref.read(databaseProvider);
    _availableDocsFuture = db.getDocumentsNotInShelf(widget.shelfId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);

    return Dialog(
      backgroundColor: theme.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: theme.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsLight.books,
                    size: 24,
                    color: theme.accent,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      'Add to "${widget.shelfName}"',
                      style: AppTypography.headline.copyWith(
                        color: theme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: PhosphorIcon(
                      PhosphorIconsLight.x,
                      size: 18,
                      color: theme.textMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              // Document list
              Expanded(
                child: FutureBuilder<List<DocumentEntry>>(
                  future: _availableDocsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(color: theme.accent),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Failed to load documents: ${snapshot.error}',
                          style: AppTypography.body.copyWith(
                            color: theme.textMuted,
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PhosphorIcon(
                              PhosphorIconsLight.checkCircle,
                              size: 48,
                              color: theme.textMuted,
                            ),
                            const SizedBox(height: Spacing.sm),
                            Text(
                              'All documents are already in this shelf',
                              style: AppTypography.body.copyWith(
                                color: theme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: Spacing.xxs),
                            Text(
                              'Or your library has no documents yet.',
                              style: AppTypography.micro.copyWith(
                                color: theme.textMuted,
                              ),
                            ),
                            if (widget.onImportFromDisk != null) ...[
                              const SizedBox(height: Spacing.md),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onImportFromDisk!();
                                },
                                icon: const PhosphorIcon(
                                  PhosphorIconsLight.folderSimplePlus,
                                  size: 16,
                                ),
                                label: const Text('Import from Disk'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: theme.accent.withValues(
                                    alpha: 0.15,
                                  ),
                                  foregroundColor: theme.accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      Radii.sm,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    final allSelected = _selectedIds.length == docs.length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Select all toggle
                        Row(
                          children: [
                            Text(
                              '${docs.length} available document${docs.length == 1 ? '' : 's'}',
                              style: AppTypography.micro.copyWith(
                                color: theme.textMuted,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  if (allSelected) {
                                    _selectedIds.clear();
                                  } else {
                                    _selectedIds.addAll(docs.map((d) => d.id));
                                  }
                                });
                              },
                              child: Text(
                                allSelected ? 'Deselect All' : 'Select All',
                                style: AppTypography.micro.copyWith(
                                  color: theme.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              vertical: Spacing.xs,
                            ),
                            itemCount: docs.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1, indent: 48),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final isSelected = _selectedIds.contains(doc.id);
                              final hasCover =
                                  doc.coverPath != null &&
                                  File(doc.coverPath!).existsSync();

                              return InkWell(
                                borderRadius: BorderRadius.circular(Radii.sm),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(doc.id);
                                    } else {
                                      _selectedIds.add(doc.id);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: Spacing.xs,
                                    horizontal: Spacing.xxs,
                                  ),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: theme.accent,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedIds.add(doc.id);
                                            } else {
                                              _selectedIds.remove(doc.id);
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: Spacing.xxs),
                                      // Mini Thumbnail
                                      SizedBox(
                                        width: 32,
                                        height: 48,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                          child: hasCover
                                              ? Image.file(
                                                  File(doc.coverPath!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      _MiniThumbnailJacket(
                                                        format: doc.format,
                                                      ),
                                                )
                                              : _MiniThumbnailJacket(
                                                  format: doc.format,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: Spacing.sm),
                                      // Title & Author
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              doc.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTypography.body
                                                  .copyWith(
                                                    color: theme.textPrimary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            if (doc.author != null &&
                                                doc.author!.trim().isNotEmpty)
                                              Text(
                                                doc.author!.trim(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.micro
                                                    .copyWith(
                                                      color: theme.textMuted,
                                                    ),
                                              ),
                                            Text(
                                              '${doc.format.toUpperCase()}${doc.pageCount > 0 ? ' • ${doc.pageCount} pages' : ''}',
                                              style: AppTypography.micro
                                                  .copyWith(
                                                    color: theme.textMuted,
                                                    fontSize: 10,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: Spacing.md),
              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _isAdding ? null : () => Navigator.of(context).pop(0),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: theme.textMuted),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed: _selectedIds.isEmpty || _isAdding
                        ? null
                        : () async {
                            setState(() => _isAdding = true);
                            final db = ref.read(databaseProvider);
                            for (final id in _selectedIds) {
                              await db.addDocumentToShelf(id, widget.shelfId);
                            }
                            if (context.mounted) {
                              Navigator.of(context).pop(_selectedIds.length);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: theme.isDark
                          ? Colors.black
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                    ),
                    child: _isAdding
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : Text(
                            _selectedIds.isEmpty
                                ? 'Add to Shelf'
                                : 'Add (${_selectedIds.length})',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniThumbnailJacket extends StatelessWidget {
  const _MiniThumbnailJacket({required this.format});
  final String format;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    return Container(
      color: theme.borderSubtle,
      child: Center(
        child: Text(
          format.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: theme.textMuted,
          ),
        ),
      ),
    );
  }
}
