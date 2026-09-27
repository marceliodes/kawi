import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../providers/library_provider.dart';
import 'typeset_book_jacket.dart';

class BookCard extends ConsumerWidget {
  const BookCard({
    required this.document,
    this.onTap,
    this.onRemoveFromShelf,
    this.shelfName,
    super.key,
  });

  final DocumentEntry document;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveFromShelf;
  final String? shelfName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ReaderTheme.of(context);
    final progressAsync = ref.watch(documentProgressProvider(document.id));

    final hasCoverFile =
        document.coverPath != null && File(document.coverPath!).existsSync();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        hoverColor: theme.hoverOverlay,
        onTap: onTap,
        onSecondaryTapUp: onRemoveFromShelf != null
            ? (details) =>
                  _showContextMenu(context, details.globalPosition, theme)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover area with 2:3 aspect ratio
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: hasCoverFile
                              ? Image.file(
                                  File(document.coverPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return TypesetBookJacket(
                                      title: document.title,
                                      author: document.author,
                                    );
                                  },
                                )
                              : TypesetBookJacket(
                                  title: document.title,
                                  author: document.author,
                                ),
                        ),
                      ),
                    ),
                    if (onRemoveFromShelf != null)
                      Positioned(
                        top: Spacing.xxs,
                        right: Spacing.xxs,
                        child: _CardMenuButton(
                          onRemoveFromShelf: onRemoveFromShelf!,
                          shelfName: shelfName,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xs),
              // Document title
              Text(
                document.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                  height: 1.2,
                ),
              ),
              if (document.author != null &&
                  document.author!.trim().isNotEmpty) ...[
                const SizedBox(height: Spacing.xxs),
                Text(
                  document.author!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.micro.copyWith(color: theme.textMuted),
                ),
              ],
              const SizedBox(height: Spacing.xxs),
              // Reading progress
              progressAsync.when(
                data: (progress) {
                  if (document.isCompleted) {
                    return Row(
                      children: [
                        PhosphorIcon(
                          PhosphorIconsLight.checkCircle,
                          size: 12,
                          color: theme.accent,
                        ),
                        const SizedBox(width: Spacing.xxs),
                        Text(
                          'Completed',
                          style: AppTypography.micro.copyWith(
                            color: theme.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  }

                  if (progress != null && document.pageCount > 0) {
                    final fraction =
                        ((progress.lastReadPageIndex + 1) / document.pageCount)
                            .clamp(0.0, 1.0);
                    final pct = (fraction * 100).toInt();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 3,
                            backgroundColor: theme.borderSubtle,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pct% complete',
                          style: AppTypography.micro.copyWith(
                            color: theme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    );
                  }

                  // Default when not yet read
                  return Text(
                    document.pageCount > 0
                        ? '${document.pageCount} pages • ${document.format.toUpperCase()}'
                        : document.format.toUpperCase(),
                    style: AppTypography.micro.copyWith(
                      color: theme.textMuted,
                      fontSize: 10,
                    ),
                  );
                },
                loading: () => const SizedBox(height: 12),
                error: (_, _) => const SizedBox(height: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    ReaderThemeData theme,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: theme.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        side: BorderSide(color: theme.borderSubtle),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsLight.folderMinus,
                size: 16,
                color: Colors.redAccent,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                shelfName != null
                    ? 'Remove from $shelfName'
                    : 'Remove from Shelf',
                style: AppTypography.body.copyWith(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'remove') {
        onRemoveFromShelf?.call();
      }
    });
  }
}

class _CardMenuButton extends StatelessWidget {
  const _CardMenuButton({required this.onRemoveFromShelf, this.shelfName});

  final VoidCallback onRemoveFromShelf;
  final String? shelfName;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<String>(
        tooltip: 'Document options',
        padding: EdgeInsets.zero,
        iconSize: 16,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        icon: const PhosphorIcon(
          PhosphorIconsLight.dotsThreeVertical,
          size: 14,
          color: Colors.white,
        ),
        color: theme.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          side: BorderSide(color: theme.borderSubtle),
        ),
        onSelected: (val) {
          if (val == 'remove') {
            onRemoveFromShelf();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(
              children: [
                const PhosphorIcon(
                  PhosphorIconsLight.folderMinus,
                  size: 16,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  shelfName != null
                      ? 'Remove from $shelfName'
                      : 'Remove from Shelf',
                  style: AppTypography.body.copyWith(
                    color: Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
