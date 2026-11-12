// Bounded source checks: displayed-answer membership and local currency.
part of 'rag_app_service.dart';

extension on RagAppService {
  /// Implementation of [RagAppService.validateSource].
  ///
  /// The displayed answer, grant, and session are captured synchronously, then
  /// one bounded canonical consent read revalidates the grant before one bounded
  /// local read checks the note, and the same identity is rechecked before the
  /// note is returned. A revoke or a moved grant on another device is therefore
  /// seen here: the local grant alone would still authorize the citation.
  ///
  /// Exactly one gateway read happens per open, inside the existing source-call
  /// budget; [RagAppService.onLocalStateChanged] still performs none.
  Future<NoteDto> _validateSource(RagSource source) async {
    if (_disposed) throw const RagFailure(RagFailureCode.cancelled);
    _enforceActorBinding();
    final String? actorId = _liveActorId;
    if (actorId == null) throw const RagFailure(RagFailureCode.unauthorized);
    if (!_state.active) throw const RagFailure(RagFailureCode.cancelled);
    final int sessionGeneration = session.sessionGeneration;
    final RagResult? displayed = _state.result;
    if (!_isDisplayedSource(displayed, source)) {
      throw const RagFailure(RagFailureCode.sourceChanged);
    }
    if (_state.consentLoading) {
      throw const RagFailure(RagFailureCode.consentUnknown);
    }
    final RagConsent? consent = _currentConsent(actorId, sessionGeneration);
    if (consent == null) {
      throw const RagFailure(RagFailureCode.consentUnknown);
    }
    if (!consent.accepted) {
      throw const RagFailure(RagFailureCode.consentRequired);
    }
    final RagCallScope call = _beginSourceCall();
    bool readSent = false;
    bool readSettled = false;
    try {
      final RagConsent canonical = await call.race(
        gateway.readConsent(
          context: RagCallContext(
            expectedUserId: actorId,
            cancelled: call.whenCancelled,
            beforeDispatch: () async {
              _beforeSourceDispatch(
                call,
                actorId,
                sessionGeneration,
                displayed,
                consent,
              );
              readSent = true;
            },
            deadline: call.deadline,
          ),
        ),
      );
      readSettled = true;
      _requireSourceCallLive(call, actorId, sessionGeneration);
      _requireDisplayUnchanged(displayed);
      final RagFailureCode? grantFailure = _adoptCanonicalGrant(
        actorId,
        sessionGeneration,
        consent,
        canonical,
      );
      if (grantFailure != null) {
        throw RagFailure(grantFailure);
      }
      final LocalSyncState local = await call.race(_readLocalState(actorId));
      _requireSourceCallLive(call, actorId, sessionGeneration);
      _requireDisplayUnchanged(displayed);
      _requireGrantUnchanged(actorId, sessionGeneration, canonical);
      return NoteDto.fromLocalState(_requireSourceNote(local, actorId, source));
    } on RagFailure catch (failure) {
      if (readSent && !readSettled && _grantReadInvalidates(failure)) {
        // The read left the process and produced no grant at all: the known
        // grant, and the answer it authorized, are unknown now.
        _clearGrantForFailedRead(failure);
      }
      _clearDisplayForSourceFailure(displayed, failure);
      rethrow;
    } finally {
      _sourceCalls.remove(call);
      call.dispose();
    }
  }

  /// The guard awaited immediately before the consent read of one source open.
  ///
  /// It rechecks only what was captured locally: the source call itself, the
  /// session, the displayed answer, and the known grant. It never reads the
  /// gateway or the local store, so it cannot recurse into the consent call it
  /// guards, and it performs no source GET.
  void _beforeSourceDispatch(
    RagCallScope call,
    String actorId,
    int sessionGeneration,
    RagResult? displayed,
    RagConsent consent,
  ) {
    _requireSourceCallLive(call, actorId, sessionGeneration);
    _requireDisplayUnchanged(displayed);
    _requireGrantUnchanged(actorId, sessionGeneration, consent);
  }

