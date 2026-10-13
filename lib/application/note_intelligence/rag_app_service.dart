/// Pure-Dart application service for one account's RAG (ask-my-notes) session.
///
/// Presentation talks to this service only; Infrastructure is reached through
/// [IRagGateway], and the Domain never learns about either. The service owns:
///
/// * the immutable [RagState] snapshot plus its broadcast stream,
/// * the canonical consent handshake (read on login/resume, compare-and-set on
///   an explicit user decision),
/// * one active question at a time, with its captured account, session
///   generation, consent generation, scope, current-note snapshot, and
///   26-second deadline,
/// * source validation against the local sync state before an answer is applied
///   or a citation is opened.
///
/// The rules those captures encode:
///
/// * A displayed answer belongs to the grant, account, session, scope, and
///   local revision that produced it. A revoke clears it before the write is
///   attempted, an unknown or moved grant clears it, inactivity clears it, and
///   resume never resurrects it.
/// * A current-note question captures the local note before its first dispatch
///   and re-reads it immediately before every dispatch, so a note that changed
///   during the consent or token wait is never queried.
/// * Every await of a call is raced against that call's cancellation and
///   deadline, so a hanging local read, consent read, or source check still
///   settles.
///
/// This file is the public surface and the single state owner. The behaviour
/// lives in private parts of the same library, grouped by responsibility: actor
/// binding, consent calls, question runs, scope/current-note checks, and source
/// validation.
///
/// The service never persists anything, never retries a query, never refreshes
/// a token to resurrect a timed-out request, and never revokes a grant on
/// logout: only an explicit [setConsent] with `false` writes a revoke.
library;

import 'dart:async';

import '../../domain/note_intelligence/i_rag_gateway.dart';
import '../../domain/note_intelligence/rag_models.dart';
import '../auth/current_user.dart';
import '../auth/current_user_session.dart';
import '../notes/note_dto.dart';
import '../sync/local_note_state.dart';
import '../sync/local_sync_state.dart';
import '../sync/note_sync_status.dart';
import '../sync/pending_mutation.dart';
import '../sync/sync_conflict.dart';
import 'rag_run_context.dart';
import 'rag_state.dart';

part 'rag_app_binding_part.dart';
part 'rag_app_consent_part.dart';
part 'rag_app_run_part.dart';
part 'rag_app_scope_part.dart';
part 'rag_app_source_part.dart';

/// Application service for one account's RAG session.
final class RagAppService {
  /// Creates the service around the gateway and the live session seams.
  ///
  /// [readLocalState] is the existing application callback that returns the
  /// whole [LocalSyncState] of one actor; this service never reads storage
  /// directly and never invents a second snapshot type.
  RagAppService({
    required this.gateway,
    required this.currentUser,
    required this.session,
    required Future<LocalSyncState> Function(String actorId) readLocalState,
    DateTime Function()? now,
  }) : _readLocalStateCallback = readLocalState,
       _now = now ?? DateTime.now;

  /// The Infrastructure port this service drives.
  final IRagGateway gateway;

  /// The live authenticated identity.
  final ICurrentUser currentUser;

  /// The live session generation, so a captured binding can be compared.
  final SessionGenerationSource session;

  final Future<LocalSyncState> Function(String actorId) _readLocalStateCallback;
  final DateTime Function() _now;

  final StreamController<RagState> _states = StreamController<RagState>.broadcast();
  RagState _state = RagState();
  RagRunContext? _activeRun;

  /// The local note a current-note run captured before its first dispatch.
  LocalNoteState? _runNoteSnapshot;

  RagConsentCall? _consentCall;

  /// Bounded, cancellable local reads for source opens and revalidations.
  final Set<RagCallScope> _sourceCalls = <RagCallScope>{};

  String? _boundActorId;
  String? _consentActorId;
  int? _consentSessionGeneration;
  bool _disposed = false;

  /// The current immutable snapshot.
  RagState get state => _state;

  /// Broadcast state changes, in order. New listeners read [state] first.
  Stream<RagState> get stateStream => _states.stream;

  /// Reads the canonical consent grant for the live account.
  ///
  /// A read failure or an unauthenticated/inactive moment leaves consent
  /// unknown, never "denied" and never "granted", so nothing can be queried
  /// until a read succeeds. A grant that differs from the one the displayed
  /// answer was produced under — or an unknown grant — clears that answer
  /// instead of leaving it clickable.
  Future<void> refreshConsent() => _refreshConsent();

  /// Applies one explicit consent decision through compare-and-set.
  ///
  /// The write carries the locally known generation, so a concurrent decision
  /// elsewhere is refused by the server instead of being overwritten. A revoke
  /// clears the retained answer immediately — before the first await — so a
  /// pending or failing PUT can never leave a withdrawn answer on screen.
  Future<void> setConsent(bool accepted) => _setConsent(accepted);

  /// Asks one single-turn question in [scope].
  ///
  /// The account, session generation, consent generation, and scope are
  /// captured before the first await; a current-note scope additionally
  /// captures the local note before its first dispatch and re-reads it
  /// immediately before every one. An account question has no local
  /// precondition, so an unrelated local draft never denies it. Failures are
  /// recorded in [state] (never thrown) so the UI has one source of truth: a
  /// new question failing on the same scope keeps the previous question/answer
  /// pair, while a scope change, logout, or revoke clears it.
  Future<void> ask({required String question, required RagScope scope}) =>
      _ask(question: question, scope: scope);

