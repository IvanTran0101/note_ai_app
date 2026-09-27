import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/notes/note_application.dart';
import 'note_detail_page.dart';
import 'note_detail_route_result.dart';
import 'note_flow_snackbar.dart';
import 'notes_application_controller.dart';
import 'notes_list_panel.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';
import 'notes_workspace_loading_view.dart';
import 'responsive_notes_workspace.dart';
import '../sync/sync_presentation_controller.dart';
import '../sync/sync_widgets.dart';

/// Responsive Notes workspace for the shell's Notes destination.
///
/// This page owns only presentation selection state. Note mutations and AI
/// calls continue to flow through [NotesApplicationController]. Every
/// breakpoint uses the Notes content area for one surface at a time: the list
/// or the focused Note Detail page.
final class NotesWorkspacePage extends StatefulWidget {
  const NotesWorkspacePage({
    super.key,
    this.applicationService,
    this.controller,
    this.embeddedInWorkspace = false,
    this.onOpenSettings,
    this.onOpenDiagnostics,
    this.provisioningReader,
    this.onProvisioningCancel,
    this.syncController,
  }) : assert(
         applicationService != null || controller != null,
         'Provide applicationService or controller.',
       );

  final NoteApplicationService? applicationService;
  final NotesApplicationController? controller;
  final bool embeddedInWorkspace;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenDiagnostics;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningCancel;
  final SyncPresentationController? syncController;

  @override
  NotesWorkspacePageState createState() => NotesWorkspacePageState();
}

final class NotesWorkspacePageState extends State<NotesWorkspacePage> {
  String? _detailKeyIdentity;
  GlobalKey<State<StatefulWidget>> _detailWidgetKey =
      GlobalKey<State<StatefulWidget>>();
  List<NoteDto> _notes = const <NoteDto>[];
  String? _selectedNoteId;
  bool _editingNewNote = false;
  bool _detailDirty = false;
  Object? _error;
  bool _loading = true;
  Future<void>? _loadInFlight;

  NotesApplicationController get _application {
    final NotesApplicationController? controller = widget.controller;
    if (controller != null) {
      return controller;
    }
    final NoteApplicationService? service = widget.applicationService;
    if (service != null) {
      return NoteApplicationServiceController(service);
    }
    throw StateError('NotesWorkspacePage requires an application dependency.');
  }

  NoteDto? get _selectedNote {
    final String? id = _selectedNoteId;
    if (id == null) {
      return null;
    }
    for (final NoteDto note in _notes) {
      if (note.id == id) {
        return note;
      }
    }
    return null;
  }

  Key _detailKeyFor(String identity) {
    if (_detailKeyIdentity != identity) {
      _detailKeyIdentity = identity;
      _detailWidgetKey = GlobalKey<State<StatefulWidget>>(
        debugLabel: 'notes-workspace-detail-$identity',
      );
    }
    return _detailWidgetKey;
  }

  /// Whether the current inline detail has edits that have not been saved.
  bool get hasUnsavedChanges => _detailDirty;

