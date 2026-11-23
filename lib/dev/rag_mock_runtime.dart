/// Composition of the explicit offline RAG mock runtime.
///
/// It wires the real [NoteFlowApp] root to the synthetic transport and the
/// in-memory fixture store: the same [NoteConnection] seam the M06 local root
/// uses, the same real `RagHttpGateway` the production entrypoint builds, and a
/// debug-only `RagMockClient` that can never reach a real AWS, profile, or
/// attachment route.
library;

import 'package:flutter/foundation.dart';

import '../application/sync/revision_source.dart';
import '../application/sync/local_sync_store.dart';
import '../infrastructure/configuration/note_connection.dart';
import 'rag_mock_actors.dart';
import 'rag_mock_client.dart';
import 'rag_mock_fixture.dart';
import 'rag_mock_store.dart';

/// One account-isolated, fully synthetic offline RAG mock runtime.
final class RagMockRuntime {
  RagMockRuntime._(this.actor, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      client = RagMockClient();

  /// Builds the runtime for [actor].
  factory RagMockRuntime.create(
    RagMockActor actor, {
    DateTime Function()? now,
  }) => RagMockRuntime._(actor, now: now);

  /// The selected synthetic actor.
  final RagMockActor actor;

  /// The in-process transport. It owns no network client of its own.
  final RagMockClient client;

  final DateTime Function() _now;
  bool _disposed = false;
  RagMockMemoryStore? _selectedStore;

  /// The logical RAG endpoint handed to the real root; the mock transport is
  /// the only thing that can answer it.
  Uri get ragApiBaseUri => ragMockLogicalBase;

  /// The single source of truth the root uses for both sync and RAG.
  NoteConnection get connection => NoteConnection(
    baseUri: ragMockLogicalBase,
    tokenProvider: _accessToken,
    client: client,
    revisionSourceFor: (_) => const RagMockInertRevisionSource(),
  );

  /// The account-bound store factory; the selected actor gets the seeded
  /// fixture, and any other id gets an isolated empty store.
  ILocalSyncStore storeFor({required String accountUserId}) {
    if (accountUserId == actor.userId) {
      return _selectedStore ??= RagMockMemoryStore.forActor(actor);
    }
    return RagMockMemoryStore.empty(accountUserId: accountUserId);
  }

  /// The visible synthetic banner, including the exact fixture question.
  String get bannerText {
    final RagMockFixture fixture = ragMockFixtureFor(actor);
    return 'OFFLINE RAG MOCK · ${actor.user.name} · ${actor.email} · '
        'synthetic example.invalid identity; no AWS, key, network, or model.\n'
        'Consent starts OFF. Grant ask-notes consent in Settings, then ask '
        '"$ragMockAnswerableQuestion" (account or own-note scope). '
        'Any other question abstains. Fixture note: ${fixture.noteId} @ '
        'r${fixture.serverRevision}.';
  }

  Future<String?> _accessToken({required bool forceRefresh}) async {
    if (!kDebugMode) {
      throw StateError('The offline RAG mock requires a debug build.');
    }
    return ragMockAccessToken(actor, now: _now());
  }

  /// Releases the in-process transport. The runtime owns only memory state: it
  /// writes no file, reaches no provider, and opens no network connection.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    client.close();
  }
}

/// A deliberately inert revision source: the offline mock has no realtime
/// service, so it never emits a notice and never opens a socket.
final class RagMockInertRevisionSource implements IRevisionSource {
  /// Creates the inert source.
  const RagMockInertRevisionSource();

  @override
  Stream<RevisionNotice> get notices => const Stream<RevisionNotice>.empty();

  @override
  void start() {}

  @override
  void reconnect() {}

  @override
  Future<void> dispose() async {}
}
