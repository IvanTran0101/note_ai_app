import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import '../../application/notes/note_application.dart';
import 'note_detail_back_confirmation.dart';
import 'note_detail_delete_confirmation.dart';
import 'note_detail_focus.dart';
import 'note_detail_localizations.dart';
import 'note_detail_more_actions.dart';
import 'note_detail_route_result.dart';
import 'note_detail_surface.dart';
import 'note_flow_snackbar.dart';
import 'notes_application_controller.dart';

/// Focused mobile-first editor for one note.
///
/// The page owns transient editor state only. All persistence and AI actions
/// go through [NotesApplicationController], keeping Presentation independent
/// from repositories, ModelManager, storage, and the native runtime.
final class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({
    super.key,
    required this.notesController,
    this.note,
    this.provisioningReader,
    this.onProvisioningCancel,
    this.showAppBar = true,
    this.onEmbeddedExit,
    this.onDirtyChanged,
  });

  final NotesApplicationController notesController;
  final NoteDto? note;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningCancel;
  final bool showAppBar;
  final ValueChanged<NoteDetailRouteResult>? onEmbeddedExit;
  final ValueChanged<bool>? onDirtyChanged;
  static const Key titleFieldKey = ValueKey<String>('note-detail-title-field');
  static const Key contentFieldKey = ValueKey<String>(
    'note-detail-content-field',
  );
  static const Key summaryKey = ValueKey<String>('note-detail-summary');
  static const Key dirtyKey = ValueKey<String>('note-detail-dirty');
  static const Key moreDeleteKey = ValueKey<String>('note-detail-more-delete');
  static const Key deleteKey = ValueKey<String>('note-detail-delete');
  static const Key backKey = ValueKey<String>('note-detail-back');

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

final class _NoteDetailPageState extends State<NoteDetailPage> {
  static const Duration _autosaveDelay = Duration(seconds: 3);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final GlobalKey _contentFieldContextKey = GlobalKey();
  Timer? _autosaveTimer;

