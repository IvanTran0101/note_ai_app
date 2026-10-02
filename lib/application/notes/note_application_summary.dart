part of 'note_application.dart';

/// Saved-note Summary orchestration shares the Application access guard.
extension NoteSummaryUseCases on NoteApplicationService {
  /// Summarizes an owned note without mutating or persisting it.
  ///
  /// [selectedSnapshot] is the exact projection the Notes UI selected; when
  /// supplied, it must match the saved, owned revision before generation and
  /// that revision must still be saved before a result is accepted, so a
  /// summary is never produced for a revision the user did not select.
  /// [scope] owns cancellation for one invocation and never reactivates.
  ///
  /// The account and session generation are captured before the asynchronous
  /// note read and rechecked after every await and before the result is
  /// accepted. With [summarizeRun] wired a failure is a typed code-only
  /// [SummaryRunFailure]. Scoped/selected local calls also recheck the revision;
  /// legacy unscoped local calls retain their original exception/read contract.
  Future<Summary> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async {
    final String userId = currentUser.requiredUserId;
    final int generation = _sessionGeneration();
    final int accessGeneration = security?.accessGeneration ?? 0;
    final SummaryRunScope runScope = scope ?? SummaryRunScope();
    final bool dispatchesRun = summarizeRun != null;
    final bool typedFailure =
        dispatchesRun || scope != null || selectedSnapshot != null;
    final SummaryCloudConsentSnapshot consent = _consentFor(userId, generation);

    _requireLiveRun(runScope, userId, generation, accessGeneration);
    if (selectedSnapshot != null &&
        (selectedSnapshot.reference != noteId ||
            !const NoteAccessPolicy().allows(
              actorId: userId,
              note: selectedSnapshot.identity,
              share: selectedSnapshot.share,
              operation: NoteOperation.summary,
            ))) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
    }

    final Note? note = await noteRepository.findById(noteId);
    _requireLiveRun(runScope, userId, generation, accessGeneration);
    if (note == null ||
        !const NoteAccessPolicy().allows(
          actorId: userId,
          note: note.identity,
          share: note.share,
          operation: NoteOperation.summary,
        )) {
      // A note owned by another account is reported as missing on the run path.
      if (typedFailure) {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
      }
      if (note == null) {
        throw NoteNotFoundException(noteId);
      }
      throw NoteOwnershipException(
        noteId: noteId,
        expectedOwnerId: userId,
        actualOwnerId: note.ownerId,
      );
    }
    _requireAccess(note, NoteOperation.summary);
    final NoteDto revision = NoteDto.fromDomain(note);
    if (selectedSnapshot != null && selectedSnapshot != revision) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
    }

    if (dispatchesRun) {
      _requireCurrentConsent(consent);
    }
    final Summary summary = dispatchesRun
        ? await summarizeRun!(
            SummaryRunContext(
              noteSnapshot: selectedSnapshot ?? revision,
              accountUserId: userId,
              sessionGeneration: generation,
              consent: consent,
              scope: runScope,
            ),
          )
        : await summarizeContent(note.content);

    _requireLiveRun(runScope, userId, generation, accessGeneration);
    _requireAccess(note, NoteOperation.summary);
    if (dispatchesRun) {
      _requireCurrentConsent(consent);
    }
    if (typedFailure) {
      await _requireSavedRevision(noteId, selectedSnapshot ?? revision);
      _requireLiveRun(runScope, userId, generation, accessGeneration);
    }
    if (dispatchesRun) {
      _requireCurrentConsent(consent);
    }
    return summary;
  }

  /// Rejects the run when the scope is cancelled or the session moved on.
  ///
  /// Cancellation is checked first and keeps its original reason.
  void _requireLiveRun(
    SummaryRunScope scope,
    String userId,
    int generation,
    int accessGeneration,
  ) {
    final SummaryRunFailureCode? cancelled = scope.cancelReason;
    if (cancelled != null || scope.isReleased) {
      throw SummaryRunFailure(cancelled ?? SummaryRunFailureCode.cancelled);
    }
    if ((security?.accessGeneration ?? 0) != accessGeneration) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteLocked);
    }
    if (currentUser.userId != userId || _sessionGeneration() != generation) {
      throw const SummaryRunFailure(SummaryRunFailureCode.sessionChanged);
    }
  }

  /// Rejects the result when a granted consent is no longer current.
  void _requireCurrentConsent(SummaryCloudConsentSnapshot consent) {
    if (!consent.isGranted) {
      // A never-granted snapshot cannot have authorized a cloud call, and local
      // summarization needs no consent, so there is nothing to revalidate.
      return;
    }
    final SummaryCloudConsent? store = cloudConsent;
    if (store == null || !store.isCurrent(consent)) {
      throw const SummaryRunFailure(SummaryRunFailureCode.consentRequired);
    }
  }

  Future<void> _requireSavedRevision(String noteId, NoteDto expected) async {
    final Note? current = await noteRepository.findById(noteId);
    if (current == null) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
    }
    _requireAccess(current, NoteOperation.summary);
    if (NoteDto.fromDomain(current) != expected) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
    }
  }

  SummaryCloudConsentSnapshot _consentFor(String userId, int generation) {
    final SummaryCloudConsent? store = cloudConsent;
    if (store == null) {
      return SummaryCloudConsentSnapshot.notGranted(
        accountUserId: userId,
        sessionGeneration: generation,
      );
    }
    return store.capture(accountUserId: userId, sessionGeneration: generation);
  }
}
