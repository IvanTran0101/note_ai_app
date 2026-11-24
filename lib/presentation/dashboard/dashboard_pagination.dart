part of 'dashboard_page.dart';

extension _DashboardPagination on DashboardPageState {
  void _subscribePageSecurity() {
    unawaited(_pageSecurity?.cancel());
    _pageSecurity = null;
    final controller = widget.notesController;
    if (!supportsNotePages(controller) ||
        controller is! SecuredNotesController) {
      return;
    }
    final secured = controller as SecuredNotesController;
    _pageSession = secured.sessionGeneration;
    _pageSecurity = secured.securityChanges.listen((_) {
      if (!mounted) return;
      final changed = _pageSession != secured.sessionGeneration;
      _pageSession = secured.sessionGeneration;
      _pageSequence++;
      _updatePageState(() {
        // Immediately discard old content and facets before any async read.
        _notes = const [];
        _recentPageNotes = const [];
        _notePage = null;
        if (changed) {
          _pageNumber = 0;
          _selectedLabels = {};
          _searchText = '';
          _searchController.clear();
          _selectedNoteId = null;
        }
      });
      unawaited(_reloadNotePage());
    });
  }

  Future<({List<NoteDto> rows, NotePage? page, List<NoteDto> recent})>
  _readDashboardPage() async {
    final controller = widget.notesController;
    if (!supportsNotePages(controller)) {
      return (
        rows: await controller.listNotes(),
        page: null,
        recent: const <NoteDto>[],
      );
    }
    final generation = controller is SecuredNotesController
        ? (controller as SecuredNotesController).sessionGeneration
        : null;
    final reader = controller as PagedNotesController;
    final page = await reader.listNotePage(
      NotePageQuery(
        page: _pageNumber,
        keyword: _searchText,
        labels: _selectedLabels,
        byCreatedAt: _sort == DashboardSort.created,
      ),
    );
    final recent = await reader.listNotePage(
      NotePageQuery(size: 10, labels: _selectedLabels),
    );
    if (widget.notesController != controller ||
        (controller is SecuredNotesController &&
            (controller as SecuredNotesController).sessionGeneration !=
                generation)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    return (rows: page.notes, page: page, recent: recent.notes);
  }

  void _restartPageQuery({bool debounce = false}) {
    if (!supportsNotePages(widget.notesController)) return;
    _pageNumber = 0;
    _searchPageTimer?.cancel();
    if (debounce) {
      _pageSequence++;
      _updatePageState(() => _loadingNotes = true);
      _searchPageTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) unawaited(_reloadNotePage());
      });
    } else {
      unawaited(_reloadNotePage());
    }
  }

  Future<void> _reloadNotePage() async {
    _searchPageTimer?.cancel();
    final sequence = ++_pageSequence;
    _updatePageState(() {
      _loadingNotes = true;
      _notesError = null;
    });
    if (_desktopSearchDialogOpen) _pageDialogState?.call(() {});
    try {
      final result = await _readDashboardPage();
      if (!mounted || sequence != _pageSequence) return;
      _updatePageState(() {
        _notes = result.rows;
        _notePage = result.page;
        _pageNumber = result.page?.page ?? 0;
        _recentPageNotes = result.recent;
        _loadingNotes = false;
      });
    } on Object catch (error) {
      if (!mounted || sequence != _pageSequence) return;
      _updatePageState(() {
        _loadingNotes = false;
        _notesError = error;
      });
    }
    if (mounted && _desktopSearchDialogOpen) _pageDialogState?.call(() {});
  }

  Widget? _dashboardPageFooter() {
    final page = _notePage;
    if (page == null) return null;
    return NotePageNavigation(
      page: page,
      busy: _loadingNotes,
      onPage: (next) {
        _pageNumber = next;
        unawaited(_reloadNotePage());
      },
    );
  }
}
