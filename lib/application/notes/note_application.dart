import '../../domain/note_intelligence/summary.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_repository.dart';
import '../auth/current_user.dart';
import '../auth/current_user_session.dart';
import '../note_intelligence/summary_cloud_consent.dart';
import '../note_intelligence/summary_run_context.dart';

/// Creates identifiers for newly created notes.
typedef NoteIdGenerator = String Function();

/// Supplies the current time to the application service.
typedef NoteClock = DateTime Function();

/// Summarizes note content without exposing a concrete provider to the
/// application layer.
typedef SummarizeNoteContent = Future<Summary> Function(String content);

/// A read-only application projection of the Note aggregate.
///
/// The DTO keeps presentation code independent from the domain aggregate's
/// mutation methods while preserving the fields needed by the Notes UI.
final class NoteDto {
  const NoteDto({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a presentation-safe projection from a domain Note.
  factory NoteDto.fromDomain(Note note) {
    return NoteDto(
      id: note.id,
      ownerId: note.ownerId,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    );
  }

  final String id;
  final String ownerId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) {
    return other is NoteDto &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, ownerId, title, content, createdAt, updatedAt);

  @override
  String toString() {
    return 'NoteDto(id: $id, ownerId: $ownerId, title: $title, '
        'content: $content, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

/// Raised when an application operation targets a note that does not exist.
final class NoteNotFoundException implements Exception {
  const NoteNotFoundException(this.noteId);

  final String noteId;

  @override
  String toString() => 'NoteNotFoundException: note "$noteId" was not found';
}

/// Raised when the current user attempts to access another owner's note.
final class NoteOwnershipException implements Exception {
  const NoteOwnershipException({
    required this.noteId,
    required this.expectedOwnerId,
    required this.actualOwnerId,
  });

  final String noteId;
  final String expectedOwnerId;
  final String actualOwnerId;

  @override
  String toString() {
    return 'NoteOwnershipException: note "$noteId" belongs to '
        '"$actualOwnerId", not "$expectedOwnerId"';
  }
}

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
  });

