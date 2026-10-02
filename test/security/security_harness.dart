import 'dart:async';

import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_security_gateway.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

import 'security_fixtures.dart';

/// Synthetic server port for client orchestration/UI; backend policies are
/// exercised independently against production use cases, not this fake.
final class SyntheticSecurityGateway implements INoteSecurityGateway {
  NoteProtection protection = const NoteProtection.unprotected();
  String password = '';
  NoteUnlockLease? lease;
  DateTime now = fixtureTime;
  int enableCalls = 0;
  @override
  Future<NoteProtection> metadata(String id) async => protection;
  @override
  Future<SyncNoteSnapshot> content(String id) async {
    if (protection.enabled &&
        !hasAuthority(id, protection, NoteOperation.read)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    return SyncNoteSnapshot(
      id: id,
      title: privateTitle,
      content: privateBody,
      createdAt: fixtureTime,
      serverUpdatedAt: fixtureTime,
      revision: 7,
      protection: protection,
    );
  }

  void _verify(String supplied) {
    if (supplied != password) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidPassword);
    }
  }

  @override
  Future<NoteProtection> enable(String id, String value, int revision) async {
    enableCalls++;
    password = value;
    return protection = NoteProtection(
      enabled: true,
      revision: protection.revision + 1,
    );
  }

  @override
  Future<NoteUnlockLease> unlock(
    String id,
    String value,
    Set<NoteOperation> operations,
  ) async {
    _verify(value);
    return lease = NoteUnlockLease(
      protection: protection,
      operations: operations,
      expiresAt: now.add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<NoteProtection> change(
    String id,
    String old,
    String value,
    int epoch,
  ) async {
    _verify(old);
    password = value;
    lease = null;
    return protection = NoteProtection(enabled: true, revision: epoch + 1);
  }

  @override
  Future<NoteProtection> disable(String id, String old, int epoch) async {
    _verify(old);
    lease = null;
    return protection = NoteProtection(enabled: false, revision: epoch + 1);
  }

  @override
  Future<NoteRecoveryChallenge> requestRecovery(String id) async =>
      NoteRecoveryChallenge(
        'synthetic-challenge',
        now.add(const Duration(minutes: 5)),
      );
  @override
  Future<NoteUnlockLease> confirmRecovery(
    String id,
    String challenge,
    String code,
    String value,
  ) async {
    if (challenge != 'synthetic-challenge' || code != '123456') {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.invalidChallenge);
    }
    password = value;
    protection = NoteProtection(
      enabled: true,
      revision: protection.revision + 1,
    );
    return unlock(id, value, {
      NoteOperation.read,
      NoteOperation.edit,
      NoteOperation.delete,
      NoteOperation.manage,
      NoteOperation.summary,
    });
  }

  @override
  bool hasAuthority(String id, NoteProtection p, NoteOperation op) =>
      lease?.protection == p &&
      lease!.expiresAt.isAfter(now) &&
      lease!.operations.contains(op);
  @override
  void invalidate(String? id) {
    lease = null;
  }
}

final class SecurityHarness {
  SecurityHarness(this.account);
  final String account;
  final session = CurrentUserSession();
  final gateway = SyntheticSecurityGateway();
  final backing = MemoryCiphertextStore();
  late final store = EncryptedSyncStore(account, backing);
  late final security = NoteSecurityService(
    accountId: account,
    currentUser: session,
    session: session,
    store: store,
    vault: store,
    gateway: gateway,
    now: () => gateway.now,
  );
  late final repo = NoteRepository(
    currentAccountUserId: () => session.requiredUserId,
    localSyncStoreFactory: ({required accountUserId}) => store,
    generateMutationId: () => 'ui-mutation-${_mutation++}',
    now: () => fixtureTime,
    accessGuard: security,
    sessionGeneration: () => session.sessionGeneration,
  );
  int _mutation = 0;
  int summaryCalls = 0;
  Completer<Summary>? delayedSummary;
  late final app = NoteApplicationService(
    noteRepository: repo,
    currentUser: session,
    generateId: () => 'synthetic-created',
    now: () => fixtureTime,
    security: security,
    summarizeContent: (_) async {
      summaryCalls++;
      return delayedSummary?.future ??
          Future.value(const Summary('synthetic private summary'));
    },
  );
  late final controller = NoteApplicationServiceController(
    app,
    securityForCurrentAccount: () => security,
    securityEvents: security.changes,
    readAccessGeneration: () => security.accessGeneration,
    readSessionGeneration: () => session.sessionGeneration,
    serverAvailable: true,
  );
  Future<void> initialize() async {
    session.setIdentity(
      AuthIdentity(
        userId: account,
        email: 'synthetic@example.test',
        isEmailVerified: true,
      ),
    );
    await store.replace(securityState(account));
  }

  void dispose() {
    security.dispose();
    store.dispose();
  }
}
