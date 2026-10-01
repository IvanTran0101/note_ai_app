import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_guard.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/application/sync/local_sync_store.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

final class _Store implements ILocalSyncStore {
  _Store(this.state);
  LocalSyncState state;
  Future<void> Function()? beforeRead;

  @override
  Future<LocalSyncState> read() async {
    await beforeRead?.call();
    return state;
  }

  @override
  Future<LocalSyncState> update(
    LocalSyncState Function(LocalSyncState current) transform,
  ) async => state = transform(state);

  @override
  Future<void> replace(LocalSyncState value) async => state = value;
}

void main() {
  final DateTime time = DateTime.utc(2026, 10, 1);
  CurrentUserSession session() => CurrentUserSession()
    ..setIdentity(
      AuthIdentity(
        userId: 'account-a',
        email: 'a@example.test',
        isEmailVerified: true,
      ),
    );
  LocalNoteState note({
    String title = 'Title',
    String content = 'Saved content',
    NoteSyncStatus status = NoteSyncStatus.pending,
    DateTime? deletedAt,
  }) => LocalNoteState(
    id: 'note-1',
    ownerId: 'account-a',
    title: title,
    content: content,
    createdAt: time,
    updatedAt: time,
    status: status,
    deletedAt: deletedAt,
  );
  NoteDto snapshot(LocalNoteState value) => NoteDto(
    id: value.id,
    ownerId: value.ownerId,
    title: value.title,
    content: value.content,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
  );
  SummaryRunContext context(
    CurrentUserSession user,
    SummaryCloudConsent consent,
    LocalNoteState saved, {
    SummaryRunScope? scope,
  }) => SummaryRunContext(
    noteSnapshot: snapshot(saved),
    accountUserId: user.requiredUserId,
    sessionGeneration: user.sessionGeneration,
    consent: consent.capture(
      accountUserId: user.requiredUserId,
      sessionGeneration: user.sessionGeneration,
    ),
    scope: scope ?? SummaryRunScope(),
  );
  SummaryRunGuard guard(
    CurrentUserSession user,
    SummaryCloudConsent consent,
    _Store store,
  ) => SummaryRunGuard(
    currentUser: user,
    session: user,
    consent: consent,
    localSyncStoreForAccount: ({required String accountUserId}) => store,
  );

  test(
    'allows an unchanged unsynced note locally without cloud consent',
    () async {
      final CurrentUserSession user = session();
      final SummaryCloudConsent consent = SummaryCloudConsent(session: user);
      final LocalNoteState saved = note();
      await guard(
        user,
        consent,
        _Store(
          LocalSyncState(
            accountUserId: 'account-a',
            notes: <LocalNoteState>[saved],
          ),
        ),
      ).revalidate(context(user, consent, saved), requireConsent: false);
    },
  );

  test(
    'remote requires a current consent snapshot before reading the store',
    () async {
      final CurrentUserSession user = session();
      final SummaryCloudConsent consent = SummaryCloudConsent(session: user);
      final _Store store = _Store(LocalSyncState(accountUserId: 'account-a'));
      await expectLater(
        guard(
          user,
          consent,
          store,
        ).revalidate(context(user, consent, note()), requireConsent: true),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
      );
      expect(store.beforeRead, isNull);
    },
  );

  test('blocks missing, deleted, changed, and conflicted notes', () async {
    final CurrentUserSession user = session();
    final SummaryCloudConsent consent = SummaryCloudConsent(session: user);
    final LocalNoteState selected = note();
    final SummaryRunContext run = context(user, consent, selected);
    Future<void> rejects(LocalSyncState state, SummaryRunFailureCode code) =>
        expectLater(
          guard(
            user,
            consent,
            _Store(state),
          ).revalidate(run, requireConsent: false),
          throwsA(SummaryRunFailure(code)),
        );

    await rejects(
      LocalSyncState(accountUserId: 'account-a'),
      SummaryRunFailureCode.noteNotFound,
    );
    await rejects(
      LocalSyncState(
        accountUserId: 'account-a',
        notes: <LocalNoteState>[note(deletedAt: time)],
      ),
      SummaryRunFailureCode.noteNotFound,
    );
    await rejects(
      LocalSyncState(
        accountUserId: 'account-a',
        notes: <LocalNoteState>[note(title: 'Changed')],
      ),
      SummaryRunFailureCode.noteChanged,
    );
    await rejects(
      LocalSyncState(
        accountUserId: 'account-a',
        notes: <LocalNoteState>[note(status: NoteSyncStatus.conflict)],
      ),
      SummaryRunFailureCode.conflict,
    );
  });

  test(
    'rechecks account/session generation and scope after store read',
    () async {
      final CurrentUserSession user = session();
      final SummaryCloudConsent consent = SummaryCloudConsent(session: user)
        ..grant(
          accountUserId: 'account-a',
          sessionGeneration: user.sessionGeneration,
        );
      final LocalNoteState saved = note();
      final _Store store = _Store(
        LocalSyncState(
          accountUserId: 'account-a',
          notes: <LocalNoteState>[saved],
        ),
      );
      final SummaryRunGuard activeGuard = guard(user, consent, store);
      final SummaryRunContext old = context(user, consent, saved);
      store.beforeRead = () async {
        user.clear();
        user.setIdentity(
          AuthIdentity(
            userId: 'account-a',
            email: 'a@example.test',
            isEmailVerified: true,
          ),
        );
      };
      await expectLater(
        activeGuard.revalidate(old, requireConsent: true),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.sessionChanged)),
      );

      final SummaryRunContext next = context(user, consent, saved);
      final SummaryRunScope scope = SummaryRunScope();
      final SummaryRunContext cancelled = context(
        user,
        consent,
        saved,
        scope: scope,
      );
      store.beforeRead = () async => scope.cancel();
      await expectLater(
        activeGuard.revalidate(cancelled, requireConsent: false),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.cancelled)),
      );

      store.beforeRead = () async => consent.revoke(accountUserId: 'account-a');
      await expectLater(
        activeGuard.revalidate(next, requireConsent: true),
        throwsA(const SummaryRunFailure(SummaryRunFailureCode.consentRequired)),
      );
    },
  );
}
