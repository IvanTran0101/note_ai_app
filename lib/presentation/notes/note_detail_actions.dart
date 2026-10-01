part of 'note_detail_page.dart';

extension _NoteDetailActions on _NoteDetailPageState {
  Future<bool> _save({bool automatic = false}) async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (_actionBusy) {
      if (automatic) {
        _scheduleAutosave();
      }
      return false;
    }
    if (!_canSave && _note != null) {
      return false;
    }
    if (_currentConflict != null || !_canEdit) return false;

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    bool persisted = false;
    _update(() {
      _saving = true;
      _error = null;
      _statusMessage = null;
    });

    try {
      final NoteDto saved = await _persistEditor();

      if (!mounted) {
        return true;
      }
      if (widget.notesController is SecuredNotesController &&
          !(widget.notesController as SecuredNotesController)
              .capabilitiesFor(saved)
              .canRead) {
        _securityChanged();
        return false;
      }
      _summaryController.markStaleIfResult();
      _update(() {
        _note = saved;
        _pendingSavedNote = null;
        _savedTitle = saved.title;
        _savedContent = saved.content;
        _summaryController.clearFailure();
        _statusMessage = copy.saved;
        _didPersist = true;
      });
      _notifyDirtyChanged();
      persisted = true;
      return true;
    } on Object catch (error) {
      if (!mounted) {
        return false;
      }
      _update(() {
        _error = error is UnsupportedError
            ? copy.persistenceUnavailable
            : copy.saveError;
      });
      return false;
    } finally {
      if (mounted) {
        _update(() => _saving = false);
        if (persisted && _isDirty) {
          _scheduleAutosave();
        }
      }
    }
  }

  Future<NoteDto> _persistEditor() async {
    final String title = _titleController.text;
    final String content = _contentController.text;
    final NoteDto? current = _note;
    final NoteDto saved;
    if (current == null) {
      saved = await widget.notesController.createNote(
        title: title,
        content: content,
      );
    } else {
      NoteDto updated = current;
      if (title != _savedTitle) {
        updated = await widget.notesController.renameNote(
          noteId: current.id,
          title: title,
        );
      }
      if (content != _savedContent) {
        updated = await widget.notesController.replaceContent(
          noteId: current.id,
          content: content,
        );
      }
      saved = updated;
    }

    return saved;
  }

  Future<void> _summarize() async {
    if (!_canSummarize) {
      return;
    }
    final int accepted = _summaryController.acceptedResultCount;
    _update(() {
      _error = null;
      _statusMessage = null;
    });
    await _summaryController.run();
    if (!mounted || _summaryController.acceptedResultCount == accepted) {
      return;
    }
    _update(() => _statusMessage = NoteDetailCopy.of(context).summarized);
  }

  /// Stops the in-flight generation; cancelling never retracts what a cloud run
  /// may already have sent, and the last accepted summary stays displayed.
  void _cancelSummary() {
    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final bool cloud = _summaryController.isCloudRun;
    _summaryController.cancelActive();
    _update(() => _statusMessage = copy.summaryCancelExplanation(cloud));
  }

  bool get _provisioningFailed {
    final ModelProvisioningPhase? phase =
        widget.provisioningReader?.current.phase;
    return phase == ModelProvisioningPhase.failed ||
        phase == ModelProvisioningPhase.cancelled;
  }

  Future<void> _handleBack() async {
    if (_actionBusy) {
      return;
    }
    if (_currentConflict != null && _isDirty) {
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
      _conflictFlowActive = true;
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
        _pop(
          reason: _didPersist
              ? NoteDetailExitReason.saved
              : NoteDetailExitReason.cancelled,
        );
        return;
      }
      _update(() => _saving = true);
      try {
        final NoteDto copy = await widget.notesController.createNote(
          title: _titleController.text,
          content: _contentController.text,
        );
        if (mounted) {
          _pop(reason: NoteDetailExitReason.saved, noteOverride: copy);
        }
      } on Object {
        if (mounted) {
          _update(() {
            _saving = false;
            _conflictFlowActive = false;
            _error = NoteDetailCopy.of(context).saveError;
          });
        }
      }
      return;
    }
    if (!_isDirty) {
      _pop();
      return;
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _backConfirmationVisible = true;
    final NoteDetailBackDecision? action = await showNoteDetailBackConfirmation(
      context: context,
      copy: copy,
      canSave: true,
    );
    _backConfirmationVisible = false;
    _ignoreNextEditorFocusLoss = true;

    if (!mounted || action == null || action == NoteDetailBackDecision.cancel) {
      if (mounted && _isDirty) {
        _scheduleAutosave();
      }
      return;
    }
    if (action == NoteDetailBackDecision.discard) {
      _pop(
        reason: _didPersist
            ? NoteDetailExitReason.saved
            : NoteDetailExitReason.discarded,
      );
      return;
    }
    if (await _save() && mounted) {
      _pop(reason: NoteDetailExitReason.saved);
    }
  }

  Future<void> _delete() async {
    final NoteDto? current = _note;
    if (current == null ||
        !_capabilities.canDelete ||
        _actionBusy ||
        _currentConflict != null) {
      return;
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final bool? confirmed = await showNoteDetailDeleteConfirmation(
      context: context,
      copy: copy,
      confirmKey: NoteDetailPage.deleteKey,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    _update(() {
      _deleting = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      await widget.notesController.deleteNote(current.id);
      if (mounted) {
        _pop(reason: NoteDetailExitReason.deleted);
      }
    } on Object {
      if (mounted) {
        _update(() => _error = copy.deleteError);
      }
    } finally {
      if (mounted) {
        _update(() => _deleting = false);
      }
    }
  }

  Future<void> _copySummary() async {
    final String? summary = _summaryController.summary;
    if (summary == null || !_canExport) {
      return;
    }
    if (!mounted) {
      return;
    }
    final String copiedMessage = NoteDetailCopy.of(context).copied;
    _update(() {
      _statusMessage = copiedMessage;
      _error = null;
    });
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        buildNoteFlowSnackBar(context: context, message: copiedMessage),
      );
    try {
      await Clipboard.setData(ClipboardData(text: summary));
    } on Object {
      // Keep the in-app feedback usable in widget tests and hosts without a
      // clipboard channel. The native clipboard remains best effort.
    }
  }
}
