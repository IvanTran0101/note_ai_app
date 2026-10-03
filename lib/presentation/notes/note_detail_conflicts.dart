part of 'note_detail_page.dart';

extension _NoteDetailConflicts on NoteDetailPageState {
  Future<void> _resolveConflict() async {
    final SyncPresentationController? sync = widget.syncController;
    final SyncConflict? conflict = _currentConflict;
    if (sync == null || conflict == null || _actionBusy || !_canEdit) return;

    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _conflictFlowActive = true;
    if (_isDirty) {
      _backConfirmationVisible = true;
      final SyncDirtyDraftChoice? draftChoice = await showSyncDirtyDraftChoices(
        context: context,
        allowSaveAsNew: _canExport,
      );
      _backConfirmationVisible = false;
      if (!mounted ||
          draftChoice == null ||
          draftChoice == SyncDirtyDraftChoice.cancel) {
        _conflictFlowActive = false;
        return;
      }
      if (draftChoice == SyncDirtyDraftChoice.discard) {
        _titleController.text = conflict.local.title;
        _contentController.text = conflict.local.content;
        _savedTitle = conflict.local.title;
        _savedContent = conflict.local.content;
        _notifyDirtyChanged();
        if (_note?.isProtected == true) await _readSecuredNote();
        if (!mounted || !_canEdit) {
          _conflictFlowActive = false;
          return;
        }
      } else {
        await _saveDraftAsNewAndResolve(conflict, sync);
        return;
      }
    }

    final SyncConflictChoice? choice = await showSyncConflictChoices(
      context: context,
      conflict: conflict,
    );
    if (!mounted || choice == null) {
      _conflictFlowActive = false;
      return;
    }
    if (choice == SyncConflictChoice.later) {
      await sync.resolveConflict(displayedConflict: conflict, choice: choice);
      _conflictFlowActive = false;
      return;
    }
    _update(() => _resolvingConflict = true);
    final bool resolved = await sync.resolveConflict(
      displayedConflict: conflict,
      choice: choice,
    );
    if (!mounted) return;
    _update(() {
      _resolvingConflict = false;
      _conflictFlowActive = false;
      _statusMessage = resolved ? null : SyncCopy.of(context).conflictChanged;
    });
    if (resolved) _pop(reason: NoteDetailExitReason.saved);
  }

  Future<void> _saveDraftAsNewAndResolve(
    SyncConflict conflict,
    SyncPresentationController sync,
  ) async {
    if (!_canExport) return;
    NoteDto? copy;
    _update(() {
      _saving = true;
      _resolvingConflict = true;
      _error = null;
    });
    try {
      copy = await widget.notesController.createNote(
        title: _titleController.text,
        content: _contentController.text,
      );
      if (!mounted) return;
      _update(() => _saving = false);
      final SyncConflictChoice? choice = await showSyncConflictChoices(
        context: context,
        conflict: conflict,
      );
      if (choice != null) {
        await sync.resolveConflict(displayedConflict: conflict, choice: choice);
      }
    } on Object {
      if (copy == null && mounted) {
        _update(() {
          _saving = false;
          _resolvingConflict = false;
          _conflictFlowActive = false;
          _error = NoteDetailCopy.of(context).saveError;
        });
        return;
      }
    }
    if (mounted && copy != null) {
      _pop(reason: NoteDetailExitReason.saved, noteOverride: copy);
    }
  }
}
