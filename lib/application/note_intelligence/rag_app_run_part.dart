// Question-run lifecycle: dispatch guard, deadline, consent, and result apply.
part of 'rag_app_service.dart';

extension on RagAppService {
  /// Implementation of [RagAppService.ask].
  ///
  /// Everything the run depends on is captured before the first await, the
  /// current note is captured before the first dispatch, and every await is
  /// raced against the run's cancellation and deadline.
  Future<void> _ask({
    required String question,
    required RagScope scope,
  }) async {
    if (_disposed) return;
    _enforceActorBinding();
    final String? actorId = _liveActorId;
    if (actorId == null) {
      _fail(const RagFailure(RagFailureCode.unauthorized));
      return;
    }
    final int sessionGeneration = session.sessionGeneration;
    if (_activeRun != null) {
      _fail(const RagFailure(RagFailureCode.alreadyRunning));
      return;
    }
    final RagQuestionProblem? problem = RagRequest.questionProblem(question);
    if (problem != null) {
      _fail(
        RagFailure(
          problem == RagQuestionProblem.tooLong
              ? RagFailureCode.inputTooLong
              : RagFailureCode.invalidInput,
        ),
      );
      return;
    }
    if (!_state.active) {
      _fail(const RagFailure(RagFailureCode.cancelled));
      return;
    }
    if (_state.consentLoading) {
      _fail(const RagFailure(RagFailureCode.consentUnknown));
      return;
    }
    final RagConsent? consent = _currentConsent(actorId, sessionGeneration);
    if (consent == null) {
      _fail(const RagFailure(RagFailureCode.consentUnknown));
      return;
    }
    if (!consent.accepted) {
      _fail(const RagFailure(RagFailureCode.consentRequired));
      return;
    }

    final bool scopeChanged = _state.scope != scope;
    final RagRunContext run = RagRunContext(
      actorId: actorId,
      sessionGeneration: sessionGeneration,
      consentGeneration: consent.generation,
      scope: scope,
      question: question,
      deadline: _now().add(RagCallContext.requestBudget),
    );
    _activeRun = run;
    _runNoteSnapshot = null;
    _armRunDeadline(run);
    _emit(
      _state.copyWith(
        queryRunning: true,
        scope: scope,
        failure: null,
        result: scopeChanged ? null : _state.result,
        resultQuestion: scopeChanged ? null : _state.resultQuestion,
      ),
    );
    try {
      final String? noteId = scope.noteId;
      if (noteId != null) {
        _runNoteSnapshot = await run.race(_captureCurrentNote(run, noteId));
        _requireRunLive(run);
      }
      final RagConsent canonical = await run.race(
        gateway.readConsent(context: _runContext(run)),
      );
      _requireRunLive(run);
      _requireRunConsent(run, canonical);
      final RagResult result = await run.race(
        gateway.query(
          RagRequest(question: run.question, scope: run.scope),
          context: _runContext(run),
        ),
      );
      _requireRunLive(run);
      await _applyResult(run, result);
      if (!identical(_activeRun, run)) return;
      _activeRun = null;
      _runNoteSnapshot = null;
      run.dispose();
      _emit(_state.copyWith(queryRunning: false, failure: null));
    } on RagFailure catch (failure) {
      _finishRun(run, failure);
    } catch (_) {
      _finishRun(run, const RagFailure(RagFailureCode.unexpected));
    } finally {
      run.dispose();
    }
  }

  RagCallContext _runContext(RagRunContext run) => RagCallContext(
    expectedUserId: run.actorId,
    cancelled: run.whenCancelled,
    beforeDispatch: () => _beforeRunDispatch(run),
    deadline: run.deadline,
  );

  /// The local/session/liveness guard awaited immediately before every
  /// dispatch of [run].
  ///
  /// For a current-note question it also re-reads the local state and compares
  /// the captured note against it, so a note that changed during the consent or
  /// token wait aborts the dispatch instead of being queried. An account
  /// question has no local precondition here.
  Future<void> _beforeRunDispatch(RagRunContext run) async {
    _requireRunLive(run);
    final LocalNoteState? snapshot = _snapshotFor(run);
    if (snapshot == null) return;
    final LocalSyncState local = await run.race(_readLocalState(run.actorId));
    _requireRunLive(run);
    final RagFailureCode? failure = _currentNoteFailure(
      local,
      run.actorId,
      snapshot,
    );
    if (failure != null) throw RagFailure(failure);
  }

