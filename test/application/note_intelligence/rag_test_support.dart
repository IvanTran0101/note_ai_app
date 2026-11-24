/// Shared fakes and fixtures for the RAG application-service tests.
///
/// Everything here is synthetic: no network, no provider, no real account. The
/// gateway records what the service asked for so a test can assert the exact
/// call sequence, captured context, and consent generations.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/note_intelligence/rag_app_service.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/i_rag_gateway.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';

/// A scripted [IRagGateway] that never touches the network.
///
/// Each script consumes its entries in order and repeats the last one, so a
/// test states only the responses it cares about. Every call awaits its token
/// wait (when one is queued) and then [RagCallContext.beforeDispatch] first,
/// exactly like the real adapter, and a call is only recorded once that guard
/// passed: an entry in [calls] means the request was really dispatched.
final class FakeRagGateway implements IRagGateway {
  FakeRagGateway({
    List<Object>? consentScript,
    List<Object>? writeScript,
    List<Object>? queryScript,
  }) : consentScript = consentScript ?? <Object>[],
       writeScript = writeScript ?? <Object>[],
       queryScript = queryScript ?? <Object>[];

  /// Ordered responses for [readConsent]: [RagConsent] or [RagFailure].
  final List<Object> consentScript;

  /// Ordered responses for [updateConsent]: [RagConsent] or [RagFailure].
  final List<Object> writeScript;

  /// Ordered responses for [query]: [RagResult] or [RagFailure].
  final List<Object> queryScript;

  /// Every dispatched method name in call order.
  final List<String> calls = <String>[];

  /// The context captured for every dispatched call, in call order.
  final List<RagCallContext> contexts = <RagCallContext>[];

  /// The requests a dispatched [query] received.
  final List<RagRequest> requests = <RagRequest>[];

  /// The updates a dispatched [updateConsent] received.
  final List<RagConsentUpdate> updates = <RagConsentUpdate>[];

  /// How many times a dispatch guard completed successfully.
  int dispatchGuards = 0;

  /// How many times [close] was called.
  int closes = 0;

  /// When set, [query] waits for this completer instead of the script.
  Completer<RagResult>? pendingQuery;

  /// When set, [readConsent] waits for this completer instead of the script.
  Completer<RagConsent>? pendingConsentRead;

  /// When set, [updateConsent] waits for this completer instead of the script.
  Completer<RagConsent>? pendingConsentWrite;

  /// Futures awaited, one per call, before [RagCallContext.beforeDispatch].
  ///
  /// They stand in for the token acquisition that happens between the service
  /// guard and the transport in the real adapter, so a test can change local
  /// state while a call is already past its capture.
  final List<Future<void>> tokenWaits = <Future<void>>[];

  int _consentCursor = 0;
  int _writeCursor = 0;
  int _queryCursor = 0;

  /// Consents recorded by readConsent, in order.
  List<RagConsent> get grants => consentScript.whereType<RagConsent>().toList();

  @override
  Future<RagConsent> readConsent({required RagCallContext context}) async {
    await _guard(context);
    _record(context, 'readConsent');
    final Completer<RagConsent>? pending = pendingConsentRead;
    if (pending != null) return pending.future;
    if (consentScript.isEmpty) return RagConsent.none;
    final Object next = _next(consentScript, _consentCursor);
    if (_consentCursor < consentScript.length) _consentCursor++;
    if (next is RagFailure) throw next;
    return next as RagConsent;
  }

  @override
  Future<RagConsent> updateConsent(
    RagConsentUpdate update, {
    required RagCallContext context,
  }) async {
    await _guard(context);
    _record(context, 'updateConsent');
    updates.add(update);
    final Completer<RagConsent>? pending = pendingConsentWrite;
    if (pending != null) return pending.future;
    if (writeScript.isEmpty) {
      return RagConsent(
        accepted: update.accepted,
        generation: update.expectedGeneration + 1,
      );
    }
    final Object next = _next(writeScript, _writeCursor);
    if (_writeCursor < writeScript.length) _writeCursor++;
    if (next is RagFailure) throw next;
    return next as RagConsent;
  }

  @override
  Future<RagResult> query(
    RagRequest request, {
    required RagCallContext context,
  }) async {
    await _guard(context);
    _record(context, 'query');
    requests.add(request);
    final Completer<RagResult>? pending = pendingQuery;
    if (pending != null) return pending.future;
    if (queryScript.isEmpty) {
      throw const RagFailure(RagFailureCode.unexpected);
    }
    final Object next = _next(queryScript, _queryCursor);
    if (_queryCursor < queryScript.length) _queryCursor++;
    if (next is RagFailure) throw next;
    return next as RagResult;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    closes++;
  }

  void _record(RagCallContext context, String name) {
    calls.add(name);
    contexts.add(context);
  }

  Future<void> _guard(RagCallContext context) async {
    if (tokenWaits.isNotEmpty) {
      await tokenWaits.removeAt(0);
    }
    await context.beforeDispatch();
    dispatchGuards++;
  }

