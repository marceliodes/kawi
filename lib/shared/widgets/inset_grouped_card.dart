import 'package:flutter/material.dart';

import '../../core/theme/reader_theme.dart';
import '../../core/theme/spacing.dart';

class InsetGroupedCard extends StatelessWidget {
  const InsetGroupedCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.bgCard,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(Spacing.sm),
        child: child,
      ),
    );
  }
}
