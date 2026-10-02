import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import '../../application/notes/note_application.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import '../../application/sync/sync_conflict.dart';
import '../../application/sync/sync_conflict_resolver.dart';
import 'note_detail_back_confirmation.dart';
import 'note_detail_delete_confirmation.dart';
import 'note_detail_focus.dart';
import 'note_detail_localizations.dart';
import 'note_detail_more_actions.dart';
import 'note_detail_route_result.dart';
import 'note_detail_surface.dart';
import 'note_flow_snackbar.dart';
import 'note_summary_availability.dart';
import 'note_summary_controller.dart';
import 'note_summary_feedback.dart';
import 'notes_application_controller.dart';
import 'summary_consent_dialog.dart';
import '../sync/sync_conflict_prompt.dart';
import '../sync/sync_localizations.dart';
import '../sync/sync_presentation_controller.dart';
import '../sync/sync_widgets.dart';

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
    this.syncController,
  });

  final NotesApplicationController notesController;
  final NoteDto? note;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningCancel;
  final bool showAppBar;
  final ValueChanged<NoteDetailRouteResult>? onEmbeddedExit;
  final ValueChanged<bool>? onDirtyChanged;
  final SyncPresentationController? syncController;
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

final class _NoteDetailPageState extends State<NoteDetailPage>
    with WidgetsBindingObserver {
  static const Duration _autosaveDelay = Duration(seconds: 3);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final GlobalKey _contentFieldContextKey = GlobalKey();
  Timer? _autosaveTimer;

  late NoteDto? _note;
  NoteDto? _pendingSavedNote;
  late String _savedTitle;
  late String _savedContent;
  String? _error;
  String? _statusMessage;
  bool _saving = false;
  bool _saveFailed = false;
  bool _deleting = false;
  bool _didPersist = false;
  bool _lastReportedDirty = false;
  bool _backConfirmationVisible = false;
  bool _ignoreNextEditorFocusLoss = false;
  bool _conflictFlowActive = false;
  bool _resolvingConflict = false;
  int _draftRevision = 0;

  /// Owns the whole Summary lifecycle for this page: scope, consent capture,
  /// revalidation, result, typed failure, and the rate-limit countdown.
  late final NoteSummaryController _summaryController = NoteSummaryController(
    notesController: () => widget.notesController,
    editorFacts: () => NoteSummaryEditorFacts(
      note: _note,
      isDirty: _isDirty,
      hasConflict: _currentConflict != null,
    ),
    confirmConsent: _confirmSummaryConsent,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _note = widget.note;
    _savedTitle = widget.note?.title ?? '';
    _savedContent = widget.note?.content ?? '';
    _titleController.text = _savedTitle;
    _contentController.text = _savedContent;
    _titleController.addListener(_editorChanged);
    _contentController.addListener(_editorChanged);
    _titleFocusNode.addListener(_titleFocusChanged);
    _contentFocusNode.addListener(_contentFocusChanged);
    _summaryController.addListener(_summaryChanged);
    widget.syncController?.addListener(_syncStateChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _isDirty &&
        _currentConflict == null) {
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
      unawaited(_save(automatic: true));
    }
  }

  @override
  void didUpdateWidget(covariant NoteDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncController != widget.syncController) {
      oldWidget.syncController?.removeListener(_syncStateChanged);
      widget.syncController?.addListener(_syncStateChanged);
      _syncStateChanged();
    }
    if (oldWidget.note != widget.note) {
      final NoteDto? incoming = widget.note;
      final bool sameIdentity =
          incoming?.id == _note?.id && incoming?.ownerId == _note?.ownerId;
      final NoteDto? previous = oldWidget.note;
      final bool sameText =
          previous != null &&
          incoming != null &&
          previous.hasSameTextAs(incoming);
      if (!sameText) {
        _summaryController.cancelActive(
          reason: SummaryRunFailureCode.noteChanged,
        );
        _summaryController.markStaleIfResult();
      }
      if (!sameIdentity) _summaryController.clearResult();
      if (!_isDirty || !sameIdentity) {
        _adoptSavedNote(incoming);
      } else {
        _pendingSavedNote = incoming;
      }
    }
    if (oldWidget.notesController != widget.notesController) {
      _summaryController.cancelActive(
        reason: SummaryRunFailureCode.sessionChanged,
      );
      _summaryController.clearResult();
    }
  }

  void _adoptSavedNote(NoteDto? incoming) {
    _pendingSavedNote = null;
    _autosaveTimer?.cancel();
    _titleController.removeListener(_editorChanged);
    _contentController.removeListener(_editorChanged);
    _note = incoming;
    _savedTitle = incoming?.title ?? '';
    _savedContent = incoming?.content ?? '';
    _titleController.text = _savedTitle;
    _contentController.text = _savedContent;
    _titleController.addListener(_editorChanged);
    _contentController.addListener(_editorChanged);
    _summaryController.clearFailure();
  }

  void _summaryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Opens the cloud disclosure for the run that already captured its request.
  Future<bool> _confirmSummaryConsent() {
    if (!mounted) {
      return Future<bool>.value(false);
    }
    return showSummaryConsentDialog(context);
  }

  void _syncStateChanged() {
    if (!mounted) return;
    if (_currentConflict != null) {
      _summaryController.cancelActive(reason: SummaryRunFailureCode.conflict);
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
    } else if (_isDirty) {
      _scheduleAutosave();
    }
    setState(() {});
  }

  SyncConflict? get _currentConflict {
    final String? noteId = _note?.id;
    return noteId == null ? null : widget.syncController?.conflictFor(noteId);
  }

  bool get _isDirty =>
      _titleController.text != _savedTitle ||
      _contentController.text != _savedContent;

  bool get _actionBusy =>
      _saving || _deleting || _resolvingConflict || _summaryController.isBusy;

  bool get _canSave =>
      !_actionBusy && _currentConflict == null && (_note == null || _isDirty);

  /// Availability of the Summary action for the facts the editor shows now.
  NoteSummaryAvailability get _summaryAvailability =>
      _summaryController.availability(
        hasSavedNote: _note != null,
        isDirty: _isDirty,
        hasConflict: _currentConflict != null,
      );

  /// The single eligibility rule the primary, retry, and regenerate actions
  /// share: the editor is ready (or needs consent), and no run or hint is live.
  bool get _canSummarize =>
      !_actionBusy &&
      _summaryController.canStart &&
      _summaryAvailability.canStart;

  void _editorChanged() {
    if (!mounted) return;
    _draftRevision++;
    _summaryController.cancelActive(reason: SummaryRunFailureCode.noteChanged);
    if (_isDirty) {
      _summaryController.markStaleIfResult();
    } else if (_pendingSavedNote != null) {
      _adoptSavedNote(_pendingSavedNote);
    }
    _ignoreNextEditorFocusLoss = false;
    setState(() {});
    _notifyDirtyChanged();
    _scheduleAutosave();
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
    if (!mounted ||
        !_isDirty ||
        _conflictFlowActive ||
        _currentConflict != null) {
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
    if (_currentConflict != null) return false;

    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final int savingDraftRevision = _draftRevision;
    bool persisted = false;
    setState(() {
      _saving = true;
      _saveFailed = false;
      _error = null;
      _statusMessage = null;
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
        final NotesApplicationController controller = widget.notesController;
        if (controller is NotesModule02Controller) {
          saved = await (controller as NotesModule02Controller).updateNote(
            noteId: current.id,
            title: title,
            content: content,
          );
        } else {
          NoteDto updated = current;
          if (title != _savedTitle) {
            updated = await controller.renameNote(
              noteId: current.id,
              title: title,
            );
          }
          if (content != _savedContent) {
            updated = await controller.replaceContent(
              noteId: current.id,
              content: content,
            );
          }
          saved = updated;
        }
      }

      if (!mounted) {
        return true;
      }
      _summaryController.markStaleIfResult();
      setState(() {
        _note = saved;
        _pendingSavedNote = null;
        _savedTitle = saved.title;
        _savedContent = saved.content;
        _summaryController.clearFailure();
        _statusMessage = _draftRevision == savingDraftRevision
            ? copy.saved
            : copy.autoSavePending;
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
        _saveFailed = error is! UnsupportedError;
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
    if (!_canSummarize) {
      return;
    }
    final int accepted = _summaryController.acceptedResultCount;
    setState(() {
      _error = null;
      _statusMessage = null;
    });
    await _summaryController.run();
    if (!mounted || _summaryController.acceptedResultCount == accepted) {
      return;
    }
    setState(() => _statusMessage = NoteDetailCopy.of(context).summarized);
  }

  /// Stops the in-flight generation; cancelling never retracts what a cloud run
  /// may already have sent, and the last accepted summary stays displayed.
  void _cancelSummary() {
    final NoteDetailCopy copy = NoteDetailCopy.of(context);
    final bool cloud = _summaryController.isCloudRun;
    _summaryController.cancelActive();
    setState(() => _statusMessage = copy.summaryCancelExplanation(cloud));
  }

  bool get _provisioningFailed {
    final ModelProvisioningPhase? phase =
        widget.provisioningReader?.current.phase;
    return phase == ModelProvisioningPhase.failed ||
        phase == ModelProvisioningPhase.cancelled;
  }

  Future<void> _handleBack() async {
    if (_actionBusy) {
      return;
    }
    if (_currentConflict != null && _isDirty) {
      _autosaveTimer?.cancel();
      _autosaveTimer = null;
      _conflictFlowActive = true;
      _backConfirmationVisible = true;
      final SyncDirtyDraftChoice? draftChoice = await showSyncDirtyDraftChoices(
        context: context,
      );
      _backConfirmationVisible = false;
      if (!mounted ||
          draftChoice == null ||
          draftChoice == SyncDirtyDraftChoice.cancel) {
        _conflictFlowActive = false;
        return;
      }
      if (draftChoice == SyncDirtyDraftChoice.discard) {
        _pop(
          reason: _didPersist
              ? NoteDetailExitReason.saved
              : NoteDetailExitReason.cancelled,
        );
        return;
      }
      setState(() => _saving = true);
      try {
        final NoteDto copy = await widget.notesController.createNote(
          title: _titleController.text,
          content: _contentController.text,
        );
        if (mounted) {
          _pop(reason: NoteDetailExitReason.saved, noteOverride: copy);
        }
      } on Object {
        if (mounted) {
          setState(() {
            _saving = false;
            _conflictFlowActive = false;
            _error = NoteDetailCopy.of(context).saveError;
          });
        }
      }
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
      canSave: true,
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
    if (await _save() && mounted) {
      _pop(reason: NoteDetailExitReason.saved);
    }
  }

  Future<void> _delete() async {
    final NoteDto? current = _note;
    if (current == null || _actionBusy || _currentConflict != null) {
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
    final String? summary = _summaryController.summary;
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

  Future<void> _resolveConflict() async {
    final SyncPresentationController? sync = widget.syncController;
    final SyncConflict? conflict = _currentConflict;
    if (sync == null || conflict == null || _actionBusy) return;

    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _conflictFlowActive = true;
    if (_isDirty) {
      _backConfirmationVisible = true;
      final SyncDirtyDraftChoice? draftChoice = await showSyncDirtyDraftChoices(
        context: context,
      );
      _backConfirmationVisible = false;
      if (!mounted ||
          draftChoice == null ||
          draftChoice == SyncDirtyDraftChoice.cancel) {
        _conflictFlowActive = false;
        return;
      }
      if (draftChoice == SyncDirtyDraftChoice.discard) {
        _titleController.text = conflict.local.title;
        _contentController.text = conflict.local.content;
        _savedTitle = conflict.local.title;
        _savedContent = conflict.local.content;
        _notifyDirtyChanged();
      } else {
        await _saveDraftAsNewAndResolve(conflict, sync);
        return;
      }
    }

    final SyncConflictChoice? choice = await showSyncConflictChoices(
      context: context,
      conflict: conflict,
    );
    if (!mounted || choice == null) {
      _conflictFlowActive = false;
      return;
    }
    if (choice == SyncConflictChoice.later) {
      await sync.resolveConflict(displayedConflict: conflict, choice: choice);
      _conflictFlowActive = false;
      return;
    }
    setState(() => _resolvingConflict = true);
    final bool resolved = await sync.resolveConflict(
      displayedConflict: conflict,
      choice: choice,
    );
    if (!mounted) return;
    setState(() {
      _resolvingConflict = false;
      _conflictFlowActive = false;
      _statusMessage = resolved ? null : SyncCopy.of(context).conflictChanged;
    });
    if (resolved) _pop(reason: NoteDetailExitReason.saved);
  }

  Future<void> _saveDraftAsNewAndResolve(
    SyncConflict conflict,
    SyncPresentationController sync,
  ) async {
    NoteDto? copy;
    setState(() {
      _saving = true;
      _resolvingConflict = true;
      _error = null;
    });
    try {
      copy = await widget.notesController.createNote(
        title: _titleController.text,
        content: _contentController.text,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final SyncConflictChoice? choice = await showSyncConflictChoices(
        context: context,
        conflict: conflict,
      );
      if (choice != null) {
        await sync.resolveConflict(displayedConflict: conflict, choice: choice);
      }
    } on Object {
      if (copy == null && mounted) {
        setState(() {
          _saving = false;
          _resolvingConflict = false;
          _conflictFlowActive = false;
          _error = NoteDetailCopy.of(context).saveError;
        });
        return;
      }
    }
    if (mounted && copy != null) {
      _pop(reason: NoteDetailExitReason.saved, noteOverride: copy);
    }
  }

  void _pop({NoteDetailExitReason? reason, NoteDto? noteOverride}) {
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
        note: exitReason == NoteDetailExitReason.saved
            ? noteOverride ?? _note
            : null,
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
    if (_note == null || _actionBusy || _currentConflict != null) {
      return null;
    }
    return () => unawaited(_showMoreActions(copy));
  }

  ValueChanged<BuildContext>? _moreActionWithContext(NoteDetailCopy copy) {
    if (_note == null || _actionBusy || _currentConflict != null) {
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
    final NoteSummaryFailureCopy? summaryFailure = noteSummaryFailureCopy(
      copy: copy,
      controller: _summaryController,
      suppressed: _provisioningFailed,
      retryEnabled: _canSummarize,
    );
    final Widget editor = NoteDetailSurface(
      titleController: _titleController,
      contentController: _contentController,
      titleFocusNode: _titleFocusNode,
      contentFocusNode: _contentFocusNode,
      contentFieldContextKey: _contentFieldContextKey,
      copy: copy,
      pageTitle: pageTitle,
      showPageHeader: !widget.showAppBar,
      statusUnavailable: false,
      onBack: widget.showAppBar ? null : () => unawaited(_handleBack()),
      backTooltip: copy.back,
      backKey: NoteDetailPage.backKey,
      hasSavedNote: _note != null,
      isDirty: _isDirty,
      error: _error ?? summaryFailure?.message,
      statusMessage: _statusMessage,
      actionBusy: _actionBusy,
      provisioningReader: widget.provisioningReader,
      onProvisioningRetry: _note == null ? null : _summarize,
      onProvisioningCancel: widget.onProvisioningCancel,
      summary: _summaryController.summary,
      summaryStale: _summaryController.isStale,
      onCopySummary: _summaryController.summary == null
          ? null
          : () => unawaited(_copySummary()),
      onRegenerateSummary: _canSummarize ? () => unawaited(_summarize()) : null,
      copySummaryLabel: copy.copySummary,
      regenerateSummaryLabel: copy.regenerate,
      onErrorRetry: _saveFailed
          ? () => unawaited(_save(automatic: true))
          : summaryFailure == null
          ? null
          : () => unawaited(_summarize()),
      errorRetryLabel: _saveFailed ? copy.retry : summaryFailure?.retryLabel,
      errorRetryEnabled: _saveFailed
          ? _canSave
          : summaryFailure?.retryEnabled ?? false,
      summaryAvailability: _summaryAvailability,
      summaryCloud:
          widget.notesController.summaryConsent?.requiresCloudConsent ?? false,
      onCancelSummary: _summaryController.isRunning ? _cancelSummary : null,
      isSaving: _saving,
      isSummarizing: _summaryController.isRunning,
      showBusyIndicator: !_summaryController.isAwaitingConsent,
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
    final SyncConflict? conflict = _currentConflict;
    final SyncPresentationController? sync = widget.syncController;
    if (conflict == null && sync == null) {
      return editor;
    }
    return Column(
      children: <Widget>[
        if (sync != null && widget.onEmbeddedExit == null)
          SyncStatusPanel(controller: sync),
        if (sync != null && _note != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SyncNoteStatusBadge(controller: sync, noteId: _note!.id),
            ),
          ),
        if (conflict != null) _buildConflictNotice(),
        Expanded(child: editor),
      ],
    );
  }

  Widget _buildConflictNotice() {
    final SyncCopy copy = SyncCopy.of(context);
    return Card(
      key: const ValueKey<String>('note-sync-conflict'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.compare_arrows),
            const SizedBox(width: 10),
            Expanded(child: Text(copy.conflictTitle)),
            FilledButton.tonal(
              key: const ValueKey<String>('note-sync-resolve-conflict'),
              onPressed: _actionBusy
                  ? null
                  : () => unawaited(_resolveConflict()),
              child: Text(copy.resolveConflict),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _summaryController.removeListener(_summaryChanged);
    _summaryController.dispose();
    _autosaveTimer?.cancel();
    widget.syncController?.removeListener(_syncStateChanged);
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
