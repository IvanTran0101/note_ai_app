import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/sync/protection_sync_change.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import '../notes/attachment_metadata_test.dart' show descriptor;

void main() {
  for (final protectedChange in [false, true]) {
    for (final populated in [false, true]) {
      test('attachment-only ${protectedChange ? 'protection' : 'ordinary'} '
          '${populated ? 'manifest' : 'unlink'} uses one typed route/encoding', () async {
        final attachments = populated ? [descriptor()] : <Attachment>[];
        final mutation = SyncMutation(
          mutationId: 'attachment-wire',
          noteId: 'note-1',
          operation: SyncMutationOperation.update,
          baseRevision: 1,
          payload: SyncNotePayload(
            title: 'Title',
            content: 'Body',
            includesAttachments: true,
            attachmentManifest: AttachmentManifest(attachments),
          ),
          protectionChange: protectedChange
              ? ProtectionSyncChange(
                  before: const NoteProtection.unprotected(),
                  after: NoteProtection(enabled: true, revision: 1),
                  verifier:
                      'pbkdf2-sha256-v1\$${base64Encode(List.filled(16, 0))}\$${base64Encode(List.filled(32, 0))}',
                )
              : null,
        );
        expect(mutation.payload!.includesLabels, false);
        final encoded = encodeSyncMutation(mutation);
        expect(encoded['wireVersion'], 2);
        expect(encoded['entityType'], 'note');
        expect((encoded['payload'] as Map).containsKey('labelIds'), false);
        final client = MockClient((request) async {
          expect(
            request.url.path,
            protectedChange
                ? '/sync/v2/protected-mutations'
                : '/sync/v2/mutations',
          );
          expect(jsonDecode(request.body), encoded);
          return http.Response(
            jsonEncode({
              'status': 'applied',
              'mutationId': mutation.mutationId,
              'wireVersion': 2,
              'note': {
                'id': 'note-1',
                'title': 'Title',
                'content': 'Body',
                'createdAt': '2026-10-05T00:00:00Z',
                'serverUpdatedAt': '2026-10-05T00:00:00Z',
                'revision': 2,
                'deletedAt': null,
                'attachments': (encoded['payload'] as Map)['attachments'],
              },
            }),
            200,
          );
        });
        addTearDown(client.close);
        final remote = HttpRemoteNoteDataSource(
          baseUri: Uri.parse('https://api.example.test/'),
          tokenProvider: ({required forceRefresh}) async => 'synthetic',
          client: client,
        );
        final result = await remote.push(mutation);
        expect(result.isApplied, true);
        expect(result.note!.attachments, attachments);
      });
    }
  }
  test('legacy text-only encoding remains byte-shape compatible', () {
    final mutation = SyncMutation(
      mutationId: 'legacy',
      noteId: 'note-1',
      operation: SyncMutationOperation.update,
      baseRevision: 1,
      payload: const SyncNotePayload(title: 'Title', content: 'Body'),
    );
    expect(requiresSyncWireV2(mutation), false);
    expect(encodeSyncMutation(mutation), {
      'mutationId': 'legacy',
      'noteId': 'note-1',
      'operation': 'update',
      'baseRevision': 1,
      'payload': {'title': 'Title', 'content': 'Body'},
    });
  });
}
