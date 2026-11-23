import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/infrastructure/security/http_note_security_gateway.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';

void main() {
  for (final owner in ['actor', 'other-owner']) {
    test(
      'authorized content negotiates V2 and keeps owner query for $owner',
      () async {
        final payload = base64UrlEncode(
          utf8.encode(jsonEncode({'sub': 'actor', 'token_use': 'access'})),
        );
        final gateway = HttpNoteSecurityGateway(
          baseUri: Uri.parse('https://example.test'),
          accountId: 'actor',
          tokenProvider: ({required forceRefresh}) async => 'e30.$payload.test',
          isCurrentSession: () => true,
          client: MockClient((request) async {
            expect(request.url.queryParameters['wireVersion'], '2');
            expect(
              request.url.queryParameters['ownerId'],
              owner == 'actor' ? null : owner,
            );
            return http.Response(
              jsonEncode({
                'id': 'alpha',
                'title': 'synthetic title',
                'content': 'synthetic body',
                'createdAt': '2026-10-13T00:00:00Z',
                'serverUpdatedAt': '2026-10-13T00:00:00Z',
                'revision': 1,
                'pinnedAt': null,
                'deletedAt': null,
                'labelIds': ['label-a'],
                'labelProjections': [],
                'attachments': [],
              }),
              200,
            );
          }),
        );
        final note = await gateway.content(
          NoteIdentity(owner, 'alpha').referenceFor('actor'),
        );
        expect(note.includesLabels, true);
        expect(note.labelIds, ['label-a']);
        expect(note.includesAttachments, true);
      },
    );
  }
}
