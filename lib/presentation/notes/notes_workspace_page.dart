import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/notes/note_application.dart';
import 'note_ordering.dart';
import 'note_detail_page.dart';
import 'note_detail_route_result.dart';
import 'note_flow_snackbar.dart';
import 'notes_application_controller.dart';
import 'notes_list_panel.dart';
import 'sharing_localizations.dart';
import 'notes_localizations.dart';
import 'notes_theme_tokens.dart';
import 'notes_workspace_loading_view.dart';
import 'responsive_notes_workspace.dart';
import '../sync/sync_presentation_controller.dart';
import '../sync/sync_widgets.dart';

part 'notes_workspace_view.dart';
part 'notes_workspace_sharing.dart';

/// Responsive Notes workspace for the shell's Notes destination.
///
/// This page owns only presentation selection state. Note mutations and AI
/// calls continue to flow through [NotesApplicationController]. The same editor
/// opens as a side peek, center peek, or full page according to the canvas.
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
  GlobalKey<NoteDetailPageState> _detailWidgetKey =
      GlobalKey<NoteDetailPageState>();
  List<NoteDto> _notes = const <NoteDto>[];
  String? _selectedNoteId;
  NoteDto? _unavailableSelection;
  bool _editingNewNote = false;
  bool _sharedOnly = false;
  Object? _lastSyncState;
  bool _detailDirty = false;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  NoteLayoutPreference _layout = NoteLayoutPreference.grid;
  bool _layoutBusy = false;
  int _layoutSequence = 0;
  String? _pinningNoteId;
  Future<void>? _loadInFlight;
  StreamSubscription<void>? _securitySubscription;
  int? _securitySession;
  int _loadSequence = 0;
  void _update(VoidCallback action) => setState(action);

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
      if (note.reference == id) {
        return note;
      }
    }
    return _unavailableSelection?.reference == id
        ? _unavailableSelection
        : null;
  }

  Key _detailKeyFor(String identity) {
    if (_detailKeyIdentity != identity) {
      _detailKeyIdentity = identity;
      _detailWidgetKey = GlobalKey<NoteDetailPageState>(
        debugLabel: 'notes-workspace-detail-$identity',
      );
    }
    return _detailWidgetKey;
  }

  /// Includes pending work so the host cannot reload away the active editor.
  bool get hasUnsavedChanges => _detailDirty || _detailBusy;

  bool get _detailBusy =>
      _detailWidgetKey.currentState?.hasActiveOperation ?? false;

  bool get _showDetail => _editingNewNote || _selectedNote != null;

  Future<void> _requestDetailClose() =>
      _detailWidgetKey.currentState?.requestClose() ?? Future<void>.value();

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
            _layoutSequence++;
            _layout = NoteLayoutPreference.grid;
            _layoutBusy = false;
            _pinningNoteId = null;
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
        if (changed) {
          unawaited(_loadLayout());
        } else {
          unawaited(_refreshSecurityList());
        }
      });
    }
    widget.syncController?.addListener(_workspaceSyncChanged);
    unawaited(reload());
    unawaited(_loadLayout());
  }

  @override
  void dispose() {
    unawaited(_securitySubscription?.cancel());
    widget.syncController?.removeListener(_workspaceSyncChanged);
    super.dispose();
  }

  Future<void> _refreshSecurityList() async {
    final sequence = ++_loadSequence;
    try {
      final notes = sortNotes(await _listAllNotes());
      if (mounted && sequence == _loadSequence) {
        setState(() {
          _preserveSelection(notes);
          _notes = List.unmodifiable(notes);
        });
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
        if (mounted) setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _loadNotesInternal() async {
    final sequence = ++_loadSequence;
    setState(() => _refreshing = true);
    try {
      final List<NoteDto> notes = sortNotes(await _listAllNotes());
      if (!mounted || sequence != _loadSequence) {
        return;
      }
      setState(() {
        _preserveSelection(notes);
        _notes = List<NoteDto>.unmodifiable(notes);
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

  Future<void> _loadLayout() async {
    final app = _application;
    if (app is! NotesModule02Controller) return;
    final sequence = ++_layoutSequence;
    setState(() => _layoutBusy = true);
    try {
      final layout = await (app as NotesModule02Controller).getNoteLayout();
      if (mounted && sequence == _layoutSequence) {
        setState(() => _layout = layout);
      }
    } on Object {
      if (mounted && sequence == _layoutSequence) {
        _showCollectionFailure(
          NotesCopy.of(context).layoutLoadError,
          () => unawaited(_loadLayout()),
        );
      }
    } finally {
      if (mounted && sequence == _layoutSequence) {
        setState(() => _layoutBusy = false);
      }
    }
  }

  Future<void> _changeLayout(NoteLayoutPreference layout) async {
    final app = _application;
    if (app is! NotesModule02Controller || _layoutBusy || layout == _layout) {
      return;
    }
    final sequence = ++_layoutSequence;
    setState(() => _layoutBusy = true);
    try {
      await (app as NotesModule02Controller).setNoteLayout(layout);
      if (mounted && sequence == _layoutSequence) {
        setState(() => _layout = layout);
      }
    } on Object {
      if (mounted && sequence == _layoutSequence) {
        _showCollectionFailure(
          NotesCopy.of(context).layoutSaveError,
          () => unawaited(_changeLayout(layout)),
        );
      }
    } finally {
      if (mounted && sequence == _layoutSequence) {
        setState(() => _layoutBusy = false);
      }
    }
  }

  bool _canPin(NoteDto note) {
    final app = _application;
    return app is NotesModule02Controller &&
        note.share == null &&
        (app is SecuredNotesController
            ? (app as SecuredNotesController).capabilitiesFor(note).canManage
            : !note.isProtected && note.contentAvailable);
  }

  Future<void> _togglePin(NoteDto note) async {
    if (!_canPin(note) ||
        _detailBusy ||
        _detailDirty ||
        _pinningNoteId != null) {
      return;
    }
    final session = _securitySession;
    setState(() => _pinningNoteId = note.reference);
    try {
      final saved = await (_application as NotesModule02Controller).setPinned(
        noteId: note.reference,
        pinned: !note.isPinned,
      );
      if (!mounted || session != _securitySession) return;
      setState(() {
        _notes = List.unmodifiable(
          sortNotes(
            _notes.map((current) {
              if (current.identity != saved.identity) return current;
              return saved.isProtected ? saved.metadataOnly() : saved;
            }),
          ),
        );
      });
      _showMessage(
        saved.isPinned
            ? NotesCopy.of(context).pinned
            : NotesCopy.of(context).unpinned,
      );
    } on Object {
      if (mounted && session == _securitySession) {
        _showCollectionFailure(
          NotesCopy.of(context).pinError,
          () => unawaited(_togglePin(note)),
        );
      }
    } finally {
      if (mounted && session == _securitySession) {
        setState(() => _pinningNoteId = null);
      }
    }
  }

  void _showCollectionFailure(String message, VoidCallback retry) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        buildNoteFlowSnackBar(
          context: context,
          message: message,
          action: SnackBarAction(
            label: NotesCopy.of(context).retry,
            onPressed: retry,
          ),
        ),
      );
  }

  void _selectNote(NoteDto note) {
    if (_detailBusy) return;
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    setState(() {
      _unavailableSelection = null;
      _selectedNoteId = note.reference;
      _editingNewNote = false;
      _error = null;
    });
  }

  void _startNewNote() {
    if (_detailBusy) return;
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    setState(() {
      _unavailableSelection = null;
      _selectedNoteId = null;
      _sharedOnly = false;
      _editingNewNote = true;
    });
  }

  /// Opens the existing create-note editor inside the workspace shell.
  void startNewNote() => _startNewNote();

  /// Selects an existing note in the workspace editor.
  void openNote(NoteDto note) {
    if (_detailBusy) return;
    if (note.isProtected) note = note.metadataOnly();
    if (_detailDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    final List<NoteDto> next = List<NoteDto>.of(_notes);
    final int index = next.indexWhere(
      (NoteDto item) => item.identity == note.identity,
    );
    if (index == -1) {
      next.add(note);
    } else {
      next[index] = note;
    }
    setState(() {
      _notes = List<NoteDto>.unmodifiable(sortNotes(next));
      _selectedNoteId = note.reference;
      _sharedOnly = note.share != null;
      _unavailableSelection = null;
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
            (NoteDto note) => note.identity == saved.identity,
          );
          if (index == -1) {
            next.add(saved);
          } else {
            next[index] = saved;
          }
        }
      case NoteDetailExitReason.deleted:
        if (selectedId != null) {
          next.removeWhere((NoteDto note) => note.reference == selectedId);
        }
      case NoteDetailExitReason.discarded:
      case NoteDetailExitReason.cancelled:
        break;
    }

    setState(() {
      _notes = List<NoteDto>.unmodifiable(sortNotes(next));
      _selectedNoteId = null;
      _unavailableSelection = null;
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
