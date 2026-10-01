import '../../domain/note_intelligence/summary.dart';
import '../../domain/notes/note.dart';
import '../../domain/notes/note_repository.dart';
import '../../domain/users/user_preferences.dart';
import '../../domain/users/user_preferences_repository.dart';
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
    this.pinnedAt,
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
      pinnedAt: note.pinnedAt,
    );
  }

  final String id;
  final String ownerId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? pinnedAt;

  /// Compares the note identity and editable text used by summary requests.
  /// Pin and sync metadata do not change the summarized text revision.
  bool hasSameTextAs(NoteDto other) =>
      id == other.id &&
      ownerId == other.ownerId &&
      title == other.title &&
      content == other.content;

  @override
  bool operator ==(Object other) {
    return other is NoteDto &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.title == title &&
        other.content == content &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.pinnedAt == pinnedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, ownerId, title, content, createdAt, updatedAt, pinnedAt);

  @override
  String toString() {
    return 'NoteDto(id: $id, ownerId: $ownerId, createdAt: $createdAt, '
        'updatedAt: $updatedAt, pinnedAt: $pinnedAt)';
  }
}

/// Stable pin-first ordering shared by note list surfaces.
List<NoteDto> sortNotes(Iterable<NoteDto> notes, {bool byCreatedAt = false}) {
  final List<NoteDto> sorted = List<NoteDto>.of(notes);
  sorted.sort((NoteDto a, NoteDto b) {
    final DateTime? aPinnedAt = a.pinnedAt;
    final DateTime? bPinnedAt = b.pinnedAt;
    if (aPinnedAt != null || bPinnedAt != null) {
      if (aPinnedAt == null) return 1;
      if (bPinnedAt == null) return -1;
      final int byPinTime = bPinnedAt.compareTo(aPinnedAt);
      if (byPinTime != 0) return byPinTime;
    }
    final DateTime aDate = byCreatedAt ? a.createdAt : a.updatedAt;
    final DateTime bDate = byCreatedAt ? b.createdAt : b.updatedAt;
    final int byDate = bDate.compareTo(aDate);
    return byDate == 0 ? a.id.compareTo(b.id) : byDate;
  });
  return sorted;
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
    this.userPreferencesRepository,
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
  final IUserPreferencesRepository? userPreferencesRepository;

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
    return sortNotes(notes.map(NoteDto.fromDomain));
  }

  /// Returns the saved layout for the current account, defaulting to grid.
  Future<NoteLayoutPreference> getNoteLayout() async {
    final String userId = currentUser.requiredUserId;
    final UserPreferences? preferences = await userPreferencesRepository
        ?.findByUserId(userId);
    return preferences?.noteLayout ?? NoteLayoutPreference.grid;
  }

  /// Persists the selected layout for the current account.
  Future<void> setNoteLayout(NoteLayoutPreference layout) async {
    final IUserPreferencesRepository? repository = userPreferencesRepository;
    if (repository == null) return;
    final String userId = currentUser.requiredUserId;
    final UserPreferences preferences =
        await repository.findByUserId(userId) ??
        UserPreferences.create(
          userId: userId,
          theme: AppThemePreference.system,
          noteFontSize: NoteFontSizePreference.medium,
        );
    preferences.changeNoteLayout(layout);
    await repository.save(preferences);
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

  /// Saves title and content in one atomic note/outbox update.
  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  }) async {
    final String userId = currentUser.requiredUserId;
    final Note? updated = await noteRepository.updateById(
      noteId,
      expectedAccountUserId: userId,
      change: (Note note) => note.replaceText(title, content, now().toUtc()),
    );
    if (updated == null) throw NoteNotFoundException(noteId);
    requestSync?.call(userId);
    return NoteDto.fromDomain(updated);
  }

  /// Changes the owner-only pin state through the atomic repository update.
  Future<NoteDto> setPinned({
    required String noteId,
    required bool pinned,
  }) async {
    final String userId = currentUser.requiredUserId;
    final Note? updated = await noteRepository.updateById(
      noteId,
      expectedAccountUserId: userId,
      change: (Note note) {
        if (pinned) {
          note.pin(now().toUtc());
        } else {
          note.unpin(now().toUtc());
        }
      },
    );
    if (updated == null) throw NoteNotFoundException(noteId);
    requestSync?.call(userId);
    return NoteDto.fromDomain(updated);
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
  /// [SummaryRunFailure]. Scoped/selected local calls also recheck the revision;
  /// legacy unscoped local calls retain their original exception/read contract.
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
    if (selectedSnapshot != null && !selectedSnapshot.hasSameTextAs(revision)) {
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
    }
    if (typedFailure) {
      await _requireSavedRevision(noteId, selectedSnapshot ?? revision);
      _requireLiveRun(runScope, userId, generation);
    }
    if (dispatchesRun) {
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
    if (!NoteDto.fromDomain(current).hasSameTextAs(expected)) {
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
