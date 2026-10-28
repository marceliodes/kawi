import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/reader_theme.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import 'reader_selection_toolbar.dart';

class HighlightNoteDialog extends StatefulWidget {
  const HighlightNoteDialog({
    super.key,
    required this.selectedText,
    required this.initialColorHex,
    this.initialNote,
    required this.onSave,
    this.onDelete,
  });

  final String selectedText;
  final String initialColorHex;
  final String? initialNote;
  final void Function(String colorHex, String note) onSave;
  final VoidCallback? onDelete;

  static Future<void> show(
    BuildContext context, {
    required String selectedText,
    required String initialColorHex,
    String? initialNote,
    required void Function(String colorHex, String note) onSave,
    VoidCallback? onDelete,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => HighlightNoteDialog(
        selectedText: selectedText,
        initialColorHex: initialColorHex,
        initialNote: initialNote,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<HighlightNoteDialog> createState() => _HighlightNoteDialogState();
}

class _HighlightNoteDialogState extends State<HighlightNoteDialog> {
  late final TextEditingController _controller;
  late String _selectedColorHex;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
    _selectedColorHex = widget.initialColorHex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _resolveAccentColor(ReaderThemeData theme) {
    if (_selectedColorHex == 'underline') return theme.accent;
    final clean = _selectedColorHex.replaceFirst('#', '');
    final val = int.tryParse(clean, radix: 16);
    if (val != null) {
      return clean.length == 6 ? Color(val | 0xFF000000) : Color(val);
    }
    return theme.accent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ReaderTheme.of(context);
    final accentColor = _resolveAccentColor(theme);

    return Dialog(
      backgroundColor: theme.bgCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: theme.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsLight.notePencil,
                    size: 20,
                    color: theme.accent,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    widget.initialNote != null ? 'Edit Note' : 'Add Note',
                    style: AppTypography.headline.copyWith(
                      color: theme.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
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
              const SizedBox(height: Spacing.xs),

              // Quoted Excerpt Preview
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: theme.bgCanvas,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border(
                    left: BorderSide(
                      color: accentColor,
                      width: 4,
                    ),
                  ),
                ),
                child: Text(
                  '“${widget.selectedText}”',
                  style: AppTypography.body.copyWith(
                    color: theme.textMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: Spacing.sm),

              // Note Input Field
              TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 4,
                style: AppTypography.body.copyWith(color: theme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type your note here...',
                  hintStyle:
                      AppTypography.body.copyWith(color: theme.textMuted),
                  filled: true,
                  fillColor: theme.bgCanvas,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: theme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: theme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    borderSide: BorderSide(color: theme.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),

              // Color Selection Row
              Row(
                children: [
                  Text(
                    'Color:',
                    style:
                        AppTypography.micro.copyWith(color: theme.textMuted),
                  ),
                  const SizedBox(width: Spacing.xs),
                  for (final c in kHighlightColors)
                    GestureDetector(
                      onTap: () => setState(() => _selectedColorHex = c.hex),
                      child: Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColorHex == c.hex
                                ? theme.accent
                                : Colors.black12,
                            width: _selectedColorHex == c.hex ? 2.5 : 1.0,
                          ),
                        ),
                      ),
                    ),
                  // Underline style chip
                  GestureDetector(
                    onTap: () => setState(() => _selectedColorHex = 'underline'),
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _selectedColorHex == 'underline'
                            ? theme.accent.withValues(alpha: 0.2)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColorHex == 'underline'
                              ? theme.accent
                              : theme.borderSubtle,
                          width: _selectedColorHex == 'underline' ? 2.0 : 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'U',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationThickness: 2.0,
                            color: _selectedColorHex == 'underline'
                                ? theme.accent
                                : theme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.onDelete != null)
                    TextButton.icon(
                      icon: const PhosphorIcon(
                        PhosphorIconsLight.trash,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.of(context).pop();
                      },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: theme.textMuted),
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  FilledButton(
                    onPressed: () {
                      widget.onSave(_selectedColorHex, _controller.text.trim());
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Note'),
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
