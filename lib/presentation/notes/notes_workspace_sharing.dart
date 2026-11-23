part of 'notes_workspace_page.dart';

extension _NotesWorkspaceSharing on NotesWorkspacePageState {
  Future<List<NoteDto>> _listAllNotes() async {
    final app = _application;
    final results = await Future.wait([
      app.listNotes(),
      if (app is SharingNotesController)
        (app as SharingNotesController).listSharedNotes(),
    ]);
    return results.expand((rows) => rows).toList(growable: false);
  }

  void _workspaceSyncChanged() {
    final state = widget.syncController?.localState;
    if (!mounted || state == null || identical(state, _lastSyncState)) return;
    _lastSyncState = state;
    unawaited(_refreshSecurityList());
  }

  void _preserveSelection(List<NoteDto> incoming) {
    final selected = _selectedNote;
    if (selected != null &&
        !incoming.any((n) => n.identity == selected.identity)) {
      // Keep the same editor key for its access-loss callback; only metadata
      // survives in the parent. Received-note removal is never an owner delete.
      _unavailableSelection = selected.metadataOnly();
    } else {
      _unavailableSelection = null;
    }
  }

  Widget _sharingTabs() {
    final copy = SharingCopy(context);
    final tokens = NoteFlowUiTokens.of(context);
    Widget tab(String label, String key, bool shared) => ChoiceChip(
      key: ValueKey(key),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: tokens.textSecondary,
      ),
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: Colors.transparent,
      selectedColor: tokens.textPrimary.withValues(alpha: .07),
      showCheckmark: false,
      selected: _sharedOnly == shared,
      onSelected: (_) => _chooseSharingTab(shared),
    );
    return Wrap(
      spacing: 8,
      children: [
        tab(NotesCopy.of(context).notes, 'owned-notes-tab', false),
        tab(copy.sharedWithMe, 'shared-notes-tab', true),
      ],
    );
  }

  void _chooseSharingTab(bool shared) {
    if (shared == _sharedOnly) return;
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    _update(() {
      _sharedOnly = shared;
      _selectedNoteId = null;
      _unavailableSelection = null;
      _editingNewNote = false;
    });
  }
}
