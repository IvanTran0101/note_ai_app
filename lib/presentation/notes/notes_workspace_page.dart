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

part 'notes_workspace_view.dart';

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
  StreamSubscription<void>? _securitySubscription;
  int? _securitySession;
  int _loadSequence = 0;

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
    final app = _application;
    if (app is SecuredNotesController) {
      final secured = app as SecuredNotesController;
      _securitySession = secured.sessionGeneration;
      _securitySubscription = secured.securityChanges.listen((_) {
        if (!mounted) return;
        final changed = _securitySession != secured.sessionGeneration;
        _securitySession = secured.sessionGeneration;
        setState(() {
          if (changed) {
            _loadSequence++;
            _notes = const [];
            _selectedNoteId = null;
            _editingNewNote = false;
            _detailDirty = false;
            _error = null;
            _loading = false;
          } else {
            _notes = _notes
                .map(
                  (n) => n.isProtected || !secured.capabilitiesFor(n).canRead
                      ? n.metadataOnly()
                      : n,
                )
                .toList();
          }
        });
        if (!changed) unawaited(_refreshSecurityList());
      });
    }
    unawaited(reload());
  }

  @override
  void dispose() {
    unawaited(_securitySubscription?.cancel());
    super.dispose();
  }

  Future<void> _refreshSecurityList() async {
    final sequence = ++_loadSequence;
    try {
      final notes = await _application.listNotes();
      if (mounted && sequence == _loadSequence) {
        setState(() => _notes = List.unmodifiable(notes));
      }
    } on Object {
      // Keep the already masked projection; retry through the normal list flow.
    }
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
    final sequence = ++_loadSequence;
    try {
      final List<NoteDto> notes = await _application.listNotes();
      if (!mounted || sequence != _loadSequence) {
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
      if (!mounted || sequence != _loadSequence) {
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
    if (note.isProtected) note = note.metadataOnly();
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
    final NoteDto? saved = result.note?.isProtected == true
        ? result.note!.metadataOnly()
        : result.note;
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
  Widget build(BuildContext context) => _buildWorkspace(context);
}
