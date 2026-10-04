import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import '../common/note_flow_primitives.dart';
import '../notes/notes_application_controller.dart';
import '../notes/note_detail_route_result.dart';
import '../notes/notes_theme_tokens.dart';
import '../workspace/workspace_ui_tokens.dart';
import 'dashboard_content.dart';
import 'dashboard_controller.dart';
import 'dashboard_localizations.dart';
import 'dashboard_state.dart';
import 'dashboard_state_views.dart';
import 'dashboard_view_models.dart';

export 'dashboard_view_models.dart' show DashboardLayout, DashboardSort;

/// Notes-first Dashboard surface for the M5.3 Presentation batch.
///
/// The page owns only orchestration and view state. It uses
/// [DashboardController] for the overview state and the existing
/// [NotesApplicationController] seam for the full note list; neither
/// repository nor Infrastructure types cross into the widget.
final class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.dashboardController,
    required this.notesController,
    required this.onOpenNote,
    required this.onCreateNote,
    this.embeddedInWorkspace = false,
    this.onOpenSettings,
    this.onOpenDiagnostics,
    this.onSearchVisibilityChanged,
    this.noteChanges,
  });

  /// Controller for M5.1/M5.2 overview state.
  final DashboardController dashboardController;

  /// Existing Presentation seam for loading all owned notes.
  final NotesApplicationController notesController;

  /// Opens a selected note in the next Presentation destination.
  ///
  /// The callback may be asynchronous so the Dashboard can refresh its list
  /// after a detail route saves or deletes a note.
  final FutureOr<NoteDetailRouteResult?> Function(NoteDto) onOpenNote;

  /// Starts the create-note flow in the next Presentation destination.
  ///
  /// The callback may be asynchronous so the Dashboard can refresh after the
  /// detail route is dismissed.
  final FutureOr<NoteDetailRouteResult?> Function() onCreateNote;

  /// Whether navigation and global actions are supplied by the host shell.
  final bool embeddedInWorkspace;

  /// Opens the existing appearance settings flow.
  final VoidCallback? onOpenSettings;

  /// Opens the existing diagnostics flow.
  final VoidCallback? onOpenDiagnostics;

  /// Reports the existing search visibility state to a compact host shell.
  final ValueChanged<bool>? onSearchVisibilityChanged;

  /// Account-scoped notifications after durable note/security sync changes.
  final Listenable? noteChanges;

  static const Key searchFieldKey = ValueKey<String>('dashboard-search-field');
  static const Key searchToggleKey = ValueKey<String>(
    'dashboard-search-toggle',
  );
  static const Key searchDockKey = ValueKey<String>('dashboard-search-dock');
  static const Key desktopSearchOverlayKey = ValueKey<String>(
    'dashboard-desktop-search-overlay',
  );
  static const Key desktopSearchSurfaceKey = ValueKey<String>(
    'dashboard-desktop-search-surface',
  );
  static const Key searchDockSortKey = ValueKey<String>(
    'dashboard-search-dock-sort',
  );
  static const Key searchDockCloseKey = ValueKey<String>(
    'dashboard-search-dock-close',
  );
  static const Key newNoteKey = ValueKey<String>('dashboard-create-note');
  static const Key contentKey = ValueKey<String>('dashboard-content');
  static const Key totalCountKey = ValueKey<String>('dashboard-total-count');
  static const Key lastUpdatedKey = ValueKey<String>('dashboard-last-updated');
  static const Key layoutToggleKey = ValueKey<String>(
    'dashboard-layout-toggle',
  );
  static const Key settingsKey = ValueKey<String>('dashboard-open-settings');
  static const Key diagnosticsKey = ValueKey<String>(
    'dashboard-open-diagnostics',
  );
  static const Key emptyCreateKey = ValueKey<String>('dashboard-empty-create');
  static const Key notesErrorKey = ValueKey<String>('dashboard-notes-error');
  static const Key notesRetryKey = ValueKey<String>('dashboard-notes-retry');
  static const Key retryKey = ValueKey<String>('dashboard-retry');
  static const Key emptyStateKey = ValueKey<String>('dashboard-empty');
  static const Key filteredEmptyKey = ValueKey<String>(
    'dashboard-filtered-empty',
  );
  static const Key loadingKey = ValueKey<String>('dashboard-loading');
  static const Key errorKey = ValueKey<String>('dashboard-error');

  @override
  DashboardPageState createState() => DashboardPageState();
}