  /// The captured current-note snapshot, only while [run] is the active one.
  LocalNoteState? _snapshotFor(RagRunContext run) =>
      identical(_activeRun, run) ? _runNoteSnapshot : null;

  void _armRunDeadline(RagRunContext run) {
    run.armDeadline(
      run.deadline.difference(_now()),
      () => run.cancel(RagFailureCode.timeout),
    );
  }

  RagFailureCode? _runFailure(RagRunContext run) {
    if (run.isCancelled) {
      return run.cancelReason ?? RagFailureCode.cancelled;
    }
    if (_disposed || !identical(_activeRun, run) || !_state.active) {
      return RagFailureCode.cancelled;
    }
    final String? actorId = _liveActorId;
    if (actorId == null ||
        !run.matchesBinding(
          actorId: actorId,
          sessionGeneration: session.sessionGeneration,
        )) {
      return RagFailureCode.sessionChanged;
    }
    if (run.isExpired(_now())) {
      return RagFailureCode.timeout;
    }
    if (_state.consentLoading) {
      return RagFailureCode.consentUnknown;
    }
    final RagConsent? consent = _currentConsent(
      run.actorId,
      run.sessionGeneration,
    );
    if (consent == null) {
      return RagFailureCode.consentUnknown;
    }
    if (!consent.accepted || consent.generation != run.consentGeneration) {
      return RagFailureCode.consentRequired;
    }
    return null;
  }

  /// The synchronous session/consent/liveness recheck after every await.
  void _requireRunLive(RagRunContext run) {
    final RagFailureCode? code = _runFailure(run);
    if (code == null) return;
    if (code == RagFailureCode.timeout) run.cancel(code);
    throw RagFailure(code);
  }

  /// Adopts the canonical grant and refuses a run the grant moved under.
  ///
  /// The same accepted value with a new generation is stale, exactly like a
  /// revoke: only the generation the question was admitted under may answer it,
  /// and a moved grant also clears any answer the old grant displayed.
  void _requireRunConsent(RagRunContext run, RagConsent canonical) {
    _consentActorId = run.actorId;
    _consentSessionGeneration = run.sessionGeneration;
    if (!canonical.accepted || canonical.generation != run.consentGeneration) {
      _emit(
        _state.copyWith(
          consent: canonical,
          consentLoading: false,
          result: null,
          resultQuestion: null,
        ),
      );
      throw const RagFailure(RagFailureCode.consentRequired);
    }
    _emit(_state.copyWith(consent: canonical));
  }

  /// Applies one result after revalidating the grant and every citation.
  ///
  /// The local state is read once for the whole answer, not once per source,
  /// and every source must match the current local note before any of the
  /// answer becomes visible. A refusal carries no note text, so it applies
  /// without a second consent read.
  Future<void> _applyResult(RagRunContext run, RagResult result) async {
    if (result.isAnswered) {
      final RagConsent canonical = await run.race(
        gateway.readConsent(context: _runContext(run)),
      );
      _requireRunLive(run);
      _requireRunConsent(run, canonical);
      final LocalSyncState local = await run.race(
        _readLocalState(run.actorId),
      );
      _requireRunLive(run);
      for (final RagSource source in result.sources) {
        _requireSourceNote(local, run.actorId, source);
      }
    }
    if (!identical(_activeRun, run)) return;
    _emit(
      _state.copyWith(
        result: result,
        resultQuestion: run.question,
        failure: null,
      ),
    );
  }

  void _finishRun(RagRunContext run, RagFailure failure) {
    if (!identical(_activeRun, run)) return;
    _activeRun = null;
    _runNoteSnapshot = null;
    run.dispose();
    _emit(_state.copyWith(queryRunning: false, failure: failure));
  }

  void _cancelActiveRun(RagFailureCode reason) {
    final RagRunContext? run = _activeRun;
    if (run == null) return;
    _activeRun = null;
    _runNoteSnapshot = null;
    run.cancel(reason);
    run.dispose();
  }
}
