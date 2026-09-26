import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../shared/widgets/inset_grouped_card.dart';

class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
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
            const InsetGroupedCard(
              padding: EdgeInsets.symmetric(vertical: Spacing.xxs),
              child: Column(
                children: [
                  _SidebarRow(
                    icon: PhosphorIconsLight.books,
                    label: 'All Documents',
                    isSelected: true,
                  ),
                  _SidebarRow(
                    icon: PhosphorIconsLight.bookOpen,
                    label: 'Currently Reading',
                  ),
                  _SidebarRow(
                    icon: PhosphorIconsLight.checkCircle,
                    label: 'Completed',
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
            const InsetGroupedCard(
              padding: EdgeInsets.symmetric(vertical: Spacing.xxs),
              child: _SidebarRow(
                icon: PhosphorIconsLight.plus,
                label: 'New Shelf',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.icon,
    required this.label,
    this.isSelected = false,
  });

  final IconData icon;
  final String label;
  final bool isSelected;

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
        onTap: () {},
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
