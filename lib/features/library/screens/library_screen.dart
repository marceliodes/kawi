import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
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
            'Your library is empty',
            style: AppTypography.largeTitle.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Drag and drop documents here, or click import.',
            style: AppTypography.body.copyWith(color: theme.textMuted),
          ),
          const SizedBox(height: Spacing.xl),
          FilledButton(
            onPressed: () {},
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
            child: const Text('Import Document'),
          ),
        ],
      ),
    );
  }
}
