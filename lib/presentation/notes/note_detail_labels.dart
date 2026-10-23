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
    _update(() {
      // Reuse the ACK rebase: controllers and the dirty saved-text baseline stay.
      if (!_rebaseUnchangedSavedText(incoming)) _pendingSavedNote = incoming;
      _didPersist = true;
      _summaryController.markStaleIfResult();
    });
    _notifyDirtyChanged();
  }
}
