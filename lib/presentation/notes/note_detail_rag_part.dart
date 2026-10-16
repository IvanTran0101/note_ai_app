// Citation reveal and edit reporting for the note editor.
//
// These helpers are additive to the editor lifecycle: they never mutate the
// saved note, never save, never unlock protection, and never import a RAG/domain
// type. A reveal is a plain [TextSelection] into the content controller; an edit
// report is the saved [NoteDto] the editor currently shows.
part of 'note_detail_page.dart';

/// One request to reveal an exact citation span in the open editor.
///
/// A new instance is created for every citation open, so the editor can tell
/// "apply this span again" apart from "same span, no new request" even when the
/// same note stays open and the widget is updated rather than recreated.
final class NoteDetailSelectionRequest {
  /// Wraps one content-editor [TextSelection].
  NoteDetailSelectionRequest(this.selection);

  /// The half-open UTF-16 span to reveal.
  final TextSelection selection;
}

extension _NoteDetailRag on NoteDetailPageState {
  /// Applies [request] once, after the editor has a chance to lay out.
  ///
  /// The token makes an older request stand down when a newer one arrives
  /// before the frame callback runs, so the newest citation always wins. The
  /// saved note's immutable facts, including its title, and the exact text the
  /// citation was resolved against are captured here, before the frame; the
  /// post-frame callback only reveals the span when they are still current. A
  /// revision/title/content/protection change, a draft, a busy editor, a lost
  /// read capability, or a superseding request all refuse, so an arbitrary newer
  /// text at the same offsets is never highlighted.
  void _applySelectionRequest(NoteDetailSelectionRequest request) {
    final int token = ++_selectionRequestToken;
    final NoteDto? captured = _note;
    final String? capturedId = captured?.id;
    final String? capturedOwnerId = captured?.ownerId;
    final String? capturedTitle = captured?.title;
    final int? capturedRevision = captured?.contentRevision;
    final String? capturedContent = captured?.content;
    final bool? capturedProtected = captured?.isProtected;
    final bool? capturedAvailable = captured?.contentAvailable;
    final Object? capturedShare = captured?.share;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _selectionRequestToken) return;
      if (captured == null) return;
      final NoteDto? current = _note;
      if (current == null ||
          current.id != capturedId ||
          current.ownerId != capturedOwnerId ||
          current.title != capturedTitle ||
          current.contentRevision != capturedRevision ||
          current.content != capturedContent ||
          current.isProtected != capturedProtected ||
          current.contentAvailable != capturedAvailable ||
          current.share != capturedShare) {
        return;
      }
      if (_isDirty || _actionBusy || !_canRead) return;
      if (_contentController.text != capturedContent) return;
      if (_titleController.text != capturedTitle) return;
      _revealSelection(request.selection);
    });
  }

  /// Highlights [selection] without treating it as a draft edit.
  ///
  /// The edit listener is detached for the assignment because a selection
  /// change fires the controller's listeners; reattaching immediately keeps the
  /// ordinary edit path intact. Focus and reveal run after the frame, and only
  /// when the span is still valid inside the current text.
  void _revealSelection(TextSelection selection) {
    final String content = _contentController.text;
    if (!_isRevealableSelection(selection, content)) return;
    final rich = _richEditor;
    if (rich != null) {
      final projection = EditorProjectionMap(rich.editor.document);
      if (projection.plainText != content) return;
      final mapped = projection.selection(selection.start, selection.end);
      if (mapped == null) return;
      for (final node in rich.editor.getNodesInSelection(mapped)) {
        for (var parent = node.parent; parent != null; parent = parent.parent) {
          if (parent.type == 'm09_toggle') {
            rich.expandedToggles[parent.attributes['m09_id'] as String] = true;
          }
        }
      }
      rich.refreshAccess();
      rich.editor.selection = mapped;
      _contentFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(rich, _richEditor)) return;
        final target = rich.editor.document
            .nodeAtPath(mapped.start.path)
            ?.key
            .currentContext;
        if (target != null) {
          unawaited(Scrollable.ensureVisible(target, alignment: .35));
        }
      });
      return;
    }
    _contentController.removeListener(_editorChanged);
    try {
      _contentController.selection = selection;
    } finally {
      _contentController.addListener(_editorChanged);
    }
    if (!_contentFocusNode.hasFocus) {
      _contentFocusNode.requestFocus();
    }
    scheduleNoteDetailContentFocus(
      focusNode: _contentFocusNode,
      fieldKey: _contentFieldContextKey,
    );
  }

  /// Whether [selection] is a non-empty half-open span inside [content] whose
  /// boundaries fall on code-point boundaries (so a surrogate pair is never
  /// bisected).
  bool _isRevealableSelection(TextSelection selection, String content) {
    final int start = selection.start;
    final int end = selection.end;
    if (start < 0 || end > content.length || end <= start) return false;
    for (final int offset in <int>[start, end]) {
      if (offset > 0 &&
          offset < content.length &&
          _isLowSurrogate(content.codeUnitAt(offset)) &&
          _isHighSurrogate(content.codeUnitAt(offset - 1))) {
        return false;
      }
    }
    return true;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// Reports one real title/text edit of the saved note to the composition root.
  ///
  /// A new draft has no saved note, so it reports nothing here; the editor's
  /// existing `onDirtyChanged` still tells its host about the draft. The report
  /// fires before the autosave timer is scheduled.
  void _notifyNoteEdited() {
    final NoteDto? note = _note;
    if (note == null || !_isDirty) return;
    widget.onNoteEdited?.call(note);
  }

  /// Whether the current note may offer the ask-notes action.
  ///
  /// Only a saved, owned, synced, unprotected, unshared note with no live draft
  /// or operation qualifies. The application service still revalidates every
  /// local precondition before a question is admitted.
  bool get _canOpenNoteRag {
    final NoteDto? note = _note;
    return widget.onOpenNoteRag != null &&
        note != null &&
        !note.isProtected &&
        note.contentAvailable &&
        note.share == null &&
        note.contentRevision > 0 &&
        _canRead &&
        !_isDirty &&
        !_actionBusy;
  }

  /// The compact ask-notes action shown next to the editor.
  Widget _buildNoteRagAction(BuildContext context) {
    final bool vi = Localizations.localeOf(context).languageCode == 'vi';
    return IconButton(
      key: NoteDetailPage.askNotesKey,
      tooltip: vi ? 'Hỏi ghi chú' : 'Ask notes',
      onPressed: () {
        final NoteDto? note = _note;
        if (note != null) widget.onOpenNoteRag?.call(note);
      },
      icon: const Icon(Icons.forum_outlined, size: 18),
    );
  }
}
