import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import '../../application/notes/note_application.dart';
import 'note_editor_panel.dart';
import 'notes_application_controller.dart';
import 'notes_list_panel.dart';
import 'notes_localizations.dart';
import 'responsive_notes_workspace.dart';

export 'notes_application_controller.dart' show NotesApplicationController;

/// Minimal persisted Notes workflow UI.
///
/// [applicationService] is the normal composition-root dependency. The
/// optional [controller] is a small test seam and still represents only the
/// Application use cases. This widget never reaches into Domain persistence,
/// database, FFI, or the local-LLM adapter.
class NotesPage extends StatefulWidget {
  const NotesPage({
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
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  List<NoteDto> _notes = const <NoteDto>[];
  String? _selectedNoteId;
  bool _editingNewNote = false;
  String? _error;
  String? _summary;
  String? _statusMessage;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  bool _summarizing = false;

  NotesApplicationController get _application {
    final NotesApplicationController? controller = widget.controller;
    if (controller != null) {
      return controller;
    }
    final NoteApplicationService? service = widget.applicationService;
    if (service != null) {
      return NoteApplicationServiceController(service);
    }
    throw StateError('NotesPage requires an application dependency.');
  }

  bool get _actionBusy => _saving || _deleting || _summarizing;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_editorChanged);
    _contentController.addListener(_editorChanged);
    unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
    if (mounted && !_loading) {
      setState(() {
        _loading = true;
        _error = null;
        _statusMessage = null;
      });
    }
    try {
      final List<NoteDto> notes = await _application.listNotes();
      if (!mounted) {
        return;
      }

      NoteDto? selected;
      final String? selectedId = _selectedNoteId;
      if (selectedId != null) {
        for (final NoteDto note in notes) {
          if (note.id == selectedId) {
            selected = note;
            break;
          }
        }
      }
      selected ??= notes.isEmpty ? null : notes.first;

      if (selected == null) {
        _clearEditor();
        _editingNewNote = false;
      } else {
        _populateEditor(selected);
        _editingNewNote = false;
      }

      setState(() {
        _notes = List<NoteDto>.unmodifiable(notes);
        _selectedNoteId = selected?.id;
        _loading = false;
        _error = null;
        _summary = null;
        _statusMessage = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _formatError(error, NotesCopy.of(context).loadError);
      });
    }
  }

