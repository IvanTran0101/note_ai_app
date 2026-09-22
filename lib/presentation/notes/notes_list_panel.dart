import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';

/// Displays the saved Note projections and the list-level actions.
///
/// Rows render as Notion-style page rows: page icon, title, light preview and
/// a token-based selected background. All keys and callbacks are unchanged.
final class NotesListPanel extends StatelessWidget {
  const NotesListPanel({
    super.key,
    required this.notes,
    required this.selectedNoteId,
    required this.error,
    required this.actionBusy,
    required this.onNewNote,
    required this.onSelectNote,
    required this.onRetry,
  });

  final List<NoteDto> notes;
  final String? selectedNoteId;
  final String? error;
  final bool actionBusy;
  final VoidCallback onNewNote;
  final ValueChanged<NoteDto> onSelectNote;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: tokens.sidebarSurface,
      child: Padding(
        padding: const EdgeInsets.all(NoteFlowSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget title = Text(
                  copy.notes,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                );
                final Widget create = OutlinedButton.icon(
                  key: const ValueKey<String>('new-note'),
                  onPressed: actionBusy ? null : onNewNote,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(copy.newNote),
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      title,
                      const SizedBox(height: NoteFlowSpacing.sm),
                      Align(alignment: Alignment.centerLeft, child: create),
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: title),
                    create,
                  ],
                );
              },
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: NoteFlowSpacing.sm),
              Text(
                error!,
                key: const ValueKey<String>('notes-list-error'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.error),
              ),
              if (notes.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey<String>('retry-notes'),
                    onPressed: actionBusy ? null : onRetry,
                    child: Text(copy.retry),
                  ),
                ),
            ],
            const SizedBox(height: NoteFlowSpacing.sm),
            Expanded(
              child: notes.isEmpty
                  ? Center(
                      key: ValueKey<String>('notes-empty'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.note_alt_outlined,
                            size: 40,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(height: NoteFlowSpacing.sm),
                          Text(
                            copy.noNotes,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                          const SizedBox(height: NoteFlowSpacing.xs),
                          TextButton(
                            key: const ValueKey<String>('new-note-empty'),
                            onPressed: actionBusy ? null : onNewNote,
                            child: Text(copy.createFirstNote),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: NoteFlowSpacing.xs),
                      itemBuilder: (BuildContext context, int index) {
                        final NoteDto note = notes[index];
                        final bool selected = note.id == selectedNoteId;
                        return Semantics(
                          selected: selected,
                          button: true,
                          label:
                              '${note.title.trim().isEmpty ? copy.untitled : note.title}. ${_preview(note.content, copy)}',
                          child: ListTile(
                            key: ValueKey<String>('note-${note.id}'),
                            selected: selected,
                            selectedTileColor: colors.primaryContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                NoteFlowRadius.row,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: NoteFlowSpacing.md,
                              vertical: 2,
                            ),
                            leading: Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: selected
                                  ? colors.onPrimaryContainer
                                  : tokens.textMuted,
                            ),
                            title: Text(
                              note.title.trim().isEmpty
                                  ? copy.untitled
                                  : note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? colors.onPrimaryContainer
                                        : tokens.textPrimary,
                                  ),
                            ),
                            subtitle: Text(
                              _preview(note.content, copy),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: selected
                                        ? colors.onPrimaryContainer
                                        : tokens.textMuted,
                                  ),
                            ),
                            onTap: actionBusy ? null : () => onSelectNote(note),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _preview(String content, NotesCopy copy) {
    final String normalized = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? copy.noContent : normalized;
  }
}