  final INoteRepository noteRepository;
  final ICurrentUser currentUser;
  final NoteIdGenerator generateId;
  final NoteClock now;
  final SummarizeNoteContent summarizeContent;
  final RequestNoteSync? requestSync;

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
    final String userId = currentUser.requiredUserId;
    final List<Note> notes = await noteRepository.findByOwnerId(userId);
    return notes.map(NoteDto.fromDomain).toList(growable: false);
  }

  /// Creates and persists a new Note aggregate.
  Future<NoteDto> createNote({
    required String title,
    required String content,
  }) async {
    final String userId = currentUser.requiredUserId;
    final Note note = Note.create(
      id: generateId(),
      ownerId: userId,
      title: title,
      content: content,
      now: now().toUtc(),
    );
    await noteRepository.save(note);
    requestSync?.call(userId);
    return NoteDto.fromDomain(note);
  }

  /// Renames an owned note and persists the changed aggregate.
  Future<NoteDto> renameNote({
    required String noteId,
    required String title,
  }) async {
    final String userId = currentUser.requiredUserId;
    final Note note = await _requireOwnedNote(noteId, userId);
    note.rename(title, now().toUtc());
    await noteRepository.save(note);
    requestSync?.call(userId);
    return NoteDto.fromDomain(note);
  }

  /// Replaces the content of an owned note and persists the changed
  /// aggregate.
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) async {
    final String userId = currentUser.requiredUserId;
    final Note note = await _requireOwnedNote(noteId, userId);
    note.replaceContent(content, now().toUtc());
    await noteRepository.save(note);
    requestSync?.call(userId);
    return NoteDto.fromDomain(note);
  }

  /// Deletes an owned note.
  Future<void> deleteNote(String noteId) async {
    final String userId = currentUser.requiredUserId;
    await _requireOwnedNote(noteId, userId);
    await noteRepository.deleteById(noteId);
    requestSync?.call(userId);
  }

  /// Summarizes an owned note without mutating or persisting it.
  ///
  /// [selectedSnapshot] is the exact projection the Notes UI selected; when
  /// supplied, it must match the saved, owned revision before generation and
  /// that revision must still be saved before a result is accepted, so a
  /// summary is never produced for a revision the user did not select.
  /// [scope] owns cancellation for one invocation and never reactivates.
  ///
  /// The account and session generation are captured before the asynchronous
  /// note read and rechecked after every await and before the result is
  /// accepted. With [summarizeRun] wired a failure is a typed code-only
  /// [SummaryRunFailure]; the local path keeps its note-not-found and ownership
  /// exception contract and only adds the session-change gate.
  Future<Summary> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async {
    final String userId = currentUser.requiredUserId;
    final int generation = _sessionGeneration();
    final SummaryRunScope runScope = scope ?? SummaryRunScope();
    final bool dispatchesRun = summarizeRun != null;
    final bool typedFailure =
        dispatchesRun || scope != null || selectedSnapshot != null;
    final SummaryCloudConsentSnapshot consent = _consentFor(userId, generation);

    _requireLiveRun(runScope, userId, generation);
    if (selectedSnapshot != null &&
        (selectedSnapshot.id != noteId || selectedSnapshot.ownerId != userId)) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
    }

    final Note? note = await noteRepository.findById(noteId);
    _requireLiveRun(runScope, userId, generation);
    if (note == null || note.ownerId != userId) {
      // A note owned by another account is reported as missing on the run path.
      if (typedFailure) {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
      }
      if (note == null) {
        throw NoteNotFoundException(noteId);
      }
      throw NoteOwnershipException(
        noteId: noteId,
        expectedOwnerId: userId,
        actualOwnerId: note.ownerId,
      );
    }
    final NoteDto revision = NoteDto.fromDomain(note);
    if (selectedSnapshot != null && selectedSnapshot != revision) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
    }

    if (dispatchesRun) {
      _requireCurrentConsent(consent);
    }
    final Summary summary = dispatchesRun
        ? await summarizeRun!(
            SummaryRunContext(
              noteSnapshot: selectedSnapshot ?? revision,
              accountUserId: userId,
              sessionGeneration: generation,
              consent: consent,
              scope: runScope,
            ),
          )
        : await summarizeContent(note.content);

    _requireLiveRun(runScope, userId, generation);
    if (dispatchesRun) {
      _requireCurrentConsent(consent);
      await _requireSavedRevision(noteId, selectedSnapshot ?? revision);
      _requireLiveRun(runScope, userId, generation);
      _requireCurrentConsent(consent);
    }
    return summary;
  }

  /// Rejects the run when the scope is cancelled or the session moved on.
  ///
  /// Cancellation is checked first and keeps its original reason.
  void _requireLiveRun(SummaryRunScope scope, String userId, int generation) {
    final SummaryRunFailureCode? cancelled = scope.cancelReason;
    if (cancelled != null || scope.isReleased) {
      throw SummaryRunFailure(cancelled ?? SummaryRunFailureCode.cancelled);
    }
    if (currentUser.userId != userId || _sessionGeneration() != generation) {
      throw const SummaryRunFailure(SummaryRunFailureCode.sessionChanged);
    }
  }

  /// Rejects the result when a granted consent is no longer current.
  void _requireCurrentConsent(SummaryCloudConsentSnapshot consent) {
    if (!consent.isGranted) {
      // A never-granted snapshot cannot have authorized a cloud call, and local
      // summarization needs no consent, so there is nothing to revalidate.
      return;
    }
    final SummaryCloudConsent? store = cloudConsent;
    if (store == null || !store.isCurrent(consent)) {
      throw const SummaryRunFailure(SummaryRunFailureCode.consentRequired);
    }
  }

  Future<void> _requireSavedRevision(String noteId, NoteDto expected) async {
    final Note? current = await noteRepository.findById(noteId);
    if (current == null) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
    }
    if (NoteDto.fromDomain(current) != expected) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
    }
  }

  SummaryCloudConsentSnapshot _consentFor(String userId, int generation) {
    final SummaryCloudConsent? store = cloudConsent;
    if (store == null) {
      return SummaryCloudConsentSnapshot.notGranted(
        accountUserId: userId,
        sessionGeneration: generation,
      );
    }
    return store.capture(accountUserId: userId, sessionGeneration: generation);
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

  Future<Note> _requireOwnedNote(String noteId, String expectedOwnerId) async {
    final Note? note = await noteRepository.findById(noteId);
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
    return note;
  }
}