final class DashboardPageState extends State<DashboardPage> {
  final TextEditingController _searchController = TextEditingController();

  List<NoteDto> _notes = const <NoteDto>[];
  Object? _notesError;
  bool _loadingNotes = true;
  bool _searchOpen = false;
  bool _desktopSearchDialogOpen = false;
  String _searchText = '';
  DashboardLayout _layout = DashboardLayout.grid;
  DashboardSort _sort = DashboardSort.updated;
  String? _selectedNoteId;
  Future<void>? _loadInFlight;
  bool _reloadAfterCurrent = false;

  @override
  void initState() {
    super.initState();
    widget.dashboardController.addListener(_onOverviewStateChanged);
    widget.noteChanges?.addListener(_notesChanged);
    unawaited(reload());
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteChanges != widget.noteChanges) {
      oldWidget.noteChanges?.removeListener(_notesChanged);
      widget.noteChanges?.addListener(_notesChanged);
      _notesChanged();
    }
    if (oldWidget.dashboardController != widget.dashboardController) {
      oldWidget.dashboardController.removeListener(_onOverviewStateChanged);
      widget.dashboardController.addListener(_onOverviewStateChanged);
      unawaited(reload());
    }
  }

  /// Reloads notes and the Dashboard overview after the page becomes active.
  Future<void> reload() {
    final Future<void>? inFlight = _loadInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<void> started = _loadInternal();
    _loadInFlight = started;
    return _clearLoadInFlight(started);
  }

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
    if (mounted) {
      setState(() {
        _loadingNotes = true;
        _notesError = null;
      });
    }

    try {
      final List<dynamic> results = await Future.wait<dynamic>(
        <Future<dynamic>>[
          widget.notesController.listNotes(),
          widget.dashboardController.load(),
          _readSavedLayout(),
        ],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = List<NoteDto>.unmodifiable(results.first as List<NoteDto>);
        _loadingNotes = false;
        _notesError = null;
        _layout = results[2] as DashboardLayout;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
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

  Future<void> _togglePin(NoteDto note) async {
    final NotesApplicationController controller = widget.notesController;
    if (controller is! NotesModule02Controller) return;
    final NotesModule02Controller module02Controller =
        controller as NotesModule02Controller;
    try {
      final NoteDto updated = await module02Controller.setPinned(
        noteId: note.id,
        pinned: note.pinnedAt == null,
      );
      if (!mounted) return;
      setState(() {
        _notes = List<NoteDto>.unmodifiable(
          _notes.map((NoteDto item) => item.id == updated.id ? updated : item),
        );
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DashboardCopy.of(context).pinSaveError)),
      );
    }
  }

  void _onOverviewStateChanged(DashboardState state) {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleSearch() {
    if (_searchOpen) {
      closeSearch();
    } else {
      openSearch();
    }
  }

  /// Opens the existing local Dashboard search flow without toggling it off.
  void openSearch() {
    if (_searchOpen) {
      return;
    }
    final bool showDesktopDialog =
        widget.embeddedInWorkspace &&
        MediaQuery.sizeOf(context).width >= NoteFlowLayout.compactBreakpoint;
    setState(() {
      _searchOpen = true;
      _desktopSearchDialogOpen = showDesktopDialog;
    });
    widget.onSearchVisibilityChanged?.call(true);
    if (showDesktopDialog) {
      unawaited(_showDesktopSearchDialog());
    }
  }

  /// Closes search when the host shell navigates away from the Dashboard.
  void closeSearch() {
    if (!_searchOpen) {
      return;
    }
    final bool closeDesktopDialog = _desktopSearchDialogOpen;
    setState(() {
      _searchOpen = false;
      _desktopSearchDialogOpen = false;
      _searchText = '';
      _searchController.clear();
    });
    widget.onSearchVisibilityChanged?.call(false);
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
          final double verticalShift = MediaQuery.sizeOf(context).height >= 880
              ? -33
              : 0;
          return Transform.translate(
            offset: Offset(0, verticalShift),
            child: Dialog(
              key: DashboardPage.desktopSearchOverlayKey,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: NoteFlowSpacing.xl,
                vertical: NoteFlowSpacing.xxxl,
              ),
              constraints: const BoxConstraints(maxWidth: 1008, maxHeight: 704),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                key: DashboardPage.desktopSearchSurfaceKey,
                width: 1008,
                height: 704,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) =>
                      _buildBody(
                        context,
                        constraints,
                        DashboardCopy.of(context),
                        searchOpenOverride: true,
                        searchOverlay: true,
                        dialogSetState: setDialogState,
                      ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }
    _desktopSearchDialogOpen = false;
    if (_searchOpen) {
      setState(() {
        _searchOpen = false;
        _searchText = '';
        _searchController.clear();
      });
      widget.onSearchVisibilityChanged?.call(false);
    }
  }

  void _clearSearch() {
    setState(() {
      _searchText = '';
      _searchController.clear();
    });
  }

  Future<void> _openNote(NoteDto note) async {
    setState(() => _selectedNoteId = note.id);
    final NoteDetailRouteResult? result = await widget.onOpenNote(note);
    if (mounted && (result?.shouldRefresh ?? false)) {
      await reload();
    }
  }

  void _createNote() {
    unawaited(_openCreateNote());
  }

  Future<void> _openCreateNote() async {
    final NoteDetailRouteResult? result = await widget.onCreateNote();
    if (mounted && (result?.shouldRefresh ?? false)) {
      await reload();
    }
  }

  bool get _isLoading =>
      _loadingNotes || widget.dashboardController.state.isLoading;

  bool get _hasError =>
      _notesError != null || widget.dashboardController.state.hasError;

  @override
  Widget build(BuildContext context) {
    final DashboardCopy copy = DashboardCopy.of(context);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 600;
    final bool wide = width >= 840;
    final bool expanded = width >= 840 && widget.embeddedInWorkspace;
    return Scaffold(
      backgroundColor: colors.surface,
      bottomNavigationBar: compact && widget.embeddedInWorkspace && _searchOpen
          ? _buildCompactSearchDock(context, copy)
          : null,
      appBar: compact && widget.embeddedInWorkspace
          ? null
          : AppBar(
              toolbarHeight: wide ? 44 : null,
              title: Text(
                '${copy.workspaceLabel} / ${copy.title}',
                key: const ValueKey<String>('dashboard-page-breadcrumb'),
              ),
              titleTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              actions: <Widget>[
                if (!expanded || !widget.embeddedInWorkspace)
                  IconButton(
                    key: DashboardPage.searchToggleKey,
                    tooltip: _searchOpen ? copy.closeSearch : copy.search,
                    icon: Icon(_searchOpen ? Icons.close : Icons.search),
                    onPressed: _toggleSearch,
                  ),
                if ((!expanded || !widget.embeddedInWorkspace) &&
                    widget.onOpenSettings != null)
                  IconButton(
                    key: DashboardPage.settingsKey,
                    tooltip: copy.settings,
                    icon: const Icon(Icons.tune_outlined),
                    onPressed: widget.onOpenSettings,
                  ),
                if ((!expanded || !widget.embeddedInWorkspace) &&
                    widget.onOpenDiagnostics != null)
                  IconButton(
                    key: DashboardPage.diagnosticsKey,
                    tooltip: copy.diagnostics,
                    icon: const Icon(Icons.monitor_heart_outlined),
                    onPressed: widget.onOpenDiagnostics,
                  ),
              ],
            ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return NoteFlowStateTransition(
            child: _buildBody(
              context,
              constraints,
              copy,
              searchOpenOverride: _desktopSearchDialogOpen ? false : null,
              searchTextOverride: _desktopSearchDialogOpen ? '' : null,
            ),
          );
        },
      ),
    );
  }

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
    final bool compact =
        constraints.maxWidth < NoteFlowLayout.compactBreakpoint;
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
    if (!_loadingNotes && _notes.isEmpty && !searchOpen) {
      return DashboardEmptyView(copy: copy, onCreateNote: _createNote);
    }

    return DashboardContent(
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
        setState(() => _searchText = value);
        dialogSetState?.call(() {});
      },
      onClearSearch: () {
        _clearSearch();
        dialogSetState?.call(() {});
      },
      onSortChanged: (DashboardSort value) {
        setState(() => _sort = value);
        dialogSetState?.call(() {});
      },
      onLayoutChanged: (DashboardLayout value) {
        setState(() => _layout = value);
        unawaited(_saveLayout(value));
        dialogSetState?.call(() {});
      },
      onOpenNote: (NoteDto note) => unawaited(_openNote(note)),
      onTogglePin: (NoteDto note) => unawaited(_togglePin(note)),
      onCreateNote: _createNote,
      onRetry: reload,
      onRefresh: reload,
      embeddedInWorkspace: widget.embeddedInWorkspace,
      dockCompactSearch: compact && widget.embeddedInWorkspace,
      searchOverlay: searchOverlay,
    );
  }

  Widget _buildCompactSearchDock(BuildContext context, DashboardCopy copy) {
    final NoteFlowWorkspaceTokens tokens = NoteFlowWorkspaceTokens.of(context);
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: tokens.divider),
    );
    return KeyedSubtree(
      key: DashboardPage.searchDockKey,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NoteFlowSpacing.md,
            NoteFlowSpacing.sm,
            NoteFlowSpacing.xs,
            NoteFlowSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: DashboardPage.searchFieldKey,
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (String value) =>
                      setState(() => _searchText = value),
                  decoration: InputDecoration(
                    hintText: copy.searchNotes,
                    isDense: true,
                    filled: true,
                    fillColor: tokens.subtleSurface,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchText.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey<String>(
                              'dashboard-clear-search-field',
                            ),
                            tooltip: copy.clearSearch,
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSearch,
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: NoteFlowSpacing.md,
                      vertical: NoteFlowSpacing.sm,
                    ),
                    border: border,
                    enabledBorder: border.copyWith(
                      borderSide: BorderSide(color: tokens.divider),
                    ),
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(color: tokens.focusRing),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<DashboardSort>(
                key: DashboardPage.searchDockSortKey,
                tooltip: copy.sort,
                initialValue: _sort,
                onSelected: (DashboardSort value) =>
                    setState(() => _sort = value),
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<DashboardSort>>[
                      PopupMenuItem<DashboardSort>(
                        value: DashboardSort.updated,
                        child: Text(copy.sortUpdated),
                      ),
                      PopupMenuItem<DashboardSort>(
                        value: DashboardSort.created,
                        child: Text(copy.sortCreated),
                      ),
                    ],
                child: SizedBox.square(
                  dimension: 48,
                  child: Tooltip(
                    message: copy.sort,
                    child: Icon(Icons.sort, color: tokens.textSecondary),
                  ),
                ),
              ),
              IconButton(
                key: DashboardPage.searchDockCloseKey,
                tooltip: copy.closeSearch,
                onPressed: closeSearch,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.noteChanges?.removeListener(_notesChanged);
    widget.dashboardController.removeListener(_onOverviewStateChanged);
    _searchController.dispose();
    super.dispose();
  }
}
