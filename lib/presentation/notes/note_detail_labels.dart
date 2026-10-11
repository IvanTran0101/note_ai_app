part of 'note_detail_page.dart';

extension _NoteDetailLabels on NoteDetailPageState {
  Widget? _buildNoteExtras() {
    final note = _note;
    if (note == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NoteLabelEditor(
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
        ),
      ],
    );
  }

  Widget _buildAttachmentTray() {
    final note = _note;
    final controller = widget.notesController;
    return ExcludeFocus(
      excluding: !_attachmentTrayOpen,
      child: Offstage(
        offstage: !_attachmentTrayOpen,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Attachments',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Flexible(flex: 2, child: _attachmentAddMenu(labeled: true)),
                  IconButton(
                    tooltip: 'Close attachments',
                    onPressed: () => _update(() => _attachmentTrayOpen = false),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              if (note == null || controller is! AttachmentNotesController)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text('No attachments'),
                )
              else
                AttachmentEditorPanel(
                  key: _attachmentKey,
                  note: note,
                  controller:
                      widget.notesController as AttachmentNotesController,
                  security: _securityController,
                  onChanged: _labelsSaved,
                  onBeforePick: () async => !_isDirty || await _save(),
                  showAddAction: false,
                  compact: true,
                  onItemsChanged: (count) {
                    if (mounted && _attachmentCount != count) {
                      _update(() => _attachmentCount = count);
                    }
                  },
                  onBusyChanged: (busy) {
                    if (mounted && _attachmentBusy != busy) {
                      _update(() => _attachmentBusy = busy);
                    }
                  },
                  onResumeProtected: () => _resumeProtectedAttachment(note),
                  enabled:
                      !_securityBusy &&
                      !_securityLoading &&
                      _capabilities.canRead,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFromToolbar(AttachmentSource source) async {
    if (!_canEdit ||
        (_note != null && !_capabilities.canManage) ||
        (_actionBusy && !_saving) ||
        _attachmentBusy) {
      return;
    }
    final editorGeneration = _editorGeneration;
    final sessionGeneration = _securityController?.sessionGeneration;
    // Opening a menu may already have started focus-loss autosave.
    if ((_saving || _note == null || _isDirty) && !await _save()) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        editorGeneration != _editorGeneration ||
        sessionGeneration != _securityController?.sessionGeneration ||
        !_canEdit ||
        !_capabilities.canManage ||
        _actionBusy ||
        _attachmentBusy) {
      return;
    }
    _update(() => _attachmentTrayOpen = true);
    await _attachmentKey.currentState?.pick(source);
  }

  Widget _attachmentToolbarAction() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Attachments',
        isSelected: _attachmentTrayOpen,
        onPressed:
            _canRead && widget.notesController is AttachmentNotesController
            ? () => _update(() => _attachmentTrayOpen = !_attachmentTrayOpen)
            : null,
        icon: Badge.count(
          count: _attachmentCount ?? _note?.attachments.length ?? 0,
          isLabelVisible:
              (_attachmentCount ?? _note?.attachments.length ?? 0) > 0,
          child: const Icon(Icons.attach_file, size: 21),
        ),
      ),
      _attachmentAddMenu(),
    ],
  );

  Widget _attachmentAddMenu({bool labeled = false}) {
    final enabled =
        !_actionBusy &&
        !_attachmentBusy &&
        (_note == null || _capabilities.canManage) &&
        _canEdit &&
        widget.notesController is AttachmentNotesController;
    final label = Localizations.localeOf(context).languageCode == 'vi'
        ? 'Thêm tệp đính kèm'
        : 'Add attachment';
    return PopupMenuButton<AttachmentSource>(
      key: labeled ? const ValueKey('note-attachment-tray-add') : null,
      requestFocus: true,
      tooltip: label,
      enabled: enabled,
      icon: labeled ? null : const Icon(Icons.add, size: 22),
      popUpAnimationStyle: NoteFlowMotion.dialogStyle(context),
      onSelected: (source) => unawaited(_pickFromToolbar(source)),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: AttachmentSource.files,
          child: Text('Choose files'),
        ),
        PopupMenuItem(
          value: AttachmentSource.gallery,
          child: Text('Photos & videos'),
        ),
        PopupMenuItem(
          value: AttachmentSource.cameraPhoto,
          child: Text('Take photo'),
        ),
        PopupMenuItem(
          value: AttachmentSource.cameraVideo,
          child: Text('Record video'),
        ),
      ],
      child: labeled
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 20,
                      color: enabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).disabledColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: enabled
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).disabledColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
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
