// Actor binding, account-scoped clearing, and the local-state read seam.
part of 'rag_app_service.dart';

extension on RagAppService {
  /// The live account, or null while unauthenticated.
  String? get _liveActorId =>
      currentUser.isAuthenticated ? currentUser.userId : null;

  /// Drops account-scoped state that belongs to a different live account.
  void _enforceActorBinding() {
    final String? live = _liveActorId;
    if (live == null) {
      if (_boundActorId != null) _clearAccountState();
      return;
    }
    if (_boundActorId != null && _boundActorId != live) _clearAccountState();
    _boundActorId = live;
  }

  /// Clears everything bound to an account: run, consent, answer, and scope.
  void _clearAccountState() {
    _cancelActiveRun(RagFailureCode.sessionChanged);
    _supersedeConsentCall();
    _cancelSourceCalls(RagFailureCode.sessionChanged);
    _boundActorId = null;
    _clearConsentBinding();
    _emit(RagState(active: _state.active));
  }

  /// The adopted grant for exactly [actorId] and [sessionGeneration].
  RagConsent? _currentConsent(String actorId, int sessionGeneration) {
    if (_consentActorId != actorId ||
        _consentSessionGeneration != sessionGeneration) {
      return null;
    }
    return _state.consent;
  }

  void _clearConsentBinding() {
    _consentActorId = null;
    _consentSessionGeneration = null;
  }

  /// Reads the local sync state of [actorId], failing closed.
  Future<LocalSyncState> _readLocalState(String actorId) async {
    final LocalSyncState local;
    try {
      local = await _readLocalStateCallback(actorId);
    } on RagFailure {
      rethrow;
    } catch (_) {
      throw const RagFailure(RagFailureCode.localStateUnavailable);
    }
    if (local.accountUserId != actorId) {
      throw const RagFailure(RagFailureCode.localStateUnavailable);
    }
    return local;
  }

  /// The owned projection of [noteId], or null for a missing/incoming note.
  LocalNoteState? _ownedNote(
    LocalSyncState local,
    String actorId,
    String noteId,
  ) {
    for (final LocalNoteState note in local.notes) {
      if (note.ownerId == actorId && note.id == noteId) return note;
    }
    return null;
  }
}
