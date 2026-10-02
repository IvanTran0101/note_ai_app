import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_editor_snapshot.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart' as domain;
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';

import 'm06_application_test.dart' as f;

void main() {
  test('atomic editor save queues both fields in one local mutation', () async {
    final h = f.harness();
    final before = (await h.app.listSharedNotes()).single;
    final saved = await h.app.saveEditorSnapshot(
      before,
      'new title',
      'new body',
    );
    expect(saved.title, 'new title');
    expect(saved.content, 'new body');
    expect(h.store.state.outbox.length, 1);
    expect(h.store.state.outbox.single.ownerId, 'owner');
    expect(h.store.state.outbox.single.baseRevision, 7);
  });
  test('editor use case preserves draft and refuses silently rebasing stale snapshot', () async {
    final h = f.harness();
    final before = (await h.app.listSharedNotes()).single;
    await h.app.replaceContent(
      noteId: before.reference,
      content: 'other device',
    );
    await expectLater(
      h.app.saveEditorSnapshot(before, 'draft', 'draft body'),
      throwsA(
        isA<NoteEditorChanged>().having(
          (e) => e.current.content,
          'fresh',
          'other device',
        ),
      ),
    );
    expect(h.store.state.outbox.single.payload!.content, 'other device');
  });
  test(
    'atomic repository compare refuses a concurrent local writer too',
    () async {
      final h = f.harness();
      final expected = (await h.repo.findSharedWith('actor')).single;
      final changed = Note.reconstitute(
        id: expected.id,
        ownerId: expected.ownerId,
        title: 'stale title',
        content: 'stale body',
        createdAt: expected.createdAt,
        updatedAt: expected.updatedAt,
        contentRevision: expected.contentRevision,
        share: expected.share,
      );
      await h.app.replaceContent(
        noteId: expected.reference,
        content: 'local concurrent',
      );
      await expectLater(
        h.repo.saveSnapshot(changed, expected),
        throwsA(isA<domain.NoteSnapshotChanged>()),
      );
      expect(h.store.state.notes.last.content, 'local concurrent');
    },
  );
  testWidgets(
    'automatic refresh keeps dirty editor and offers explicit cloud/local review',
    (tester) async {
      final h = f.harness();
      final key = GlobalKey<NotesWorkspacePageState>();
      tester.testTextInput.register();
      await tester.pumpWidget(
        MaterialApp(
          home: NotesWorkspacePage(
            key: key,
            controller: NoteApplicationServiceController(h.app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shared-notes-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shared title'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(NoteDetailPage.contentFieldKey),
        'unsaved editor body',
      );
      final old = h.store.state.notes.last;
      await h.store.replace(
        LocalSyncState(
          accountUserId: 'actor',
          notes: [
            f.owned(),
            LocalNoteState(
              id: old.id,
              ownerId: old.ownerId,
              share: old.share,
              title: old.title,
              content: 'remote fresh body',
              createdAt: old.createdAt,
              updatedAt: old.updatedAt.add(const Duration(seconds: 1)),
              serverRevision: 8,
            ),
          ],
        ),
      );
      await key.currentState!.reload();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
            .controller!
            .text,
        'unsaved editor body',
      );
      expect(
        find.byKey(const ValueKey('editor-remote-change')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(h.store.state.outbox, isEmpty);
      await tester.tap(find.byKey(const ValueKey('editor-use-cloud')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
            .controller!
            .text,
        'remote fresh body',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
