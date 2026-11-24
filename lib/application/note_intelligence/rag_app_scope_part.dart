// Current-note capture and the eligibility verdicts a dispatch depends on.
part of 'rag_app_service.dart';

extension on RagAppService {
  /// Implementation of [RagAppService.invalidateNote].
  ///
  /// Nothing is read: the matching run is cancelled and the matching pair is
  /// cleared in the same synchronous turn, because the caller reports that the
  /// local revision moved under both of them.
  void _invalidateNote(String noteId) {
    if (_disposed || noteId.trim().isEmpty) return;
    _enforceActorBinding();
    if (_liveActorId == null) return;
    final RagRunContext? run = _activeRun;
    final bool cancelsRun = run != null && run.scope.noteId == noteId;
    final RagResult? displayed = _state.result;
    final bool clearsDisplay = _citesNote(displayed, noteId);
    if (!cancelsRun && !clearsDisplay) return;
    if (cancelsRun) _cancelActiveRun(RagFailureCode.sourceChanged);
    RagState next = _state;
    if (cancelsRun) next = next.copyWith(queryRunning: false);
    if (clearsDisplay) next = next.copyWith(result: null, resultQuestion: null);
    _emit(
      next.copyWith(failure: const RagFailure(RagFailureCode.sourceChanged)),
    );
  }

  /// Whether a displayed answer carries a citation of [noteId].
  bool _citesNote(RagResult? displayed, String noteId) {
    if (displayed == null || !displayed.isAnswered) return false;
    for (final RagSource source in displayed.sources) {
      if (source.noteId == noteId) return true;
    }
    return false;
  }

  /// Captures the local current note before the run's first dispatch.
  ///
  /// The captured projection is the run's reference: every later dispatch
  /// compares the live note against it. Throws [RagFailure] when the note is
  /// not eligible right now, so nothing is sent for a note the backend could
  /// not safely read.
  Future<LocalNoteState> _captureCurrentNote(
    RagRunContext run,
    String noteId,
  ) async {
    final LocalSyncState local = await _readLocalState(run.actorId);
    _requireRunLive(run);
    final LocalNoteState? note = _ownedNote(local, run.actorId, noteId);
    if (note == null ||
        note.isDeleted ||
        !note.contentAvailable ||
        note.protection.enabled) {
      throw const RagFailure(RagFailureCode.sourceUnavailable);
    }
    if (note.serverRevision < 1 ||
        _hasPendingChange(local, note) ||
        _hasConflict(local, note)) {
      throw const RagFailure(RagFailureCode.sourceChanged);
    }
    return note;
  }

  /// Why the captured note may no longer be read, or null while it is current.
  ///
  /// Revision, content, protection, deletion, availability, ownership, pending
  /// changes, and conflicts are all compared: a note that moved under the run
  /// is refused, never queried against stale evidence.
  RagFailureCode? _currentNoteFailure(
    LocalSyncState local,
    String actorId,
    LocalNoteState snapshot,
  ) {
    final LocalNoteState? note = _ownedNote(local, actorId, snapshot.id);
    if (note == null ||
        note.ownerId != actorId ||
        note.isDeleted ||
        !note.contentAvailable ||
        note.protection.enabled) {
      return RagFailureCode.sourceUnavailable;
    }
    if (note.serverRevision != snapshot.serverRevision ||
        note.content != snapshot.content ||
        note.protection != snapshot.protection ||
        note.serverRevision < 1 ||
        _hasPendingChange(local, note) ||
        _hasConflict(local, note)) {
      return RagFailureCode.sourceChanged;
    }
    return null;
  }

  /// Whether the note has a queued, non-label mutation of its own.
  bool _hasPendingChange(LocalSyncState local, LocalNoteState note) {
    for (final PendingMutation entry in local.outbox) {
      if (entry.isLabel) continue;
      if (entry.mutation.identityFor(local.accountUserId) == note.identity) {
        return true;
      }
    }
    return false;
  }

  /// Whether the note is in conflict state or has a recorded conflict.
  bool _hasConflict(LocalSyncState local, LocalNoteState note) {
    if (note.status == NoteSyncStatus.conflict) return true;
    for (final SyncConflict conflict in local.conflicts) {
      if (conflict.noteId == note.id && conflict.identity == note.identity) {
        return true;
      }
    }
    return false;
  }
}
