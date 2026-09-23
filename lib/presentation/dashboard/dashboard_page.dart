import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import '../notes/notes_application_controller.dart';
import '../notes/note_detail_route_result.dart';
import '../notes/notes_theme_tokens.dart';
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

  static const Key searchFieldKey = ValueKey<String>('dashboard-search-field');
  static const Key searchToggleKey = ValueKey<String>(
    'dashboard-search-toggle',
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
  String _searchText = '';
  DashboardLayout? _layoutOverride;
  DashboardSort _sort = DashboardSort.updated;
  String? _selectedNoteId;
  Future<void>? _loadInFlight;

  @override
  void initState() {
    super.initState();
    widget.dashboardController.addListener(_onOverviewStateChanged);
    unawaited(reload());
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      }
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
        ],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = List<NoteDto>.unmodifiable(results.first as List<NoteDto>);
        _loadingNotes = false;
        _notesError = null;
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

  void _onOverviewStateChanged(DashboardState state) {
    if (mounted) {
      setState(() {});
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchText = '';
        _searchController.clear();
      }
    });
  }

  /// Opens the existing local Dashboard search flow without toggling it off.
  void openSearch() {
    if (_searchOpen) {
      return;
    }
    setState(() => _searchOpen = true);
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
          return _buildBody(context, constraints, copy);
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    BoxConstraints constraints,
    DashboardCopy copy,
  ) {
    if (_isLoading && _notes.isEmpty) {
      return DashboardLoadingView(key: DashboardPage.loadingKey, copy: copy);
    }
    if (_notesError != null && _notes.isEmpty) {
      final bool storageUnavailable = _notesError is UnsupportedError;
      return DashboardNotesErrorView(
        copy: copy,
        message: storageUnavailable ? copy.storageUnavailable : null,
        onRetry: storageUnavailable ? null : reload,
      );
    }
    if (_hasError && _notes.isEmpty) {
      return DashboardErrorView(copy: copy, onRetry: reload);
    }
    if (!_loadingNotes && _notes.isEmpty) {
      return DashboardEmptyView(copy: copy, onCreateNote: _createNote);
    }

    return DashboardContent(
      notes: _notes,
      overview: widget.dashboardController.state.overview,
      copy: copy,
      searchController: _searchController,
      searchOpen: _searchOpen,
      searchText: _searchText,
      layout:
          _layoutOverride ??
          (constraints.maxWidth >= NoteFlowLayout.expandedBreakpoint
              ? DashboardLayout.grid
              : DashboardLayout.list),
      sort: _sort,
      selectedNoteId: _selectedNoteId,
      hasError: _hasError,
      onSearchChanged: (String value) => setState(() => _searchText = value),
      onClearSearch: _clearSearch,
      onSortChanged: (DashboardSort value) => setState(() => _sort = value),
      onLayoutChanged: (DashboardLayout value) =>
          setState(() => _layoutOverride = value),
      onOpenNote: (NoteDto note) => unawaited(_openNote(note)),
      onCreateNote: _createNote,
      onRetry: reload,
      onRefresh: reload,
    );
  }

  @override
  void dispose() {
    widget.dashboardController.removeListener(_onOverviewStateChanged);
    _searchController.dispose();
    super.dispose();
  }
}
