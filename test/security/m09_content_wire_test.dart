import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/infrastructure/security/http_note_security_gateway.dart';
import 'package:note_ai_app/application/notes/note_access.dart';

import '../infrastructure/documents/m09_document_wire_test.dart' show wireNote;
import '../infrastructure/documents/m09_storage_fixtures.dart' as fixture;

HttpNoteSecurityGateway gateway(MockClient client) {
  final claims = base64UrlEncode(utf8.encode(jsonEncode({'sub': 'owner'})));
  return HttpNoteSecurityGateway(
    baseUri: Uri.parse('https://fixture.invalid'),
    accountId: 'owner',
    documentsEnabled: true,
    isCurrentSession: () => true,
    tokenProvider: ({required forceRefresh}) async => 'e30.$claims.test',
    client: client,
  );
}

http.Response response(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  test(
    'authorized V3 content requires capability and retains rich structure',
    () async {
      final service = gateway(
        MockClient((request) async {
          expect(request.url.queryParameters['wireVersion'], '3');
          return response({
            ...wireNote(),
            'documentCapability': 'basicBlocksV1',
          });
        }),
      );
      expect((await service.content('n')).document, fixture.doc());
      service.close();
    },
  );
  test(
    'older content version refuses then V2 fallback stays explicitly legacy',
    () async {
      final versions = <String?>[];
      final service = gateway(
        MockClient((request) async {
          final version = request.url.queryParameters['wireVersion'];
          versions.add(version);
          return version == '3'
              ? response({'code': 'NOTE_SECURITY_INPUT_INVALID'}, 400)
              : response(wireNote(rich: false));
        }),
      );
      expect((await service.content('n')).includesDocument, false);
      expect(versions, ['3', '2']);
      service.close();
    },
  );
  test(
    'missing V3 capability refuses instead of downgrading readable content',
    () async {
      var count = 0;
      final service = gateway(
        MockClient((_) async {
          count++;
          return response(wireNote());
        }),
      );
      await expectLater(
        service.content('n'),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(count, 1);
      service.close();
    },
  );
}
