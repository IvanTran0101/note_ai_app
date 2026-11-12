import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/security/http_note_security_gateway.dart';

String _jwt(String subject) =>
    '${base64UrlEncode(utf8.encode('{}'))}.'
    '${base64UrlEncode(utf8.encode(jsonEncode({'sub': subject, 'token_use': 'access'})))}.test';
Map<String, Object?> _lease() => {
  'enabled': true,
  'revision': 1,
  'grant': 'g' * 43,
  'operations': ['read'],
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 15))
      .millisecondsSinceEpoch,
};
HttpNoteSecurityGateway _gateway(
  http.Client client, {
  bool Function()? current,
  Future<String?> Function({required bool forceRefresh})? token,
}) => HttpNoteSecurityGateway(
  baseUri: Uri.parse('https://example.test'),
  accountId: 'synthetic',
  client: client,
  tokenProvider: token ?? ({required forceRefresh}) async => _jwt('synthetic'),
  isCurrentSession: current ?? () => true,
);

void main() {
  test('JWT subject mismatch is denied before transport', () async {
    var sends = 0;
    final g = _gateway(
      MockClient((_) async {
        sends++;
        return http.Response('{}', 200);
      }),
      token: ({required forceRefresh}) async => _jwt('other'),
    );
    await expectLater(g.metadata('alpha'), throwsA(isA<NoteSecurityFailure>()));
    expect(sends, 0);
  });
  test('raw proof stays private, is scoped and is cleared by lock', () async {
    final requests = <http.Request>[];
    final g = _gateway(
      MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(_lease()), 200);
      }),
    );
    final lease = await g.unlock('alpha', 'synthetic-password', {
      NoteOperation.read,
    });
    expect(lease.toString(), isNot(contains('g' * 43)));
    expect(
      g.grantHeader('alpha', lease.protection, NoteOperation.read),
      'g' * 43,
    );
    expect(
      () => g.grantHeader('beta', lease.protection, NoteOperation.read),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect(
      () => g.grantHeader('alpha', lease.protection, NoteOperation.edit),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect(
      requests.single.url.toString(),
      isNot(contains('synthetic-password')),
    );
    expect(requests.single.url.toString(), isNot(contains('g' * 43)));
    expect(requests.single.followRedirects, false);
    g.invalidate('alpha');
    expect(
      g.hasAuthority('alpha', lease.protection, NoteOperation.read),
      false,
    );
  });
  test(
    'late unlock after session invalidation cannot install a grant',
    () async {
      final response = Completer<http.Response>();
      var sent = false;
      final g = _gateway(
        MockClient((_) {
          sent = true;
          return response.future;
        }),
      );
      final pending = g.unlock('alpha', 'synthetic-password', {
        NoteOperation.read,
      });
      final observed = expectLater(
        pending,
        throwsA(isA<NoteSecurityFailure>()),
      );
      while (!sent) {
        await Future<void>.delayed(Duration.zero);
      }
      g.invalidate(null);
      response.complete(http.Response(jsonEncode(_lease()), 200));
      await observed;
      expect(
        g.hasAuthority(
          'alpha',
          NoteProtection(enabled: true, revision: 1),
          NoteOperation.read,
        ),
        false,
      );
    },
  );
  test('malformed lease and metadata map to safe typed failure', () async {
    for (final value in [
      {
        ..._lease(),
        'operations': ['unknown-operation'],
      },
      {..._lease(), 'revision': 'invalid'},
    ]) {
      final g = _gateway(
        MockClient((_) async => http.Response(jsonEncode(value), 200)),
      );
      await expectLater(
        g.unlock('alpha', 'synthetic-password', {NoteOperation.read}),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(
        g.hasAuthority(
          'alpha',
          NoteProtection(enabled: true, revision: 1),
          NoteOperation.read,
        ),
        false,
      );
    }
    final g = _gateway(
      MockClient(
        (_) async =>
            http.Response('{"enabled":true,"revision":"invalid"}', 200),
      ),
    );
    await expectLater(g.metadata('alpha'), throwsA(isA<NoteSecurityFailure>()));
  });
  test('401 refreshes once and unsafe endpoint fails closed', () async {
    var attempts = 0, refreshes = 0;
    final g = _gateway(
      MockClient((_) async {
        attempts++;
        return attempts == 1
            ? http.Response('{}', 401)
            : http.Response('{"enabled":false,"revision":0}', 200);
      }),
      token: ({required forceRefresh}) async {
        if (forceRefresh) refreshes++;
        return _jwt('synthetic');
      },
    );
    await g.metadata('alpha');
    expect(attempts, 2);
    expect(refreshes, 1);
    expect(
      () => HttpNoteSecurityGateway(
        baseUri: Uri.parse('http://example.test'),
        accountId: 'synthetic',
        tokenProvider: ({required forceRefresh}) async => null,
        isCurrentSession: () => true,
      ),
      throwsA(isA<NoteSecurityFailure>()),
    );
  });
}
