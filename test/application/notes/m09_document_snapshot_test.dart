import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_editor_snapshot.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';

import 'm09_document_snapshot_fixtures.dart' as f;

void main() {
  test('a text-only writer cannot silently drop the new document', () async {
    final h = f.harness(documentsSupported: false);
    final selected = await h.app.readNote('n');
    await expectLater(
      h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
      throwsA(isA<NoteDocumentStorageUnavailable>()),
    );
    expect(h.repo.note.document, f.document());
    expect(h.repo.writes, 0);
    expect(h.syncs, isEmpty);
  });
  test(
    'format-only snapshot uses one guarded writer and requests sync after it',
    () async {
      final h = f.harness();
      final selected = await h.app.readNote('n');
      final saved = await h.app.saveDocumentSnapshot(
        selected,
        'Title',
        f.document(bold: true),
      );
      expect(saved.content, selected.content);
      expect(saved.document, f.document(bold: true));
      expect(saved.pinnedAt, selected.pinnedAt);
      expect(saved.labelIds, selected.labelIds);
      expect(h.repo.writes, 1);
      expect(h.syncs, ['owner']);
    },
  );
  test('equal document is no-op', () async {
    final h = f.harness();
    final selected = await h.app.readNote('n');
    final saved = await h.app.saveDocumentSnapshot(
      selected,
      selected.title,
      f.document(),
    );
    expect(saved, selected);
    expect(h.repo.writes, 0);
    expect(h.syncs, isEmpty);
  });
  test(
    'same-text/time format drift invalidates the selected snapshot',
    () async {
      final h = f.harness();
      final selected = await h.app.readNote('n');
      h.repo.note.replaceDocument('Title', f.document(bold: true), f.at);
      await expectLater(
        h.app.saveDocumentSnapshot(selected, 'Draft', f.document()),
        throwsA(
          isA<NoteEditorChanged>().having(
            (error) => error.current.document,
            'current document',
            f.document(bold: true),
          ),
        ),
      );
      expect(h.repo.writes, 0);
      expect(h.syncs, isEmpty);
    },
  );
  test('Viewer cannot save a document', () async {
    final h = f.harness(role: NoteRole.viewer);
    final selected = await h.app.readNote('n');
    await expectLater(
      h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
      throwsA(isA<NoteOwnershipException>()),
    );
    expect(h.repo.writes, 0);
  });
  test('Editor retains canonical owner when saving a document', () async {
    final h = f.harness(role: NoteRole.editor);
    final selected = await h.app.readNote('n');
    final saved = await h.app.saveDocumentSnapshot(
      selected,
      'Title',
      f.document(bold: true),
    );
    expect(saved.ownerId, 'owner');
    expect(saved.share, selected.share);
    expect(h.syncs, ['actor']);
  });
  test('lock before save refuses the snapshot', () async {
    final h = f.harness();
    final selected = await h.app.readNote('n');
    h.guard.denied = true;
    h.guard.generation++;
    await expectLater(
      h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
      throwsA(
        isA<NoteSecurityFailure>().having(
          (error) => error.code,
          'failure',
          NoteSecurityFailureCode.locked,
        ),
      ),
    );
    expect(h.repo.writes, 0);
  });
  test('session change at commit leaves the original document', () async {
    final h = f.harness();
    final selected = await h.app.readNote('n');
    h.repo.beforeCommit = () => h.session.setIdentity(f.identity('other'));
    await expectLater(
      h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
      throwsA(isA<NoteMutationCancelledException>()),
    );
    expect(h.repo.note.document, f.document());
    expect(h.repo.writes, 0);
    expect(h.syncs, isEmpty);
  });
  test(
    'access generation change at commit leaves the original document',
    () async {
      final h = f.harness();
      final selected = await h.app.readNote('n');
      h.repo.beforeCommit = () {
        h.guard.generation++;
        h.guard.denied = true;
      };
      await expectLater(
        h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
        throwsA(isA<NoteMutationCancelledException>()),
      );
      expect(h.repo.note.document, f.document());
      expect(h.repo.writes, 0);
    },
  );
  test('metadata-only editor snapshot cannot overwrite content', () async {
    final h = f.harness();
    final selected = (await h.app.readNote('n')).metadataOnly();
    await expectLater(
      h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
      throwsA(isA<NoteEditorChanged>()),
    );
    expect(selected.document, isNull);
    expect(h.repo.writes, 0);
  });
  test('storage failure neither replaces document nor requests sync', () async {
    final h = f.harness();
    final selected = await h.app.readNote('n');
    h.repo.storageFailure = StateError('synthetic storage failure');
    await expectLater(
      h.app.saveDocumentSnapshot(selected, 'Title', f.document(bold: true)),
      throwsStateError,
    );
    expect(h.repo.note.document, f.document());
    expect(h.repo.writes, 0);
    expect(h.syncs, isEmpty);
  });
}
