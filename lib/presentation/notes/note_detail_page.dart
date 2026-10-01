import '../../application/notes/note_access.dart';
import 'note_security_dialog.dart';
import 'note_security_localizations.dart';
import 'note_security_panel.dart';

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

part 'note_detail_actions.dart';
part 'note_detail_conflicts.dart';
part 'note_detail_view.dart';
part 'note_detail_security.dart';

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

final class _NoteDetailPageState extends State<NoteDetailPage> {
  static const Duration _autosaveDelay = Duration(seconds: 3);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final GlobalKey _contentFieldContextKey = GlobalKey();
  Timer? _autosaveTimer;
  StreamSubscription<void>? _securitySubscription;
  bool _securityBusy = false;
  bool _securityLoading = false;
  int _securityRead = 0;
  int? _securitySession;
  void _update(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => _buildDetail(context);

  late NoteDto? _note;
  NoteDto? _pendingSavedNote;
  late String _savedTitle;
  late String _savedContent;
  String? _error;
  String? _statusMessage;
  bool _saving = false;
  bool _deleting = false;
  bool _didPersist = false;
  bool _lastReportedDirty = false;
  bool _backConfirmationVisible = false;
  bool _ignoreNextEditorFocusLoss = false;
  bool _conflictFlowActive = false;
  bool _resolvingConflict = false;

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
    _listenSecurity();
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
      _securityRead++;
      _summaryController.cancelActive(
        reason: SummaryRunFailureCode.noteChanged,
      );
      _summaryController.markStaleIfResult();
      final NoteDto? incoming = widget.note;
      final bool sameIdentity =
          incoming?.id == _note?.id && incoming?.ownerId == _note?.ownerId;
      if (!sameIdentity) _summaryController.clearResult();
      if (!_isDirty || !sameIdentity) {
        if (incoming?.isProtected == true) {
          _adoptSavedNote(_masked(incoming!));
          unawaited(_readSecuredNote());
        } else {
          _adoptSavedNote(incoming);
        }
      } else {
        _pendingSavedNote = incoming;
      }
    }
    if (oldWidget.notesController != widget.notesController) {
      unawaited(_securitySubscription?.cancel());
      _listenSecurity();
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
      _saving ||
      _deleting ||
      _resolvingConflict ||
      _summaryController.isBusy ||
      _securityBusy ||
      _securityLoading;

  bool get _canSave =>
      !_actionBusy &&
      _canEdit &&
      _currentConflict == null &&
      (_note == null || _isDirty);

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
      _canRead &&
      (_note == null || _capabilities.canSummarize) &&
      _summaryController.canStart &&
      _summaryAvailability.canStart;

  void _editorChanged() {
    if (!mounted) return;
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
        !_canEdit ||
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
  void dispose() {
    _securityRead++;
    unawaited(_securitySubscription?.cancel());
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
