import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/labels/label_application.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_note_page_store.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart';

const paginationQaActor = 'pagination-local-qa-20261112';

final class PaginationFixture {
  PaginationFixture(this.store, this.repository, this.app, this.labels);
  final ILocalSyncStore store;
  final NoteRepository repository;
  final NoteApplicationService app;
  final LabelApplication labels;
}

Future<PaginationFixture> createPaginationFixture() async {
  final store = createLocalSyncStore(accountUserId: paginationQaActor);
  final date = DateTime.utc(2026, 11, 12);
  final count = store is ILocalNotePageStore
      ? await (store as ILocalNotePageStore).withNotePageView(
          (view) async => view.headers.length,
        )
      : (await store.read()).notes.length;
  if (count == 0) {
    await store.replace(
      LocalSyncState(
        accountUserId: paginationQaActor,
        syncWireVersion: 3,
        notes: _syntheticRows(date),
      ),
    );
  }
  final repository = NoteRepository(
    currentAccountUserId: () => paginationQaActor,
    localSyncStoreFactory: ({required accountUserId}) => store,
    generateMutationId: () => 'unused-pagination-fixture',
    now: () => date,
  );
  final app = NoteApplicationService(
    noteRepository: repository,
    currentUser: StaticCurrentUser(
      identity: AuthIdentity(
        userId: paginationQaActor,
        email: 'pagination@example.invalid',
        isEmailVerified: true,
      ),
    ),
    generateId: () => 'unused-pagination-note',
    now: () => date,
    summarizeContent: (_) async => const Summary('Unused synthetic summary'),
  );
  final labels = LabelApplication(
    currentActor: () => paginationQaActor,
    generation: () => 0,
    storeFor: (_) => store,
    notes: repository,
    generateId: () => 'unused-pagination-label',
    now: () => date,
    requestSync: (_) {},
  );
  return PaginationFixture(store, repository, app, labels);
}

List<LocalNoteState> _syntheticRows(DateTime date) => List.generate(
  1000,
  (i) => LocalNoteState(
    id: 'qa-${i.toString().padLeft(4, '0')}',
    ownerId: paginationQaActor,
    title: 'QA note $i',
    content: 'Synthetic body marker-$i',
    createdAt: date,
    updatedAt: date,
  ),
);
