part of 'note_detail_page.dart';

extension _NoteDetailSecurity on NoteDetailPageState {
  void _retainDirtySharedDraft() {
    final selected = _note;
    final service = _securityController?.noteSecurity;
    if (selected?.share == null ||
        !_isDirty ||
        service == null ||
        !selected!.contentAvailable) {
      return;
    }
    final title = _titleController.text, content = _contentController.text;
    unawaited(
      service.retainEditorDraft(selected, title, content).catchError((
        Object _,
      ) {
        if (mounted) {
          _update(() => _error = NoteSecurityCopy(context).unavailable);
        }
      }),
    );
  }

  SecuredNotesController? get _securityController =>
      widget.notesController is SecuredNotesController
      ? widget.notesController as SecuredNotesController
      : null;
  NoteAccessCapabilities get _capabilities {
    final note = _note;
    if (note == null) {
      return const NoteAccessCapabilities(canRead: true, canEdit: true);
    }
    return _securityController?.capabilitiesFor(note) ??
        (note.isProtected || !note.contentAvailable
            ? const NoteAccessCapabilities()
            : const NoteAccessCapabilities(
                canRead: true,
                canEdit: true,
                canDelete: true,
                canManage: true,
                canSummarize: true,
                canExport: true,
              ));
  }

  bool get _canRead => _capabilities.canRead;
  bool get _canEdit => _capabilities.canEdit;
  bool get _canExport => _capabilities.canExport;

  NoteDto _masked(NoteDto note) => note.metadataOnly();

  void _listenSecurity() {
    _securitySession = _securityController?.sessionGeneration;
    _securitySubscription = _securityController?.securityChanges.listen(
      (_) => _securityChanged(),
    );
    final note = _note;
    if (note != null && (note.isProtected || !_canRead)) {
      _adoptSavedNote(_masked(note));
      unawaited(_readSecuredNote());
    }
  }

  void _securityChanged() {
    if (!mounted) return;
    final note = _note;
    final changedSession =
        _securitySession != _securityController?.sessionGeneration;
    _securitySession = _securityController?.sessionGeneration;
    if (changedSession ||
        (note != null &&
            (!_canRead || (note.share != null && !_canEdit && _isDirty)))) {
      if (!changedSession) _retainDirtySharedDraft();
      _securityRead++;
      _summaryController.cancelActive(reason: SummaryRunFailureCode.noteLocked);
      _summaryController.clearResult();
      _titleFocusNode.unfocus();
      _contentFocusNode.unfocus();
      _update(() {
        _adoptSavedNote(note == null ? null : _masked(note));
        _securityLoading = false;
        _error = null;
        _statusMessage = null;
      });
      _notifyDirtyChanged();
    }
    if (note != null && (note.isProtected || changedSession)) {
      unawaited(_readSecuredNote());
    } else {
      _update(() {});
    }
  }

  Future<void> _readSecuredNote() async {
    final controller = _securityController, note = _note;
    if (controller == null || note == null || !mounted) return;
    final request = ++_securityRead, generation = controller.accessGeneration;
    _update(() => _securityLoading = true);
    try {
      final fresh = await controller.readNote(note.reference);
      if (!mounted ||
          request != _securityRead ||
          _note?.identity != note.identity ||
          generation != controller.accessGeneration) {
        return;
      }
      if (!controller.capabilitiesFor(fresh).canRead) return;
      _update(() {
        if (!_isDirty) {
          _adoptSavedNote(fresh);
        } else if (_rebaseUnchangedSavedText(fresh)) {
          // Protected reads also receive metadata-only ACKs before full text.
        } else {
          _pendingSavedNote = fresh;
        }
      });
    } on NoteSecurityFailure {
      /* Locked view remains safe and available for unlock. */
    } on Object {
      if (mounted && request == _securityRead) {
        _update(() => _error = NoteSecurityCopy(context).unavailable);
      }
    } finally {
      if (mounted && request == _securityRead) {
        _update(() => _securityLoading = false);
      }
    }
  }

  Future<void> _runSecurity(NoteSecurityAction action) async {
    final note = _note, controller = _securityController;
    final service = controller?.noteSecurity;
    if (note == null || service == null || controller == null || _actionBusy) {
      return;
    }
    if (_isDirty && !await _save()) return;
    if (!mounted) return;
    if (action == NoteSecurityAction.lock) {
      service.lock(note.reference);
      return;
    }
    _autosaveTimer?.cancel();
    _summaryController.cancelActive(reason: SummaryRunFailureCode.noteLocked);
    _summaryController.clearResult();
    _update(() => _securityBusy = true);
    try {
      await showNoteSecurityDialog(
        context: context,
        service: service,
        noteId: note.reference,
        action: action,
        serverAvailable: controller.securityServerAvailable,
        sessionEvents: controller.securityChanges,
        isCurrent: () => identical(controller.noteSecurity, service),
      );
      if (mounted) await _readSecuredNote();
    } finally {
      if (mounted) _update(() => _securityBusy = false);
    }
  }

  Widget _securityPanel() {
    final controller = _securityController;
    Widget panel(bool pending) => NoteSecurityPanel(
      localFirst: controller?.noteSecurity?.localFirst ?? false,
      pendingProtection: pending,
      note: _note!,
      locked: !_canRead,
      busy: _actionBusy,
      serverAvailable: controller?.securityServerAvailable ?? false,
      canManage: _capabilities.canManage,
      retained:
          controller?.noteSecurity?.retainedPending(_note!.reference) ?? false,
      onBack: !widget.showAppBar && !_canRead
          ? () => unawaited(_handleBack())
          : null,
      onAction: (action) => unawaited(_runSecurity(action)),
    );
    if (controller?.noteSecurity?.localFirst != true) return panel(false);
    return FutureBuilder<bool>(
      future: controller?.noteSecurity?.hasPendingProtection(_note!.reference),
      builder: (context, pending) => panel(pending.data ?? false),
    );
  }
}