  /// Adopts the canonical grant and reports the failure that stops the open,
  /// or null while the open may continue.
  ///
  /// A revoke clears the displayed pair and reports
  /// [RagFailureCode.consentRequired]: the permission itself is gone. An
  /// accepted grant that merely moved to a new generation is not a withdrawal —
  /// the new grant is adopted, and the former is retained — but the answer the
  /// old generation authorized is stale, so the pair is cleared and the failure
  /// is [RagFailureCode.sourceChanged].
  RagFailureCode? _adoptCanonicalGrant(
    String actorId,
    int sessionGeneration,
    RagConsent captured,
    RagConsent canonical,
  ) {
    _consentActorId = actorId;
    _consentSessionGeneration = sessionGeneration;
    if (!canonical.accepted) {
      _emit(
        _state.copyWith(
          consent: canonical,
          consentLoading: false,
          result: null,
          resultQuestion: null,
          failure: const RagFailure(RagFailureCode.consentRequired),
        ),
      );
      return RagFailureCode.consentRequired;
    }
    if (canonical.generation != captured.generation) {
      _emit(
        _state.copyWith(
          consent: canonical,
          consentLoading: false,
          result: null,
          resultQuestion: null,
          failure: const RagFailure(RagFailureCode.sourceChanged),
        ),
      );
      return RagFailureCode.sourceChanged;
    }
    if (_state.consent != canonical) {
      _emit(_state.copyWith(consent: canonical, consentLoading: false));
    }
    return null;
  }

  /// Whether a consent read that produced nothing invalidates the known grant.
  ///
  /// A local cancel and a session change are owned by the lifecycle path that
  /// produced them; neither removes a still-valid answer by itself.
  bool _grantReadInvalidates(RagFailure failure) =>
      failure.code != RagFailureCode.cancelled &&
      failure.code != RagFailureCode.sessionChanged;

  /// Drops the known grant and the pair it authorized after a failed read.
  void _clearGrantForFailedRead(RagFailure failure) {
    _clearConsentBinding();
    _emit(
      _state.copyWith(
        consent: null,
        consentLoading: false,
        result: null,
        resultQuestion: null,
        failure: failure,
      ),
    );
  }

  /// Implementation of [RagAppService.onLocalStateChanged].
  ///
  /// One read revalidates the captured display and the in-flight run; the hook
  /// never queries, never touches consent, and never throws.
  Future<void> _onLocalStateChanged() async {
    if (_disposed) return;
    _enforceActorBinding();
    final String? actorId = _liveActorId;
    if (actorId == null) return;
    final RagResult? displayed = _state.result;
    final RagRunContext? run = _activeRun;
    final String? runNoteId = run?.scope.noteId;
    if (displayed == null && runNoteId == null) return;
    final int sessionGeneration = session.sessionGeneration;
    final RagCallScope call = _beginSourceCall();
    try {
      final LocalSyncState local = await call.race(_readLocalState(actorId));
      _requireSourceCallLive(call, actorId, sessionGeneration);
      _revalidateDisplayedAnswer(displayed, local, actorId);
      _revalidateInFlightNote(run, runNoteId, local, actorId);
    } on RagFailure {
      // A read that failed or was cut short proves nothing about the answer.
    } finally {
      _sourceCalls.remove(call);
      call.dispose();
    }
  }

  /// Starts one bounded, cancellable local read for a source check.
  ///
  /// The shared request budget applies to a source open exactly as it does to a
  /// question, and logout, inactivity, or disposal cancels the read, so a
  /// hanging store can never hold a caller forever.
  RagCallScope _beginSourceCall() {
    final RagCallScope call = RagCallScope(
      deadline: _now().add(RagCallContext.requestBudget),
    );
    call.armDeadline(
      call.deadline.difference(_now()),
      () => call.cancel(RagFailureCode.timeout),
    );
    _sourceCalls.add(call);
    return call;
  }

  /// Cancels every in-flight source check.
  void _cancelSourceCalls(RagFailureCode reason) {
    if (_sourceCalls.isEmpty) return;
    final List<RagCallScope> calls = List<RagCallScope>.of(_sourceCalls);
    _sourceCalls.clear();
    for (final RagCallScope call in calls) {
      call.cancel(reason);
      call.dispose();
    }
  }

  void _requireSourceCallLive(
    RagCallScope call,
    String actorId,
    int sessionGeneration,
  ) {
    if (call.isCancelled) {
      throw RagFailure(call.cancelReason ?? RagFailureCode.cancelled);
    }
    if (_disposed || !_state.active) {
      throw const RagFailure(RagFailureCode.cancelled);
    }
    if (!currentUser.isAuthenticated ||
        currentUser.userId != actorId ||
        session.sessionGeneration != sessionGeneration) {
      throw const RagFailure(RagFailureCode.sessionChanged);
    }
    if (call.isExpired(_now())) {
      throw const RagFailure(RagFailureCode.timeout);
    }
  }

