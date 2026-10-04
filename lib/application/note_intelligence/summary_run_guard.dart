import '../auth/current_user.dart';
import '../auth/current_user_session.dart';
import '../notes/note_application.dart';
import '../sync/local_note_state.dart';
import '../sync/local_sync_state.dart';
import '../sync/local_sync_store.dart';
import '../sync/note_sync_status.dart';
import 'summary_cloud_consent.dart';
import 'summary_run_context.dart';
import '../notes/note_access.dart';
import '../../domain/notes/note_protection.dart';

/// Revalidates one saved note run using its captured account and session.
///
/// Remote composition calls this before each stage and immediately before
/// every HTTP dispatch, after any asynchronous token read.
final class SummaryRunGuard {
  const SummaryRunGuard({
    required this.currentUser,
    required this.session,
    required this.consent,
    required this.localSyncStoreForAccount,
    this.accessGuardForAccount,
  });

  final ICurrentUser currentUser;
  final SessionGenerationSource session;
  final SummaryCloudConsent consent;
  final ILocalSyncStore Function({required String accountUserId})
  localSyncStoreForAccount;
  final INoteAccessGuard Function(String accountId)? accessGuardForAccount;

  /// Checks the session, optional cloud consent, and the exact persisted note.
  Future<void> revalidate(
    SummaryRunContext context, {
    required bool requireConsent,
  }) async {
    _requireActive(context, requireConsent: requireConsent);
    final LocalSyncState state = await localSyncStoreForAccount(
      accountUserId: context.accountUserId,
    ).read();
    _requireActive(context, requireConsent: requireConsent);

    if (state.accountUserId != context.accountUserId) {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
    }
    for (final LocalNoteState note in state.notes) {
      if (note.identity != context.noteSnapshot.identity) continue;
      if (note.isDeleted) {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
      }
      if (!note.contentAvailable ||
          (note.protection.enabled &&
              !(accessGuardForAccount
                      ?.call(context.accountUserId)
                      .allows(
                        ownerId: note.ownerId,
                        noteId: note.id,
                        protection: note.protection,
                        operation: NoteOperation.summary,
                      ) ??
                  false))) {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteLocked);
      }
      if (requireConsent &&
          (note.serverRevision < 1 ||
              state.outbox.any(
                (m) =>
                    !m.isLabel &&
                    m.mutation.identityFor(state.accountUserId) ==
                        note.identity,
              ))) {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
      }
      if (note.status == NoteSyncStatus.conflict ||
          state.conflicts.any((conflict) => conflict.noteId == note.id)) {
        throw const SummaryRunFailure(SummaryRunFailureCode.conflict);
      }
      final NoteDto persisted = NoteDto.fromLocalState(note);
      if (persisted != context.noteSnapshot) {
        throw const SummaryRunFailure(SummaryRunFailureCode.noteChanged);
      }
      return;
    }
    throw const SummaryRunFailure(SummaryRunFailureCode.noteNotFound);
  }

  /// Synchronous identity, consent, and scope check for the instruction
  /// immediately after an async revalidation and before HTTP dispatch.
  SummaryRunFailureCode? currentFailure(
    SummaryRunContext context, {
    required bool requireConsent,
  }) {
    final SummaryRunScope scope = context.scope;
    if (scope.isCancelled || scope.isReleased) {
      return scope.cancelReason ?? SummaryRunFailureCode.cancelled;
    }
    if (currentUser.userId != context.accountUserId ||
        session.sessionGeneration != context.sessionGeneration) {
      return SummaryRunFailureCode.sessionChanged;
    }
    if (requireConsent && !consent.isCurrent(context.consent)) {
      return SummaryRunFailureCode.consentRequired;
    }
    final note = context.noteSnapshot;
    if (!note.contentAvailable ||
        (note.isProtected &&
            !(accessGuardForAccount
                    ?.call(context.accountUserId)
                    .allows(
                      ownerId: note.ownerId,
                      noteId: note.id,
                      protection: NoteProtection(
                        enabled: true,
                        revision: note.protectionRevision,
                      ),
                      operation: NoteOperation.summary,
                    ) ??
                false))) {
      return SummaryRunFailureCode.noteLocked;
    }
    return null;
  }

  void _requireActive(
    SummaryRunContext context, {
    required bool requireConsent,
  }) {
    final SummaryRunFailureCode? code = currentFailure(
      context,
      requireConsent: requireConsent,
    );
    if (code != null) {
      throw SummaryRunFailure(code);
    }
  }
}
