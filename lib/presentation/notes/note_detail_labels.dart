part of 'note_detail_page.dart';

extension _NoteDetailLabels on NoteDetailPageState {
  Widget? _buildNoteExtras() {
    final note = _note;
    if (note == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoteLabelEditor(
          key: ValueKey(('labels', note.identity)),
          note: note,
          readable: _canRead,
          canManage:
              _capabilities.canManage &&
              !_actionBusy &&
              !_securityBusy &&
              !_securityLoading &&
              _currentConflict == null &&
              !_hasRemoteEditorChange,
          onChanged: _labelsSaved,
        ),
        if (widget.notesController is AttachmentNotesController)
          AttachmentEditorPanel(
            key: ValueKey(note.identity),
            note: note,
            controller: widget.notesController as AttachmentNotesController,
            security: _securityController,
            onChanged: _labelsSaved,
            onBeforePick: () async => !_isDirty || await _save(),
            onResumeProtected: () => _resumeProtectedAttachment(note),
            enabled:
                !_securityBusy && !_securityLoading && _capabilities.canRead,
          ),
      ],
    );
  }

  void _labelsSaved(NoteDto incoming) {
    if (!_canRead || incoming.identity != _note?.identity) return;
    _update(() {
      // Reuse the ACK rebase: controllers and the dirty saved-text baseline stay.
      if (!_rebaseUnchangedSavedText(incoming)) _pendingSavedNote = incoming;
      _didPersist = true;
      _summaryController.markStaleIfResult();
    });
    _notifyDirtyChanged();
  }
}
