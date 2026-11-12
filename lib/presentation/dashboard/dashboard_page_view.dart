part of 'dashboard_page.dart';

extension _DashboardPageView on DashboardPageState {
  Widget _buildBody(
    BuildContext context,
    BoxConstraints constraints,
    DashboardCopy copy, {
    bool? searchOpenOverride,
    String? searchTextOverride,
    bool searchOverlay = false,
    StateSetter? dialogSetState,
  }) {
    final bool searchOpen = searchOpenOverride ?? _searchOpen;
    final String searchText = searchTextOverride ?? _searchText;
    // Match the scaffold's phone classification when a phone rotates.
    final bool compact = NoteFlowLayout.isCompact(
      context,
      availableWidth: constraints.maxWidth,
    );
    if (_isLoading && _notes.isEmpty && !searchOpen) {
      return DashboardLoadingView(key: DashboardPage.loadingKey, copy: copy);
    }
    if (_notesError != null && _notes.isEmpty && !searchOpen) {
      final bool storageUnavailable = _notesError is UnsupportedError;
      return DashboardNotesErrorView(
        copy: copy,
        message: storageUnavailable ? copy.storageUnavailable : null,
        onRetry: storageUnavailable ? null : reload,
      );
    }
    if (_hasError && _notes.isEmpty && !searchOpen) {
      return DashboardErrorView(copy: copy, onRetry: reload);
    }
    if (!_loadingNotes &&
        _notes.isEmpty &&
        !searchOpen &&
        _selectedLabels.isEmpty) {
      return DashboardEmptyView(copy: copy, onCreateNote: _createNote);
    }

    if (dialogSetState != null) _pageDialogState = dialogSetState;
    return DashboardContent(
      page: _notePage,
      pageFooter: _dashboardPageFooter(),
      recentNotes: _recentPageNotes,
      selectedLabels: _selectedLabels,
      onLabelsChanged: (next) {
        _updatePageState(() => _selectedLabels = next);
        _restartPageQuery();
        dialogSetState?.call(() {});
      },
      readable: (note) => widget.notesController is SecuredNotesController
          ? (widget.notesController as SecuredNotesController)
                .capabilitiesFor(note)
                .canRead
          : !note.isProtected && note.contentAvailable,
      notes: _notes,
      overview: widget.dashboardController.state.overview,
      copy: copy,
      searchController: _searchController,
      searchOpen: searchOpen,
      searchText: searchText,
      onCloseSearch: _toggleSearch,
      layout: _layout,
      sort: _sort,
      selectedNoteId: _selectedNoteId,
      hasError: _hasError,
      onSearchChanged: (String value) {
        _updatePageState(() => _searchText = value);
        _restartPageQuery(debounce: true);
        dialogSetState?.call(() {});
      },
      onClearSearch: () {
        _clearSearch();
        dialogSetState?.call(() {});
      },
      onSortChanged: (DashboardSort value) {
        _updatePageState(() => _sort = value);
        _restartPageQuery();
        dialogSetState?.call(() {});
      },
      onLayoutChanged: (DashboardLayout value) {
        _updatePageState(() => _layout = value);
        unawaited(_saveLayout(value));
        dialogSetState?.call(() {});
      },
      onOpenNote: (NoteDto note) => unawaited(_openNote(note)),
      onTogglePin: (NoteDto note) => unawaited(_togglePin(note)),
      onCreateNote: _createNote,
      onRetry: reload,
      onRefresh: reload,
      embeddedInWorkspace: widget.embeddedInWorkspace,
      dockCompactSearch:
          !searchOverlay && compact && widget.embeddedInWorkspace,
      searchOverlay: searchOverlay,
    );
  }

  Widget _buildCompactSearchDock(BuildContext context, DashboardCopy copy) =>
      DashboardSearchDock(
        key: DashboardPage.searchDockKey,
        copy: copy,
        controller: _searchController,
        sort: _sort,
        onChanged: (value) {
          _updatePageState(() => _searchText = value);
          _restartPageQuery(debounce: true);
        },
        onClear: _clearSearch,
        onSortChanged: (value) {
          _updatePageState(() => _sort = value);
          _restartPageQuery();
        },
        onClose: closeSearch,
        fieldKey: DashboardPage.searchFieldKey,
        sortKey: DashboardPage.searchDockSortKey,
        closeKey: DashboardPage.searchDockCloseKey,
      );
}