  void _selectNote(NoteDto note) {
    if (_editorDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    _populateEditor(note);
    setState(() {
      _selectedNoteId = note.id;
      _editingNewNote = false;
      _error = null;
      _summary = null;
      _statusMessage = null;
    });
  }

  void _startNewNote() {
    if (_editorDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    _clearEditor();
    setState(() {
      _selectedNoteId = null;
      _editingNewNote = true;
      _error = null;
      _summary = null;
      _statusMessage = null;
    });
  }

  Future<void> _saveNote() async {
    if (_saving) {
      return;
    }

    final String? noteId = _selectedNoteId;
    final String title = _titleController.text;
    final String content = _contentController.text;
    final NoteDto? existing = noteId == null ? null : _findNote(noteId);

    setState(() {
      _saving = true;
      _error = null;
      _summary = null;
      _statusMessage = null;
    });

    try {
      final NoteDto saved;
      if (noteId == null) {
        saved = await _application.createNote(title: title, content: content);
      } else {
        if (existing == null) {
          throw StateError('The selected note is no longer available.');
        }

        NoteDto updated = existing;
        if (updated.title != title) {
          updated = await _application.renameNote(noteId: noteId, title: title);
        }
        if (updated.content != content) {
          updated = await _application.replaceContent(
            noteId: noteId,
            content: content,
          );
        }
        saved = updated;
      }

      if (!mounted) {
        return;
      }
      _upsertAndSelect(saved);
      _showMessage(NotesCopy.of(context).saved);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => _error = _formatError(error, NotesCopy.of(context).saveError),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmDeleteNote() async {
    final String? noteId = _selectedNoteId;
    if (noteId == null || _actionBusy) {
      return;
    }
    final NotesCopy copy = NotesCopy.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(copy.deleteTitle),
          content: Text(copy.deleteMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(copy.cancel),
            ),
            FilledButton(
              key: const ValueKey<String>('notes-delete-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(copy.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      await _deleteNote();
    }
  }

  Future<void> _deleteNote() async {
    final String? noteId = _selectedNoteId;
    if (noteId == null || _deleting) {
      return;
    }
    final NoteDto? deleted = _findNote(noteId);
    if (deleted == null) {
      return;
    }

    setState(() {
      _deleting = true;
      _error = null;
      _summary = null;
      _statusMessage = null;
    });

    try {
      await _application.deleteNote(noteId);
      if (!mounted) {
        return;
      }

      final List<NoteDto> remaining = _notes
          .where((NoteDto note) => note.id != noteId)
          .toList(growable: false);
      final NoteDto? next = remaining.isEmpty ? null : remaining.first;
      if (next == null) {
        _clearEditor();
        _editingNewNote = false;
      } else {
        _populateEditor(next);
        _editingNewNote = false;
      }
      setState(() {
        _notes = List<NoteDto>.unmodifiable(remaining);
        _selectedNoteId = next?.id;
      });
      final NotesCopy copy = NotesCopy.of(context);
      _showUndoMessage(deleted: deleted, message: copy.deleted, copy: copy);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(
        () => _error = _formatError(error, NotesCopy.of(context).deleteError),
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _summarizeNote() async {
    final String? noteId = _selectedNoteId;
    if (noteId == null || _summarizing) {
      return;
    }
    if (_editorDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }

    setState(() {
      _summarizing = true;
      _error = null;
      _summary = null;
      _statusMessage = null;
    });

    try {
      final String summary = await _application.summarizeNote(noteId);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
        _statusMessage = NotesCopy.of(context).summarized;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final ModelProvisioningState? provisioningState =
          widget.provisioningReader?.current;
      final bool provisioningFailed =
          provisioningState?.phase == ModelProvisioningPhase.failed ||
          provisioningState?.phase == ModelProvisioningPhase.cancelled;
      setState(
        () => _error = provisioningFailed
            ? null
            : _formatError(error, NotesCopy.of(context).summarizeError),
      );
    } finally {
      if (mounted) {
        setState(() => _summarizing = false);
      }
    }
  }

  NoteDto? _findNote(String noteId) {
    for (final NoteDto note in _notes) {
      if (note.id == noteId) {
        return note;
      }
    }
    return null;
  }

  void _upsertAndSelect(NoteDto note) {
    final List<NoteDto> next = List<NoteDto>.of(_notes);
    final int index = next.indexWhere((NoteDto item) => item.id == note.id);
    if (index == -1) {
      next.add(note);
    } else {
      next[index] = note;
    }
    _populateEditor(note);
    setState(() {
      _notes = List<NoteDto>.unmodifiable(next);
      _selectedNoteId = note.id;
      _editingNewNote = false;
      _error = null;
    });
  }

  void _populateEditor(NoteDto note) {
    _titleController.text = note.title;
    _contentController.text = note.content;
  }

  void _clearEditor() {
    _titleController.clear();
    _contentController.clear();
  }

  bool get _editorDirty {
    final NoteDto? selected = _selectedNoteId == null
        ? null
        : _findNote(_selectedNoteId!);
    return _titleController.text != (selected?.title ?? '') ||
        _contentController.text != (selected?.content ?? '');
  }

  void _editorChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String _formatError(Object _, String message) => message;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showUndoMessage({
    required NoteDto deleted,
    required String message,
    required NotesCopy copy,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: copy.undo,
            onPressed: () => unawaited(_restoreDeletedNote(deleted)),
          ),
        ),
      );
  }

  Future<void> _restoreDeletedNote(NoteDto note) async {
    try {
      final NoteDto restored = await _application.createNote(
        title: note.title,
        content: note.content,
      );
      if (!mounted) {
        return;
      }
      _upsertAndSelect(restored);
      _showMessage(NotesCopy.of(context).saved);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = _formatError(error, NotesCopy.of(context).saveError),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_editorChanged);
    _contentController.removeListener(_editorChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(copy.title),
        actions:
            widget.onOpenSettings == null && widget.onOpenDiagnostics == null
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
      ),
      body: _loading
          ? Center(
              key: const ValueKey<String>('notes-loading'),
              child: Semantics(
                liveRegion: true,
                label: copy.loadingNotes,
                child: const CircularProgressIndicator(),
              ),
            )
          : _buildWorkspace(copy),
    );
  }

  Widget _buildWorkspace(NotesCopy copy) {
    final Widget listPanel = NotesListPanel(
      notes: _notes,
      selectedNoteId: _selectedNoteId,
      error: _error,
      actionBusy: _actionBusy,
      onNewNote: _startNewNote,
      onSelectNote: _selectNote,
      onRetry: _loadNotes,
    );
    final Widget editor = NoteEditorPanel(
      titleController: _titleController,
      contentController: _contentController,
      hasSelectedNote: _selectedNoteId != null,
      actionBusy: _actionBusy,
      error: _error,
      summary: _summary,
      isDirty: _editorDirty,
      summaryBusy: _summarizing,
      statusMessage: _statusMessage,
      provisioningReader: widget.provisioningReader,
      onProvisioningRetry: _summarizeNote,
      onProvisioningCancel: widget.onProvisioningCancel,
      onSave: _saveNote,
      onDelete: _selectedNoteId == null || _actionBusy
          ? null
          : _confirmDeleteNote,
      onSummarize: _selectedNoteId == null || _actionBusy
          ? null
          : _summarizeNote,
    );
    return ResponsiveNotesWorkspace(
      list: listPanel,
      detail: editor,
      hasSelection: _selectedNoteId != null || _editingNewNote,
      onCompactBack: _handleCompactBack,
      compactBackLabel: copy.notes,
    );
  }

  void _handleCompactBack() {
    if (_editorDirty) {
      _showMessage(NotesCopy.of(context).unsavedChanges);
      return;
    }
    _clearEditor();
    setState(() {
      _selectedNoteId = null;
      _editingNewNote = false;
      _summary = null;
      _error = null;
      _statusMessage = null;
    });
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
