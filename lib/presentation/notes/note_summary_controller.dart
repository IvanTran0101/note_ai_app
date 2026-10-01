import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/note_intelligence/summary_consent_app_service.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import '../../application/notes/note_application.dart';
import 'note_summary_availability.dart';
import 'notes_application_controller.dart';

final class NoteSummaryController extends ChangeNotifier {
  NoteSummaryController({
    required NotesApplicationController Function() notesController,
    required NoteSummaryEditorFacts Function() editorFacts,
    required this._confirmConsent,
  }) : _readNotesController = notesController,
       _readEditorFacts = editorFacts;

  final NotesApplicationController Function() _readNotesController;
  final NoteSummaryEditorFacts Function() _readEditorFacts;
  final Future<bool> Function() _confirmConsent;

  String? _summary;
  int _acceptedResults = 0;
  bool _stale = false;
  bool _running = false;
  bool _awaitingConsent = false;
  bool _untypedFailure = false;
  bool _cloudRun = false;
  bool _disposed = false;
  SummaryRunFailureCode? _failureCode;
  SummaryRunScope? _scope;
  NoteDto? _blockedSnapshot;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  String? get summary => _summary;

  int get acceptedResultCount => _acceptedResults;

  bool get isStale => _stale;

  bool get isRunning => _running;

  bool get isAwaitingConsent => _awaitingConsent;

  bool get isBusy => _running || _awaitingConsent;

  bool get isCloudRun => _cloudRun;

  bool get isCoolingDown => _cooldownSeconds > 0;

  int get cooldownSeconds => _cooldownSeconds;

  SummaryRunFailureCode? get failureCode => _failureCode;

  bool get hasUntypedFailure => _untypedFailure;

  bool get hasFailure => _failureCode != null || _untypedFailure;

  bool get canStart {
    final NoteDto? blocked = _blockedSnapshot;
    final NoteDto? current = _readEditorFacts().note;
    return !_disposed &&
        !isBusy &&
        !isCoolingDown &&
        (blocked == null || current == null || !current.hasSameTextAs(blocked));
  }

  NoteSummaryAvailability availability({
    required bool hasSavedNote,
    required bool isDirty,
    required bool hasConflict,
  }) {
    return noteSummaryAvailability(
      consent: _readNotesController().summaryConsent,
      hasSavedNote: hasSavedNote,
      isDirty: isDirty,
      hasConflict: hasConflict,
    );
  }

  Future<void> run() async {
    if (_disposed || !canStart) {
      return;
    }
    final NotesApplicationController notes = _readNotesController();
    final NoteSummaryEditorFacts facts = _readEditorFacts();
    final NoteDto? note = facts.note;
    if (note == null || !_readyToStart(facts)) {
      return;
    }

    final SummaryConsentAppService? consent = notes.summaryConsent;
    final bool cloud = consent != null && consent.requiresCloudConsent;
    SummaryConsentRequest? request;
    if (cloud) {
      final SummaryConsentStatus status = consent.state;
      if (status == SummaryConsentStatus.consentRequired) {
        try {
          request = consent.beginConsent();
        } on SummaryRunFailure catch (failure) {
          _recordFailure(failure);
          return;
        }
      } else if (status != SummaryConsentStatus.granted) {
        return;
      }
    }

    final SummaryRunScope scope = _beginRun(
      cloud: cloud,
      awaitingConsent: request != null,
    );
    try {
      await Future.any<void>(<Future<void>>[
        _runCaptured(scope, note, notes, consent, request),
        scope.whenCancelled.then((_) {}),
      ]);
    } on Object catch (error) {
      if (_owns(scope) && !scope.isCancelled) {
        _recordFailure(
          error is SummaryRunFailure
              ? error
              : const SummaryRunFailure(SummaryRunFailureCode.unexpected),
        );
      }
    } finally {
      _finishRun(scope);
    }
  }

  Future<void> _runCaptured(
    SummaryRunScope scope,
    NoteDto note,
    NotesApplicationController notes,
    SummaryConsentAppService? consent,
    SummaryConsentRequest? request,
  ) async {
    if (request != null && !await _acceptConsent(scope)) return;
    if (!_isCurrent(scope)) return;
    _awaitingConsent = false;
    _running = true;
    _notify();
    if (!await _revalidate(scope, note, notes)) return;
    if (!_grant(scope, consent, request)) return;
    await _dispatch(scope, note, notes);
  }

  void cancelActive({
    SummaryRunFailureCode reason = SummaryRunFailureCode.cancelled,
  }) {
    final SummaryRunScope? scope = _scope;
    if (scope == null && !_running && !_awaitingConsent) {
      return;
    }
    _scope = null;
    _running = false;
    _awaitingConsent = false;
    scope?.cancel(reason: reason);
    _notify();
  }

  void markStaleIfResult() {
    if (_summary == null || _stale) {
      return;
    }
    _stale = true;
    _notify();
  }

  void clearFailure() {
    if (!hasFailure) {
      return;
    }
    _failureCode = null;
    _untypedFailure = false;
    _notify();
  }

  void clearResult() {
    _summary = null;
    _stale = false;
    _blockedSnapshot = null;
    clearFailure();
    _notify();
  }

  bool _readyToStart(NoteSummaryEditorFacts facts) {
    return availability(
      hasSavedNote: true,
      isDirty: facts.isDirty,
      hasConflict: facts.hasConflict,
    ).canStart;
  }

