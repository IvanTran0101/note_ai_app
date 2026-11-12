import '../../application/labels/note_query.dart';
import '../labels/label_catalog_scope.dart';

import 'dart:async';

import '../../application/notes/note_page.dart';
import '../../application/notes/note_access.dart';
import '../notes/note_page_navigation.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'dashboard_search_dock.dart';
import 'dashboard_search_dialog.dart';
import 'dashboard_state.dart';
import 'dashboard_state_views.dart';
import 'dashboard_view_models.dart';

export 'dashboard_view_models.dart' show DashboardLayout, DashboardSort;

part 'dashboard_pagination.dart';
part 'dashboard_page_view.dart';
part 'dashboard_loading.dart';
part 'dashboard_search_actions.dart';

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

  void _updatePageState(VoidCallback action) => setState(action);
  StreamSubscription<void>? _pageSecurity;
  int? _pageSession;
  Timer? _searchPageTimer;
  NotePage? _notePage;
  int _pageNumber = 0;
  int _pageSequence = 0;
  StateSetter? _pageDialogState;
  List<NoteDto> _recentPageNotes = const [];
  List<NoteDto> _notes = const <NoteDto>[];
  Object? _notesError;
  bool _loadingNotes = true;
  bool _searchOpen = false;
  bool _desktopSearchDialogOpen = false;
  String _searchText = '';
  Set<LabelSelection> _selectedLabels = {};
  String? _labelActor;
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
    _subscribePageSecurity();
    unawaited(reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final actor = LabelCatalogScope.maybeOf(context)?.application
        ?.currentActor();
    if (_labelActor != actor) {
      _labelActor = actor;
      _selectedLabels = {};
      _searchText = '';
      _searchController.clear();
    }
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notesController != widget.notesController) {
      _pageSequence++;
      _subscribePageSecurity();
      if (supportsNotePages(widget.notesController)) _restartPageQuery();
    }
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
      if (supportsNotePages(widget.notesController)) {
        await _reloadNotePage();
      }
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

  void openSearch() => _openDashboardSearch();
  void closeSearch() => _closeDashboardSearch();

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
    final bool compact = NoteFlowLayout.isCompact(context);
    final bool wide = width >= 840;
    final bool expanded = width >= 840 && widget.embeddedInWorkspace;
    return Scaffold(
      backgroundColor: compact && (!_searchOpen || !kIsWeb)
          ? NoteFlowWorkspaceTokens.of(context).compactHomeSurface
          : colors.surface,
      bottomNavigationBar:
          compact &&
              widget.embeddedInWorkspace &&
              _searchOpen &&
              !_desktopSearchDialogOpen
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

  @override
  void dispose() {
    _searchPageTimer?.cancel();
    unawaited(_pageSecurity?.cancel());
    widget.noteChanges?.removeListener(_notesChanged);
    widget.dashboardController.removeListener(_onOverviewStateChanged);
    _searchController.dispose();
    super.dispose();
  }
}