  /// Whether [source] is part of the currently displayed answer.
  ///
  /// A retained or foreign citation is refused before any read, so a stale
  /// source can never look clickable.
  bool _isDisplayedSource(RagResult? displayed, RagSource source) {
    if (displayed == null || !displayed.isAnswered) return false;
    for (final RagSource candidate in displayed.sources) {
      if (candidate == source) return true;
    }
    return false;
  }

  void _requireDisplayUnchanged(RagResult? displayed) {
    if (!identical(_state.result, displayed)) {
      throw const RagFailure(RagFailureCode.sourceChanged);
    }
  }

  void _requireGrantUnchanged(
    String actorId,
    int sessionGeneration,
    RagConsent consent,
  ) {
    if (_state.consentLoading) {
      throw const RagFailure(RagFailureCode.consentUnknown);
    }
    final RagConsent? current = _currentConsent(actorId, sessionGeneration);
    if (current == null) {
      throw const RagFailure(RagFailureCode.consentUnknown);
    }
    if (!current.accepted || current.generation != consent.generation) {
      throw const RagFailure(RagFailureCode.consentRequired);
    }
  }

  /// Clears the displayed pair when its citation can no longer be opened.
  void _clearDisplayForSourceFailure(RagResult? displayed, RagFailure failure) {
    if (displayed == null || !identical(_state.result, displayed)) return;
    if (failure.code != RagFailureCode.sourceChanged &&
        failure.code != RagFailureCode.sourceUnavailable) {
      return;
    }
    _emit(
      _state.copyWith(result: null, resultQuestion: null, failure: failure),
    );
  }

  /// Clears the displayed answer when one of its citations stopped matching.
  void _revalidateDisplayedAnswer(
    RagResult? displayed,
    LocalSyncState local,
    String actorId,
  ) {
    if (displayed == null ||
        !displayed.isAnswered ||
        !identical(_state.result, displayed)) {
      return;
    }
    for (final RagSource source in displayed.sources) {
      final RagFailureCode? failure = _sourceFailure(local, actorId, source);
      if (failure == null) continue;
      _emit(
        _state.copyWith(
          result: null,
          resultQuestion: null,
          failure: RagFailure(failure),
        ),
      );
      return;
    }
  }

  /// Cancels the in-flight run when its own current note became ineligible.
  ///
  /// Only the run's matching note scope is examined: an unrelated local change
  /// never cancels an account question.
  void _revalidateInFlightNote(
    RagRunContext? run,
    String? noteId,
    LocalSyncState local,
    String actorId,
  ) {
    if (run == null ||
        noteId == null ||
        !identical(_activeRun, run) ||
        run.isCancelled) {
      return;
    }
    final LocalNoteState? snapshot = _runNoteSnapshot;
    if (snapshot == null) return;
    final RagFailureCode? failure = _currentNoteFailure(
      local,
      actorId,
      snapshot,
    );
    if (failure != null) run.cancel(failure);
  }

  /// Why [source] cannot be opened against [local], or null while it can.
  RagFailureCode? _sourceFailure(
    LocalSyncState local,
    String actorId,
    RagSource source,
  ) {
    if (local.accountUserId != actorId) {
      return RagFailureCode.localStateUnavailable;
    }
    final LocalNoteState? note = _ownedNote(local, actorId, source.noteId);
    if (note == null ||
        note.isDeleted ||
        !note.contentAvailable ||
        note.protection.enabled) {
      return RagFailureCode.sourceUnavailable;
    }
    if (note.serverRevision != source.revision ||
        note.serverRevision < 1 ||
        _hasPendingChange(local, note) ||
        _hasConflict(local, note)) {
      return RagFailureCode.sourceChanged;
    }
    if (!source.matchesContent(note.content)) {
      return RagFailureCode.sourceChanged;
    }
    return null;
  }

  /// Finds the cited note and refuses anything that cannot be opened now.
  LocalNoteState _requireSourceNote(
    LocalSyncState local,
    String actorId,
    RagSource source,
  ) {
    final RagFailureCode? failure = _sourceFailure(local, actorId, source);
    if (failure != null) throw RagFailure(failure);
    final LocalNoteState? note = _ownedNote(local, actorId, source.noteId);
    if (note == null) {
      throw const RagFailure(RagFailureCode.sourceUnavailable);
    }
    return note;
  }
}
