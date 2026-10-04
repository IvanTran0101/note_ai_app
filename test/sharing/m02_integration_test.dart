import '../support/legacy_label_fields.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_editor_snapshot.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_codec_exception.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_state_codec.dart';
import 'package:note_ai_app/infrastructure/sync/sync_http_mapper.dart';

import 'm06_application_test.dart' as f;

void main() {
  test('M02 legacy save cannot bypass shared owner-only pin policy', () async {
    final h = f.harness();
    final note = (await h.repo.findSharedWith('actor')).single;
    note.pin(f.at);
    await expectLater(h.repo.save(note), throwsA(isA<NoteSecurityFailure>()));
    expect(h.store.state.notes.last.pinnedAt, isNull);
    expect(h.store.state.outbox, isEmpty);
  });

  test('v3 malformed migration records fail with a safe codec error', () {
    for (final field in ['notes', 'conflicts']) {
      final old = LocalSyncStateCodec.encode(f.harness().store.state);
      old['schemaVersion'] = 3;
      stripM04Fields(old);
      old[field] = 'private corrupt content';
      expect(
        () => LocalSyncStateCodec.decode(old),
        throwsA(isA<LocalSyncCodecException>()),
      );
    }
  });
  test(
    'M02 editor atomic mutation preserves owner pin and canonical sharing',
    () async {
      final h = f.harness();
      final original = h.store.state.notes.last;
      final state = LocalSyncStateCodec.encode(h.store.state);
      (state['notes'] as List).last['pinnedAt'] = f.at.toIso8601String();
      await h.store.replace(LocalSyncStateCodec.decode(state));
      final selected = (await h.app.listSharedNotes()).single;
      final saved = await h.app.saveEditorSnapshot(
        selected,
        'Changed title',
        'Changed body',
      );
      expect(saved.pinnedAt, f.at);
      expect(saved.share, original.share);
      final request = h.store.state.outbox.single.mutation;
      expect(request.ownerId, 'owner');
      expect(request.payload!.includesPinnedAt, false);
      expect(
        encodeSyncMutation(request)['payload'],
        isNot(contains('pinnedAt')),
      );
      await expectLater(
        h.app.setPinned(noteId: saved.reference, pinned: false),
        throwsA(isA<NoteOwnershipException>()),
      );
    },
  );

  test(
    'M02 stale editor snapshot includes pin even when text did not change',
    () async {
      final h = f.harness();
      final selected = (await h.app.listNotes()).single;
      await h.app.setPinned(noteId: selected.reference, pinned: true);
      await expectLater(
        h.app.saveEditorSnapshot(selected, 'Draft title', 'Draft body'),
        throwsA(isA<NoteEditorChanged>()),
      );
      expect(h.store.state.notes.first.title, 'Owned title');
    },
  );

  test('M02 same-user new-session fence aborts before local commit', () async {
    final h = f.harness();
    final generation = h.session.sessionGeneration;
    await expectLater(
      h.repo.updateById(
        noteId: 'same',
        ownerId: 'actor',
        expectedAccountUserId: 'actor',
        canCommit: () => h.session.sessionGeneration == generation,
        change: (fresh) {
          fresh.replaceText('Cancelled title', 'Cancelled body', f.at);
          final identity = h.session.identity!;
          h.session.clear();
          h.session.setIdentity(identity);
          return fresh;
        },
      ),
      throwsA(isA<NoteMutationCancelledException>()),
    );
    expect(h.store.state.notes.first.title, 'Owned title');
    expect(h.store.state.outbox, isEmpty);
  });

  test('M02 no-op pin does not enqueue or request redundant sync', () async {
    final h = f.harness();
    await h.app.setPinned(noteId: 'same', pinned: true);
    final once = h.store.state;
    await h.app.setPinned(noteId: 'same', pinned: true);
    expect(h.store.state, once);
  });

  test(
    'M05 v3 migration preserves pin-compatible payload bytes and sharing',
    () {
      final h = f.harness();
      final old = LocalSyncStateCodec.encode(h.store.state);
      old['schemaVersion'] = 3;
      stripM04Fields(old);
      old.remove('userPreferences');
      for (final note in old['notes'] as List) {
        note.remove('pinnedAt');
        note.remove('attachments');
      }
      final decoded = LocalSyncStateCodec.decode(old);
      expect(decoded.notes.last.share, h.store.state.notes.last.share);
      expect(decoded.notes.last.serverRevision, 7);
      expect(decoded.userPreferences.userId, 'actor');
      expect(LocalSyncStateCodec.encode(decoded)['schemaVersion'], 6);
    },
  );

  test('TanMinh v3 migration preserves pin and account layout', () {
    final h = f.harness();
    final old = jsonDecode(
      jsonEncode(LocalSyncStateCodec.encode(h.store.state)),
    ) as Map<String, dynamic>;
    old['schemaVersion'] = 3;
    stripM04Fields(old);
    old['notes'] = [(old['notes'] as List).first];
    for (final note in old['notes'] as List) {
      note.remove('attachments');
      note.remove('protected');
      note.remove('protectionRevision');
      note.remove('contentAvailable');
      note['pinnedAt'] = f.at.toIso8601String();
    }
    old['userPreferences']['noteLayout'] = 'list';
    final decoded = LocalSyncStateCodec.decode(old);
    expect(decoded.notes.single.pinnedAt, f.at);
    expect(decoded.userPreferences.noteLayout, NoteLayoutPreference.list);
    expect(decoded.notes.single.protection.enabled, false);
  });
}
