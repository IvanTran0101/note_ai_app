part of 'note_detail_page.dart';

extension _NoteDetailLabels on NoteDetailPageState {
  Widget? _buildNoteLabels() {
    final note = _note;
    if (note == null) return null;
    return NoteLabelEditor(
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
    );
  }

  Widget? _buildNoteAttachments() {
    if (_richEditor != null) {
      return ListenableBuilder(
        listenable: _inlineFiles,
        builder: (context, _) =>
            !_canRead || (_editorDocument?.inlineAttachments ?? false)
            ? const SizedBox.shrink()
            : _inlineFiles.buildLegacy(context),
      );
    }
    return _buildAttachmentOwner();
  }

  Widget? _buildAttachmentOwner({bool hiddenOwner = false}) {
    final note = _note;
    if (note == null || widget.notesController is! AttachmentNotesController) {
      return null;
    }
    return AttachmentEditorPanel(
      key: ValueKey(note.identity),
      note: note,
      controller: widget.notesController as AttachmentNotesController,
      security: _securityController,
      onChanged: _labelsSaved,
      inlineController: _inlineFiles,
      hiddenOwner: hiddenOwner,
      inlineLayout: _editorDocument?.inlineAttachments ?? false,
      onFilesPicked: (block, ids) async =>
          await _richEditor?.bindFiles(block, ids) ?? false,
      onBeforePick: () async => !_isDirty || await _save(),
      onResumeProtected: () => _resumeProtectedAttachment(note),
      enabled: !_securityBusy && !_securityLoading && _capabilities.canRead,
    );
  }

  void _labelsSaved(NoteDto incoming) {
    if (!_canRead || incoming.identity != _note?.identity) return;
    final previous = _note;
    final previousAttachmentIds = previous!.attachments
        .map((attachment) => attachment.id)
        .toSet();
    final incomingAttachmentIds = incoming.attachments
        .map((attachment) => attachment.id)
        .toSet();
    final previousDocument = previous.document;
    final incomingDocument = incoming.document;
    // Pending local drafts are not in the server-verified manifest yet. Their
    // File IDs still need the same targeted editor reconciliation on cancel.
    if (previousDocument != null && incomingDocument != null) {
      previousAttachmentIds.addAll(previousDocument.attachmentReferenceIds);
      incomingAttachmentIds.addAll(incomingDocument.attachmentReferenceIds);
    }
    final removedAttachmentIds = previousAttachmentIds.difference(
      incomingAttachmentIds,
    );
    if (removedAttachmentIds.isNotEmpty) {
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
      _update(() => _attachmentRemovalReconciliations++);
      final previous = _attachmentRemovalTail;
      _attachmentRemovalTail = () async {
        // ACK order must also be editor-apply order. An older removal waiting
        // for IME must never replace a newer removal's saved baseline.
        try {
          await previous;
        } on Object {
          // A prior failed reconciliation must not strand later canonical ACKs.
        }
        await _acceptAttachmentRemoval(incoming, removedAttachmentIds);
      }();
      unawaited(_attachmentRemovalTail);
      return;
    }
    _update(() {
      // Reuse the ACK rebase: controllers and the dirty saved-text baseline stay.
      if (!_rebaseUnchangedSavedText(incoming)) _pendingSavedNote = incoming;
      _didPersist = true;
      _summaryController.markStaleIfResult();
    });
    _notifyDirtyChanged();
  }

  Future<void> _acceptAttachmentRemoval(
    NoteDto incoming,
    Set<String> removedAttachmentIds,
  ) async {
    try {
      final rich = _richEditor;
      if (rich != null) {
        var applied = false;
        try {
          applied = await rich.removeAttachmentBlocks(removedAttachmentIds);
        } on Object {
          // Keep the canonical Note pending so a failed editor transaction
          // cannot autosave the removed File back into the document.
        }
        if (!mounted || !_canRead || incoming.identity != _note?.identity) {
          return;
        }
        if (!applied) {
          if (_isDirty) {
            _update(() => _pendingSavedNote = incoming);
          } else {
            _update(() => _adoptSavedNote(incoming));
          }
          _notifyDirtyChanged();
          return;
        }
      }

      if (!mounted || !_canRead || incoming.identity != _note?.identity) {
        return;
      }
      _update(() {
        _note = incoming;
        _savedTitle = incoming.title;
        _savedContent = incoming.content;
        _savedDocument = incoming.document;
        rich?.acceptSavedDocument(incoming.document);
        _pendingSavedNote = null;
        _didPersist = true;
        _summaryController.markStaleIfResult();
      });
      _notifyDirtyChanged();
    } finally {
      if (mounted) {
        _update(() {
          if (_attachmentRemovalReconciliations > 0) {
            _attachmentRemovalReconciliations--;
          }
        });
        if (_attachmentRemovalReconciliations == 0 && _isDirty) {
          _scheduleAutosave();
        }
      }
    }
  }
}
