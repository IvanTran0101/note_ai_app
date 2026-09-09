import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'notes_localizations.dart';

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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    copy.notes,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('new-note'),
                  onPressed: actionBusy ? null : onNewNote,
                  icon: const Icon(Icons.add),
                  label: Text(copy.newNote),
                ),
              ],
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
                        return ListTile(
                          key: ValueKey<String>('note-${note.id}'),
                          selected: selected,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          title: Text(
                            note.title.trim().isEmpty
                                ? copy.untitled
                                : note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _preview(note.content, copy),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: actionBusy ? null : () => onSelectNote(note),
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
