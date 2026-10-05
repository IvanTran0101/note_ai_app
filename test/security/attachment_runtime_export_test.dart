import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_security_adapter.dart';
import 'package:note_ai_app/infrastructure/security/note_security_runtime.dart';

import 'security_fixtures.dart';
import 'security_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SecurityHarness harness;
  late NoteSecurityRuntime runtime;
  late AttachmentSecurityAdapter adapter;
  const actor = 'attachment-export-owner';
  final grant = 'g' * 43;
  final denied = throwsA(isA<NoteSecurityFailure>());

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    harness = SecurityHarness(actor);
    await harness.initialize();
    runtime = NoteSecurityRuntime(
      session: harness.session,
      storeForAccount: ({required accountUserId}) => harness.store,
      baseUri: Uri.parse('https://example.test'),
      cancelSummaries: () {},
      syncNow: (_) async {},
      tokenProvider: ({required forceRefresh}) async =>
          '${base64UrlEncode(utf8.encode('{}'))}.'
          '${base64UrlEncode(utf8.encode(jsonEncode({'sub': actor, 'token_use': 'access'})))}.test',
      client: MockClient((request) async {
        final path = request.url.path;
        final Map<String, Object?> response;
        if (path.endsWith('/protection/unlock')) {
          response = {
            'enabled': true,
            'revision': 1,
            'grant': grant,
            'operations': (jsonDecode(request.body) as Map)['operations'],
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 15))
                .millisecondsSinceEpoch,
          };
        } else if (path.endsWith('/protection')) {
          response = {'enabled': true, 'revision': 1};
        } else if (path.endsWith('/content')) {
          response = {
            'id': 'alpha',
            'ownerId': actor,
            'title': privateTitle,
            'content': privateBody,
            'createdAt': fixtureTime.toIso8601String(),
            'serverUpdatedAt': fixtureTime.toIso8601String(),
            'revision': 7,
            'protected': true,
            'protectionRevision': 1,
            'contentAvailable': true,
          };
        } else {
          throw StateError('Unexpected synthetic security route');
        }
        return http.Response.bytes(utf8.encode(jsonEncode(response)), 200);
      }),
    );
    adapter = AttachmentSecurityAdapter(
      security: runtime,
      storeForAccount: (_) => harness.store,
    );
  });
  tearDown(() {
    runtime.dispose();
    harness.dispose();
  });

  Future<void> onlineUnlock() async {
    await runtime.observe(
      actor,
      SyncNoteSnapshot(
        id: 'alpha',
        ownerId: actor,
        title: '',
        content: '',
        createdAt: fixtureTime,
        serverUpdatedAt: fixtureTime,
        revision: 7,
        protection: NoteProtection(enabled: true, revision: 1),
        contentAvailable: false,
      ),
    );
    await runtime.forAccount(actor).unlock('alpha', securityPassword);
  }

  test(
    'protected owner forwards export grant after first online unlock',
    () async {
      await onlineUnlock();
      final binding = await adapter.capture('alpha');
      expect(runtime.attachmentGrant(binding, NoteOperation.export), grant);
      expect(
        runtime.attachmentGrant(binding, NoteOperation.attachmentRead),
        grant,
      );
    },
  );

  test('unprotected owner export needs no password grant', () async {
    final binding = await adapter.capture('alpha');
    expect(runtime.attachmentGrant(binding, NoteOperation.export), null);
    expect(
      () => runtime.attachmentGrant(binding, NoteOperation.manage),
      denied,
    );
  });

  test('recipient cannot forward attachment export or write', () {
    final binding = AttachmentBinding(
      actorId: actor,
      note: NoteIdentity('different-owner', 'alpha'),
      protection: const NoteProtection.unprotected(),
      accessRevision: 1,
      sessionGeneration: harness.session.sessionGeneration,
      accessGeneration: runtime.accessGeneration,
      contentRevision: 7,
    );
    expect(
      () => runtime.attachmentGrant(binding, NoteOperation.export),
      denied,
    );
    expect(
      () => runtime.attachmentGrant(binding, NoteOperation.attachmentWrite),
      denied,
    );
  });

  test('lock and session invalidation fence captured owner export', () async {
    await onlineUnlock();
    final binding = await adapter.capture('alpha');
    runtime.lockAll();
    expect(
      () => runtime.attachmentGrant(binding, NoteOperation.export),
      denied,
    );
    await onlineUnlock();
    final next = await adapter.capture('alpha');
    runtime.invalidateSession();
    expect(() => runtime.attachmentGrant(next, NoteOperation.export), denied);
  });
}
