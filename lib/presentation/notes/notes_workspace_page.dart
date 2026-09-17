import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/notes/note_application.dart';
import 'note_detail_page.dart';
import 'note_detail_route_result.dart';
import 'notes_application_controller.dart';
import 'notes_list_panel.dart';
import 'notes_localizations.dart';
import 'responsive_notes_workspace.dart';

/// Responsive list/detail workspace for the shell's Notes destination.
///
/// This page owns only Presentation selection state. Note mutations and AI
/// calls continue to flow through [NotesApplicationController]. On compact
/// screens the frame shows one surface at a time; on wider screens it keeps a
/// list pane and a focused Note Detail pane side by side.
final class NotesWorkspacePage extends StatefulWidget {
  const NotesWorkspacePage({
    super.key,
    this.applicationService,
    this.controller,
    this.onOpenSettings,
    this.onOpenDiagnostics,
    this.provisioningReader,
    this.onProvisioningCancel,
  }) : assert(
         applicationService != null || controller != null,
         'Provide applicationService or controller.',
       );

  final NoteApplicationService? applicationService;
  final NotesApplicationController? controller;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenDiagnostics;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningCancel;

  @override
  NotesWorkspacePageState createState() => NotesWorkspacePageState();
}

final class NotesWorkspacePageState extends State<NotesWorkspacePage> {
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

  bool get _showDetail => _editingNewNote || _selectedNote != null;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
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
      _error = null;
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
      _error = null;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    final bool compact =
        MediaQuery.sizeOf(context).width <
        ResponsiveNotesWorkspace.compactBreakpoint;
    final bool compactDetailActive = compact && _showDetail;
    return Scaffold(
      appBar: compactDetailActive ? null : _buildWorkspaceAppBar(copy),
      body: _loading
          ? Center(
              key: const ValueKey<String>('notes-workspace-loading'),
              child: Semantics(
                liveRegion: true,
                label: copy.loadingNotes,
                child: const CircularProgressIndicator(),
              ),
            )
          : ResponsiveNotesWorkspace(
              list: NotesListPanel(
                notes: _notes,
                selectedNoteId: _selectedNoteId,
                error: _error == null ? null : copy.loadError,
                actionBusy: false,
                onNewNote: _startNewNote,
                onSelectNote: _selectNote,
                onRetry: reload,
              ),
              detail: _buildDetail(copy, showAppBar: compact),
              hasSelection: _showDetail,
            ),
    );
  }

  PreferredSizeWidget _buildWorkspaceAppBar(NotesCopy copy) {
    return AppBar(
      title: Text(copy.title),
      actions: widget.onOpenSettings == null && widget.onOpenDiagnostics == null
          ? null
          : <Widget>[
              if (widget.onOpenSettings != null) _settingsAction(),
              if (widget.onOpenDiagnostics != null)
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
      return Center(
        key: const ValueKey<String>('notes-workspace-detail-empty'),
        child: Text(copy.createFirstNote),
      );
    }
    return NoteDetailPage(
      key: ValueKey<String>(
        'notes-workspace-detail-${_selectedNote?.id ?? 'new'}',
      ),
      notesController: _application,
      note: _selectedNote,
      provisioningReader: widget.provisioningReader,
      onProvisioningCancel: widget.onProvisioningCancel,
      showAppBar: showAppBar,
      onEmbeddedExit: _handleDetailExit,
      onDirtyChanged: _handleDetailDirtyChanged,
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
