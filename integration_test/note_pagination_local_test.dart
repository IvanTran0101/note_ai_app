import 'package:flutter/material.dart';

import 'support/note_pagination_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';
import 'package:note_ai_app/application/notes/note_page.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/presentation/labels/label_catalog_scope.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_page.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_controller.dart';

/// Real platform encryption/storage; only this synthetic account may be seeded.
const actor = paginationQaActor;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('1000 encrypted local notes: paging, global search and reopen', (
    tester,
  ) async {
    final fixture = await createPaginationFixture();
    final store = fixture.store;
    final repo = fixture.repository;
    final app = fixture.app;
    final labels = fixture.labels;
    // Cold adapter/page after cutover: no canonical read/decode is permitted.
    final cold =
        createLocalSyncStore(accountUserId: actor) as EncryptedSyncStore;
    final coldRepo = NoteRepository(
      currentAccountUserId: () => actor,
      localSyncStoreFactory: ({required accountUserId}) => cold,
      generateMutationId: () => 'unused',
      now: DateTime.now,
    );
    final lastPage = await coldRepo.queryNotePage(
      actor,
      NotePageQuery(page: 19),
    );
    expect(lastPage.total, 1000);
    expect(lastPage.notes, hasLength(50));
    expect(cold.codec.decodedAccountCount, 0);
    expect(cold.pagePayloadReads, 50);
    expect((await coldRepo.findById('qa-0000'))!.id, 'qa-0000');
    expect(cold.pagePayloadReads, 51);
    cold.dispose();
    (store as EncryptedSyncStore).codec.decodedAccountCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LabelCatalogHost(
          application: labels,
          securityChanges: const Stream.empty(),
          child: NotesWorkspacePage(
            controller: NoteApplicationServiceController(app),
          ),
        ),
      ),
    );
    Future<void> settleUntil(Finder finder) async {
      for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsOneWidget);
    }

    await settleUntil(find.text('1–50 / 1000'));
    expect(
      tester
          .widget<AnimatedNoteList>(find.byType(AnimatedNoteList))
          .notes
          .length,
      50,
    );
    await tester.tap(find.byKey(const ValueKey('notes-page-next')));
    await settleUntil(find.text('51–100 / 1000'));
    await tester.enterText(
      find.byKey(const ValueKey('notes-search-field')),
      'marker-999',
    );
    await settleUntil(find.text('1–1 / 1'));
    await settleUntil(find.text('QA note 999'));
    expect(
      tester
          .widget<AnimatedNoteList>(find.byType(AnimatedNoteList))
          .notes
          .single
          .id,
      'qa-0999',
    );
    expect(store.codec.decodedAccountCount, 0);
    final dashboard = DashboardController(
      query: GetDashboardOverview(
        noteRepository: repo,
        currentUser: app.currentUser,
      ),
    );
    addTearDown(dashboard.dispose);
    final key = GlobalKey<DashboardPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: LabelCatalogHost(
          application: labels,
          securityChanges: const Stream.empty(),
          child: DashboardPage(
            key: key,
            dashboardController: dashboard,
            notesController: NoteApplicationServiceController(app),
            onOpenNote: (_) async => null,
            onCreateNote: () async => null,
          ),
        ),
      ),
    );
    await settleUntil(find.text('1–50 / 1000'));
    await tester.tap(find.byKey(const ValueKey('notes-page-next')));
    await settleUntil(find.text('51–100 / 1000'));
    key.currentState!.openSearch();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('dashboard-search-field')),
      'marker-999',
    );
    await settleUntil(find.text('1–1 / 1'));
    expect(store.codec.decodedAccountCount, 0);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