  Object _next(List<Object> script, int cursor) {
    if (script.isEmpty) return const RagFailure(RagFailureCode.unexpected);
    if (cursor < script.length) return script[cursor];
    return script.last;
  }
}

/// A mutable [ICurrentUser] for account-switch tests.
final class FakeCurrentUser implements ICurrentUser {
  FakeCurrentUser({String? userId}) {
    if (userId != null) {
      signIn(userId);
    }
  }

  @override
  AuthIdentity? identity;

  @override
  bool get isAuthenticated => identity != null;

  @override
  String? get userId => identity?.userId;

  @override
  String get requiredUserId => identity!.userId;

  /// Records a signed-in identity.
  void signIn(String userId) {
    identity = AuthIdentity(
      userId: userId,
      email: '$userId@example.test',
      isEmailVerified: true,
    );
  }

  /// Clears the identity, as a sign-out does.
  void signOut() => identity = null;
}

/// A mutable [SessionGenerationSource] for generation-change tests.
final class FakeSession implements SessionGenerationSource {
  /// Creates a session at [generation], defaulting to an authenticated one.
  FakeSession({this.generation = 1});

  /// The live generation.
  int generation;

  @override
  int get sessionGeneration => generation;

  /// Simulates a real identity transition (logout, login, or switch).
  void advance() => generation++;
}

/// A manually advanced clock for deadline tests.
final class FakeClock {
  /// Creates a clock pinned to [now].
  FakeClock(this.now);

  /// The current instant.
  DateTime now;

  /// Jump applied after every read.
  ///
  /// A test uses it to drive a call past its 26-second budget without waiting
  /// for the real timer: the capture reads one instant and the deadline arm
  /// reads the next, so the remaining budget is already spent.
  Duration step = Duration.zero;

  /// Reads the clock; pass this tear-off as the service's `now`.
  DateTime call() {
    final DateTime value = now;
    now = now.add(step);
    return value;
  }

  /// Moves the clock forward.
  void advance(Duration duration) {
    now = now.add(duration);
  }
}

/// Builds one owned local note; defaults are eligible for a source check.
LocalNoteState ownedNote({
  String id = 'note-1',
  String ownerId = 'user-1',
  String title = 'Title',
  String content = 'Body text',
  int serverRevision = 3,
  DateTime? deletedAt,
  NoteProtection protection = const NoteProtection.unprotected(),
  bool contentAvailable = true,
  NoteSyncStatus status = NoteSyncStatus.synced,
  NoteShareGrant? share,
}) {
  final DateTime created = DateTime.utc(2026, 1, 1);
  return LocalNoteState(
    id: id,
    ownerId: ownerId,
    title: title,
    content: content,
    createdAt: created,
    updatedAt: created,
    serverRevision: serverRevision,
    deletedAt: deletedAt,
    protection: protection,
    contentAvailable: contentAvailable,
    status: status,
    share: share,
  );
}

/// Builds one incoming share projection owned by another account.
LocalNoteState incomingNote({
  String id = 'shared-1',
  String ownerId = 'user-2',
  String recipientId = 'user-1',
  String content = 'Shared body',
  int serverRevision = 2,
}) {
  final DateTime created = DateTime.utc(2026, 1, 1);
  return LocalNoteState(
    id: id,
    ownerId: ownerId,
    title: 'Shared',
    content: content,
    createdAt: created,
    updatedAt: created,
    serverRevision: serverRevision,
    share: NoteShareGrant(
      note: NoteIdentity(ownerId, id),
      recipientId: recipientId,
      role: NoteRole.viewer,
      sharedAt: created,
      updatedAt: created,
      accessRevision: 1,
    ),
  );
}

/// Builds one account sync state with unique note ids.
LocalSyncState localState({
  String actorId = 'user-1',
  List<LocalNoteState> notes = const <LocalNoteState>[],
  List<PendingMutation> outbox = const <PendingMutation>[],
  List<SyncConflict> conflicts = const <SyncConflict>[],
}) {
  return LocalSyncState(
    accountUserId: actorId,
    notes: notes,
    outbox: outbox,
    conflicts: conflicts,
  );
}

/// Builds one queued update for [noteId].
PendingMutation pendingUpdate({
  String noteId = 'note-1',
  String mutationId = 'mutation-1',
  String? ownerId,
  int baseRevision = 2,
}) {
  return PendingMutation(
    mutationId: mutationId,
    noteId: noteId,
    ownerId: ownerId,
    operation: SyncMutationOperation.update,
    baseRevision: baseRevision,
    payload: const SyncNotePayload(title: 'Title', content: 'Body text'),
    createdAt: DateTime.utc(2026, 1, 2),
  );
}

/// Builds one recorded conflict for [note].
SyncConflict conflictFor(LocalNoteState note, {PendingMutation? pending}) {
  return SyncConflict(
    noteId: note.id,
    local: note,
    pending: pending ?? pendingUpdate(noteId: note.id),
    detectedAt: DateTime.utc(2026, 1, 3),
  );
}

