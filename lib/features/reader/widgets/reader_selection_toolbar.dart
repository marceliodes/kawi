import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../models/highlight.dart';
import '../providers/document_content_provider.dart';

const List<({String label, String hex, Color color})> kHighlightColors = [
  (label: 'Amber', hex: '#FFD54F', color: Color(0xFFFFD54F)),
  (label: 'Mint', hex: '#81C784', color: Color(0xFF81C784)),
  (label: 'Sky', hex: '#64B5F6', color: Color(0xFF64B5F6)),
  (label: 'Coral', hex: '#FF8A80', color: Color(0xFFFF8A80)),
];

class ReaderSelectionToolbar extends StatelessWidget {
  const ReaderSelectionToolbar({
    super.key,
    required this.anchors,
    required this.selectedText,
    required this.startAnchor,
    required this.endAnchor,
    this.existingHighlight,
    required this.onColorSelected,
    required this.onAddOrEditNote,
    required this.onClose,
    this.onPlayFromHere,
    this.onDeleteHighlight,
  });

  final TextSelectionToolbarAnchors anchors;
  final String selectedText;
  final ReadingAnchor startAnchor;
  final ReadingAnchor endAnchor;
  final Highlight? existingHighlight;
  final ValueChanged<String> onColorSelected;
  final VoidCallback onAddOrEditNote;
  final VoidCallback onClose;
  final ValueChanged<String>? onPlayFromHere;
  final VoidCallback? onDeleteHighlight;

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final screenSize = MediaQuery.of(context).size;

    const double toolbarHeight = 44.0;
    const double toolbarWidth = 320.0;
    final bool flipBelow = anchors.primaryAnchor.dy < 80.0;

    final double rawDy = flipBelow
        ? (anchors.secondaryAnchor?.dy ?? anchors.primaryAnchor.dy) + 12.0
        : anchors.primaryAnchor.dy - toolbarHeight - 12.0;
    final double dy =
        rawDy.clamp(12.0, screenSize.height - toolbarHeight - 12.0);

    final double rawDx = anchors.primaryAnchor.dx - (toolbarWidth / 2);
    final double dx = rawDx.clamp(16.0, screenSize.width - toolbarWidth - 16.0);

    return Stack(
      children: [
        Positioned(
          left: dx,
          top: dy,
          child: Material(
            elevation: 8,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(22),
            color: theme.bgCard,
            child: Container(
              height: toolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.borderSubtle, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in kHighlightColors)
                    _buildColorChip(
                      context,
                      color: c.color,
                      tooltip: c.label,
                      isSelected: existingHighlight?.colorHex == c.hex,
                      onTap: () {
                        onColorSelected(c.hex);
                        onClose();
                      },
                    ),

                  _buildUnderlineChip(
                    context,
                    theme: theme,
                    isSelected: existingHighlight?.isUnderline == true,
                    onTap: () {
                      onColorSelected('underline');
                      onClose();
                    },
                  ),

                  Container(
                    height: 20,
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: Spacing.xxs),
                    color: theme.borderSubtle,
                  ),

                  IconButton(
                    tooltip: existingHighlight?.note != null
                        ? 'Edit Note'
                        : 'Add Note',
                    icon: PhosphorIcon(
                      existingHighlight?.note != null
                          ? PhosphorIconsFill.chatTeardropText
                          : PhosphorIconsLight.chatTeardropText,
                      size: 18,
                      color: existingHighlight?.note != null
                          ? theme.accent
                          : theme.textPrimary,
                    ),
                    onPressed: () {
                      onClose();
                      onAddOrEditNote();
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),

                  IconButton(
                    tooltip: 'Copy',
                    icon: PhosphorIcon(
                      PhosphorIconsLight.copy,
                      size: 18,
                      color: theme.textPrimary,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: selectedText));
                      onClose();
                    },
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),

                  if (onPlayFromHere != null && selectedText.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Play from here',
                      icon: PhosphorIcon(
                        PhosphorIconsLight.speakerHigh,
                        size: 18,
                        color: theme.textPrimary,
                      ),
                      onPressed: () {
                        onPlayFromHere!(selectedText);
                        onClose();
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),

                  if (existingHighlight != null && onDeleteHighlight != null)
                    IconButton(
                      tooltip: 'Delete highlight',
                      icon: const PhosphorIcon(
                        PhosphorIconsLight.trash,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      onPressed: () {
                        onClose();
                        onDeleteHighlight!();
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorChip(
    BuildContext context, {
    required Color color,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : Colors.black12,
              width: isSelected ? 2.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildUnderlineChip(
    BuildContext context, {
    required ReaderThemeData theme,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: 'Underline',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? theme.accent : theme.borderSubtle,
              width: 1.2,
            ),
          ),
          child: Center(
            child: Text(
              'U',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationThickness: 2.0,
                color: isSelected ? theme.accent : theme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