  SummaryRunScope _beginRun({
    required bool cloud,
    required bool awaitingConsent,
  }) {
    _scope?.cancel(reason: SummaryRunFailureCode.cancelled);
    final SummaryRunScope scope = SummaryRunScope();
    _scope = scope;
    _cloudRun = cloud;
    _failureCode = null;
    _untypedFailure = false;
    _running = !awaitingConsent;
    _awaitingConsent = awaitingConsent;
    _notify();
    return scope;
  }

  Future<bool> _acceptConsent(SummaryRunScope scope) async {
    final bool allowed = await _confirmConsent();
    if (!_isCurrent(scope)) {
      scope.release();
      return false;
    }
    if (allowed) {
      return true;
    }
    _finishRun(scope);
    return false;
  }

  Future<bool> _revalidate(
    SummaryRunScope scope,
    NoteDto snapshot,
    NotesApplicationController notes,
  ) async {
    if (!_matchesEditor(scope, snapshot, notes)) {
      return false;
    }
    final List<NoteDto> owned = await notes.listNotes();
    if (!_matchesEditor(scope, snapshot, notes)) {
      return false;
    }
    for (final NoteDto candidate in owned) {
      if (candidate.id == snapshot.id) {
        if (candidate.hasSameTextAs(snapshot)) return true;
        _recordFailure(
          const SummaryRunFailure(SummaryRunFailureCode.noteChanged),
        );
        markStaleIfResult();
        return false;
      }
    }
    _recordFailure(const SummaryRunFailure(SummaryRunFailureCode.noteNotFound));
    return false;
  }

  bool _matchesEditor(
    SummaryRunScope scope,
    NoteDto snapshot,
    NotesApplicationController notes,
  ) {
    if (_disposed || !_isCurrent(scope)) {
      return false;
    }
    if (!identical(_readNotesController(), notes)) {
      return false;
    }
    final NoteSummaryEditorFacts facts = _readEditorFacts();
    return facts.note != null &&
        facts.note!.hasSameTextAs(snapshot) &&
        !facts.isDirty &&
        !facts.hasConflict;
  }

  bool _grant(
    SummaryRunScope scope,
    SummaryConsentAppService? consent,
    SummaryConsentRequest? request,
  ) {
    final SummaryConsentAppService? service = consent;
    if (!_isCurrent(scope) || (request != null && service == null)) {
      _finishRun(scope);
      return false;
    }
    if (request == null) {
      return true;
    }
    try {
      // Synchronous by contract: it rechecks the captured account, session
      // generation, runtime, and consent generation before it mutates.
      service!.grantConsent(request);
    } on SummaryRunFailure catch (failure) {
      _recordFailure(failure);
      return false;
    }
    return _isCurrent(scope);
  }

  Future<void> _dispatch(
    SummaryRunScope scope,
    NoteDto note,
    NotesApplicationController notes,
  ) async {
    if (!_isCurrent(scope)) {
      _finishRun(scope);
      return;
    }
    _awaitingConsent = false;
    _running = true;
    _notify();
    try {
      final String summary = await notes.summarizeNote(
        note.id,
        selectedSnapshot: note,
        scope: scope,
      );
      if (!_matchesEditor(scope, note, notes)) {
        return;
      }
      _summary = summary;
      _acceptedResults += 1;
      _stale = false;
      _failureCode = null;
      _untypedFailure = false;
      _clearCooldown();
    } on SummaryRunFailure catch (failure) {
      if (!_isCurrent(scope) || _isSilent(failure.code)) {
        return;
      }
      if (failure.code == SummaryRunFailureCode.invalidInput ||
          failure.code == SummaryRunFailureCode.inputTooLong ||
          failure.code == SummaryRunFailureCode.pipelineTooLarge) {
        _blockedSnapshot = note;
      }
      _recordFailure(failure);
    } on Object {
      if (!_isCurrent(scope)) {
        return;
      }
      _failureCode = null;
      _untypedFailure = true;
      _notify();
    }
  }

  bool _isCurrent(SummaryRunScope scope) =>
      !_disposed && !scope.isCancelled && identical(_scope, scope);

  bool _owns(SummaryRunScope scope) => !_disposed && identical(_scope, scope);

  void _finishRun(SummaryRunScope scope) {
    if (identical(_scope, scope)) {
      _scope = null;
      _running = false;
      _awaitingConsent = false;
    }
    scope.release();
    _notify();
  }

  void _recordFailure(SummaryRunFailure failure) {
    _failureCode = failure.code;
    _untypedFailure = false;
    _startCooldown(failure);
    _notify();
  }

  void _startCooldown(SummaryRunFailure failure) {
    final int? hint = failure.retryAfterSeconds;
    if (failure.code != SummaryRunFailureCode.rateLimited || hint == null) {
      return;
    }
    _clearCooldown();
    _cooldownSeconds = hint;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      _cooldownSeconds -= 1;
      if (_cooldownSeconds <= 0) {
        _cooldownSeconds = 0;
        timer.cancel();
        _cooldownTimer = null;
      }
      _notify();
    });
  }

  void _clearCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _cooldownSeconds = 0;
  }

  static bool _isSilent(SummaryRunFailureCode code) => switch (code) {
    SummaryRunFailureCode.cancelled ||
    SummaryRunFailureCode.sessionChanged => true,
    _ => false,
  };

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _clearCooldown();
    _scope?.cancel();
    _scope = null;
    _running = false;
    _awaitingConsent = false;
    super.dispose();
  }
}