  /// Cancels the active question, if any.
  ///
  /// The cancellation future handed to the gateway completes, so an in-flight
  /// transport can abort, but this method never waits for it: the run releases
  /// its slot immediately and a late completion cannot touch [state] again. The
  /// retained question/answer pair stays visible while its scope, grant, and
  /// sources are still valid.
  void cancel() {
    if (_disposed) return;
    final RagRunContext? run = _activeRun;
    if (run == null) return;
    _activeRun = null;
    _runNoteSnapshot = null;
    run.cancel(RagFailureCode.cancelled);
    run.dispose();
    _emit(
      _state.copyWith(
        queryRunning: false,
        failure: const RagFailure(RagFailureCode.cancelled),
      ),
    );
  }

  /// Selects the evidence [scope] before a question is asked.
  ///
  /// This is a synchronous, local state-owner operation: it never reaches the
  /// gateway and never writes. Selecting the same scope is a no-op, so a
  /// retained question/answer pair survives. Selecting a different scope
  /// cancels the question and any source check the previous scope started, then
  /// clears the displayed pair and records the new scope in one emit, so a late
  /// result or source callback cannot restore an answer that belonged to the
  /// old scope. The canonical grant and the account binding are untouched.
  void selectScope(RagScope scope) {
    if (_disposed) return;
    if (_state.scope == scope) return;
    _cancelActiveRun(RagFailureCode.cancelled);
    _cancelSourceCalls(RagFailureCode.cancelled);
    _emit(
      _state.copyWith(
        scope: scope,
        queryRunning: false,
        result: null,
        resultQuestion: null,
      ),
    );
  }

  /// Clears every account-scoped value after a sign-out.
  ///
  /// Nothing is written to the server: logout never revokes the account grant.
  /// Only an explicit [setConsent] with `false` does that.
  void invalidateSession() {
    if (_disposed) return;
    _clearAccountState();
  }

  /// Marks the app inactive: cancels the active question, invalidates the known
  /// grant, and clears the displayed answer, without touching the server.
  void onInactive() {
    if (_disposed) return;
    _cancelActiveRun(RagFailureCode.cancelled);
    _supersedeConsentCall();
    _cancelSourceCalls(RagFailureCode.cancelled);
    _clearConsentBinding();
    _emit(
      _state.copyWith(
        active: false,
        consent: null,
        consentLoading: false,
        queryRunning: false,
        failure: const RagFailure(RagFailureCode.cancelled),
        result: null,
        resultQuestion: null,
      ),
    );
  }

  /// Marks the app active again and re-reads the canonical grant.
  ///
  /// The interrupted question is never resent and a cleared answer is never
  /// resurrected: only a fresh canonical grant and a fresh question can produce
  /// a new answer. The user asks again explicitly.
  Future<void> onResume() async {
    if (_disposed) return;
    _emit(_state.copyWith(active: true));
    await _refreshConsent();
  }

  /// Revalidates the displayed answer and the in-flight question after the
  /// local sync, security, or editor state changed.
  ///
  /// One local read, no gateway call, and no new question: a displayed citation
  /// that no longer matches its local note clears the pair, and an in-flight
  /// current-note question whose own note became ineligible is cancelled. An
  /// unrelated local draft never denies an account question. The composition
  /// root wires this to sync, security, and editor changes; the service never
  /// calls it itself.
  Future<void> onLocalStateChanged() => _onLocalStateChanged();

  /// Invalidates everything this session holds for one note.
  ///
  /// The composition root calls this when a note becomes dirty, so an answer
  /// that was produced from that note's previous revision cannot stay on screen.
  /// The call is synchronous and local: it cancels the active question only when
  /// that question was asked in this note's own scope, and it clears the
  /// displayed answer only when the answer cites this note. An unrelated edit
  /// never denies an account question, never resets the scope, and never touches
  /// the canonical grant; nothing is written to the server and no note state or
  /// history is kept here. A blank id matches nothing and does nothing.
  void invalidateNote(String noteId) => _invalidateNote(noteId);

  /// Revalidates one citation against the local state and returns its note.
  ///
  /// The source must belong to the currently displayed answer, the service must
  /// be active with a canonical accepted grant for the captured session, and
  /// the note must still be owned, live, content-available, unprotected, synced
  /// (`serverRevision > 0`), free of pending changes and conflicts, with the
  /// exact half-open UTF-16 span. A source that is gone or changed also clears
  /// the displayed pair, because an answer whose citation can no longer be
  /// opened must not stay on screen.
  Future<NoteDto> validateSource(RagSource source) => _validateSource(source);

  /// Cancels everything and closes the state stream.
  ///
  /// The gateway is not closed here: the composition root owns its lifetime.
  void dispose() {
    if (_disposed) return;
    _cancelActiveRun(RagFailureCode.cancelled);
    _supersedeConsentCall();
    _cancelSourceCalls(RagFailureCode.cancelled);
    _emit(_state.copyWith(queryRunning: false, consentLoading: false));
    _disposed = true;
    unawaited(_states.close());
  }

  /// Publishes one immutable snapshot to [state] and [stateStream].
  void _emit(RagState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Records one local refusal without touching the rest of the state.
  void _fail(RagFailure failure) => _emit(_state.copyWith(failure: failure));
}
