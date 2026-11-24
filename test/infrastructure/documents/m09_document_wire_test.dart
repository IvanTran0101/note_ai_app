import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/infrastructure/documents/note_document_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import 'm09_storage_fixtures.dart' as fixture;

Map<String, Object?> wireNote({bool rich = true}) => {
  'id': 'n',
  'title': 'Title',
  'content': fixture.doc().plainText,
  'createdAt': fixture.at.toIso8601String(),
  'serverUpdatedAt': fixture.at.toIso8601String(),
  'revision': 8,
  'pinnedAt': fixture.at.toIso8601String(),
  'deletedAt': null,
  'attachments': [],
  'labelIds': [],
  'labelProjections': [],
  if (rich) 'document': NoteDocumentCodec.encode(fixture.doc()),
};
Map<String, Object?> wirePage(List<Object?> items) => {
  'wireVersion': 3,
  'documentCapability': 'basicBlocksV1',
  'items': items,
  'nextCursor': 'next',
  'hasMore': false,
};

void main() {
  test('V3 owned/shared routes retain canonical document and metadata', () {
    for (final share in [null, fixture.grant()]) {
      final mutation = fixture.pending(share: share).toMutation();
      final encoded = encodeSyncMutation(mutation);
      expect(encoded['wireVersion'], 3);
      expect(encoded['documentCapability'], 'basicBlocksV1');
      expect(
        (encoded['payload'] as Map)['document'],
        NoteDocumentCodec.encode(fixture.doc()),
      );
      expect(
        syncMutationPath(mutation),
        share == null ? 'sync/v3/mutations' : 'sync/v3/shared-mutations',
      );
      expect(encoded['ownerId'], share == null ? null : 'owner');
      expect(encoded['accessRevision'], share?.accessRevision);
    }
  });

  test(
    'V3 applied/conflict/page responses retain document1; plain V2 omits it',
    () {
      final note = wireNote();
      final applied = decodeSyncMutationResponse(
        statusCode: 200,
        body: {
          'wireVersion': 3,
          'documentCapability': 'basicBlocksV1',
          'entityType': 'note',
          'mutationId': 'attempt',
          'status': 'applied',
          'note': note,
        },
      );
      expect(applied.note!.document, fixture.doc());
      final conflict = decodeSyncMutationResponse(
        statusCode: 409,
        body: {
          'wireVersion': 3,
          'documentCapability': 'basicBlocksV1',
          'mutationId': 'attempt',
          'remoteNote': note,
        },
      );
      expect(conflict.conflictRemote!.document, fixture.doc());
      final page = decodeChangesPage(
        wirePage([
          {'entityType': 'note', 'note': note},
        ]),
      );
      expect(page.wireVersion, 3);
      expect(page.snapshots.single.document, fixture.doc());
      expect(page.nextCursor, 'next');
      final legacy = decodeChangesPage({
        'wireVersion': 2,
        'items': [
          {'entityType': 'note', 'note': wireNote(rich: false)},
        ],
      });
      expect(legacy.snapshots.single.includesDocument, false);
      expect(legacy.snapshots.single.document, null);
    },
  );

  test('V3 requires capability, typed presence and exact plain projection', () {
    for (final invalid in [
      {...wirePage([]), 'documentCapability': 'another'},
      wirePage([
        {'entityType': 'note', 'note': wireNote(rich: false)},
      ]),
      wirePage([
        {
          'entityType': 'note',
          'note': {...wireNote(), 'content': 'wrong'},
        },
      ]),
      wirePage([
        {
          'entityType': 'note',
          'note': {
            ...wireNote(),
            'document': {'version': 99, 'blocks': []},
          },
        },
      ]),
    ]) {
      expect(() => decodeChangesPage(invalid), throwsFormatException);
    }
    final empty = {
      ...wireNote(),
      'document': {'version': 1, 'blocks': []},
      'content': '',
    };
    expect(
      decodeChangesPage(
        wirePage([
          {'entityType': 'note', 'note': empty},
        ]),
      ).snapshots.single.document!.blocks,
      isEmpty,
    );
  });

  test('protected metadata never accepts a non-null document without read authority', () {
    final protected = {
      ...wireNote(),
      'protected': true,
      'protectionRevision': 1,
      'contentAvailable': true,
      'ownerId': 'owner',
    };
    expect(
      () => decodeSyncNoteSnapshot(protected, documents: true),
      throwsFormatException,
    );
    final hidden = {...protected, 'document': null, 'contentAvailable': false}
      ..remove('title')
      ..remove('content');
    final metadata = decodeSyncNoteSnapshot(hidden, documents: true);
    expect(metadata.document, null);
    expect(metadata.contentAvailable, false);
    expect(metadata.content, isEmpty);
    expect(
      decodeSyncNoteSnapshot(
        protected,
        documents: true,
        authorizedContent: true,
      ).document,
      fixture.doc(),
    );
  });

  test('explicit null preserves typed legacy presence; tombstone rejects leaked document', () {
    final plain = {...wireNote(rich: false), 'document': null};
    expect(
      decodeSyncNoteSnapshot(plain, documents: true).includesDocument,
      true,
    );
    expect(
      () => decodeSyncNoteSnapshot({
        ...wireNote(),
        'deletedAt': fixture.at.toIso8601String(),
      }, documents: true),
      throwsFormatException,
    );
    expect(
      decodeSyncNoteSnapshot({
        ...plain,
        'deletedAt': fixture.at.toIso8601String(),
      }, documents: true).document,
      null,
    );
  });

  test(
    'upgrade envelope overrides generic422 without exposing provider text',
    () {
      final failure = decodeError(
        statusCode: 422,
        body: {
          'code': 'DOCUMENT_REQUIRES_UPGRADE',
          'message': 'private token/body',
        },
      );
      expect(failure.code, SyncErrorCode.documentRequiresUpgrade);
      expect(failure.retryable, false);
      expect(failure.detail, null);
      expect(failure.toString(), isNot(contains('private')));
    },
  );

  test('format-only changes alter canonical document while derived text stays identical', () {
    final old = encodeSyncMutation(fixture.pending().toMutation());
    final formatted = encodeSyncMutation(
      SyncMutation(
        mutationId: 'format',
        noteId: 'n',
        operation: SyncMutationOperation.update,
        baseRevision: 7,
        payload: SyncNotePayload(
          title: 'Title',
          content: fixture.doc().plainText,
          document: fixture.doc(bold: true),
          includesDocument: true,
        ),
      ),
    );
    expect(
      (formatted['payload'] as Map)['content'],
      (old['payload'] as Map)['content'],
    );
    expect(
      (formatted['payload'] as Map)['document'],
      isNot((old['payload'] as Map)['document']),
    );
  });
}
