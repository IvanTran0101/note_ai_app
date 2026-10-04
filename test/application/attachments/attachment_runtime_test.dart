import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_runtime.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_blob_store_io.dart';
import 'package:note_ai_app/infrastructure/security/note_security_runtime.dart';

import '../../security/security_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SecurityHarness h;
  late NoteSecurityRuntime security;
  late AttachmentRuntime runtime;
  late Directory directory;
  final bytes = utf8.encode('PRIVATE-ATTACHMENT-CONTENT');
  AttachmentInput input() => AttachmentInput(
    fileName: 'PRIVATE-FILE.txt',
    mimeType: 'text/plain',
    sizeBytes: bytes.length,
    openRead: ([start, end]) =>
        Stream.value(bytes.sublist(start ?? 0, end ?? bytes.length)),
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('m03-runtime-');
    h = SecurityHarness('binary-runtime-owner');
    await h.initialize();
    security = NoteSecurityRuntime(
      session: h.session,
      storeForAccount: ({required accountUserId}) => h.store,
      baseUri: null,
      cancelSummaries: () {},
      syncNow: (_) async {},
    );
    runtime = AttachmentRuntime(
      security: security,
      notes: h.repo,
      storeForAccount: (_) => h.store,
      requestSync: (_) {},
      blobStoreFactory: ({required actorId}) => FileAttachmentBlobStore(
        actorId: actorId,
        supportPath: () async => directory.path,
      ),
    );
  });
  tearDown(() async {
    security.dispose();
    h.dispose();
    await directory.delete(recursive: true);
  });

  test('production composition stages ciphertext, reopens Pending and fails cloud closed', () async {
    final service = runtime.forCurrentAccount();
    final draft = await service.stage('alpha', input());
    final files = await directory
        .list(recursive: true)
        .where((f) => f is File)
        .cast<File>()
        .toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      final encoded = await file.readAsString();
      expect(encoded, isNot(contains('PRIVATE-FILE')));
      expect(encoded, isNot(contains('PRIVATE-ATTACHMENT')));
    }
    expect(
      await service.readLocal('alpha', draft.cacheId).expand((b) => b).toList(),
      bytes,
    );
    final reopened = AttachmentRuntime(
      security: security,
      notes: h.repo,
      storeForAccount: (_) => h.store,
      requestSync: (_) {},
      blobStoreFactory: ({required actorId}) => FileAttachmentBlobStore(
        actorId: actorId,
        supportPath: () async => directory.path,
      ),
    ).forCurrentAccount();
    expect((await reopened.pending('alpha')).single.cacheId, draft.cacheId);
    await expectLater(
      reopened.retry('alpha', draft.cacheId),
      throwsA(
        isA<NoteSecurityFailure>().having(
          (e) => e.code,
          'code',
          NoteSecurityFailureCode.unavailable,
        ),
      ),
    );
    expect((await h.store.read()).notes.first.attachments, isEmpty);
    expect((await reopened.pending('alpha')).single.cacheId, draft.cacheId);
    await reopened.cancel('alpha', draft.cacheId);
    expect(await reopened.pending('alpha'), isEmpty);
  });

  test(
    'same actor relogin fences active reader but preserves pending ciphertext',
    () async {
      final service = runtime.forCurrentAccount();
      final draft = await service.stage('alpha', input());
      final stream = StreamIterator(service.readLocal('alpha', draft.cacheId));
      expect(await stream.moveNext(), isTrue);
      h.session.clear();
      security.invalidateSession();
      h.session.setIdentity(
        AuthIdentity(
          userId: h.account,
          email: 'synthetic@example.test',
          isEmailVerified: true,
        ),
      );
      await expectLater(stream.moveNext(), throwsA(isA<NoteSecurityFailure>()));
      await stream.cancel();
      expect(
        (await runtime.forCurrentAccount().pending('alpha')).single.cacheId,
        draft.cacheId,
      );
    },
  );
}
