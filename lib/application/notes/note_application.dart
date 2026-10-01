import 'note_access.dart';
import 'note_dto.dart';
import '../../domain/notes/note_protection.dart';

export 'note_dto.dart';

import '../../domain/note_intelligence/summary.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_repository.dart';
import '../auth/current_user.dart';
import '../auth/current_user_session.dart';
import '../note_intelligence/summary_cloud_consent.dart';
import '../note_intelligence/summary_run_context.dart';

part 'note_application_summary.dart';

/// Creates identifiers for newly created notes.
typedef NoteIdGenerator = String Function();

/// Supplies the current time to the application service.
typedef NoteClock = DateTime Function();

/// Summarizes note content without exposing a concrete provider to the
/// application layer.
typedef SummarizeNoteContent = Future<Summary> Function(String content);

/// Requests a non-blocking sync after one local note mutation has persisted.
typedef RequestNoteSync = void Function(String accountUserId);

/// Dispatches one validated, note-aware summary run.
typedef SummarizeNoteRun = Future<Summary> Function(SummaryRunContext context);

/// Immutable note, account, session, consent, and cancellation facts for a run.
final class SummaryRunContext {
  const SummaryRunContext({
    required this.noteSnapshot,
    required this.accountUserId,
    required this.sessionGeneration,
    required this.consent,
    required this.scope,
  });

  final NoteDto noteSnapshot;

  final String accountUserId;

  final int sessionGeneration;

  final SummaryCloudConsentSnapshot consent;

  final SummaryRunScope scope;

  @override
  String toString() {
    return 'SummaryRunContext(accountUserId: $accountUserId, '
        'sessionGeneration: $sessionGeneration, '
        'noteId: ${noteSnapshot.id}, consentGranted: ${consent.isGranted})';
  }
}

/// Application use cases for the Note aggregate.
///
/// This service coordinates domain behavior and persistence. It deliberately
/// contains no file, JSON, Flutter, FFI, or concrete AI-provider concerns.
/// The injected clock is normalized to UTC at this boundary so notes created
/// or mutated through the application use cases have stable persisted times.
final class NoteApplicationService {
  NoteApplicationService({
    required this.noteRepository,
    required this.currentUser,
    required this.generateId,
    required this.now,
    required this.summarizeContent,
    this.requestSync,
    this.summarizeRun,
    this.cloudConsent,
    this.sessionGeneration,
    this.security,
  });

  final INoteRepository noteRepository;
  final ICurrentUser currentUser;
  final NoteIdGenerator generateId;
  final NoteClock now;
  final SummarizeNoteContent summarizeContent;
  final RequestNoteSync? requestSync;
  final INoteAccessGuard? security;

  /// Optional note-snapshot-aware dispatcher supplied by the composition root.
  ///
  /// When set, [summarizeNote] dispatches through it with a validated
  /// [SummaryRunContext]; otherwise the local [summarizeContent] seam runs.
  final SummarizeNoteRun? summarizeRun;

  /// In-memory cloud consent captured into every run context.
  ///
  /// When null, each run captures a not-granted snapshot, so a missing store
  /// fails closed instead of inventing consent.
  final SummaryCloudConsent? cloudConsent;

  /// Overrides how the session generation is read.
  ///
  /// Defaults to [currentUser] when it implements [SessionGenerationSource],
  /// and to 0 otherwise.
  final SessionGenerationReader? sessionGeneration;

  /// Lists the notes owned by the authenticated user.
  Future<List<NoteDto>> listNotes() async {
    final context = _captureContext();
    final String userId = context.userId;
    final List<Note> notes = await noteRepository.findByOwnerId(userId);
    _requireContext(context);
    return notes.map(NoteDto.fromDomain).toList(growable: false);
  }

  Future<NoteDto> readNote(String noteId) async {
    final context = _captureContext();
    final Note note = await _requireOwnedNote(
      noteId,
      context,
      NoteOperation.read,
    );
    return NoteDto.fromDomain(note);
  }

