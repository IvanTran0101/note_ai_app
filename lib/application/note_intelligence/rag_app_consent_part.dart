// Canonical consent read/write lifecycle for the RAG application service.
part of 'rag_app_service.dart';

extension on RagAppService {
  /// Implementation of [RagAppService.refreshConsent].
  ///
  /// A superseded read is cancelled, and a grant that moved (or became unknown)
  /// clears the answer the previous grant displayed, so a remote revoke cannot
  /// leave a stale answer clickable.
  Future<void> _refreshConsent() async {
    if (_disposed) return;
    _enforceActorBinding();
    final String? actorId = _liveActorId;
    final int sessionGeneration = session.sessionGeneration;
    _supersedeConsentCall();
    if (actorId == null) {
      _clearConsentBinding();
      _emit(
        _state.copyWith(
          consent: null,
          consentLoading: false,
          failure: null,
          result: null,
          resultQuestion: null,
        ),
      );
      return;
    }
    if (!_state.active) {
      _clearConsentBinding();
      _emit(
        _state.copyWith(
          consent: null,
          consentLoading: false,
          result: null,
          resultQuestion: null,
        ),
      );
      return;
    }
    final RagConsentCall call = RagConsentCall(
      actorId: actorId,
      sessionGeneration: sessionGeneration,
      deadline: _now().add(RagCallContext.requestBudget),
    );
    _consentCall = call;
    _armConsentDeadline(call);
    final RagConsent? previous = _state.consent;
    _emit(_state.copyWith(consentLoading: true, failure: null));
    try {
      final RagConsent grant = await call.race(
        gateway.readConsent(context: _consentContext(call)),
      );
      _requireConsentCallLive(call);
      if (!identical(_consentCall, call)) return;
      _consentCall = null;
      call.dispose();
      _consentActorId = actorId;
      _consentSessionGeneration = sessionGeneration;
      final bool grantMoved = previous == null || previous != grant;
      _emit(
        _state.copyWith(
          consent: grant,
          consentLoading: false,
          failure: null,
          result: grantMoved ? null : _state.result,
          resultQuestion: grantMoved ? null : _state.resultQuestion,
        ),
      );
    } on RagFailure catch (failure) {
      _finishConsentFailure(call, failure);
    } catch (_) {
      _finishConsentFailure(call, const RagFailure(RagFailureCode.unexpected));
    }
  }

  /// Implementation of [RagAppService.setConsent].
  ///
  /// A revoke takes effect locally before the first await: the displayed answer
  /// was produced under the grant being withdrawn, and the write may still fail,
  /// so waiting for the response would leave it on screen.
  Future<void> _setConsent(bool accepted) async {
    if (_disposed) return;
    _enforceActorBinding();
    final String? actorId = _liveActorId;
    if (actorId == null) {
      _fail(const RagFailure(RagFailureCode.unauthorized));
      return;
    }
    final int sessionGeneration = session.sessionGeneration;
    if (!_state.active) {
      _fail(const RagFailure(RagFailureCode.cancelled));
      return;
    }
    _cancelActiveRun(RagFailureCode.consentRequired);
    _supersedeConsentCall();
    final RagConsentCall call = RagConsentCall(
      actorId: actorId,
      sessionGeneration: sessionGeneration,
      deadline: _now().add(RagCallContext.requestBudget),
      isWrite: true,
    );
    _consentCall = call;
    _armConsentDeadline(call);
    _emit(
      _state.copyWith(
        consentLoading: true,
        failure: null,
        queryRunning: false,
        result: accepted ? _state.result : null,
        resultQuestion: accepted ? _state.resultQuestion : null,
      ),
    );
    try {
      final RagConsent known;
      final RagConsent? captured = _currentConsent(actorId, sessionGeneration);
      if (captured != null) {
        known = captured;
      } else {
        known = await call.race(
          gateway.readConsent(context: _consentContext(call)),
        );
        _requireConsentCallLive(call);
        _consentActorId = actorId;
        _consentSessionGeneration = sessionGeneration;
        _emit(_state.copyWith(consent: known, consentLoading: true));
      }
      final RagConsentUpdate update = RagConsentUpdate(
        accepted: accepted,
        expectedGeneration: known.generation,
      );
      final RagConsent written = await call.race(
        gateway.updateConsent(update, context: _consentContext(call)),
      );
      _requireConsentCallLive(call);
      _requireWriteApplied(update, written);
      if (!identical(_consentCall, call)) return;
      _consentCall = null;
      call.dispose();
      _consentActorId = actorId;
      _consentSessionGeneration = sessionGeneration;
      final bool grantMoved = written != known;
      _emit(
        _state.copyWith(
          consent: written,
          consentLoading: false,
          failure: null,
          result: grantMoved ? null : _state.result,
          resultQuestion: grantMoved ? null : _state.resultQuestion,
        ),
      );
    } on RagFailure catch (failure) {
      _finishConsentFailure(call, failure);
    } catch (_) {
      _finishConsentFailure(call, const RagFailure(RagFailureCode.unexpected));
    }
  }

