part of 'attachment_editor_panel.dart';

extension _AttachmentEditorActions on _AttachmentEditorPanelState {
  Future<void> _perform(
    String key,
    Future<void> Function(AttachmentApplicationService) action, {
    bool write = false,
    bool picker = false,
    bool background = false,
  }) async {
    if (!_allowed || write && !_canWrite || _working.contains(key)) return;
    final service = _service;
    if (service == null) return;
    final generation = _generation;
    final authority = picker ? _pickerAuthority : null;
    bool current() =>
        _current(generation) ||
        picker && mounted && _canWrite && _pickerAuthority == authority;
    _update(() {
      _working.add(key);
      if (!background) _error = null;
    });
    try {
      await action(service);
    } on AttachmentAwaitingNoteSync {
      // The panel describes this normal Pending state without a false error.
    } on Object catch (failure) {
      if (current() && (!background || _error == null)) {
        _update(() => _error = _attachmentFailureMessage(failure));
      }
    } finally {
      if (current()) {
        _update(() => _working.remove(key));
        await _reload();
      }
    }
  }

  Future<void> _pick(AttachmentSource source) async {
    if (_busy) return;
    if (widget.onBeforePick != null && !await widget.onBeforePick!()) return;
    if (!mounted || !_canWrite) return;
    await _perform(
      'picker',
      (service) => service.pickAndStage(
        _reference,
        () => widget.controller.pickAttachments(source),
        resumeProtected: widget.onResumeProtected,
      ),
      write: true,
      picker: true,
    );
    if (mounted && _canWrite) {
      await _reload();
      for (final draft in List<LocalAttachmentDraft>.of(_pending)) {
        if (!_canWrite) break;
        await _retry(draft.cacheId, background: true);
      }
    }
  }

  Future<void> _retry(String id, {bool background = false}) async {
    _retryAfter[id] = DateTime.now().add(const Duration(seconds: 30));
    await _perform(
      'upload/$id',
      (service) async {
        final result = await service.retry(_reference, id);
        if (mounted && _canWrite) widget.onChanged?.call(result);
      },
      write: true,
      background: background,
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _remove(_AttachmentItem item) async {
    final generation = _generation;
    final confirmed = await _confirm(
      item.draft == null ? 'Remove attachment?' : 'Remove local attachment?',
      item.draft == null
          ? 'Remove this attachment from the note? Other devices update after sync.'
          : 'The pending encrypted copy on this device will be removed and its upload cancelled.',
    );
    if (!confirmed || !_current(generation) || !_canWrite) return;
    _clearPreview();
    await _perform('remove/${item.id}', (service) async {
      if (item.attachment != null) {
        final result = await service.remove(_reference, item.id);
        if (mounted && _canWrite) widget.onChanged?.call(result);
      } else {
        await service.cancel(_reference, item.id);
      }
    }, write: true);
  }
}

String _attachmentFailureMessage(Object failure) => switch (failure) {
  AttachmentSelectionFailure(:final code) =>
    code == AttachmentSelectionFailureCode.denied
        ? 'File or camera access was denied. Allow access in device settings, or use Add files.'
        : 'This picker is unavailable. Use Add files or choose from the gallery.',
  NoteSecurityFailure(:final code) =>
    {
          NoteSecurityFailureCode.unavailable,
          NoteSecurityFailureCode.network,
          NoteSecurityFailureCode.pendingSync,
        }.contains(code)
        ? 'Cloud attachments are unavailable. Completed local files remain Pending; reconnect and retry.'
        : 'Attachment access changed. Unlock and retry.',
  _ => 'Attachment operation failed. Check file type, size and note quota, then retry. Completed local drafts are retained.',
};
