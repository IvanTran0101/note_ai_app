import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_cursor.dart';
import 'package:note_ai_app/application/sync/sync_mutation.dart';
import 'package:note_ai_app/application/sync/sync_snapshot.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';

import '../../domain/notes/m09_document_fixtures.dart' as model;

final at = model.at;
NoteDocument doc({bool bold = false}) => NoteDocument([
  DocumentBlock(
    id: 'p',
    kind: DocumentBlockKind.paragraph,
    runs: [
      DocumentText(
        'private rich Việt 📝',
        marks: DocumentMarks(bold: bold, fontSize: 24),
      ),
      DocumentMath(r'\sqrt{x^2+1}'),
    ],
    children: [model.block('nested', text: 'nested body')],
  ),
  model.table('table'),
]);
Attachment get attachment => Attachment(
  id: 'file',
  noteId: 'n',
  fileName: 'synthetic.txt',
  mimeType: 'text/plain',
  sizeBytes: 4,
  storageObjectId: 'object',
  objectVersion: 'v1',
  sha256: 'a' * 64,
  addedAt: at,
);
NoteShareGrant grant({
  NoteRole role = NoteRole.editor,
  int revision = 1,
  NoteShareStatus status = NoteShareStatus.active,
}) => NoteShareGrant(
  note: NoteIdentity('owner', 'n'),
  recipientId: 'actor',
  role: role,
  accessRevision: revision,
  sharedAt: at,
  updatedAt: at,
  status: status,
  revokedAt: status == NoteShareStatus.revoked ? at : null,
);
LocalNoteState note({
  bool rich = true,
  NoteShareGrant? share,
  NoteProtection protection = const NoteProtection.unprotected(),
}) => LocalNoteState(
  id: 'n',
  ownerId: 'owner',
  title: 'Title',
  content: doc().plainText,
  document: rich ? doc() : null,
  createdAt: at,
  updatedAt: at,
  serverRevision: 7,
  pinnedAt: at,
  labelIds: ['label'],
  attachments: [attachment],
  share: share,
  protection: protection,
);
PendingMutation pending({
  bool rich = true,
  int retryCount = 0,
  NoteShareGrant? share,
}) => PendingMutation(
  mutationId: 'attempt',
  noteId: 'n',
  operation: SyncMutationOperation.update,
  baseRevision: 7,
  createdAt: at,
  retryCount: retryCount,
  ownerId: share == null ? null : 'owner',
  accessRevision: share?.accessRevision,
  payload: SyncNotePayload(
    title: 'Title',
    content: doc().plainText,
    document: rich ? doc() : null,
    includesDocument: rich,
  ),
);
LocalSyncState state({
  bool rich = true,
  bool queued = false,
  int retryCount = 0,
  NoteShareGrant? share,
}) => LocalSyncState(
  accountUserId: share == null ? 'owner' : 'actor',
  notes: [note(rich: rich, share: share)],
  outbox: queued
      ? [pending(rich: rich, retryCount: retryCount, share: share)]
      : [],
  labels: share == null
      ? [
          LocalLabelState(
            id: 'label',
            ownerId: 'owner',
            name: 'Synthetic label',
            createdAt: at,
            updatedAt: at,
          ),
        ]
      : [],
  cursor: const SyncCursor('cursor'),
);
SyncNoteSnapshot snapshot({
  NoteDocument? document,
  bool typed = true,
  bool available = true,
  NoteShareGrant? share,
  int revision = 8,
  bool deleted = false,
}) => SyncNoteSnapshot(
  id: 'n',
  ownerId: 'owner',
  title: available ? 'Title' : '',
  content: available ? (document ?? doc()).plainText : '',
  document: available && !deleted ? document : null,
  includesDocument: typed,
  createdAt: at,
  serverUpdatedAt: at,
  revision: revision,
  pinnedAt: at,
  attachments: available && !deleted ? [attachment] : [],
  includesAttachments: true,
  labelIds: available && !deleted ? ['label'] : [],
  includesLabels: true,
  contentAvailable: available,
  share: share,
  deletedAt: deleted ? at : null,
);
NoteApplicationService app(EncryptedSyncStore store, {List<String>? syncs}) {
  final session = CurrentUserSession()
    ..setIdentity(
      AuthIdentity(
        userId: 'owner',
        email: 'owner@example.invalid',
        isEmailVerified: true,
      ),
    );
  var next = 0;
  return NoteApplicationService(
    noteRepository: NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'new-${++next}',
      now: () => at,
      labelsEnabled: true,
    ),
    currentUser: session,
    generateId: () => 'new-note',
    now: () => at.add(const Duration(seconds: 1)),
    summarizeContent: (_) async => const Summary('synthetic'),
    requestSync: syncs?.add,
  );
}