  NoteAccessCapabilities capabilitiesFor(NoteDto note) {
    if (currentUser.userId != note.ownerId || !note.contentAvailable) {
      return const NoteAccessCapabilities();
    }
    bool allowed(NoteOperation operation) =>
        security?.allows(
          ownerId: note.ownerId,
          noteId: note.id,
          protection: NoteProtection(
            enabled: note.isProtected,
            revision: note.protectionRevision,
          ),
          operation: operation,
        ) ??
        !note.isProtected;
    return NoteAccessCapabilities(
      canRead: allowed(NoteOperation.read),
      canEdit: allowed(NoteOperation.edit),
      canDelete: allowed(NoteOperation.delete),
      canManage: allowed(NoteOperation.manage),
      canSummarize: allowed(NoteOperation.summary),
      canExport: allowed(NoteOperation.export),
    );
  }

  /// Creates and persists a new Note aggregate.
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final context = _captureContext();
    final String userId = context.userId;
    final Note note = Note.create(
      id: generateId(),
      ownerId: userId,
      title: title,
      content: content,
      now: now().toUtc(),
    );
    await noteRepository.save(note);
    _requireContext(context);
    _requireAccess(note, NoteOperation.edit);
    requestSync?.call(userId);
    return NoteDto.fromDomain(note);
  }

  /// Renames an owned note and persists the changed aggregate.
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    final context = _captureContext();
    final String userId = context.userId;
    final Note note = await _requireOwnedNote(
      noteId,
      context,
      NoteOperation.edit,
    );
    note.rename(title, now().toUtc());
    await noteRepository.save(note);
    _requireContext(context);
    _requireAccess(note, NoteOperation.edit);
    requestSync?.call(userId);
    return NoteDto.fromDomain(note);
  }

  /// Replaces the content of an owned note and persists the changed
  /// aggregate.
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    final context = _captureContext();
    final String userId = context.userId;
    final Note note = await _requireOwnedNote(
      noteId,
      context,
      NoteOperation.edit,
    );
    note.replaceContent(content, now().toUtc());
    await noteRepository.save(note);
    _requireContext(context);
    _requireAccess(note, NoteOperation.edit);
    requestSync?.call(userId);
    return NoteDto.fromDomain(note);
  }

  /// Deletes an owned note.
  Future<void> deleteNote(String noteId) async {
    final context = _captureContext();
    final String userId = context.userId;
    await _requireOwnedNote(noteId, context, NoteOperation.delete);
    await noteRepository.deleteById(noteId);
    _requireContext(context);
    requestSync?.call(userId);
  }

  ({String userId, int session, int access}) _captureContext() => (
    userId: currentUser.requiredUserId,
    session: _sessionGeneration(),
    access: security?.accessGeneration ?? 0,
  );

  void _requireContext(({String userId, int session, int access}) context) {
    if (currentUser.userId != context.userId ||
        _sessionGeneration() != context.session) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    if ((security?.accessGeneration ?? 0) != context.access) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
  }

  int _sessionGeneration() {
    final SessionGenerationReader? reader = sessionGeneration;
    if (reader != null) {
      return reader();
    }
    // Widened to Object so the interface test can promote an unrelated type.
    final Object user = currentUser;
    return user is SessionGenerationSource ? user.sessionGeneration : 0;
  }

  Future<Note> _requireOwnedNote(
    String noteId,
    ({String userId, int session, int access}) context,
    NoteOperation operation,
  ) async {
    final Note? note = await noteRepository.findById(noteId);
    _requireContext(context);
    final String expectedOwnerId = context.userId;
    if (note == null) {
      throw NoteNotFoundException(noteId);
    }
    if (note.ownerId != expectedOwnerId) {
      throw NoteOwnershipException(
        noteId: noteId,
        expectedOwnerId: expectedOwnerId,
        actualOwnerId: note.ownerId,
      );
    }
    if (currentUser.userId != expectedOwnerId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    _requireAccess(note, operation);
    return note;
  }

  void _requireAccess(Note note, NoteOperation operation) {
    if (currentUser.userId != note.ownerId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    if (!note.contentAvailable) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    final INoteAccessGuard? guard = security;
    if (!note.protection.enabled && guard == null) return;
    if (guard == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    guard.requireAccess(
      ownerId: note.ownerId,
      noteId: note.id,
      protection: note.protection,
      operation: operation,
    );
  }
}
