part of 'note_detail_page.dart';

extension _NoteDetailSharing on NoteDetailPageState {
  bool _rebaseUnchangedSavedText(NoteDto incoming) {
    final previous = _note;
    if (previous == null ||
        incoming.identity != previous.identity ||
        !incoming.contentAvailable ||
        incoming.contentRevision < previous.contentRevision ||
        incoming.isProtected != previous.isProtected ||
        incoming.protectionRevision != previous.protectionRevision ||
        incoming.share != previous.share ||
        incoming.title != _savedTitle ||
        incoming.content != _savedContent ||
        incoming.document != _savedDocument) {
      return false;
    }
    // An ACK can advance revision/timestamps while the user types a new draft.
    // Keep that draft and compare the next save against the acknowledged base.
    _note = incoming;
    _pendingSavedNote = null;
    _scheduleAutosave();
    return true;
  }

  bool get _hasRemoteEditorChange {
    final fresh = _pendingSavedNote, old = _note;
    return fresh != null &&
        old != null &&
        fresh.contentAvailable &&
        (fresh.contentRevision != old.contentRevision ||
            fresh.title != old.title ||
            fresh.content != old.content ||
            fresh.document != old.document);
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
                          _update(() {
                            _adoptSavedNote(_pendingSavedNote);
                            _error = null;
                          });
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
        _savedDocument = fresh.document;
        _richEditor?.acceptSavedDocument(fresh.document);
        _pendingSavedNote = null;
        _error = null;
      });
      await _save();
    } on Object {
      if (mounted) _update(() => _error = NoteDetailCopy.of(context).saveError);
    }
  }

  Widget _sharingPanel({bool compact = false}) {
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
    final trigger = _sharingTrigger(copy, compact: compact);
    return compact
        ? trigger
        : Align(alignment: Alignment.centerRight, child: trigger);
  }

  Widget _sharingTrigger(SharingCopy copy, {required bool compact}) => Builder(
    builder: (triggerContext) {
      final onPressed = _actionBusy
          ? null
          : () => _manageSharing(triggerContext: triggerContext);
      if (compact) {
        return IconButton(
          key: const ValueKey('manage-note-sharing'),
          tooltip: copy.manage,
          onPressed: onPressed,
          icon: Icon(
            NoteFlowLayout.isCompact(context)
                ? Icons.ios_share
                : Icons.people_outline,
            size: NoteFlowLayout.isCompact(context) ? 22 : 20,
          ),
        );
      }
      return TextButton.icon(
        key: const ValueKey('manage-note-sharing'),
        icon: const Icon(Icons.people_outline),
        label: Text(copy.manage),
        onPressed: onPressed,
      );
    },
  );

  double? _sharingAnchorInset(BuildContext? triggerContext) {
    if (!kIsWeb || triggerContext == null || !triggerContext.mounted) {
      return null;
    }
    final trigger = triggerContext.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    if (trigger is! RenderBox ||
        overlay is! RenderBox ||
        !trigger.attached ||
        !overlay.attached ||
        !trigger.hasSize ||
        !overlay.hasSize) {
      return null;
    }
    final right = overlay
        .globalToLocal(trigger.localToGlobal(Offset(trigger.size.width, 0)))
        .dx;
    return (overlay.size.width - right)
        .clamp(0.0, overlay.size.width)
        .toDouble();
  }

  Future<void> _manageSharing({BuildContext? triggerContext}) async {
    final anchorInset = _sharingAnchorInset(triggerContext);
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
    final compact = NoteFlowLayout.isCompact(context) && !kIsWeb;
    await showDialog<void>(
      context: context,
      useSafeArea: !compact,
      barrierColor: compact ? Colors.black54 : Colors.transparent,
      builder: (_) {
        final dialog = ShareManagementDialog(
          service: service,
          webAnchorInset: anchorInset,
          identity: _note!.identity,
          sessionEvents: secured?.securityChanges ?? const Stream<void>.empty(),
          isCurrent: () =>
              mounted &&
              identical(controller.sharing, service) &&
              secured?.sessionGeneration == generation &&
              _capabilities.canManage,
        );
        // The compact sheet paints behind the navbar; its content consumes the
        // bottom inset. Keep the route clear of the top and side cutouts here.
        return compact ? SafeArea(bottom: false, child: dialog) : dialog;
      },
    );
  }
}
