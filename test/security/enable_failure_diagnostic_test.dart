import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_gateway.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';

import 'security_fixtures.dart';

final class RejectEnableGateway implements INoteSecurityGateway {
  @override
  Future<NoteProtection> metadata(String id) async =>
      const NoteProtection.unprotected();

  @override
  Future<NoteProtection> enable(
    String id,
    String password,
    int revision,
  ) async =>
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);

  @override
  void invalidate(String? id) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'failed remote enable leaves the local note sealed and locked',
    () async {
      const account = 'synthetic-enable-failure';
      final session = CurrentUserSession()
        ..setIdentity(
          AuthIdentity(
            userId: account,
            email: 'synthetic@example.invalid',
            isEmailVerified: true,
          ),
        );
      final store = EncryptedSyncStore(account, MemoryCiphertextStore());
      final service = NoteSecurityService(
        accountId: account,
        currentUser: session,
        session: session,
        store: store,
        vault: store,
        gateway: RejectEnableGateway(),
        localFirst: false,
      );
      addTearDown(() {
        service.dispose();
        store.dispose();
      });
      await store.replace(securityState(account));

      await expectLater(
        service.enable('alpha', securityPassword, securityPassword),
        throwsA(
          isA<NoteSecurityFailure>().having(
            (failure) => failure.code,
            'code',
            NoteSecurityFailureCode.unavailable,
          ),
        ),
      );
      final note = (await store.read()).notes.singleWhere(
        (n) => n.id == 'alpha',
      );
      expect(note.protection.enabled, isTrue);
      expect(note.contentAvailable, isFalse);
      expect(note.content, isEmpty);

      await service.unlock('alpha', securityPassword, offline: true);
      final recovered = (await store.read()).notes.singleWhere(
        (n) => n.id == 'alpha',
      );
      expect(recovered.content, privateBody);
    },
  );
}
