part of 'dashboard_page.dart';

extension _DashboardSearchActions on DashboardPageState {
  /// Opens the existing local Dashboard search flow without toggling it off.
  void _openDashboardSearch() {
    if (_searchOpen) {
      return;
    }
    // Web keeps its modal Search UX even when opened from a narrow window.
    // Native phones retain the bottom-docked Search presentation.
    final bool showDesktopDialog =
        widget.embeddedInWorkspace &&
        (kIsWeb || !NoteFlowLayout.isCompact(context));
    _updatePageState(() {
      _searchOpen = true;
      _desktopSearchDialogOpen = showDesktopDialog;
    });
    widget.onSearchVisibilityChanged?.call(true);
    if (showDesktopDialog) {
      unawaited(_showDesktopSearchDialog());
    }
  }

  /// Closes search when the host shell navigates away from the Dashboard.
  void _closeDashboardSearch() {
    if (!_searchOpen) {
      return;
    }
    final bool closeDesktopDialog = _desktopSearchDialogOpen;
    _updatePageState(() {
      _searchOpen = false;
      _desktopSearchDialogOpen = false;
      _searchText = '';
      _searchController.clear();
    });
    widget.onSearchVisibilityChanged?.call(false);
    _pageDialogState = null;
    _restartPageQuery();
    if (closeDesktopDialog) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _showDesktopSearchDialog() async {
    await showDialog<void>(
      context: context,
      animationStyle: NoteFlowMotion.dialogStyle(context),
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: const Color(0x26000000),
      builder: (BuildContext _) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return DashboardSearchDialog(
            key: DashboardPage.desktopSearchOverlayKey,
            surfaceKey: DashboardPage.desktopSearchSurfaceKey,
            builder: (BuildContext context, BoxConstraints constraints) =>
                _buildBody(
                  context,
                  constraints,
                  DashboardCopy.of(context),
                  searchOpenOverride: true,
                  searchOverlay: true,
                  dialogSetState: setDialogState,
                ),
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    _desktopSearchDialogOpen = false;
    _pageDialogState = null;
    if (_searchOpen) {
      _updatePageState(() {
        _searchOpen = false;
        _searchText = '';
        _searchController.clear();
      });
      widget.onSearchVisibilityChanged?.call(false);
      _restartPageQuery();
    }
  }

  void _clearSearch() {
    _updatePageState(() {
      _searchText = '';
      _searchController.clear();
    });
    _restartPageQuery();
  }
}
