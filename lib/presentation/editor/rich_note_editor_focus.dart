part of 'rich_note_editor.dart';

/// Recover only the actual editor input after a Web menu semantics commit.
extension _RichNoteEditorInputFocus on _RichNoteEditorState {
  void _restoreMenuInput(
    void Function(VoidCallback, bool) restore,
    bool changedVisibility,
    RichSelectionSnapshot selection,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Web commits the semantics DOM after the Flutter frame. Wait for that
      // commit before checking whether its reordering dropped the input.
      Timer.run(
        () => _restoreCommittedInput(restore, changedVisibility, selection),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _restoreCommittedInput(
    void Function(VoidCallback, bool) restore,
    bool changedVisibility,
    RichSelectionSnapshot captured,
  ) {
    if (!mounted ||
        slash.touchOpen ||
        !widget.adapter.editable ||
        widget.adapter.composing ||
        !widget.adapter.accepts(captured) ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    restore(() {
      final keyboard = widget.adapter.editor.service.keyboardService;
      final selection = widget.adapter.editor.selection;
      if (selection == null) return;
      // Replay focus only for the captured selection. A DOM field can remain
      // focused after a menu transition while its input handlers are inactive.
      keyboard?.enableKeyBoard(selection);
    }, changedVisibility);
  }
}
