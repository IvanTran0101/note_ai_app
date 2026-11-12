part of 'note_detail_page.dart';

/// Saved ACKs and conflict state never replace a newer editor draft.
extension _NoteDetailSyncState on NoteDetailPageState {
  void _syncStateChanged() {
    if (!mounted) return;
    _refreshAcknowledgedNote();
    if (_currentConflict != null) {
      _summaryController.cancelActive(reason: SummaryRunFailureCode.conflict);
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
    } else if (_isDirty) {
      _scheduleAutosave();
    }
    _update(() {});
  }

  void _refreshAcknowledgedNote() {
    final note = _note;
    final state = widget.syncController?.localState;
    if (note == null ||
        state == null ||
        note.share != null ||
        state.accountUserId != note.ownerId) {
      return;
    }
    for (final saved in state.notes) {
      if (saved.id == note.id &&
          saved.ownerId == note.ownerId &&
          saved.deletedAt == null) {
        // A new embedded editor has no parent selection yet. Accept only an
        // ACK for the same saved text/protection/access, retaining any draft.
        final fresh = NoteDto.fromLocalState(saved);
        if (fresh.contentRevision > note.contentRevision &&
            (_pendingSavedNote == null ||
                fresh.contentRevision >= _pendingSavedNote!.contentRevision) &&
            _rebaseUnchangedSavedText(fresh)) {
          _summaryController.cancelActive(
            reason: SummaryRunFailureCode.noteChanged,
          );
          _summaryController.markStaleIfResult();
        }
        return;
      }
    }
  }

  SyncConflict? get _currentConflict {
    final String? noteId = _note?.reference;
    return noteId == null ? null : widget.syncController?.conflictFor(noteId);
  }
}
