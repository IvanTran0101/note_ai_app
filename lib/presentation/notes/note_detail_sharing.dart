part of 'note_detail_page.dart';

extension _NoteDetailSharing on _NoteDetailPageState {
  bool get _hasRemoteEditorChange {
    final fresh = _pendingSavedNote, old = _note;
    return fresh != null &&
        old != null &&
        fresh.contentAvailable &&
        (fresh.contentRevision != old.contentRevision ||
            fresh.title != old.title ||
            fresh.content != old.content);
  }

  Widget _remoteEditorNotice() {
    final copy = SharingCopy(context);
    return Card(
      key: const ValueKey('editor-remote-change'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(copy.remoteChanged),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('editor-use-cloud'),
                  onPressed: _actionBusy
                      ? null
                      : () {
                          _update(() => _adoptSavedNote(_pendingSavedNote));
                          _notifyDirtyChanged();
                        },
                  child: Text(copy.useCloud),
                ),
                TextButton(
                  key: const ValueKey('editor-review-local'),
                  onPressed: _actionBusy ? null : _reviewEditorDraft,
                  child: Text(copy.useLocal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewEditorDraft() async {
    final controller = _securityController;
    final old = _note;
    if (controller == null || old == null) return;
    final session = controller.sessionGeneration;
    try {
      final fresh = await controller.readNote(old.reference);
      if (!mounted ||
          session != controller.sessionGeneration ||
          _note?.identity != old.identity ||
          !controller.capabilitiesFor(fresh).canEdit) {
        return;
      }
      _update(() {
        _note = fresh;
        _savedTitle = fresh.title;
        _savedContent = fresh.content;
        _pendingSavedNote = null;
        _error = null;
      });
      await _save();
    } on Object {
      if (mounted) _update(() => _error = NoteDetailCopy.of(context).saveError);
    }
  }

  Widget _sharingPanel() {
    final note = _note!;
    final copy = SharingCopy(context);
    if (note.share != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          copy.metadata(note.share!),
          key: const ValueKey('shared-note-access'),
        ),
      );
    }
    if (!_capabilities.canManage ||
        widget.notesController is! SharingNotesController) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const ValueKey('manage-note-sharing'),
        icon: const Icon(Icons.people_outline),
        label: Text(copy.manage),
        onPressed: _actionBusy ? null : _manageSharing,
      ),
    );
  }

  Future<void> _manageSharing() async {
    if (_isDirty && !await _save()) return;
    if (!mounted || !_capabilities.canManage) return;
    final controller = widget.notesController as SharingNotesController;
    final service = controller.sharing;
    if (service == null) {
      _update(() => _error = SharingCopy(context).onlineOnly);
      return;
    }
    final secured = _securityController;
    final generation = secured?.sessionGeneration;
    await showDialog<void>(
      context: context,
      builder: (_) => ShareManagementDialog(
        service: service,
        identity: _note!.identity,
        sessionEvents: secured?.securityChanges ?? const Stream<void>.empty(),
        isCurrent: () =>
            mounted &&
            identical(controller.sharing, service) &&
            secured?.sessionGeneration == generation &&
            _capabilities.canManage,
      ),
    );
  }
}
