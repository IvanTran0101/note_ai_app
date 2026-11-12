import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/dev/m06_local_connection.dart';
import 'package:note_ai_app/infrastructure/security/note_jwt_subject.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_codec.dart';
import 'package:note_ai_app/infrastructure/attachments/http_attachment_upload.dart';

final class _AbortObserver extends http.BaseClient {
  http.BaseRequest? sent;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent = request;
    await request.finalize().drain<void>();
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }
}

void main() {
  test(
    'dev attachment staging uses anonymous loopback PUT and verified ACK',
    () async {
      final id = 'a' * 64;
      final descriptor = Attachment(
        id: id,
        noteId: 'note',
        fileName: 'file.txt',
        mimeType: 'text/plain',
        sizeBytes: 5,
        storageObjectId: 'final/object',
        objectVersion: 'v1',
        sha256: 'b' * 64,
        addedAt: DateTime.utc(2026, 10, 5),
      );
      var puts = 0;
      final client = M06LoopbackClient(
        inner: MockClient((request) async {
          expect(request.url.host, '127.0.0.1');
          expect(request.url.port, 8796);
          if (request.method == 'PUT') {
            puts++;
            expect(request.url.path, '/dev/attachment-put');
            expect(
              request.headers.keys.map((k) => k.toLowerCase()),
              isNot(contains('authorization')),
            );
            expect(request.bodyBytes, utf8.encode('hello'));
            return http.Response('', 200);
          }
          expect(request.headers['authorization'], endsWith('.local-dev'));
          final action = request.url.pathSegments.last;
          return http.Response(
            jsonEncode(
              action == 'chunk-url'
                  ? {
                      'url': 'http://127.0.0.1:8796/dev/attachment-put?ticket=fixture',
                      'headers': {'content-type': 'application/octet-stream'},
                    }
                  : action == 'verify'
                  ? {
                      'phase': 'verified',
                      'attachment': AttachmentCodec.encode(descriptor),
                    }
                  : {
                      'phase': 'uploading',
                      'completedChunks': 0,
                      'chunkCount': 1,
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final connection = devConnection('m06-dev-owner', client);
      expect(connection.allowLocalAttachmentUploads, true);
      final uploader = HttpAttachmentUpload(
        baseUri: connection.baseUri,
        tokenProvider: connection.tokenProvider,
        grantHeader: (_, _) => null,
        requireAccess: (_, _) {},
        client: client,
        allowLocalDev: connection.allowLocalAttachmentUploads,
      );
      final result = await uploader.upload(
        AttachmentBinding(
          actorId: 'm06-dev-owner',
          note: NoteIdentity('m06-dev-owner', 'note'),
          protection: const NoteProtection.unprotected(),
          accessRevision: 0,
          sessionGeneration: 1,
          contentRevision: 1,
        ),
        LocalAttachmentDraft(
          cacheId: id,
          fileName: 'file.txt',
          mimeType: 'text/plain',
          sizeBytes: 5,
          sha256: 'b' * 64,
          chunkCount: 1,
        ),
        () => Stream.value(Uint8List.fromList(utf8.encode('hello'))),
      );
      expect(result, descriptor);
      expect(puts, 1);
    },
  );
  test('rewritten API request keeps its abort signal', () async {
    final inner = _AbortObserver();
    final client = M06LoopbackClient(inner: inner);
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'POST',
            devLogicalApi.replace(path: '/notes/n'),
            abortTrigger: abort.future,
          )
          ..headers['authorization'] =
              'Bearer ${devToken('m06-dev-owner', 'access')}'
          ..body = '{}';
    await client.send(request);
    expect(inner.sent, isA<http.AbortableRequest>());
    expect(
      (inner.sent as http.AbortableRequest).abortTrigger,
      same(abort.future),
    );
    client.close();
  });
  test('anonymous staging refuses other routes, methods, credentials and redirects', () async {
    final client = M06LoopbackClient(
      inner: MockClient((_) async => fail('must not send')),
    );
    addTearDown(client.close);
    for (final path in ['/notes/n', '/dev/attachment-put']) {
      for (final method in ['GET', 'PUT']) {
        final request = http.Request(
          method,
          Uri.parse('http://127.0.0.1:8796$path'),
        )..followRedirects = false;
        if (path == '/dev/attachment-put' && method == 'PUT') {
          request.headers['authorization'] = 'Bearer x.local-dev';
        }
        await expectLater(
          client.send(request),
          throwsA(isA<http.ClientException>()),
        );
      }
    }
    final redirect = http.Request(
      'PUT',
      Uri.parse('http://127.0.0.1:8796/dev/attachment-put'),
    );
    await expectLater(
      client.send(redirect),
      throwsA(isA<http.ClientException>()),
    );
  });
  test('demo JWT binds exactly one fixed actor and token use', () {
    final token = devToken('m06-dev-owner', 'access');
    expect(noteJwtSubject(token), 'm06-dev-owner');
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    ) as Map;
    expect(claims['iss'], 'm06-local-dev');
    expect(claims['token_use'], 'access');
    expect(token.endsWith('.local-dev'), isTrue);
    expect(() => devToken('real-account', 'access'), throwsStateError);
  });
  test(
    'loopback client preserves body/query/grant and disables redirects',
    () async {
      late http.Request sent;
      final client = M06LoopbackClient(
        inner: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
      );
      await client.post(
        devLogicalApi.replace(
          path: '/notes/n/shares',
          query: 'ownerId=m06-dev-owner',
        ),
        headers: {
          'Authorization': 'Bearer ${devToken('m06-dev-owner', 'access')}',
          'X-Note-Unlock-Grant': 'test',
        },
        body: '{"action":"create"}',
      );
      expect(
        sent.url.toString(),
        'http://127.0.0.1:8796/notes/n/shares?ownerId=m06-dev-owner',
      );
      expect(sent.body, '{"action":"create"}');
      expect(sent.headers['X-Note-Unlock-Grant'], 'test');
      expect(sent.followRedirects, isFalse);
      client.close();
    },
  );
  for (final uri in [
    'https://cloud.example/notes',
    'http://m06-dev.invalid/',
    'https://name@m06-dev.invalid/',
    'https://m06-dev.invalid:8443/',
    'https://m06-dev.invalid/#fragment',
  ]) {
    test('refuses non-demo endpoint $uri before transport', () async {
      var calls = 0;
      final client = M06LoopbackClient(
        inner: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        client.get(
          Uri.parse(uri),
          headers: {'Authorization': 'Bearer x.local-dev'},
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(calls, 0);
      client.close();
    });
  }
  test('refuses real provider credentials before transport', () async {
    final client = M06LoopbackClient(
      inner: MockClient((_) async => fail('must not send')),
    );
    await expectLater(
      client.get(
        devLogicalApi,
        headers: {'Authorization': 'Bearer real-token'},
      ),
      throwsA(isA<http.ClientException>()),
    );
    client.close();
  });
  test('revision factory refuses a different actor', () {
    final client = M06LoopbackClient();
    final connection = devConnection('m06-dev-owner', client);
    expect(
      () => connection.revisionSourceFor('m06-dev-recipient'),
      throwsStateError,
    );
    client.close();
  });
}