  RagCallContext _consentContext(RagConsentCall call) => RagCallContext(
    expectedUserId: call.actorId,
    cancelled: call.whenCancelled,
    beforeDispatch: () => _beforeConsentDispatch(call),
    deadline: call.deadline,
  );

  Future<void> _beforeConsentDispatch(RagConsentCall call) async {
    _requireConsentCallLive(call);
    call.markDispatched();
  }

  void _requireConsentCallLive(RagConsentCall call) {
    if (call.isCancelled) {
      throw RagFailure(call.cancelReason ?? RagFailureCode.cancelled);
    }
    if (_disposed || !identical(_consentCall, call) || !_state.active) {
      throw const RagFailure(RagFailureCode.cancelled);
    }
    if (!currentUser.isAuthenticated ||
        currentUser.userId != call.actorId ||
        session.sessionGeneration != call.sessionGeneration) {
      throw const RagFailure(RagFailureCode.sessionChanged);
    }
    if (call.isExpired(_now())) {
      throw const RagFailure(RagFailureCode.timeout);
    }
  }

  void _armConsentDeadline(RagConsentCall call) {
    call.armDeadline(
      call.deadline.difference(_now()),
      () => call.cancel(RagFailureCode.timeout),
    );
  }

  /// Cancels the in-flight consent call, if any.
  ///
  /// A write that already reached the transport may have been applied, so the
  /// local grant becomes unknown instead of being trusted, and the answer it
  /// used to authorize is cleared with it.
  void _supersedeConsentCall() {
    final RagConsentCall? call = _consentCall;
    if (call == null) return;
    _consentCall = null;
    call.cancel(RagFailureCode.cancelled);
    call.dispose();
    final bool dispatchedWrite = call.isWrite && call.wasDispatched;
    if (!dispatchedWrite) return;
    _clearConsentBinding();
    _emit(
      _state.copyWith(
        consent: null,
        consentLoading: false,
        result: null,
        resultQuestion: null,
      ),
    );
  }

  /// Records one consent failure: consent is unknown, and so is any answer it
  /// used to authorize.
  void _finishConsentFailure(RagConsentCall call, RagFailure failure) {
    if (!identical(_consentCall, call)) return;
    _consentCall = null;
    call.dispose();
    _clearConsentBinding();
    _emit(
      _state.copyWith(
        consent: null,
        consentLoading: false,
        failure: failure,
        result: null,
        resultQuestion: null,
      ),
    );
  }

  void _requireWriteApplied(RagConsentUpdate update, RagConsent written) {
    if (written.accepted != update.accepted) {
      throw const RagFailure(RagFailureCode.invalidProviderOutput);
    }
    if (written.generation != update.expectedGeneration + 1) {
      throw const RagFailure(RagFailureCode.sourceChanged);
    }
  }
}
