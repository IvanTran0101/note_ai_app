part of 'attachment_editor_panel.dart';

extension _AttachmentInlineTransfer on _AttachmentEditorPanelState {
  Future<void> _recoverPendingForBlock(String blockId) async {
    if (!_canWrite || _busy) return;
    if (widget.onBeforePick != null && !await widget.onBeforePick!()) return;
    if (!mounted || !_canWrite) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_canWrite) return;

    final service = _service;
    if (service == null) return;
    final authority = _pickerAuthority;
    bool current() => _samePickerResource(authority);
    bool sameResource() => _samePickerResource(authority);
    const key = 'recover/inline';
    _update(() {
      _working.add(key);
      _error = null;
      _inlineErrorBlock = null;
    });
    try {
      final pending = await service.pending(_reference);
      if (!current()) return;
      _update(() => _pending = pending);
      final ids = _unboundPendingDrafts()
          .map((draft) => draft.cacheId)
          .toList(growable: false);
      if (ids.isEmpty) return;

      final bindPicked = widget.onFilesPicked;
      if (bindPicked == null) {
        _setRecoveryError(blockId);
        _showPendingRecoveryFeedback(context);
        return;
      }
      final bound = await bindPicked(blockId, ids);
      if (!bound) {
        if (sameResource()) {
          _setRecoveryError(blockId);
          _showPendingRecoveryFeedback(context);
        }
        return;
      }
      if (!current()) return;
      _update(() {
        _error = null;
        _inlineErrorBlock = null;
      });
      await _reload();
    } on Object catch (failure) {
      if (current()) {
        _update(() {
          _error = _attachmentFailureMessage(failure);
          _inlineErrorBlock = blockId;
        });
      }
    } finally {
      if (sameResource()) _update(() => _working.remove(key));
    }
  }

  void _setRecoveryError(String blockId) {
    _update(() {
      _error = 'The file is saved locally. Retry local files to attach it.';
      _inlineErrorBlock = blockId;
    });
  }

  void _showPendingRecoveryFeedback(BuildContext anchorContext) {
    if (!anchorContext.mounted) return;
    ScaffoldMessenger.maybeOf(anchorContext)?.showSnackBar(
      const SnackBar(
        content: Text(
          'File is saved on this device. Insert a File block and tap Retry local files.',
        ),
      ),
    );
  }

  bool _samePickerResource(
    ({
      int? session,
      String note,
      bool protected,
      int protectionRevision,
      int? accessRevision,
      int contentRevision,
    })
    authority,
  ) {
    final current = _pickerAuthority;
    return mounted &&
        _canWrite &&
        current.session == authority.session &&
        current.note == authority.note &&
        current.protected == authority.protected &&
        current.protectionRevision == authority.protectionRevision &&
        current.accessRevision == authority.accessRevision;
  }

  Future<void> _pickForBlock(String blockId, AttachmentSource source) async {
    if (_busy || !_canWrite) return;
    if (widget.onBeforePick != null && !await widget.onBeforePick!()) return;
    if (!mounted || !_canWrite) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_canWrite) return;

    final service = _service;
    if (service == null) return;
    final authority = _pickerAuthority;
    bool current() => _samePickerResource(authority);
    bool sameResource() => _samePickerResource(authority);

    final before = <String>{...widget.note.attachments.map((item) => item.id)};
    try {
      before.addAll(
        (await service.pending(_reference)).map((item) => item.cacheId),
      );
    } on Object catch (failure) {
      if (sameResource()) {
        _update(() {
          _error = _attachmentFailureMessage(failure);
          _inlineErrorBlock = blockId;
        });
      }
      return;
    }
    if (!current()) return;
    _update(() {
      _error = null;
      _inlineErrorBlock = null;
    });

    var selectionCompleted = false;
    await _perform(
      'picker/$blockId',
      (attachmentService) async {
        await attachmentService.pickAndStage(
          _reference,
          () => widget.controller.pickAttachments(source),
          resumeProtected: widget.onResumeProtected,
        );
        selectionCompleted = true;
      },
      write: true,
      picker: true,
      deferReload: true,
    );
    if (!current()) return;
    if (!selectionCompleted) {
      _update(() => _inlineErrorBlock = blockId);
      return;
    }

    late final List<LocalAttachmentDraft> after;
    try {
      after = await service.pending(_reference);
    } on Object catch (failure) {
      if (sameResource()) {
        _update(() {
          _error = _attachmentFailureMessage(failure);
          _inlineErrorBlock = blockId;
        });
        _showPendingRecoveryFeedback(context);
      }
      return;
    }
    if (!current()) return;

    final pickedIds = after
        .map((item) => item.cacheId)
        .where((id) => !before.contains(id))
        .toList(growable: false);
    _update(() {
      _pending = after;
      _error = null;
      _inlineErrorBlock = null;
    });
    if (pickedIds.isEmpty) {
      // A dismissed chooser is a normal outcome; keep the empty block in place.
      return;
    }

    final bindPicked = widget.onFilesPicked;
    if (bindPicked == null) {
      _setRecoveryError(blockId);
      _showPendingRecoveryFeedback(context);
      return;
    }

    bool bound;
    try {
      bound = await bindPicked(blockId, pickedIds);
    } on Object catch (failure) {
      if (sameResource()) {
        _update(() {
          _error = _attachmentFailureMessage(failure);
          _inlineErrorBlock = blockId;
        });
        _showPendingRecoveryFeedback(context);
      }
      return;
    }
    if (!bound) {
      if (sameResource()) {
        _setRecoveryError(blockId);
        _showPendingRecoveryFeedback(context);
      }
      return;
    }
    if (!current()) return;

    _update(() {
      _error = null;
      _inlineErrorBlock = null;
    });
    await _reload();
  }
}