  late NoteDto? _note;
  late String _savedTitle;
  late String _savedContent;
  String? _summary;
  String? _error;
  String? _statusMessage;
  bool _summaryStale = false;
  bool _saving = false;
  bool _deleting = false;
  bool _summarizing = false;
  bool _didPersist = false;
  bool _lastReportedDirty = false;
  bool _summaryError = false;
  bool _backConfirmationVisible = false;
  bool _ignoreNextEditorFocusLoss = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _savedTitle = widget.note?.title ?? '';
    _savedContent = widget.note?.content ?? '';
    _titleController.text = _savedTitle;
    _contentController.text = _savedContent;
    _titleController.addListener(_editorChanged);
    _contentController.addListener(_editorChanged);
    _titleFocusNode.addListener(_titleFocusChanged);
    _contentFocusNode.addListener(_contentFocusChanged);
  }

  bool get _isDirty =>
      _titleController.text != _savedTitle ||
      _contentController.text != _savedContent;

  bool get _actionBusy => _saving || _deleting || _summarizing;

  bool get _canSave => !_actionBusy && (_note == null || _isDirty);

  bool get _canSummarize => !_actionBusy && _note != null && !_isDirty;

  void _editorChanged() {
    if (mounted) {
      _ignoreNextEditorFocusLoss = false;
      setState(() {
        if (_summary != null && _isDirty) {
          _summaryStale = true;
        }
      });
      _notifyDirtyChanged();
      _scheduleAutosave();
    }
  }

  void _notifyDirtyChanged() {
    final bool dirty = _isDirty;
    if (dirty == _lastReportedDirty) {
      return;
    }
    _lastReportedDirty = dirty;
    widget.onDirtyChanged?.call(dirty);
  }

  void _contentFocusChanged() {
    scheduleNoteDetailContentFocus(
      focusNode: _contentFocusNode,
      fieldKey: _contentFieldContextKey,
    );
    _saveWhenEditorLosesFocus();
  }

  void _titleFocusChanged() {
    _saveWhenEditorLosesFocus();
  }

  void _saveWhenEditorLosesFocus() {
    if (_ignoreNextEditorFocusLoss &&
        !_titleFocusNode.hasFocus &&
        !_contentFocusNode.hasFocus) {
      _ignoreNextEditorFocusLoss = false;
      return;
    }
    if (!_backConfirmationVisible &&
        !_titleFocusNode.hasFocus &&
        !_contentFocusNode.hasFocus) {
      _scheduleAutosave(immediate: true);
    }
  }

  void _scheduleAutosave({bool immediate = false}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (!mounted || !_isDirty) {
      return;
    }
    if (immediate) {
      unawaited(_save(automatic: true));
      return;
    }
    _autosaveTimer = Timer(_autosaveDelay, () {
      _autosaveTimer = null;
      unawaited(_save(automatic: true));
    });
  }

  Future<bool> _save({bool automatic = false}) async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (_actionBusy) {
      if (automatic) {
        _scheduleAutosave();
      }
      return false;
    }
    if (!_canSave && _note != null) {
      return false;
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    bool persisted = false;
    setState(() {
      _saving = true;
      _error = null;
      _statusMessage = null;
      _summaryError = false;
    });

    try {
      final String title = _titleController.text;
      final String content = _contentController.text;
      final NoteDto? current = _note;
      final NoteDto saved;
      if (current == null) {
        saved = await widget.notesController.createNote(
          title: title,
          content: content,
        );
      } else {
        NoteDto updated = current;
        if (title != _savedTitle) {
          updated = await widget.notesController.renameNote(
            noteId: current.id,
            title: title,
          );
        }
        if (content != _savedContent) {
          updated = await widget.notesController.replaceContent(
            noteId: current.id,
            content: content,
          );
        }
        saved = updated;
      }

      if (!mounted) {
        return true;
      }
      setState(() {
        _note = saved;
        _savedTitle = saved.title;
        _savedContent = saved.content;
        _summaryStale = _summary != null;
        _statusMessage = copy.saved;
        _didPersist = true;
      });
      _notifyDirtyChanged();
      persisted = true;
      return true;
    } on Object catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _error = error is UnsupportedError
            ? copy.persistenceUnavailable
            : copy.saveError;
      });
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (persisted && _isDirty) {
          _scheduleAutosave();
        }
      }
    }
  }

  Future<void> _summarize() async {
    final NoteDto? current = _note;
    if (current == null || !_canSummarize) {
      return;
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    setState(() {
      _summarizing = true;
      _error = null;
      _statusMessage = null;
      _summaryError = false;
    });

    try {
      final String summary = await widget.notesController.summarizeNote(
        current.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
        _summaryStale = false;
        _statusMessage = copy.summarized;
        _summaryError = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      final ModelProvisioningState? provisioningState =
          widget.provisioningReader?.current;
      final bool provisioningFailed =
          provisioningState?.phase == ModelProvisioningPhase.failed ||
          provisioningState?.phase == ModelProvisioningPhase.cancelled;
      if (!provisioningFailed) {
        setState(() {
          _error = copy.summarizeError;
          _summaryError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _summarizing = false);
      }
    }
  }

  Future<void> _handleBack() async {
    if (_actionBusy) {
      return;
    }
    if (!_isDirty) {
      _pop();
      return;
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _backConfirmationVisible = true;
    final NoteDetailBackDecision? action = await showNoteDetailBackConfirmation(
      context: context,
      copy: copy,
      canSave: !kIsWeb,
    );
    _backConfirmationVisible = false;
    _ignoreNextEditorFocusLoss = true;

    if (!mounted || action == null || action == NoteDetailBackDecision.cancel) {
      if (mounted && _isDirty) {
        _scheduleAutosave();
      }
      return;
    }
    if (action == NoteDetailBackDecision.discard) {
      _pop(
        reason: _didPersist
            ? NoteDetailExitReason.saved
            : NoteDetailExitReason.discarded,
      );
      return;
    }
    if (kIsWeb) {
      setState(() => _statusMessage = copy.persistenceUnavailable);
      return;
    }
    if (await _save() && mounted) {
      _pop(reason: NoteDetailExitReason.saved);
    }
  }

  Future<void> _delete() async {
    final NoteDto? current = _note;
    if (current == null || _actionBusy) {
      return;
    }

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final bool? confirmed = await showNoteDetailDeleteConfirmation(
      context: context,
      copy: copy,
      confirmKey: NoteDetailPage.deleteKey,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _deleting = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      await widget.notesController.deleteNote(current.id);
      if (mounted) {
        _pop(reason: NoteDetailExitReason.deleted);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = copy.deleteError);
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _copySummary() async {
    final String? summary = _summary;
    if (summary == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final String copiedMessage = NoteDetailCopy.of(context).copied;
    setState(() {
      _statusMessage = copiedMessage;
      _error = null;
    });
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        buildNoteFlowSnackBar(context: context, message: copiedMessage),
      );
    try {
      await Clipboard.setData(ClipboardData(text: summary));
    } on Object {
      // Keep the in-app feedback usable in widget tests and hosts without a
      // clipboard channel. The native clipboard remains best effort.
    }
  }

  void _pop({NoteDetailExitReason? reason}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (mounted) {
      final NoteDetailExitReason exitReason =
          reason ??
          (_didPersist
              ? NoteDetailExitReason.saved
              : NoteDetailExitReason.cancelled);
      final NoteDetailRouteResult result = NoteDetailRouteResult(
        reason: exitReason,
        note: exitReason == NoteDetailExitReason.saved ? _note : null,
      );
      final ValueChanged<NoteDetailRouteResult>? onEmbeddedExit =
          widget.onEmbeddedExit;
      if (onEmbeddedExit != null) {
        onEmbeddedExit(result);
        return;
      }
      Navigator.of(context).pop<NoteDetailRouteResult>(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final String currentTitle = _titleController.text.trim();
    final String pageTitle = currentTitle.isNotEmpty
        ? currentTitle
        : (_note == null ? copy.newNote : copy.editNote);
    final Widget surface = _buildSurface(copy, pageTitle);
    final Widget content = widget.onEmbeddedExit != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.showAppBar) _buildAppBar(copy, pageTitle),
              Expanded(child: surface),
            ],
          )
        : Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: widget.showAppBar ? _buildAppBar(copy, pageTitle) : null,
            body: surface,
          );
    return PopScope<NoteDetailRouteResult>(
      canPop:
          widget.onEmbeddedExit == null &&
          !_isDirty &&
          !_actionBusy &&
          !_didPersist,
      onPopInvokedWithResult: (bool didPop, NoteDetailRouteResult? result) {
        if (!didPop) {
          unawaited(_handleBack());
        }
      },
      child: content,
    );
  }

  PreferredSizeWidget _buildAppBar(NoteDetailCopy copy, String pageTitle) {
    final VoidCallback? moreAction = _moreAction(copy);
    return AppBar(
      leading: IconButton(
        key: NoteDetailPage.backKey,
        tooltip: copy.back,
        onPressed: _actionBusy ? null : () => unawaited(_handleBack()),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: moreAction == null
          ? null
          : <Widget>[
              Builder(
                builder: (BuildContext buttonContext) => IconButton(
                  key: const ValueKey<String>('note-detail-more'),
                  tooltip: copy.more,
                  onPressed: () => unawaited(
                    _showMoreActions(copy, anchorContext: buttonContext),
                  ),
                  icon: const Icon(Icons.more_horiz),
                ),
              ),
            ],
    );
  }

  VoidCallback? _moreAction(NoteDetailCopy copy) {
    if (_note == null || _actionBusy) {
      return null;
    }
    return () => unawaited(_showMoreActions(copy));
  }

  ValueChanged<BuildContext>? _moreActionWithContext(NoteDetailCopy copy) {
    if (_note == null || _actionBusy) {
      return null;
    }
    return (BuildContext anchorContext) =>
        unawaited(_showMoreActions(copy, anchorContext: anchorContext));
  }

  Future<void> _showMoreActions(
    NoteDetailCopy copy, {
    BuildContext? anchorContext,
  }) {
    return runNoteDetailMoreActions(
      context: context,
      copy: copy,
      anchorContext: anchorContext,
      onDelete: _delete,
    );
  }

  Widget _buildSurface(NoteDetailCopy copy, String pageTitle) {
    return NoteDetailSurface(
      titleController: _titleController,
      contentController: _contentController,
      titleFocusNode: _titleFocusNode,
      contentFocusNode: _contentFocusNode,
      contentFieldContextKey: _contentFieldContextKey,
      copy: copy,
      pageTitle: pageTitle,
      showPageHeader: !widget.showAppBar,
      statusUnavailable: kIsWeb,
      onBack: widget.showAppBar ? null : () => unawaited(_handleBack()),
      backTooltip: copy.back,
      backKey: NoteDetailPage.backKey,
      hasSavedNote: _note != null,
      isDirty: _isDirty,
      error: _error,
      statusMessage: _statusMessage,
      actionBusy: _actionBusy,
      provisioningReader: widget.provisioningReader,
      onProvisioningRetry: _note == null ? null : _summarize,
      onProvisioningCancel: widget.onProvisioningCancel,
      summary: _summary,
      summaryStale: _summaryStale,
      onCopySummary: _summary == null ? null : () => unawaited(_copySummary()),
      onRegenerateSummary: _canSummarize ? () => unawaited(_summarize()) : null,
      copySummaryLabel: copy.copySummary,
      regenerateSummaryLabel: copy.regenerate,
      onErrorRetry: _summaryError ? () => unawaited(_summarize()) : null,
      errorRetryLabel: copy.retry,
      isSaving: _saving,
      isSummarizing: _summarizing,
      canSave: false,
      canSummarize: _canSummarize,
      onSave: null,
      onSummarize: _canSummarize ? () => unawaited(_summarize()) : null,
      onMore: widget.showAppBar ? null : _moreAction(copy),
      onMoreWithContext: widget.showAppBar
          ? null
          : _moreActionWithContext(copy),
      saveLabel: copy.save,
      summarizeLabel: copy.summarize,
      moreLabel: copy.more,
      savingLabel: copy.saving,
      summarizingLabel: copy.summarizing,
    );
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _titleController.removeListener(_editorChanged);
    _contentController.removeListener(_editorChanged);
    _titleFocusNode.removeListener(_titleFocusChanged);
    _contentFocusNode.removeListener(_contentFocusChanged);
    _titleController.dispose();
    _contentController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }
}
