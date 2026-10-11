import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/domain/users/user_preferences_repository.dart';

/// Behavior coverage for the theme use cases added to the existing preferences
/// extension: which account a read/write belongs to, that a write preserves the
/// other stored preferences, and that a stale or failed write never reports
/// success.

final DateTime _now = DateTime.utc(2026, 10, 9, 9);

final class _FakeCurrentUser implements ICurrentUser {
  _FakeCurrentUser(this.identity);

  @override
  AuthIdentity? identity;

  @override
  bool get isAuthenticated => identity != null;

  @override
  String? get userId => identity?.userId;

  @override
  String get requiredUserId {
    final String? currentUserId = userId;
    if (currentUserId == null) {
      throw const UnauthenticatedException();
    }
    return currentUserId;
  }
}

final class _NoopNoteRepository implements INoteRepository {
  @override
  Future<void> deleteById(String id) => throw UnimplementedError();

  @override
  Future<Note?> findById(String id) => throw UnimplementedError();

  @override
  Future<List<Note>> findByOwnerId(String ownerId) =>
      throw UnimplementedError();

  @override
  Future<void> save(Note note) => throw UnimplementedError();

  @override
  Future<Note> updateById({
    required String noteId,
    required String ownerId,
    required String expectedAccountUserId,
    required NoteChange change,
    required NoteCommitFence canCommit,
  }) => throw UnimplementedError();
}

final class _FakePreferencesRepository implements IUserPreferencesRepository {
  _FakePreferencesRepository({Map<String, UserPreferences>? initial})
    : stored = <String, UserPreferences>{...?initial};

  final Map<String, UserPreferences> stored;
  final List<String> reads = <String>[];
  final List<UserPreferences> writes = <UserPreferences>[];
  Completer<void>? readGate;
  Object? saveError;

  @override
  Future<UserPreferences?> findByUserId(String userId) async {
    reads.add(userId);
    final Completer<void>? gate = readGate;
    if (gate != null) {
      await gate.future;
    }
    // A real repository hands out a detached value, not its stored instance.
    return stored[userId]?.copy();
  }

  @override
  Future<void> save(UserPreferences preferences) async {
    final Object? error = saveError;
    if (error != null) {
      throw error;
    }
    writes.add(preferences.copy());
    stored[preferences.userId] = preferences.copy();
  }
}

_FakeCurrentUser _user(String userId) {
  return _FakeCurrentUser(
    AuthIdentity(
      userId: userId,
      email: '$userId@example.test',
      isEmailVerified: true,
    ),
  );
}

NoteApplicationService _service(
  _FakePreferencesRepository? preferences, {
  _FakeCurrentUser? currentUser,
  SessionGenerationReader? sessionGeneration,
}) {
  return NoteApplicationService(
    noteRepository: _NoopNoteRepository(),
    currentUser: currentUser ?? _user('account-a'),
    generateId: () => 'note-id',
    now: () => _now,
    summarizeContent: (String content) async => Summary(content),
    userPreferencesRepository: preferences,
    sessionGeneration: sessionGeneration,
  );
}

UserPreferences _preferences({
  String userId = 'account-a',
  AppThemePreference theme = AppThemePreference.system,
  NoteFontSizePreference fontSize = NoteFontSizePreference.large,
  String? colorKey = 'sand',
  NoteLayoutPreference layout = NoteLayoutPreference.list,
}) {
  return UserPreferences.create(
    userId: userId,
    theme: theme,
    noteFontSize: fontSize,
    noteColorKey: colorKey,
    noteLayout: layout,
  );
}

Matcher _sessionChanged() => throwsA(
  isA<NoteSecurityFailure>().having(
    (NoteSecurityFailure failure) => failure.code,
    'code',
    NoteSecurityFailureCode.sessionChanged,
  ),
);

