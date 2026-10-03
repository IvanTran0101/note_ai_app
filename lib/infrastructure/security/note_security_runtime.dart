import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../application/auth/current_user_session.dart';
import '../../application/notes/local_note_vault.dart';
import '../../application/notes/note_access.dart';
import '../../application/notes/note_application.dart';
import '../../application/notes/note_security_service.dart';
import '../../application/sync/local_sync_store.dart';
import '../../application/sync/sync_mutation.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_access_policy.dart';
import '../sync/cognito_access_token_provider.dart';
import 'http_note_security_gateway.dart';
import 'unavailable_note_security_gateway.dart';

/// Composition/lifecycle of one isolated security service per signed-in account.
final class NoteSecurityRuntime implements INoteAccessGuard {
  NoteSecurityRuntime({
    required this.session,
    required this.storeForAccount,
    required this.baseUri,
    required this.cancelSummaries,
    required this.syncNow,
    Future<String?> Function({required bool forceRefresh})? tokenProvider,
    this.client,
  }) : tokenProvider = tokenProvider ?? const CognitoAccessTokenProvider().call;
  final CurrentUserSession session;
  final ILocalSyncStore Function({required String accountUserId})
  storeForAccount;
  final Uri? baseUri;
  final Future<String?> Function({required bool forceRefresh}) tokenProvider;
  final http.Client? client;
  final void Function() cancelSummaries;
  final Future<void> Function(String accountId) syncNow;
  final _services = <String, NoteSecurityService>{};
  final _gateways = <String, HttpNoteSecurityGateway>{};
  final _subscriptions = <StreamSubscription<void>>[];
  final _changes = StreamController<void>.broadcast(sync: true);
  int _generation = 0;
  Stream<void> get changes => _changes.stream;
  bool get serverAvailable => baseUri != null;
  @override
  int get accessGeneration => _generation;

  void requireSession(String account) {
    if (_changes.isClosed || session.userId != account) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
  }

  NoteSecurityService forAccount(String account) {
    requireSession(account);
    return _services.putIfAbsent(account, () {
      final store = storeForAccount(accountUserId: account);
      if (store is! ILocalNoteVault) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
      }
      final generation = session.sessionGeneration;
      final uri = baseUri;
      final gateway = uri == null
          ? null
          : HttpNoteSecurityGateway(
              baseUri: uri,
              accountId: account,
              tokenProvider: tokenProvider,
              client: client,
              isCurrentSession: () =>
                  !_changes.isClosed &&
                  session.userId == account &&
                  session.sessionGeneration == generation,
            );
      if (gateway != null) _gateways[account] = gateway;
      final service = NoteSecurityService(
        accountId: account,
        localFirst: kIsWeb,
        currentUser: session,
        session: session,
        store: store,
        vault: store as ILocalNoteVault,
        gateway: gateway ?? const UnavailableNoteSecurityGateway(),
        syncNow: () => syncNow(account),
        cancelSummaries: cancelSummaries,
      );
      _subscriptions.add(
        service.changes.listen((_) {
          _generation++;
          if (!_changes.isClosed) _changes.add(null);
        }),
      );
      return service;
    });
  }

  @override
  bool allows({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) {
    if (_changes.isClosed || session.userId == null) return false;
    return _services[session.userId]?.allows(
          ownerId: ownerId,
          noteId: noteId,
          protection: protection,
          operation: operation,
        ) ??
        !protection.enabled;
  }

  @override
  void requireAccess({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) {
    if (!allows(
      ownerId: ownerId,
      noteId: noteId,
      protection: protection,
      operation: operation,
    )) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
  }

  Future<String?> mutationGrant(String account, SyncMutation mutation) async {
    requireSession(account);
    final generation = session.sessionGeneration;
    final state = await storeForAccount(accountUserId: account).read();
    requireSession(account);
    if (generation != session.sessionGeneration) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    final note = state.notes
        .where((n) => n.identity == mutation.identityFor(account))
        .firstOrNull;
    if (note == null || !note.contentAvailable) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    final op = mutation.operation == SyncMutationOperation.delete
        ? NoteOperation.delete
        : NoteOperation.edit;
    if (!const NoteAccessPolicy().allows(
          actorId: account,
          note: note.identity,
          share: note.share,
          operation: op,
        ) ||
        (note.ownerId != account &&
            mutation.accessRevision != note.share?.accessRevision)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    requireAccess(
      ownerId: note.ownerId,
      noteId: note.id,
      protection: note.protection,
      operation: op,
    );
    final change =
        mutation.protectionChange ??
        state.outbox
            .where(
              (m) =>
                  m.mutation.identityFor(account) == note.identity &&
                  m.protectionChange != null,
            )
            .firstOrNull
            ?.protectionChange;
    if (mutation.protectionChange == null &&
        change != null &&
        !change.before.enabled &&
        note.protection.enabled) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.pendingSync);
    }
    final remoteProtection = change?.before ?? note.protection;
    final remoteOperation = mutation.protectionChange == null
        ? op
        : NoteOperation.manage;
    if (!remoteProtection.enabled) return null;
    forAccount(account).requireRemote(
      note.referenceFor(account),
      remoteProtection,
      remoteOperation,
    );
    return _gateways[account]!.grantHeader(
      note.referenceFor(account),
      remoteProtection,
      remoteOperation,
    );
  }

  String? summaryGrant(SummaryRunContext context) {
    requireSession(context.accountUserId);
    final note = context.noteSnapshot;
    final p = NoteProtection(
      enabled: note.isProtected,
      revision: note.protectionRevision,
    );
    requireAccess(
      ownerId: note.ownerId,
      noteId: note.id,
      protection: p,
      operation: NoteOperation.summary,
    );
    if (!p.enabled) return null;
    forAccount(context.accountUserId)
        .requireRemote(note.reference, p, NoteOperation.summary);
    return _gateways[context.accountUserId]!.grantHeader(
      note.reference,
      p,
      NoteOperation.summary,
    );
  }

  Future<String?> sharingGrant(NoteIdentity identity) async {
    final account = session.requiredUserId;
    requireSession(account);
    if (identity.ownerId != account) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    final state = await storeForAccount(accountUserId: account).read();
    requireSession(account);
    final note = state.notes.where((n) => n.identity == identity).firstOrNull;
    if (note == null ||
        state.outbox.any(
          (m) =>
              m.mutation.identityFor(account) == identity &&
              m.protectionChange != null,
        )) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.pendingSync);
    }
    if (!note.protection.enabled) return null;
    forAccount(account).requireRemote(
      note.referenceFor(account),
      note.protection,
      NoteOperation.manage,
    );
    return _gateways[account]!.grantHeader(
      note.referenceFor(account),
      note.protection,
      NoteOperation.manage,
    );
  }

  Future<void> observe(String account, SyncNoteSnapshot snapshot) =>
      forAccount(account).observeSnapshot(snapshot);
  Future<void> hydrate(String account, SyncNoteSnapshot snapshot) =>
      forAccount(account).hydrateSnapshot(snapshot);

  void invalidateSession() {
    _generation++;
    for (final service in _services.values) {
      service.dispose();
    }
    for (final gateway in _gateways.values) {
      gateway.close();
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _services.clear();
    _gateways.clear();
    _subscriptions.clear();
    if (!_changes.isClosed) _changes.add(null);
  }

  void lockAll() {
    for (final service in _services.values) {
      service.lock(null);
    }
  }

  void dispose() {
    invalidateSession();
    unawaited(_changes.close());
  }
}
