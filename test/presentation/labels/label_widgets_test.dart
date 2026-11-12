import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/label_application.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/presentation/labels/label_catalog_scope.dart';
import 'package:note_ai_app/presentation/labels/label_filter_bar.dart';
import 'package:note_ai_app/presentation/labels/note_label_editor.dart';
import 'package:note_ai_app/presentation/notes/notes_list_panel.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

void main() {
  late FakeLocalSyncStore store;
  late LabelApplication app;
  late NoteRepository notes;
  late String actor;
  late int epoch, sequence;
  final time = DateTime.utc(2026, 10, 4);
  void setup() {
    actor = 'owner';
    epoch = 1;
    sequence = 0;
    store = FakeLocalSyncStore(accountUserId: actor);
    notes = NoteRepository(
      labelsEnabled: true,
      currentAccountUserId: () => actor,
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'm${++sequence}',
      now: () => time,
      sessionGeneration: () => epoch,
    );
    app = LabelApplication(
      currentActor: () => actor,
      generation: () => epoch,
      storeFor: (_) => store,
      notes: notes,
      generateId: () => 'id${++sequence}',
      now: () => time,
      requestSync: (_) {},
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, c) => LabelCatalogHost(
          application: app,
          securityChanges: const Stream.empty(),
          child: c!,
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Widget filters() => LabelFilterBar(
    notes: const [],
    selected: const {},
    readable: (_) => true,
    onChanged: (_) {},
  );

  testWidgets('query empty state and actor change clear private selections', (
    tester,
  ) async {
    setup();
    final semantics = tester.ensureSemantics();
    final note = NoteDto.fromDomain(
      Note.create(
        id: 'query-note',
        ownerId: actor,
        title: 'Query title',
        content: 'Loaded body',
        now: time,
      ),
    );
    await app.create('Private owner filter');
    await pump(
      tester,
      NotesListPanel(
        notes: [note],
        selectedNoteId: null,
        error: null,
        actionBusy: false,
        onNewNote: () {},
        onSelectNote: (_) {},
        onRetry: null,
      ),
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('notes-search-field')))
          .rect
          .height,
      lessThan(100),
    );
    await tester.enterText(
      find.byKey(const ValueKey('notes-search-field')),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching notes.'), findsOneWidget);
    expect(find.text('Create your first note'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('notes-search-field')),
      'loaded',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching notes.'), findsNothing);
    await tester.tap(find.text('Private owner filter'));
    await tester.pumpAndSettle();
    expect(find.text('No matching notes.'), findsOneWidget);
    actor = 'recipient';
    epoch++;
    app.notifyChanged();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('notes-search-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('No matching notes.'), findsNothing);
    expect(find.text('Private owner filter'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'catalog create duplicate/rename/delete refresh without Note cascade',
    (tester) async {
      setup();
      await pump(tester, filters());
      await tester.tap(find.text('Manage labels'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      Future<void> create() async {
        await tester.tap(find.text('Add label'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Study');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      }

      await create();
      await create();
      expect((await app.list()).length, 2);
      expect((await app.list()).map((l) => l.id).toSet().length, 2);
      await tester.tap(find.byTooltip('Rename label').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Renamed');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed'), findsWidgets);
      await tester.tap(find.byTooltip('Delete label').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete label').last);
      await tester.pumpAndSettle();
      expect((await app.list()).where((l) => l.isDeleted).length, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'old dialog intent cannot create a label in a new actor/session',
    (tester) async {
      setup();
      await pump(tester, filters());
      await tester.tap(find.text('Manage labels'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add label'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Private old intent');
      actor = 'other';
      epoch++;
      app.notifyChanged();
      await tester.pumpAndSettle();
      expect(find.text('Private old intent'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect((await store.read()).labels, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'owner attach/detach persists IDs and reactive chip; editor recipient has no organize',
    (tester) async {
      setup();
      final label = await app.create('Study');
      final n = Note.create(
        id: 'n',
        ownerId: actor,
        title: 'Draft base',
        content: 'Body',
        now: time,
      );
      await notes.save(n);
      var projection = NoteDto.fromDomain(n);
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, refresh) => NoteLabelEditor(
            note: projection,
            readable: true,
            canManage: true,
            onChanged: (next) => refresh(() => projection = next),
          ),
        ),
      );
      Future<void> choose() async {
        await tester.tap(find.text('Choose note labels'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(projection.labelIds, [label.id]);
      expect(find.byType(Chip), findsOneWidget);
      await choose();
      expect(projection.labelIds, isEmpty);
      expect(find.byType(Chip), findsNothing);
      actor = 'recipient';
      epoch++;
      app.notifyChanged();
      await tester.pumpAndSettle();
      expect(find.text('Choose note labels'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
