part of 'note_detail_page.dart';

/// Rich editor lifecycle and draft snapshots. The page still uses one Application
/// writer; its plaintext controller mirrors only the derived search/AI projection.
extension _NoteDetailDocument on NoteDetailPageState {
  NoteDocument? get _editorDocument =>
      _richEditor?.document ??
      (widget.notesController is DocumentNotesController
          ? null
          : _note?.document);
  void _resetRichEditor() {
    final old = _richEditor;
    _richEditor = null;
    _editorEpoch++;
    _savedDocument = _note?.document;
    old?.dispose();
    if (widget.notesController is! DocumentNotesController || !_canRead) return;
    final epoch = _editorEpoch;
    final session = _securityController?.sessionGeneration;
    final initial = _note == null ? NoteDocument(const []) : _note?.document;
    if (_note == null) _savedDocument = initial;
    _richEditor = RichEditorAdapter(
      document: initial,
      legacyText: _savedContent,
      canEdit: () => _canEdit && !_securityBusy && !_securityLoading,
      canRead: () => _canRead && !_securityLoading,
      isLive: () =>
          mounted &&
          epoch == _editorEpoch &&
          session == _securityController?.sessionGeneration,
      accessGeneration: () =>
          _securityController?.accessGeneration ?? _editorEpoch,
      onChanged: _richDocumentChanged,
    );
  }

  void _richDocumentChanged() {
    if (!mounted || _richEditor == null) return;
    _contentController.removeListener(_editorChanged);
    _contentController.text = _richEditor!.plainText;
    _contentController.addListener(_editorChanged);
    _lastEditorContent = _contentController.text;
    _lastEditorTitle = _titleController.text;
    _recordEditorChange();
  }

  void _recordEditorChange() {
    _summaryController.cancelActive(reason: SummaryRunFailureCode.noteChanged);
    if (_isDirty) {
      _summaryController.markStaleIfResult();
    } else if (_pendingSavedNote != null && !_saving) {
      _adoptSavedNote(_pendingSavedNote);
    }
    _ignoreNextEditorFocusLoss = false;
    _update(() {
      if (!_isDirty) _statusMessage = null;
    });
    _notifyDirtyChanged();
    _notifyNoteEdited();
    _scheduleAutosave();
  }

  Widget _richEditorWidget(Widget header, Widget footer) {
    final adapter = _richEditor;
    if (adapter == null) return const SizedBox.shrink();
    return KeyedSubtree(
      key: NoteDetailPage.contentFieldKey,
      child: RichNoteEditor(
        key: ObjectKey(adapter),
        adapter: adapter,
        focusNode: _contentFocusNode,
        header: header,
        footer: footer,
      ),
    );
  }

  void _adoptSavedNote(NoteDto? incoming) {
    final previous = _note, rich = _richEditor;
    final preserveRich =
        rich != null &&
        rich.isLive() &&
        incoming != null &&
        previous != null &&
        incoming.identity == previous.identity &&
        incoming.contentAvailable &&
        _canRead &&
        incoming.share == previous.share &&
        incoming.isProtected == previous.isProtected &&
        incoming.protectionRevision == previous.protectionRevision &&
        incoming.document == _editorDocument &&
        incoming.content == _contentController.text;
    _pendingSavedNote = null;
    _autosaveTimer?.cancel();
    _titleController.removeListener(_editorChanged);
    _contentController.removeListener(_editorChanged);
    _note = incoming;
    _savedTitle = incoming?.title ?? '';
    _savedContent = incoming?.content ?? '';
    if (_titleController.text != _savedTitle) {
      _titleController.text = _savedTitle;
    }
    if (_contentController.text != _savedContent) {
      _contentController.text = _savedContent;
    }
    _lastEditorTitle = _titleController.text;
    _lastEditorContent = _contentController.text;
    if (preserveRich) {
      _savedDocument = incoming.document;
      rich.acceptSavedDocument(incoming.document);
    } else {
      _resetRichEditor();
    }
    _titleController.addListener(_editorChanged);
    _contentController.addListener(_editorChanged);
    _summaryController.clearFailure();
  }
}
