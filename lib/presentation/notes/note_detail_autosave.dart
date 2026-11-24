part of 'note_detail_page.dart';

/// Editor edit/focus listeners schedule one existing Application save path.
extension _NoteDetailAutosave on NoteDetailPageState {
  void _editorChanged() {
    if (!mounted) return;
    final String title = _titleController.text;
    final String content = _contentController.text;
    if (title == _lastEditorTitle && content == _lastEditorContent) {
      // A selection, cursor, or composing-only update is not an edit: it must
      // not move the draft revision, cancel a run, schedule a save, or report.
      return;
    }
    _lastEditorTitle = title;
    _lastEditorContent = content;
    _recordEditorChange();
  }

  void _notifyDirtyChanged() {
    final bool dirty = _isDirty;
    if (dirty == _lastReportedDirty) {
      return;
    }
    _lastReportedDirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  void _contentFocusChanged() {
    scheduleNoteDetailContentFocus(
      focusNode: _contentFocusNode,
      fieldKey: _contentFieldContextKey,
    );
    _saveWhenEditorLosesFocus();
  }

  void _titleFocusChanged() {
    _saveWhenEditorLosesFocus();
  }

  void _saveWhenEditorLosesFocus() {
    if (_ignoreNextEditorFocusLoss &&
        !_titleFocusNode.hasFocus &&
        !_contentFocusNode.hasFocus) {
      _ignoreNextEditorFocusLoss = false;
      return;
    }
    if (!_backConfirmationVisible &&
        !_titleFocusNode.hasFocus &&
        !_contentFocusNode.hasFocus) {
      _scheduleAutosave(immediate: true);
    }
  }

  void _scheduleAutosave({bool immediate = false}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (!mounted ||
        !_isDirty ||
        !_canEdit ||
        _backConfirmationVisible ||
        _conflictFlowActive ||
        _currentConflict != null) {
      return;
    }
    if (immediate) {
      // A back click also moves focus. Let its confirmation cancel this save
      // before persisting, so Discard remains meaningful on every platform.
      _autosaveTimer = Timer(Duration.zero, () {
        _autosaveTimer = null;
        if (!_backConfirmationVisible) unawaited(_save(automatic: true));
      });
      return;
    }
    _autosaveTimer = Timer(NoteDetailPageState._autosaveDelay, () {
      _autosaveTimer = null;
      unawaited(_save(automatic: true));
    });
  }
}
