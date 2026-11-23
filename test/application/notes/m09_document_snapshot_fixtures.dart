import 'dart:async';

import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';

final at = DateTime.utc(2026, 10, 14);
NoteDocument document({bool bold = false}) => NoteDocument([
  DocumentBlock(
    id: 'p',
    kind: DocumentBlockKind.paragraph,
    runs: [DocumentText('same 📝', marks: DocumentMarks(bold: bold))],
  ),
]);

({
  NoteApplicationService app,
  DocumentTestRepository repo,
  CurrentUserSession session,
  DocumentTestAccess guard,
  List<String> syncs,
})
harness({NoteRole? role, bool documentsSupported = true}) {
  final actor = role == null ? 'owner' : 'actor';
  final session = CurrentUserSession()..setIdentity(identity(actor));
  final content = document();
  final note = Note.reconstitute(
    id: 'n',
    ownerId: 'owner',
    title: 'Title',
    content: content.plainText,
    document: content,
    createdAt: at,
    updatedAt: at,
    pinnedAt: at,
    labelIds: ['label-a'],
    share: role == null
        ? null
        : NoteShareGrant(
            note: NoteIdentity('owner', 'n'),
            recipientId: actor,
            role: role,
            sharedAt: at,
            updatedAt: at,
            accessRevision: 1,
          ),
  );
  final repo = DocumentTestRepository(note, session);
  final guard = DocumentTestAccess();
  final syncs = <String>[];
  final app = NoteApplicationService(
    noteRepository: documentsSupported
        ? repo
        : LegacyDocumentTestRepository(repo),
    currentUser: session,
    generateId: () => 'new',
    now: () => at.add(const Duration(seconds: 1)),
    summarizeContent: (_) async => const Summary('synthetic'),
    security: guard,
    requestSync: syncs.add,
  );
  return (app: app, repo: repo, session: session, guard: guard, syncs: syncs);
}

AuthIdentity identity(String id) => AuthIdentity(
  userId: id,
  email: '$id@example.invalid',
  isEmailVerified: true,
);

final class DocumentTestAccess implements INoteAccessGuard {
  bool denied = false;
  int generation = 0;
  @override
  int get accessGeneration => generation;
  @override
  bool allows({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) => !denied;
  @override
  void requireAccess({
    required String ownerId,
    required String noteId,
    required NoteProtection protection,
    required NoteOperation operation,
  }) {
    if (denied) throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
  }
}

/// Transaction double for guard proof only; encryption/outbox are P2 tests.
final class DocumentTestRepository implements INoteDocumentRepository {
  DocumentTestRepository(this.note, this.session);
  Note note;
  final CurrentUserSession session;
  int writes = 0;
  FutureOr<void> Function()? beforeCommit;
  Object? storageFailure;
  @override
  int get documentVersion => 1;

  @override
  Future<Note?> findById(String id) async => note;
  @override
  Future<List<Note>> findByOwnerId(String ownerId) async =>
      note.ownerId == ownerId ? [note] : [];
  @override
  Future<void> save(Note value) async {
    note = value;
  }

  @override
  Future<void> deleteById(String id) async => throw UnimplementedError();

  @override
  Future<Note> updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required NoteChange change,
    required NoteCommitFence canCommit,
  }) async {
    if (noteId != note.id || ownerId != note.ownerId) {
      throw const NoteMutationMissingException();
    }
    final before = NoteDto.fromDomain(note);
    final changed = change(_copy(note));
    await beforeCommit?.call();
    if (session.userId != expectedAccountUserId || !canCommit()) {
      throw const NoteMutationCancelledException();
    }
    if (storageFailure != null) throw storageFailure!;
    if (before != NoteDto.fromDomain(changed)) {
      writes++;
      note = changed;
    }
    return note;
  }
}

Note _copy(Note note) => Note.reconstitute(
  id: note.id,
  ownerId: note.ownerId,
  title: note.contentAvailable ? note.title : '',
  content: note.contentAvailable ? note.content : '',
  document: note.contentAvailable ? note.document : null,
  createdAt: note.createdAt,
  updatedAt: note.updatedAt,
  protection: note.protection,
  contentAvailable: note.contentAvailable,
  contentRevision: note.contentRevision,
  share: note.share,
  pinnedAt: note.pinnedAt,
  attachments: note.contentAvailable ? note.attachments : [],
  labelIds: note.contentAvailable ? note.labelIds : [],
  labelProjections: note.contentAvailable ? note.labelProjections : [],
);

/// Existing text-only writer does not advertise document persistence.
final class LegacyDocumentTestRepository implements INoteRepository {
  LegacyDocumentTestRepository(this.delegate);
  final DocumentTestRepository delegate;
  @override
  Future<Note?> findById(String id) => delegate.findById(id);
  @override
  Future<List<Note>> findByOwnerId(String ownerId) =>
      delegate.findByOwnerId(ownerId);
  @override
  Future<void> save(Note note) => delegate.save(note);
  @override
  Future<void> deleteById(String id) => delegate.deleteById(id);
  @override
  Future<Note> updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required NoteChange change,
    required NoteCommitFence canCommit,
  }) => delegate.updateById(
    noteId: noteId,
    ownerId: ownerId,
    expectedAccountUserId: expectedAccountUserId,
    change: change,
    canCommit: canCommit,
  );
}