void main() {
  test('overlapping theme and layout writes preserve both fields', () async {
    final repository = _FakePreferencesRepository(
      initial: {'account-a': _preferences(layout: NoteLayoutPreference.grid)},
    );
    final service = _service(repository);
    await Future.wait([
      service.setTheme(AppThemePreference.dark),
      service.setNoteLayout(NoteLayoutPreference.list),
    ]);
    final saved = repository.stored['account-a']!;
    expect(saved.theme, AppThemePreference.dark);
    expect(saved.noteLayout, NoteLayoutPreference.list);
    expect(saved.noteColorKey, 'sand');
    expect(saved.noteFontSize, NoteFontSizePreference.large);
  });

  group('getTheme', () {
    test('returns the theme stored for the active account', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{
          'account-a': _preferences(theme: AppThemePreference.dark),
        },
      );

      expect(await _service(repository).getTheme(), AppThemePreference.dark);
      expect(repository.reads, <String>['account-a']);
    });

    test('falls back to the system theme when nothing is stored', () async {
      final _FakePreferencesRepository repository =
          _FakePreferencesRepository();

      expect(await _service(repository).getTheme(), AppThemePreference.system);
      expect(repository.writes, isEmpty);
    });

    test('falls back to the system theme without a repository', () async {
      expect(await _service(null).getTheme(), AppThemePreference.system);
    });

    test('never returns another account stored theme', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{
          'account-a': _preferences(theme: AppThemePreference.dark),
        },
      );
      final _FakeCurrentUser currentUser = _user('account-b');

      expect(
        await _service(repository, currentUser: currentUser).getTheme(),
        AppThemePreference.system,
      );
      expect(repository.reads, <String>['account-b']);
    });
  });

  group('setTheme', () {
    test('persists the theme and preserves every other preference', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{'account-a': _preferences()},
      );

      await _service(repository).setTheme(AppThemePreference.dark);

      expect(repository.writes, hasLength(1));
      expect(
        repository.writes.single,
        _preferences(userId: 'account-a', theme: AppThemePreference.dark),
      );
      // The other values survive the write untouched.
      expect(
        repository.writes.single.noteFontSize,
        NoteFontSizePreference.large,
      );
      expect(repository.writes.single.noteColorKey, 'sand');
      expect(repository.writes.single.noteLayout, NoteLayoutPreference.list);
    });

    test('creates the missing record and keeps the other defaults', () async {
      final _FakePreferencesRepository repository =
          _FakePreferencesRepository();

      await _service(repository).setTheme(AppThemePreference.light);

      final UserPreferences saved = repository.writes.single;
      expect(saved.userId, 'account-a');
      expect(saved.theme, AppThemePreference.light);
      expect(saved.noteFontSize, NoteFontSizePreference.medium);
      expect(saved.noteLayout, NoteLayoutPreference.grid);
      expect(saved.noteColorKey, isNull);
    });

    test('writes only the active account record', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{
          'account-a': _preferences(theme: AppThemePreference.dark),
        },
      );

      await _service(
        repository,
        currentUser: _user('account-b'),
      ).setTheme(AppThemePreference.light);

      expect(repository.writes.single.userId, 'account-b');
      expect(repository.stored['account-a']!.theme, AppThemePreference.dark);
    });

    test('does nothing without a repository', () async {
      await _service(null).setTheme(AppThemePreference.dark);
    });

    test('refuses a write whose session generation moved on', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{
          'account-a': _preferences(theme: AppThemePreference.system),
        },
      );
      int generation = 1;
      repository.readGate = Completer<void>();
      final NoteApplicationService service = _service(
        repository,
        sessionGeneration: () => generation,
      );

      final Future<void> pending = service.setTheme(AppThemePreference.dark);
      generation = 2;
      repository.readGate!.complete();
      await expectLater(pending, _sessionChanged());

      expect(repository.stored['account-a']!.theme, AppThemePreference.system);
      expect(repository.writes, isEmpty);
    });

    test('refuses a write that started under another identity', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{
          'account-a': _preferences(theme: AppThemePreference.system),
        },
      )..readGate = Completer<void>();
      final _FakeCurrentUser currentUser = _user('account-a');
      final NoteApplicationService service = _service(
        repository,
        currentUser: currentUser,
      );

      final Future<void> pending = service.setTheme(AppThemePreference.dark);
      currentUser.identity = null;
      repository.readGate!.complete();
      await expectLater(pending, _sessionChanged());

      expect(repository.writes, isEmpty);
    });

    test('reports a failed write instead of claiming it persisted', () async {
      final _FakePreferencesRepository repository = _FakePreferencesRepository(
        initial: <String, UserPreferences>{
          'account-a': _preferences(theme: AppThemePreference.system),
        },
      )..saveError = StateError('store unavailable');

      await expectLater(
        _service(repository).setTheme(AppThemePreference.dark),
        throwsStateError,
      );
      expect(repository.stored['account-a']!.theme, AppThemePreference.system);
    });
  });
}
