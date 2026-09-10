import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'dashboard_localizations.dart';

/// Visual density used by a Dashboard note card.
enum DashboardNoteCardLayout { list, grid }

/// A responsive, accessible preview card for one note.
final class DashboardNoteCard extends StatelessWidget {
  const DashboardNoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.copy,
    required this.layout,
    this.selected = false,
  });

  /// Note projection shown by the card.
  final NoteDto note;

  /// Called when the user activates the card.
  final ValueChanged<NoteDto> onTap;

  /// Localized Dashboard copy supplied by the parent.
  final DashboardCopy copy;

  /// Layout context used to tune the preview without changing its data.
  final DashboardNoteCardLayout layout;

  /// Whether the card is the current selection in an expanded layout.
  final bool selected;

  static const Key cardKeyPrefix = ValueKey<String>('dashboard-note-card');

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String title = note.title.trim().isEmpty ? copy.untitled : note.title;
    final String preview = _preview(note.content);
    final String updatedDate = MaterialLocalizations.of(context)
        .formatCompactDate(note.updatedAt);

    return Semantics(
      button: true,
      selected: selected,
      label: copy.noteSemantics(title: title, preview: preview),
      child: Card(
        key: ValueKey<String>('dashboard-note-card-${note.id}'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: InkWell(
          onTap: () => onTap(note),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 136.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    preview,
                    maxLines: layout == DashboardNoteCardLayout.grid ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Text(
                    copy.updatedOn(updatedDate),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _preview(String content) {
    final String normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? copy.noContent : normalized;
  }
}
