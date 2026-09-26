import 'package:flutter/material.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';

class TypesetBookJacket extends StatelessWidget {
  const TypesetBookJacket({required this.title, this.author, super.key});

  final String title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.bgCard,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: theme.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 4px vertical accent stripe simulating book spine
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: theme.accent),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: Spacing.sm + 4,
              right: Spacing.sm,
              top: Spacing.md,
              bottom: Spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.readerSerif,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                ),
                if (author != null && author!.isNotEmpty) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.textMuted,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
