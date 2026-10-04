import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/domain/labels/label_membership.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/sync/http_remote_note_data_source.dart';

const timestamp = '2026-10-04T10:00:00.000Z';
String token(String actor) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor})))}.signature';
Map<String, Object?> wireNote({bool protected = false}) => {
  'id': 'n',
  'ownerId': 'owner',
  'title': 'Authorized',
  'content': 'Body',
  'createdAt': timestamp,
  'serverUpdatedAt': timestamp,
  'deletedAt': null,
  'revision': 1,
  'protected': protected,
  'protectionRevision': protected ? 1 : 0,
  'contentAvailable': true,
  'labelIds': ['a'],
  'labelProjections': [
    {'id': 'a', 'name': 'Label'},
  ],
};
HttpRemoteNoteDataSource adapter(
  MockClient client, {
  String? Function(LocalNoteState)? grant,
}) => HttpRemoteNoteDataSource(
  baseUri: Uri.parse('https://example.invalid'),
  labelsEnabled: true,
  expectedAccountUserId: 'owner',
  client: client,
  tokenProvider: ({required forceRefresh}) async => token('owner'),
  projectionGrant: grant,
);

void main() {
  test('typed Label route, bounded feed version and immutable legacy request shape', () async {
    final calls = <http.Request>[];
    final remote = adapter(
      MockClient((r) async {
        calls.add(r);
        if (r.method == 'GET') {
          return http.Response(
            jsonEncode({'wireVersion': 2, 'items': [], 'hasMore': false}),
            200,
          );
        }
        final body = jsonDecode(r.body) as Map;
        if (body['entityType'] == 'label') {
          return http.Response(
            jsonEncode({
              'wireVersion': 2,
              'entityType': 'label',
              'mutationId': 'm',
              'status': 'applied',
              'label': {
                'id': 'a',
                'ownerId': 'owner',
                'name': 'Label',
                'revision': 1,
                'createdAt': timestamp,
                'serverUpdatedAt': timestamp,
                'deletedAt': null,
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'status': 'applied',
            'mutationId': 'old',
            'note': wireNote(),
          }),
          200,
        );
      }),
    );
    await remote.push(
      SyncMutation(
        mutationId: 'm',
        noteId: 'a',
        entityType: SyncEntityType.label,
        labelName: 'Label',
        operation: SyncMutationOperation.create,
        baseRevision: 0,
      ),
    );
    await remote.pull();
    await remote.push(
      SyncMutation(
        mutationId: 'old',
        noteId: 'n',
        operation: SyncMutationOperation.update,
        baseRevision: 1,
        payload: const SyncNotePayload(title: 'Old', content: 'Body'),
      ),
    );
    expect(calls.map((c) => c.url.path), [
      '/sync/v2/mutations',
      '/sync/v2/changes',
      '/sync/mutations',
    ]);
    expect(jsonDecode(calls.last.body), isNot(contains('wireVersion')));
  });
  test('missing label-aware ACK never clears an empty detach', () async {
    final remote = adapter(
      MockClient((r) async {
        final n = wireNote()
          ..remove('labelIds')
          ..remove('labelProjections');
        return http.Response(
          jsonEncode({'status': 'applied', 'mutationId': 'm', 'note': n}),
          200,
        );
      }),
    );
    await expectLater(
      remote.push(
        SyncMutation(
          mutationId: 'm',
          noteId: 'n',
          operation: SyncMutationOperation.update,
          baseRevision: 0,
          payload: const SyncNotePayload(
            title: 'T',
            content: 'B',
            includesLabels: true,
            labelMembership: LabelMembership.empty(),
          ),
        ),
      ),
      throwsA(isA<SyncFailure>()),
    );
  });
  test('scoped protected refresh retains authorized labels and keeps grant out of URL', () async {
    final remote = adapter(
      MockClient((r) async {
        expect(r.url.toString(), isNot(contains('transient-grant')));
        expect(
          (jsonDecode(r.body) as Map)['notes'][0]['grant'],
          'transient-grant',
        );
        return http.Response(
          jsonEncode({
            'wireVersion': 2,
            'items': [
              {'entityType': 'note', 'note': wireNote(protected: true)},
            ],
            'hasMore': false,
          }),
          200,
        );
      }),
      grant: (_) => 'transient-grant',
    );
    final notes = await remote.refreshLabels([localProtected()]);
    expect(notes.single.labelProjections.single.name, 'Label');
    expect(notes.single.contentAvailable, true);
  });
  test('local lock during HTTP rejects protected labels even when server responded', () async {
    var unlocked = true;
    final remote = adapter(
      MockClient((r) async {
        unlocked = false;
        return http.Response(
          jsonEncode({
            'wireVersion': 2,
            'items': [
              {'entityType': 'note', 'note': wireNote(protected: true)},
            ],
            'hasMore': false,
          }),
          200,
        );
      }),
      grant: (_) => unlocked ? 'transient' : null,
    );
    await expectLater(
      remote.refreshLabels([localProtected()]),
      throwsA(isA<SyncFailure>()),
    );
  });
}

LocalNoteState localProtected() => LocalNoteState(
  id: 'n',
  ownerId: 'owner',
  title: 'Authorized',
  content: 'Body',
  createdAt: DateTime.parse(timestamp),
  updatedAt: DateTime.parse(timestamp),
  protection: NoteProtection(enabled: true, revision: 1),
  labelIds: ['a'],
);
