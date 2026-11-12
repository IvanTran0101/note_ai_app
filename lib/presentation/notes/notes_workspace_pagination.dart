part of 'notes_workspace_page.dart';

extension _NotesWorkspacePagination on NotesWorkspacePageState {
  Future<void> _clearLoadInFlight(Future<void> operation) async {
    try {
      await operation;
    } finally {
      if (identical(_loadInFlight, operation)) {
        _loadInFlight = null;
      }
    }
  }

  Future<void> _loadNotesInternal() async {
    _pageQueryTimer?.cancel();
    final sequence = ++_loadSequence;
    if (mounted) _update(() => _pageBusy = true);
    try {
      final result = await _readWorkspacePage();
      final notes = result.rows;
      if (!mounted || sequence != _loadSequence) {
        return;
      }
      _update(() {
        _notePage = result.page;
        _pageNumber = result.page?.page ?? 0;
        _pageBusy = false;
        if (result.page != null) {
          _unavailableSelection = result.selected;
        } else {
          _preserveSelection(notes);
        }
        _notes = List<NoteDto>.unmodifiable(notes);
        _error = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || sequence != _loadSequence) {
        return;
      }
      _update(() {
        _error = error;
        _pageBusy = false;
        _loading = false;
      });
    }
  }

  Future<({List<NoteDto> rows, NotePage? page, NoteDto? selected})>
  _readWorkspacePage() async {
    final app = _application;
    if (!supportsNotePages(app)) {
      return (
        rows: sortNotes(await _listAllNotes()),
        page: null,
        selected: null,
      );
    }
    final selected = _selectedNote;
    final page = await (app as PagedNotesController).listNotePage(
      NotePageQuery(
        page: _pageNumber,
        scope: _sharedOnly ? NotePageScope.shared : NotePageScope.owned,
        keyword: _pageKeyword,
        labels: _pageLabels,
      ),
    );
    NoteDto? detached;
    if (selected != null &&
        !page.notes.any((n) => n.identity == selected.identity)) {
      // Moving/filtering a page is not a revoke. Re-read authority separately;
      // a denied/missing note only retains redacted evidence for the editor.
      detached = selected;
      if (app is SecuredNotesController) {
        try {
          detached = await (app as SecuredNotesController).readNote(
            selected.reference,
          );
        } on Object {
          detached = selected.metadataOnly();
          // Existing editor guard observes the unavailable projection.
        }
      }
    }
    return (rows: page.notes, page: page, selected: detached);
  }

  void _changePageQuery(String keyword, Set<LabelSelection> labels) {
    final typing = keyword != _pageKeyword;
    _pageQueryTimer?.cancel();
    _update(() {
      _pageNumber = 0;
      _pageKeyword = keyword;
      _pageLabels = Set.of(labels);
    });
    if (typing) {
      _loadSequence++;
      _update(() => _pageBusy = true);
      _pageQueryTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) unawaited(_loadNotesInternal());
      });
    } else {
      unawaited(_loadNotesInternal());
    }
  }

  Widget? _workspacePageFooter() {
    final page = _notePage;
    if (page == null) return null;
    return NotePageNavigation(
      page: page,
      busy: _pageBusy || _detailBusy,
      onPage: (next) {
        _update(() => _pageNumber = next);
        unawaited(_loadNotesInternal());
      },
    );
  }
}
