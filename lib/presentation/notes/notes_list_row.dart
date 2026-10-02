part of 'notes_list_panel.dart';

/// Row rendering is separate from list layout and error states.
extension _NotesListRow on NotesListPanel {
  Widget _buildNoteRow(
    BuildContext context,
    NoteDto note,
    NotesCopy copy,
    NoteFlowUiTokens tokens,
  ) {
    final securityCopy = NoteSecurityCopy(context);
    final title = note.isProtected
        ? securityCopy.protectedNote
        : (note.title.trim().isEmpty ? copy.untitled : note.title);
    final preview = note.isProtected
        ? securityCopy.locked
        : _preview(note.content, copy);
    final bool selected = note.reference == selectedNoteId;
    return Semantics(
      selected: selected,
      button: true,
      label: '$title. $preview',
      child: ListTile(
        key: ValueKey<String>('note-${note.reference}'),
        selected: selected,
        selectedTileColor: tokens.selectedSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.row),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NoteFlowSpacing.md,
          vertical: 2,
        ),
        leading: Icon(
          note.isProtected ? Icons.lock_outline : Icons.description_outlined,
          size: 20,
          color: selected ? tokens.textPrimary : tokens.textMuted,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: tokens.textPrimary,
          ),
        ),
        subtitle: Text(
          note.share == null
              ? preview
              : '$preview\n${SharingCopy(context).metadata(note.share!)}',
          maxLines: note.share == null ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textMuted),
        ),
        onTap: actionBusy ? null : () => onSelectNote(note),
      ),
    );
  }
}
