import '../labels/note_label_editor.dart';
import '../../application/notes/note_access.dart';
import '../../application/notes/note_security_service.dart';
import 'note_security_dialog.dart';
import 'attachment_editor_panel.dart';
import 'attachment_editor_controller.dart';
import 'note_security_localizations.dart';
import 'note_security_panel.dart';
import 'sharing_localizations.dart';
import 'share_management_dialog.dart';
import '../../application/notes/note_editor_snapshot.dart';

import 'dart:async';

import '../../domain/notes/note_document.dart';
import '../editor/rich_editor_adapter.dart';
import '../editor/rich_note_editor.dart';
import '../editor/editor_copy.dart';
import '../editor/editor_projection_map.dart';
import '../common/note_flow_primitives.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'notes_theme_tokens.dart';
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
part 'note_detail_rag_part.dart';
part 'note_detail_view.dart';
part 'note_detail_compact_actions.dart';
part 'note_detail_labels.dart';
part 'note_detail_security.dart';
part 'note_detail_sharing.dart';
part 'note_detail_document.dart';
part 'note_detail_files.dart';
part 'note_detail_autosave.dart';
part 'note_detail_sync_state.dart';

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
    this.initialContentSelection,
    this.onNoteEdited,
    this.onOpenNoteRag,
    this.syncController,
  });

  final NotesApplicationController notesController;
  final NoteDto? note;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningCancel;
  final bool showAppBar;
  final ValueChanged<NoteDetailRouteResult>? onEmbeddedExit;
  final ValueChanged<bool>? onDirtyChanged;

  /// A one-shot citation reveal applied after this editor is laid out.
  ///
  /// The value is presentation-only: a raw [TextSelection] into the content
  /// editor. It carries no RAG/domain type and never mutates the saved note.
  final NoteDetailSelectionRequest? initialContentSelection;

  /// Reports a real title/text edit of the saved note before autosave.
  ///
  /// It is not fired for a selection move, focus change, or initial hydration;
  /// the composition root uses it to invalidate stale citations and, when an
  /// account query is live, to cancel it conservatively.
  final ValueChanged<NoteDto>? onNoteEdited;

  /// Opens the ask-notes screen for the current saved note.
  ///
  /// Supplied only when the composition root offers the feature. The action is
  /// rendered for a saved, owned, synced, unprotected, unshared, clean note
  /// with no active operation; the application service remains the authority
  /// for the local preconditions.
  final ValueChanged<NoteDto>? onOpenNoteRag;
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
  static const Key askNotesKey = ValueKey<String>('note-detail-ask-notes');

  @override
  NoteDetailPageState createState() => NoteDetailPageState();
}

final class NoteDetailPageState extends State<NoteDetailPage>
    with WidgetsBindingObserver {
  static const Duration _autosaveDelay = Duration(seconds: 3);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final GlobalKey _contentFieldContextKey = GlobalKey();
  RichEditorAdapter? _richEditor;
  late final AttachmentEditorController _inlineFiles =
      AttachmentEditorController(readReferencedIds: () => _fileReferences);
  NoteDocument? _savedDocument;
  int _editorEpoch = 0;
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
  bool _saveFailed = false;
  bool _deleting = false;
  bool _didPersist = false;
  bool _lastReportedDirty = false;
  bool _backConfirmationVisible = false;
  bool _ignoreNextEditorFocusLoss = false;
  bool _conflictFlowActive = false;
  bool _resolvingConflict = false;

  /// Last text observed from the editor fields, so a listener firing for a
  /// selection/cursor change is not mistaken for a title/content edit.
  String? _lastEditorTitle;
  String? _lastEditorContent;

  /// Monotonic token that lets a stale reveal callback stand down.
  int _selectionRequestToken = 0;

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
    _lastEditorTitle = _titleController.text;
    _lastEditorContent = _contentController.text;
    _resetRichEditor();
    _titleController.addListener(_editorChanged);
    _contentController.addListener(_editorChanged);
    _titleFocusNode.addListener(_titleFocusChanged);
    _contentFocusNode.addListener(_contentFocusChanged);
    _summaryController.addListener(_summaryChanged);
    widget.syncController?.addListener(_syncStateChanged);
    _listenSecurity();
    final NoteDetailSelectionRequest? selection =
        widget.initialContentSelection;
    if (selection != null) _applySelectionRequest(selection);
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
    final NoteDetailSelectionRequest? selection =
        widget.initialContentSelection;
    if (selection != null &&
        !identical(oldWidget.initialContentSelection, selection)) {
      // The same note may already be open (same key, updated widget); a fresh
      // citation request still has to reveal its span exactly once.
      _applySelectionRequest(selection);
    }
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
      final NoteDto? previous = oldWidget.note;
      final bool sameText =
          previous != null && incoming != null && previous == incoming;
      if (!sameText) {
        _summaryController.cancelActive(
          reason: SummaryRunFailureCode.noteChanged,
        );
        _summaryController.markStaleIfResult();
      }
      if (!sameIdentity) _summaryController.clearResult();
      final accessChanged =
          sameIdentity &&
          _note?.share != null &&
          (incoming?.share != _note?.share ||
              incoming?.contentAvailable != true);
      if (accessChanged) {
        _retainDirtySharedDraft();
        _summaryController.clearResult();
        _adoptSavedNote(incoming?.metadataOnly());
        unawaited(_readSecuredNote());
      } else if (!_isDirty || !sameIdentity) {
        if (incoming?.isProtected == true) {
          _adoptSavedNote(_masked(incoming!));
          unawaited(_readSecuredNote());
        } else {
          _adoptSavedNote(incoming);
        }
      } else if (incoming != null && _rebaseUnchangedSavedText(incoming)) {
        // The saved text is unchanged; preserve the newer editor draft.
      } else {
        _pendingSavedNote = incoming;
        _autosaveTimer?.cancel();
        if (incoming?.isProtected == true) unawaited(_readSecuredNote());
      }
    }
    if (oldWidget.notesController != widget.notesController) {
      unawaited(_securitySubscription?.cancel());
      _listenSecurity();
      _summaryController.cancelActive(
        reason: SummaryRunFailureCode.sessionChanged,
      );
      _summaryController.clearResult();
      _resetRichEditor();
    }
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

  bool get _isDirty =>
      _titleController.text != _savedTitle ||
      _contentController.text != _savedContent ||
      _editorDocument != _savedDocument;

  bool get _actionBusy =>
      _saving ||
      _deleting ||
      _resolvingConflict ||
      _summaryController.isBusy ||
      _securityBusy ||
      _securityLoading;

  bool get hasActiveOperation => _actionBusy || _backConfirmationVisible;

  /// Layout fact for the workspace; includes a new note not yet in its list.
  bool get rendersSyncHeader => mounted && !widget.showAppBar && _canRead;

  Future<void> requestClose() =>
      _backConfirmationVisible ? Future<void>.value() : _handleBack();

  bool get _canSave =>
      !_actionBusy &&
      _canEdit &&
      !_hasRemoteEditorChange &&
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
    WidgetsBinding.instance.removeObserver(this);
    if (!_canEdit) _retainDirtySharedDraft();
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
    _editorEpoch++;
    _richEditor?.dispose();
    _inlineFiles.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }
}
