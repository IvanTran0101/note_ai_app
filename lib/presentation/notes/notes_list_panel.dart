import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';
import '../sync/sync_presentation_controller.dart';
import '../sync/sync_widgets.dart';

/// Displays the saved Note projections and the list-level actions.
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
    this.syncController,
  });

  final List<NoteDto> notes;
  final String? selectedNoteId;
  final String? error;
  final bool actionBusy;
  final VoidCallback onNewNote;
  final ValueChanged<NoteDto> onSelectNote;
  final VoidCallback onRetry;
  final SyncPresentationController? syncController;

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget title = Text(
                  copy.notes,
                  style: Theme.of(context).textTheme.titleLarge,
                );
                final Widget create = OutlinedButton.icon(
                  key: const ValueKey<String>('new-note'),
                  onPressed: actionBusy ? null : onNewNote,
                  icon: const Icon(Icons.add),
                  label: Text(copy.newNote),
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      title,
                      const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              Text(
                error!,
                key: const ValueKey<String>('notes-list-error'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
            const SizedBox(height: 8),
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
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(copy.noNotes),
                          const SizedBox(height: 4),
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
                      separatorBuilder: (_, _) => const Divider(height: 1),
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
                            title: Text(
                              note.title.trim().isEmpty
                                  ? copy.untitled
                                  : note.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _preview(note.content, copy),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                                if (syncController
                                    case final SyncPresentationController sync)
                                  SyncNoteStatusBadge(
                                    controller: sync,
                                    noteId: note.id,
                                  ),
                              ],
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
