import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/dev/m06_local_connection.dart';
import 'package:note_ai_app/infrastructure/security/note_jwt_subject.dart';

void main() {
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
