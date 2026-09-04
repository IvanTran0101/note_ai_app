import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/notes/note_application.dart';
import 'note_editor_panel.dart';
import 'notes_application_controller.dart';
import 'notes_list_panel.dart';

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
    this.onOpenDiagnostics,
  }) : assert(
         applicationService != null || controller != null,
         'Provide applicationService or controller.',
       );

  final NoteApplicationService? applicationService;
  final NotesApplicationController? controller;
  final VoidCallback? onOpenDiagnostics;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  List<NoteDto> _notes = const <NoteDto>[];
  String? _selectedNoteId;
  String? _error;
  String? _summary;
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
    unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
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
      } else {
        _populateEditor(selected);
      }

      setState(() {
        _notes = List<NoteDto>.unmodifiable(notes);
        _selectedNoteId = selected?.id;
        _loading = false;
        _error = null;
        _summary = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _formatError(error);
      });
    }
  }

  void _selectNote(NoteDto note) {
    _populateEditor(note);
    setState(() {
      _selectedNoteId = note.id;
      _error = null;
      _summary = null;
    });
  }

  void _startNewNote() {
    _clearEditor();
    setState(() {
      _selectedNoteId = null;
      _error = null;
      _summary = null;
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
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _formatError(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteNote() async {
    final String? noteId = _selectedNoteId;
    if (noteId == null || _deleting) {
      return;
    }

    setState(() {
      _deleting = true;
      _error = null;
      _summary = null;
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
      } else {
        _populateEditor(next);
      }
      setState(() {
        _notes = List<NoteDto>.unmodifiable(remaining);
        _selectedNoteId = next?.id;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _formatError(error));
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

    setState(() {
      _summarizing = true;
      _error = null;
      _summary = null;
    });

    try {
      final String summary = await _application.summarizeNote(noteId);
      if (!mounted) {
        return;
      }
      setState(() => _summary = summary);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = _formatError(error));
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

  String _formatError(Object error) => 'Error: $error';

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteFlow · Notes'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: widget.onOpenDiagnostics == null
            ? null
            : <Widget>[
                TextButton(
                  key: const ValueKey<String>('open-diagnostics'),
                  onPressed: widget.onOpenDiagnostics,
                  child: const Text('Diagnostics'),
                ),
              ],
      ),
      body: _loading
          ? const Center(
              key: ValueKey<String>('notes-loading'),
              child: CircularProgressIndicator(),
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
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
                  onSave: _saveNote,
                  onDelete: _selectedNoteId == null || _actionBusy
                      ? null
                      : _deleteNote,
                  onSummarize: _selectedNoteId == null || _actionBusy
                      ? null
                      : _summarizeNote,
                );
                if (constraints.maxWidth < 700) {
                  return Column(
                    children: <Widget>[
                      SizedBox(height: 205, child: listPanel),
                      const Divider(height: 1),
                      Expanded(child: editor),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: 300, child: listPanel),
                    const VerticalDivider(width: 1),
                    Expanded(child: editor),
                  ],
                );
              },
            ),
    );
  }
}
