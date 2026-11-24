part of 'dashboard_page.dart';

extension _DashboardLoading on DashboardPageState {
  Future<void> _clearLoadInFlight(Future<void> operation) async {
    try {
      await operation;
    } finally {
      if (identical(_loadInFlight, operation)) {
        _loadInFlight = null;
        if (_reloadAfterCurrent && mounted) {
          _reloadAfterCurrent = false;
          unawaited(reload());
        }
      }
    }
  }

  void _notesChanged() {
    if (!mounted) return;
    if (_loadInFlight != null) {
      _reloadAfterCurrent = true;
    } else {
      unawaited(reload());
    }
  }

  Future<void> _loadInternal() async {
    final sequence = ++_pageSequence;
    if (mounted) {
      _updatePageState(() {
        _loadingNotes = true;
        _notesError = null;
      });
    }

    try {
      final List<dynamic> results = await Future.wait<dynamic>(
        <Future<dynamic>>[
          _readDashboardPage(),
          widget.dashboardController.load(),
          _readSavedLayout(),
        ],
      );
      if (!mounted || sequence != _pageSequence) {
        return;
      }
      final result =
          results.first
              as ({List<NoteDto> rows, NotePage? page, List<NoteDto> recent});
      _updatePageState(() {
        _notePage = result.page;
        _pageNumber = result.page?.page ?? 0;
        _recentPageNotes = result.recent;
        _notes = List<NoteDto>.unmodifiable(result.rows);
        _loadingNotes = false;
        _notesError = null;
        _layout = results[2] as DashboardLayout;
      });
    } on Object catch (error) {
      if (!mounted || sequence != _pageSequence) {
        return;
      }
      _updatePageState(() {
        _loadingNotes = false;
        _notesError = error;
      });
    }
  }

  Future<DashboardLayout> _readSavedLayout() async {
    final NotesApplicationController controller = widget.notesController;
    if (controller is! NotesModule02Controller) return DashboardLayout.grid;
    final NotesModule02Controller module02Controller =
        controller as NotesModule02Controller;
    try {
      return await module02Controller.getNoteLayout() ==
              NoteLayoutPreference.list
          ? DashboardLayout.list
          : DashboardLayout.grid;
    } on Object {
      return _layout;
    }
  }

  Future<void> _saveLayout(DashboardLayout layout) async {
    final NotesApplicationController controller = widget.notesController;
    if (controller is! NotesModule02Controller) return;
    final NotesModule02Controller module02Controller =
        controller as NotesModule02Controller;
    try {
      await module02Controller.setNoteLayout(
        layout == DashboardLayout.list
            ? NoteLayoutPreference.list
            : NoteLayoutPreference.grid,
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DashboardCopy.of(context).layoutSaveError)),
      );
    }
  }
}
