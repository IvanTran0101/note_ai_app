import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/notes/note_page.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';

import 'note_repository_test_support.dart';

void main() {
  final date = DateTime.utc(2026, 11, 12);

  test(
    'session switch while a page read is pending rejects late content',
    () async {
      var generation = 0;
      final store = FakeLocalSyncStore(
        accountUserId: 'user-1',
        initial: LocalSyncState(
          accountUserId: 'user-1',
          notes: [testLocalNote(id: 'one')],
        ),
      );
      store.readGate = Completer<void>();
      final repo = NoteRepository(
        currentAccountUserId: () => 'user-1',
        sessionGeneration: () => generation,
        localSyncStoreFactory: ({required accountUserId}) => store,
        generateMutationId: () => 'unused',
        now: () => date,
      );
      final pending = repo.queryNotePage('user-1', NotePageQuery());
      final assertion = expectLater(pending, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      generation++;
      store.readGate!.complete();
      await assertion;
    },
  );
  LocalNoteState row(
    int i, {
    bool protected = false,
    bool deleted = false,
    DateTime? pinnedAt,
    List<String> labelIds = const [],
  }) => LocalNoteState(
    id: 'n${i.toString().padLeft(4, '0')}',
    ownerId: 'user-1',
    title: 'Note $i',
    content: 'Body marker-$i',
    createdAt: date,
    updatedAt: date,
    pinnedAt: pinnedAt,
    labelIds: labelIds,
    deletedAt: deleted ? date : null,
    protection: protected
        ? NoteProtection(enabled: true, revision: 1)
        : const NoteProtection.unprotected(),
  );
  NoteRepository repository(LocalSyncState state) => NoteRepository(
    currentAccountUserId: () => 'user-1',
    localSyncStoreFactory: FakeLocalSyncStoreFactory(
      initialStates: {'user-1': state},
    ).create,
    generateMutationId: () => 'unused',
    now: () => date,
  );

  test('shared scope excludes revoked rows and owner/name collisions stay isolated', () async {
    LocalNoteState shared(String owner, {bool revoked = false}) =>
        LocalNoteState(
          id: 'same-id',
          ownerId: owner,
          title: revoked ? '' : owner,
          contentAvailable: !revoked,
          content: revoked ? '' : 'shared body',
          createdAt: date,
          updatedAt: date,
          share: NoteShareGrant(
            note: NoteIdentity(owner, 'same-id'),
            recipientId: 'user-1',
            role: NoteRole.viewer,
            sharedAt: date,
            updatedAt: date,
            accessRevision: 1,
            status: revoked ? NoteShareStatus.revoked : NoteShareStatus.active,
            revokedAt: revoked ? date : null,
          ),
        );
    final repo = repository(
      LocalSyncState(
        accountUserId: 'user-1',
        notes: [
          row(1),
          shared('owner-a'),
          shared('owner-b'),
          shared('owner-c', revoked: true),
        ],
      ),
    );
    final page = await repo.queryNotePage(
      'user-1',
      NotePageQuery(scope: NotePageScope.shared),
    );
    expect(page.total, 2);
    expect(page.notes.map((n) => n.ownerId), ['owner-a', 'owner-b']);
    expect(page.notes.map((n) => n.reference).toSet().length, 2);
    expect(
      (await repo.queryNotePage(
        'user-1',
        NotePageQuery(),
      )).notes.single.ownerId,
      'user-1',
    );
  });

  test(
    '1000 notes: 20 bounded pages, deterministic tie order, no gaps/duplicates',
    () async {
      final repo = repository(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: List.generate(1000, row).reversed,
        ),
      );
      final ids = <String>[];
      for (var page = 0; page < 20; page++) {
        final result = await repo.queryNotePage(
          'user-1',
          NotePageQuery(page: page),
        );
        expect(result.total, 1000);
        expect(result.notes.length, 50);
        expect(result.hasNext, page < 19);
        ids.addAll(result.notes.map((n) => n.id));
      }
      expect(ids.toSet().length, 1000);
      expect(ids.first, 'n0000');
      expect(ids.last, 'n0999');
    },
  );

  test(
    'search and label filter run before page cut; facets span all pages',
    () async {
      final repo = repository(
        LocalSyncState(
          accountUserId: 'user-1',
          labels: [
            LocalLabelState(
              id: 'l1',
              ownerId: 'user-1',
              name: 'Deep',
              createdAt: date,
              updatedAt: date,
            ),
          ],
          notes: [
            for (var i = 0; i < 1000; i++)
              row(i, labelIds: i == 999 ? ['l1'] : []),
          ],
        ),
      );
      final first = await repo.queryNotePage('user-1', NotePageQuery());
      expect(first.labelChoices[(ownerId: 'user-1', id: 'l1')], 'Deep');
      final search = await repo.queryNotePage(
        'user-1',
        NotePageQuery(keyword: 'marker-999'),
      );
      expect(search.notes.single.id, 'n0999');
      final filtered = await repo.queryNotePage(
        'user-1',
        NotePageQuery(labels: {(ownerId: 'user-1', id: 'l1')}),
      );
      expect(filtered.notes.single.id, 'n0999');
    },
  );

  test(
    'protected rows are masked and cannot leak via search or label facets',
    () async {
      final repo = repository(
        LocalSyncState(
          accountUserId: 'user-1',
          labels: [
            LocalLabelState(
              id: 'secret',
              ownerId: 'user-1',
              name: 'Secret',
              createdAt: date,
              updatedAt: date,
            ),
          ],
          notes: [
            row(1, protected: true, labelIds: ['secret']),
            row(2, deleted: true),
          ],
        ),
      );
      final page = await repo.queryNotePage('user-1', NotePageQuery());
      expect(page.total, 1);
      expect(page.notes.single.contentAvailable, false);
      expect(page.notes.single.title, '');
      expect(page.notes.single.document, isNull);
      expect(page.labelChoices, isEmpty);
      expect(
        (await repo.queryNotePage(
          'user-1',
          NotePageQuery(keyword: 'marker-1'),
        )).total,
        0,
      );
      expect(
        (await repo.queryNotePage(
          'user-1',
          NotePageQuery(scope: NotePageScope.shared),
        )).total,
        0,
      );
      await expectLater(
        repo.queryNotePage('other', NotePageQuery()),
        throwsA(anything),
      );
    },
  );

  test(
    'pin precedes date; out-of-range and empty pages clamp safely',
    () async {
      final repo = repository(
        LocalSyncState(
          accountUserId: 'user-1',
          notes: [
            row(1),
            row(999, pinnedAt: date),
          ],
        ),
      );
      expect(
        (await repo.queryNotePage('user-1', NotePageQuery())).notes.first.id,
        'n0999',
      );
      final last = await repo.queryNotePage(
        'user-1',
        NotePageQuery(page: 99, size: 1),
      );
      expect(last.page, 1);
      expect(last.notes.single.id, 'n0001');
      final empty = await repo.queryNotePage(
        'user-1',
        NotePageQuery(page: 99, keyword: 'absent'),
      );
      expect([empty.page, empty.start, empty.end, empty.total], [0, 0, 0, 0]);
      expect(() => NotePageQuery(size: 101), throwsArgumentError);
      expect(() => NotePageQuery(page: -1), throwsArgumentError);
    },
  );
}