/// Builds a citation whose span is the exact slice [quote] inside [note].
RagSource sourceFor(
  LocalNoteState note, {
  String sourceId = 'source-1',
  String? quote,
  int? startOffset,
}) {
  final String text = quote ?? note.content;
  final int start = startOffset ?? note.content.indexOf(text);
  if (start < 0) {
    throw ArgumentError.value(quote, 'quote', 'is not inside the note content');
  }
  return RagSource(
    sourceId: sourceId,
    noteId: note.id,
    revision: note.serverRevision,
    title: note.title,
    startOffset: start,
    endOffset: start + text.length,
    quote: text,
  );
}

/// Builds one answered result carrying [sources].
RagResult answeredResult(
  Iterable<RagSource> sources, {
  String answer = 'Answer [S1]',
  String requestId = 'req-1',
}) {
  return RagResult.answered(
    requestId: requestId,
    answer: answer,
    sources: sources,
  );
}

/// Builds one refusal with the canonical insufficient-evidence reason.
RagResult notEnoughContextResult({String requestId = 'req-1'}) {
  return RagResult.notEnoughContext(
    requestId: requestId,
    reason: RagResult.reasonInsufficientEvidence,
  );
}

/// Grants consent, asks one question, and leaves [sources] displayed.
///
/// A citation is only clickable while it belongs to the displayed answer, so a
/// test that opens one starts here.
Future<void> showAnswer(
  RagHarness harness,
  Iterable<RagSource> sources, {
  String question = 'What did I decide?',
  RagScope scope = const RagScope.account(),
}) async {
  harness.gateway.queryScript
    ..clear()
    ..add(answeredResult(sources));
  await harness.grant();
  await harness.service.ask(question: question, scope: scope);
}

/// One harness that displayed an answer over some notes, plus its citations.
final class DisplayedAnswer {
  DisplayedAnswer(this.harness, this.sources);

  final RagHarness harness;
  final List<RagSource> sources;
}

/// Displays one answered result citing every note in [notes].
Future<DisplayedAnswer> displayedAnswer(List<LocalNoteState> notes) async {
  final RagHarness harness = RagHarness(local: localState(notes: notes));
  final List<RagSource> sources = <RagSource>[
    for (int index = 0; index < notes.length; index++)
      sourceFor(notes[index], sourceId: 'source-${index + 1}'),
  ];
  await showAnswer(harness, sources);
  if (harness.service.state.result == null) {
    throw StateError('the fixture answer was not applied');
  }
  return DisplayedAnswer(harness, sources);
}

/// Matches a thrown [RagFailure] whose code is [code].
Matcher throwsFailure(RagFailureCode code) {
  return throwsA(
    isA<RagFailure>().having((RagFailure f) => f.code, 'code', code),
  );
}

/// One wired [RagAppService] with its fakes and a mutable local state.
final class RagHarness {
  /// Creates the harness; the local state defaults to one eligible note.
  RagHarness({
    List<Object>? consentScript,
    List<Object>? writeScript,
    List<Object>? queryScript,
    LocalSyncState? local,
    String userId = 'user-1',
    DateTime? start,
  }) : gateway = FakeRagGateway(
         consentScript: consentScript,
         writeScript: writeScript,
         queryScript: queryScript,
       ),
       currentUser = FakeCurrentUser(userId: userId),
       session = FakeSession(),
       clock = FakeClock(start ?? DateTime.utc(2026, 1, 1)),
       local =
           local ??
           localState(notes: <LocalNoteState>[ownedNote(ownerId: userId)]) {
    service = RagAppService(
      gateway: gateway,
      currentUser: currentUser,
      session: session,
      readLocalState: (String actorId) async {
        readLocalStateCalls++;
        final Future<LocalSyncState>? pending = pendingLocalRead;
        if (pending != null && hangLocalReadAt == readLocalStateCalls) {
          return pending;
        }
        final Object? failure = localStateError;
        if (failure != null) throw failure;
        final LocalSyncState current = this.local;
        if (current.accountUserId != actorId) {
          throw StateError('store returned another account');
        }
        return current;
      },
      now: clock.call,
    );
  }

  final FakeRagGateway gateway;
  final FakeCurrentUser currentUser;
  final FakeSession session;
  final FakeClock clock;

  /// The local sync state every `readLocalState` call returns.
  LocalSyncState local;

  /// When set, `readLocalState` throws this instead of returning [local].
  Object? localStateError;

  /// When set together with [hangLocalReadAt], that read never completes.
  Future<LocalSyncState>? pendingLocalRead;

  /// Which read (1-based) [pendingLocalRead] replaces, or null for none.
  int? hangLocalReadAt;

  /// How many times the service read the local state.
  int readLocalStateCalls = 0;

  /// The wired service.
  late final RagAppService service;

  /// Makes the next local read hang on [pending] until it completes.
  void hangNextLocalRead(Future<LocalSyncState> pending) {
    pendingLocalRead = pending;
    hangLocalReadAt = readLocalStateCalls + 1;
  }

  /// Grants the canonical consent and lets the service adopt it.
  Future<void> grant({int generation = 1}) async {
    gateway.consentScript
      ..clear()
      ..add(RagConsent(accepted: true, generation: generation));
    await service.refreshConsent();
  }
}