  bool get _showDetail => _editingNewNote || _selectedNote != null;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Reloads the list after the page becomes active.
  Future<void> reload() {
    final Future<void>? inFlight = _loadInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<void> started = _loadNotesInternal();
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

  Future<void> _loadNotesInternal() async {
    try {
      final List<NoteDto> notes = await _application.listNotes();
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = List<NoteDto>.unmodifiable(notes);
        _selectedNoteId = null;
        _editingNewNote = false;
        _detailDirty = false;
        _error = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectNote(NoteDto note) {
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    setState(() {
      _selectedNoteId = note.id;
      _editingNewNote = false;
      _error = null;
    });
  }

  void _startNewNote() {
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    setState(() {
      _selectedNoteId = null;
      _editingNewNote = true;
    });
  }

  /// Opens the existing create-note editor inside the workspace shell.
  void startNewNote() => _startNewNote();

  /// Selects an existing note in the workspace editor.
  void openNote(NoteDto note) {
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    final List<NoteDto> next = List<NoteDto>.of(_notes);
    final int index = next.indexWhere((NoteDto item) => item.id == note.id);
    if (index == -1) {
      next.add(note);
    } else {
      next[index] = note;
    }
    setState(() {
      _notes = List<NoteDto>.unmodifiable(next);
      _selectedNoteId = note.id;
      _editingNewNote = false;
      _error = null;
      _loading = false;
    });
  }

  void _handleDetailDirtyChanged(bool dirty) {
    if (mounted && _detailDirty != dirty) {
      setState(() => _detailDirty = dirty);
    }
  }

  void _handleDetailExit(NoteDetailRouteResult result) {
    final NoteDto? saved = result.note;
    final String? selectedId = _selectedNoteId;
    final List<NoteDto> next = List<NoteDto>.of(_notes);

    switch (result.reason) {
      case NoteDetailExitReason.saved:
        if (saved != null) {
          final int index = next.indexWhere(
            (NoteDto note) => note.id == saved.id,
          );
          if (index == -1) {
            next.add(saved);
          } else {
            next[index] = saved;
          }
        }
      case NoteDetailExitReason.deleted:
        if (selectedId != null) {
          next.removeWhere((NoteDto note) => note.id == selectedId);
        }
      case NoteDetailExitReason.discarded:
      case NoteDetailExitReason.cancelled:
        break;
    }

    setState(() {
      _notes = List<NoteDto>.unmodifiable(next);
      _selectedNoteId = null;
      _editingNewNote = false;
      _detailDirty = false;
      if (result.reason == NoteDetailExitReason.saved ||
          result.reason == NoteDetailExitReason.deleted) {
        _error = null;
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(buildNoteFlowSnackBar(context: context, message: message));
  }

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    final bool persistenceUnavailable = _error is UnsupportedError;
    final String? loadError = _error == null
        ? null
        : persistenceUnavailable
        ? copy.persistenceUnavailable
        : copy.loadError;
    final bool compact =
        MediaQuery.sizeOf(context).width <
        ResponsiveNotesWorkspace.compactBreakpoint;
    return Scaffold(
      appBar: _showDetail || (compact && widget.embeddedInWorkspace)
          ? null
          : _buildWorkspaceAppBar(copy),
      body: _loading
          ? NotesWorkspaceLoadingView(copy: copy)
          : Column(
              children: <Widget>[
                if (widget.syncController
                    case final SyncPresentationController sync)
                  SyncStatusPanel(controller: sync),
                Expanded(
                  child: ResponsiveNotesWorkspace(
                    list: NotesListPanel(
                      notes: _notes,
                      selectedNoteId: _selectedNoteId,
                      error: loadError,
                      actionBusy: false,
                      onNewNote: _startNewNote,
                      onSelectNote: _selectNote,
                      onRetry: persistenceUnavailable ? null : reload,
                    ),
                    detail: _buildDetail(
                      copy,
                      showAppBar: compact && !widget.embeddedInWorkspace,
                    ),
                    hasSelection: _showDetail,
                  ),
                ),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildWorkspaceAppBar(NotesCopy copy) {
    final bool expanded =
        MediaQuery.sizeOf(context).width >= 840 && widget.embeddedInWorkspace;
    return AppBar(
      title: Text(copy.notes),
      actions:
          expanded ||
              widget.onOpenSettings == null && widget.onOpenDiagnostics == null
          ? null
          : <Widget>[
              if (!expanded && widget.onOpenSettings != null) _settingsAction(),
              if (!expanded && widget.onOpenDiagnostics != null)
                TextButton(
                  key: const ValueKey<String>('open-diagnostics'),
                  onPressed: widget.onOpenDiagnostics,
                  child: Text(copy.diagnostics),
                ),
            ],
    );
  }

  Widget _buildDetail(NotesCopy copy, {required bool showAppBar}) {
    if (!_showDetail) {
      final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
      if (_error != null) {
        final bool persistenceUnavailable = _error is UnsupportedError;
        final String errorMessage = persistenceUnavailable
            ? copy.persistenceUnavailable
            : copy.loadError;
        return Center(
          key: const ValueKey<String>('notes-workspace-detail-error'),
          child: Semantics(
            liveRegion: true,
            container: true,
            label: errorMessage,
            child: Padding(
              padding: const EdgeInsets.all(NoteFlowSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 32,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(height: NoteFlowSpacing.sm),
                  Text(
                    errorMessage,
                    key: const ValueKey<String>(
                      'notes-workspace-detail-error-message',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.textSecondary),
                  ),
                  if (!persistenceUnavailable) ...<Widget>[
                    const SizedBox(height: NoteFlowSpacing.xs),
                    TextButton.icon(
                      key: const ValueKey<String>(
                        'notes-workspace-detail-retry',
                      ),
                      onPressed: reload,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(copy.retry),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Center(
        key: const ValueKey<String>('notes-workspace-detail-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.description_outlined, size: 40, color: tokens.textMuted),
            const SizedBox(height: NoteFlowSpacing.sm),
            Text(
              copy.createFirstNote,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      );
    }
    final NoteDto? note = _selectedNote;
    return NoteDetailPage(
      key: _detailKeyFor(note?.id ?? 'new'),
      notesController: _application,
      note: note,
      provisioningReader: widget.provisioningReader,
      onProvisioningCancel: widget.onProvisioningCancel,
      showAppBar: showAppBar,
      onEmbeddedExit: _handleDetailExit,
      onDirtyChanged: _handleDetailDirtyChanged,
      syncController: widget.syncController,
    );
  }

  Widget _settingsAction() {
    final NotesCopy copy = NotesCopy.of(context);
    return IconButton(
      key: const ValueKey<String>('open-settings'),
      tooltip: copy.appearanceAndLanguage,
      icon: const Icon(Icons.tune_outlined),
      onPressed: widget.onOpenSettings,
    );
  }
}
